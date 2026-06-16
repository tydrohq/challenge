// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ForkBase} from "../ForkBase.sol";
import {MockERC20} from "../../src/harness/MockERC20.sol";
import {BetterOracle} from "../../src/harness/BetterOracle.sol";
import {ListingHelper, ListingParams} from "../../src/harness/ListingHelper.sol";
import {InterestRateData} from "../../src/interfaces/IAaveV3.sol";

/// @notice TASK 3 — List a brand-new market.
///
///   Run:  forge script script/tasks/03_ListMarket.s.sol
///
///   The plumbing (initReserves with Tydro's exact token impls, oracle wiring, etc.) is done
///   for you by `ListingHelper.listMarket`. Your job is to CHOOSE and justify the
///   `ListingParams` — that's the signal. You do not re-implement initReserves.
contract ListMarket is Script, ForkBase {
    using ListingHelper for ListingHelper.Wiring;

    function run() external {
        createForkAndLoad();
        grantRolesPranked(candidate);

        vm.startPrank(candidate);

        // Test token + price source are provided for you:
        MockERC20 asset = new MockERC20("Demo Token", "DEMO", 18);
        BetterOracle source = new BetterOracle(1e8, 8); // $1.00

        // ================= TODO(candidate) =================
        // Asset: DEMO is a brand-new, thinly-traded token being listed for the first time.
        // In volatility terms, treat it as comparable to a small-cap memecoin (PEPE-class
        // price swings). Choose and justify the full ListingParams below.
        ListingParams memory params = ListingParams({
            ltv: 0, // TODO
            liquidationThreshold: 0, // TODO
            liquidationBonus: 0, // TODO  (>10000, e.g. 10800 = 8% bonus)
            reserveFactor: 0, // TODO
            supplyCap: 0, // TODO  (whole tokens; 0 = unlimited)
            borrowCap: 0, // TODO
            borrowingEnabled: false, // TODO
            irParams: InterestRateData({ // TODO: the rate curve (bps)
                optimalUsageRatio: 0,
                baseVariableBorrowRate: 0,
                variableRateSlope1: 0,
                variableRateSlope2: 0
            })
        });

        // listingWiring() uses WETH as the reference reserve to clone token impls from.
        listingWiring().listMarket(address(asset), address(source), params);
        // ===================================================

        vm.stopPrank();

        (, uint256 ltv, uint256 lt, uint256 bonus,,,,,,) =
            dataProvider.getReserveConfigurationData(address(asset));
        console.log("listed              ", address(asset));
        console.log("source              ", oracle.getSourceOfAsset(address(asset)));
        console.log("price               ", oracle.getAssetPrice(address(asset)));
        console.log("ltv/lt/bonus        ", ltv, lt, bonus);
    }
}
