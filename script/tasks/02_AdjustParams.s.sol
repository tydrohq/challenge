// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ForkBase} from "../ForkBase.sol";

/// @notice TASK 2 — Adjust the risk parameters of an existing reserve (`oracleMigrationTarget`).
///
///   Run:  forge script script/tasks/02_AdjustParams.s.sol
///
///   Decide new collateral parameters and at least one cap, apply them via the configurator,
///   and verify. Think about which levers are safe to move and which can force liquidations.
contract AdjustParams is Script, ForkBase {
    function run() external {
        createForkAndLoad();
        grantRolesPranked(candidate);

        address asset = oracleMigrationTarget;
        _print("before", asset);

        vm.startPrank(candidate);
        // ================= TODO(candidate) =================
        // Choose and justify new params, then apply. Available configurator calls:
        //   configurator.configureReserveAsCollateral(asset, ltv, liqThreshold, liqBonus);
        //   configurator.setReserveFactor(asset, bps);
        //   configurator.setSupplyCap(asset, wholeTokens);   // 0 = no cap
        //   configurator.setBorrowCap(asset, wholeTokens);
        //   configurator.setReserveBorrowing(asset, bool);
        // Invariant to preserve: ltv <= liquidationThreshold.
        // ===================================================
        vm.stopPrank();

        _print("after", asset);
    }

    function _print(string memory tag, address asset) internal view {
        (, uint256 ltv, uint256 lt, uint256 bonus, uint256 rf,,,,,) =
            dataProvider.getReserveConfigurationData(asset);
        console.log(string.concat("[", tag, "] ltv/lt/bonus/rf:"), ltv, lt, bonus);
        console.log("                rf:", rf);
    }
}
