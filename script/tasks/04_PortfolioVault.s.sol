// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ForkBase} from "../ForkBase.sol";
import {MockERC20} from "../../src/harness/MockERC20.sol";
import {BetterOracle} from "../../src/harness/BetterOracle.sol";
import {MockSwapRouter} from "../../src/harness/MockSwapRouter.sol";
import {ListingHelper, ListingParams} from "../../src/harness/ListingHelper.sol";
import {InterestRateData} from "../../src/interfaces/IAaveV3.sol";
import {PortfolioVault} from "../../src/vault/PortfolioVault.sol";

/// @notice TASK 4 — Implement + exercise the ERC-4626 PortfolioVault.
///
///   First implement the TODOs in src/vault/PortfolioVault.sol, then use this script to
///   deploy and smoke-test it: deposit, check the split across the two markets, redeem,
///   and confirm totalAssets() responds to an oracle move.
///
///   Run:  forge script script/tasks/04_PortfolioVault.s.sol
///
///   This stub wires up the prerequisites (a base market + the WETH market + a funded swap
///   router). Implement the vault and the assertions/log lines marked TODO.
contract DeployVault is Script, ForkBase {
    using ListingHelper for ListingHelper.Wiring;

    function run() external {
        createForkAndLoad();
        grantRolesPranked(candidate);

        vm.startPrank(candidate);

        // --- prerequisites: a base-asset market (DEMO) you can deposit into ---
        MockERC20 base = new MockERC20("Demo Token", "DEMO", 18);
        BetterOracle baseSrc = new BetterOracle(1e8, 8); // $1.00
        ListingParams memory p = ListingParams({
            ltv: 7000,
            liquidationThreshold: 7500,
            liquidationBonus: 10800,
            reserveFactor: 1500,
            supplyCap: 100_000_000,
            borrowCap: 50_000_000,
            borrowingEnabled: true,
            irParams: InterestRateData(8000, 0, 400, 7500)
        });
        listingWiring().listMarket(address(base), address(baseSrc), p);
        (address aBase,,) = dataProvider.getReserveTokensAddresses(address(base));
        (address aWeth,,) = dataProvider.getReserveTokensAddresses(oracleMigrationTarget);

        // --- swap router (oracle-priced), pre-funded so it can pay out both legs ---
        MockSwapRouter router = new MockSwapRouter(oracle);
        base.mint(address(router), 1_000_000e18);
        // (WETH inventory: in a real run, wrap ETH and transfer to the router.)

        // ================= TODO(candidate) =================
        // 1. Deploy the vault with your chosen split, e.g. 75% WETH / 25% base:
        //      PortfolioVault vault = new PortfolioVault(
        //          IERC20(address(base)), pool, oracle, router,
        //          oracleMigrationTarget, IERC20(aBase), IERC20(aWeth), 7500);
        //
        // 2. Deposit and verify the realized split across market A (base) and market B (WETH).
        // 3. Redeem and confirm the round-trip is within tolerance.
        // 4. Move the WETH price source and confirm totalAssets() tracks it.
        // ===================================================

        vm.stopPrank();
        console.log("aBase / aWeth        ", aBase, aWeth);
        console.log("router               ", address(router));
    }
}
