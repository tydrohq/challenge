// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console2 as console} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {
    IPoolAddressesProvider,
    IPool,
    IPoolConfigurator,
    IAaveOracle,
    IACLManager,
    IAaveProtocolDataProvider
} from "../src/interfaces/IAaveV3.sol";
import {ListingHelper} from "../src/harness/ListingHelper.sol";

/// @title ForkBase
/// @notice Shared base for every script and test. Loads addresses (env + addresses.json),
///         derives all Tydro contracts from the single PoolAddressesProvider, grants the
///         candidate EOA the ACL roles it needs, and seeds a deterministic position book so
///         tasks 1 & 2 have real positions to verify against.
///
///         Inherits CommonBase (provides `vm`) + StdCheats (provides `deal`) so it composes
///         with both forge-std Script and Test and can fund the seeded actors.
abstract contract ForkBase is CommonBase, StdCheats {
    using stdJson for string;

    // ---- Seeded position book (see {seedPositionBook}) ----
    struct SeededPosition {
        address user; // dedicated borrower (never the candidate's account)
        uint256 targetHfBps; // requested health factor, bps (10000 = 1.0)
        uint256 healthFactor; // realized HF right after seeding, 1e18-scaled
    }

    struct PositionBook {
        address collateral; // == oracleMigrationTarget (the market the tasks key off)
        address borrowAsset; // the stable borrowed against the collateral
        address lp; // address that supplied borrow-side liquidity
        uint256 lpLiquidity; // borrowAsset units the LP supplied
        SeededPosition[] positions;
    }

    struct SeedConfig {
        address collateral;
        address borrowAsset;
        address lp;
        address[] borrowers;
        uint256[] targetHfBps;
        uint256 collUnits; // collateral units (decimals-scaled) per borrower
    }

    // ---- Default candidate EOA: anvil account 0 (public test key). ----
    address internal constant DEFAULT_CANDIDATE = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    // ---- Loaded config ----
    address internal candidate;
    address internal oracleMigrationTarget;

    // ---- The one hardcoded address; everything else derives from it ----
    IPoolAddressesProvider internal provider;
    IAaveProtocolDataProvider internal dataProvider;

    // ---- Derived at runtime (never hardcoded) ----
    IPool internal pool;
    IPoolConfigurator internal configurator;
    IAaveOracle internal oracle;
    IACLManager internal acl;
    address internal aclAdmin;

    /// @notice Read addresses.json + env and derive every contract from the provider.
    ///         Does NOT create a fork (so it is safe to call in a script that already runs
    ///         against an external anvil node). Tests call {createForkAndLoad} instead.
    function loadAddresses() internal {
        string memory json = vm.readFile("addresses.json");
        address providerAddr = json.readAddress(".addressesProvider");
        address dataProviderAddr = json.readAddress(".dataProvider");
        require(providerAddr != address(0), "addresses.json: addressesProvider unset (TODO)");
        require(dataProviderAddr != address(0), "addresses.json: dataProvider unset (TODO)");

        provider = IPoolAddressesProvider(providerAddr);
        dataProvider = IAaveProtocolDataProvider(dataProviderAddr);

        // ORACLE_MIGRATION_TARGET: prefer env, fall back to addresses.json.
        oracleMigrationTarget = vm.envOr("ORACLE_MIGRATION_TARGET", json.readAddress(".oracleMigrationTarget"));
        require(oracleMigrationTarget != address(0), "ORACLE_MIGRATION_TARGET unset (TODO)");

        candidate = vm.envOr("CANDIDATE", DEFAULT_CANDIDATE);

        // Derive everything from the provider — do not hardcode these.
        pool = IPool(provider.getPool());
        configurator = IPoolConfigurator(provider.getPoolConfigurator());
        oracle = IAaveOracle(provider.getPriceOracle());
        acl = IACLManager(provider.getACLManager());
        aclAdmin = provider.getACLAdmin();

        require(address(pool) != address(0), "provider.getPool() returned zero");
        require(address(configurator) != address(0), "provider.getPoolConfigurator() returned zero");
        require(address(oracle) != address(0), "provider.getPriceOracle() returned zero");
        require(address(acl) != address(0), "provider.getACLManager() returned zero");
        require(aclAdmin != address(0), "provider.getACLAdmin() returned zero");
    }

    /// @notice Create the Ink fork at the pinned block, then load addresses. For tests.
    ///         Fails loudly naming any unset env var.
    function createForkAndLoad() internal {
        string memory rpc = vm.envOr("INK_RPC_URL", string(""));
        require(bytes(rpc).length != 0, "INK_RPC_URL unset (copy .env.example -> .env)");
        uint256 forkBlock = vm.envOr("FORK_BLOCK", uint256(0));
        require(forkBlock != 0, "FORK_BLOCK unset (copy .env.example -> .env)");
        vm.createSelectFork(rpc, forkBlock);
        loadAddresses();
    }

    /// @notice Grant the four ACL roles to `to` by impersonating the ACL admin.
    ///         The ACL admin on Tydro is a CONTRACT but holds DEFAULT_ADMIN_ROLE directly,
    ///         so a simple prank is sufficient — no timelock/executor dance. (Verified on
    ///         the fork.) Use in tests / fork simulations.
    function grantRolesPranked(address to) internal {
        vm.startPrank(aclAdmin);
        acl.addPoolAdmin(to);
        acl.addRiskAdmin(to);
        acl.addAssetListingAdmin(to);
        acl.addEmergencyAdmin(to);
        vm.stopPrank();
    }

    /// @notice Convenience wiring for the listMarket helper, using WETH as the reference
    ///         reserve to clone token implementations from.
    function listingWiring() internal view returns (ListingHelper.Wiring memory) {
        return ListingHelper.Wiring({
            configurator: configurator,
            oracle: oracle,
            dataProvider: dataProvider,
            referenceReserve: oracleMigrationTarget
        });
    }

    // ============================ Position-book seeding (§3a) ============================

    /// @notice Seed a deterministic position book against the target market
    ///         (`oracleMigrationTarget`, the collateral the tasks key off):
    ///           1. supply borrow-side liquidity from a dedicated LP (never the candidate);
    ///           2. open a spread of borrower positions at known health factors.
    ///         All amounts are computed off-chain from live price/decimals/LT — nothing is
    ///         hardcoded (§6 robustness) — so the book is identical on every run at the pinned
    ///         block. Borrowers/LP are dedicated addresses, so the candidate's own positions
    ///         never collide with the book.
    /// @dev Cheatcode-based (`deal`/prank): seeds the in-process fork that the createSelectFork
    ///      entrypoints (ReadState, the task scripts, tests) run against.
    function seedPositionBook() internal returns (PositionBook memory book) {
        SeedConfig memory c = _readSeedConfig();

        // Size each borrow off-chain, then size LP liquidity to cover the book plus headroom
        // for the candidate's own experiments.
        uint256[] memory borrowAmts = new uint256[](c.borrowers.length);
        uint256 totalBorrow;
        for (uint256 i; i < c.borrowers.length; i++) {
            borrowAmts[i] = _computeBorrowAmount(c.collateral, c.collUnits, c.borrowAsset, c.targetHfBps[i]);
            totalBorrow += borrowAmts[i];
        }

        // 1. Guarantee borrow-side liquidity FIRST (§3a.1).
        uint256 lpSupply = totalBorrow * 3;
        _supplyAs(c.borrowAsset, c.lp, lpSupply);

        // 2. Open the borrower positions at their target HFs (§3a.2).
        book.collateral = c.collateral;
        book.borrowAsset = c.borrowAsset;
        book.lp = c.lp;
        book.lpLiquidity = lpSupply;
        book.positions = new SeededPosition[](c.borrowers.length);
        for (uint256 i; i < c.borrowers.length; i++) {
            uint256 hf = _openPosition(c.collateral, c.collUnits, c.borrowAsset, c.borrowers[i], borrowAmts[i]);
            require(hf > 1e18, "seeded position must end with HF > 1"); // else instantly liquidatable
            book.positions[i] =
                SeededPosition({user: c.borrowers[i], targetHfBps: c.targetHfBps[i], healthFactor: hf});
        }
    }

    /// @dev Read + validate seed params: env override -> addresses.json -> fail loud (§3a.4).
    function _readSeedConfig() internal returns (SeedConfig memory c) {
        string memory json = vm.readFile("addresses.json");

        c.collateral = oracleMigrationTarget;
        c.borrowAsset = vm.envOr("SEED_BORROW_ASSET", json.readAddress(".seed.borrowAsset"));
        c.lp = vm.envOr("SEED_LP", json.readAddress(".seed.lp"));

        c.borrowers = new address[](2);
        c.borrowers[0] = vm.envOr("SEED_BORROWER_1", json.readAddress(".seed.borrower1"));
        c.borrowers[1] = vm.envOr("SEED_BORROWER_2", json.readAddress(".seed.borrower2"));

        c.targetHfBps = new uint256[](2);
        c.targetHfBps[0] = vm.envOr("SEED_TARGET_HF_1", json.readUint(".seed.targetHfBps1"));
        c.targetHfBps[1] = vm.envOr("SEED_TARGET_HF_2", json.readUint(".seed.targetHfBps2"));

        uint256 collWhole = vm.envOr("SEED_COLLATERAL_AMOUNT", json.readUint(".seed.collateralWholeTokens"));

        require(c.borrowAsset != address(0), "SEED_BORROW_ASSET unset (TODO)");
        require(c.lp != address(0), "SEED_LP unset (TODO)");
        require(c.borrowers[0] != address(0) && c.borrowers[1] != address(0), "SEED_BORROWER_* unset (TODO)");
        require(collWhole > 0, "SEED_COLLATERAL_AMOUNT unset (TODO)");
        require(c.targetHfBps[0] > 1e4 && c.targetHfBps[1] > 1e4, "SEED_TARGET_HF_* must be > 1.0 (10000 bps)");
        require(
            c.lp != candidate && c.borrowers[0] != candidate && c.borrowers[1] != candidate,
            "SEED actors must not be the candidate account"
        );

        c.collUnits = collWhole * (10 ** IERC20Metadata(c.collateral).decimals());
    }

    /// @dev `from` supplies `amount` of `asset` (funded via cheatcode) as borrow-side liquidity.
    function _supplyAs(address asset, address from, uint256 amount) internal {
        deal(asset, from, amount);
        vm.startPrank(from);
        IERC20(asset).approve(address(pool), amount);
        pool.supply(asset, amount, from, 0);
        vm.stopPrank();
    }

    /// @dev `borrower` supplies `collUnits` of collateral and borrows `borrowAmt`; returns its HF.
    function _openPosition(
        address collateral,
        uint256 collUnits,
        address borrowAsset,
        address borrower,
        uint256 borrowAmt
    ) internal returns (uint256) {
        deal(collateral, borrower, collUnits);
        vm.startPrank(borrower);
        IERC20(collateral).approve(address(pool), collUnits);
        pool.supply(collateral, collUnits, borrower, 0);
        pool.setUserUseReserveAsCollateral(collateral, true);
        pool.borrow(borrowAsset, borrowAmt, 2, 0, borrower); // 2 = variable rate
        vm.stopPrank();
        return currentHf(borrower);
    }

    /// @notice Borrow amount (in borrowAsset units) that puts `collUnits` of `collateral` at
    ///         `targetHfBps`. Reads decimals, oracle prices, and the collateral's liquidation
    ///         threshold at runtime — assumes nothing about feed/token decimals.
    function _computeBorrowAmount(address collateral, uint256 collUnits, address borrowAsset, uint256 targetHfBps)
        internal
        view
        returns (uint256)
    {
        uint8 collDec = IERC20Metadata(collateral).decimals();
        uint256 pColl = oracle.getAssetPrice(collateral); // base-currency price (USD, 1e8)
        (, , uint256 ltBps,,,,,,,) = dataProvider.getReserveConfigurationData(collateral);
        require(ltBps > 0, "collateral has no liquidation threshold");

        uint256 collateralBase = collUnits * pColl / (10 ** collDec); // value in base currency
        uint256 targetDebtBase = collateralBase * ltBps / targetHfBps; // HF = collBase*LT / debtBase

        uint8 bDec = IERC20Metadata(borrowAsset).decimals();
        uint256 pBorrow = oracle.getAssetPrice(borrowAsset);
        require(pBorrow > 0, "borrow asset has no price");
        return targetDebtBase * (10 ** bDec) / pBorrow;
    }

    /// @notice Current health factor of `user` (1e18-scaled); type(uint256).max if no debt.
    function currentHf(address user) internal view returns (uint256 hf) {
        (,,,,, hf) = pool.getUserAccountData(user);
    }

    /// @notice Print each seeded position's CURRENT health factor — call before/after a change
    ///         (oracle swap, param tweak) to watch the book move.
    function logBook(string memory tag, PositionBook memory book) internal view {
        console.log(string.concat("  seed book [", tag, "]  HF (1e18), target(bps):"));
        for (uint256 i; i < book.positions.length; i++) {
            SeededPosition memory p = book.positions[i];
            console.log("   ", p.user, currentHf(p.user), p.targetHfBps);
        }
    }
}
