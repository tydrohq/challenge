// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CommonBase} from "forge-std/Base.sol";
import {stdJson} from "forge-std/StdJson.sol";
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
///         derives all Tydro contracts from the single PoolAddressesProvider, and grants
///         the candidate EOA the ACL roles it needs so every admin-gated write "just works".
///
///         Inherits only CommonBase (which provides `vm`) so it composes with both
///         forge-std Script and Test via the shared base.
abstract contract ForkBase is CommonBase {
    using stdJson for string;

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
}
