// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ForkBase} from "./ForkBase.sol";
import {MockERC20} from "../src/harness/MockERC20.sol";
import {BetterOracle} from "../src/harness/BetterOracle.sol";
import {MockSwapRouter} from "../src/harness/MockSwapRouter.sol";

/// @notice Deploys the harness mocks against a running anvil fork and prints their
///         addresses. Roles are granted to the candidate EOA by `script/setup.sh` (live
///         anvil, via cast impersonation) or by ForkBase in tests.
///
///         One-command live setup:  `./script/setup.sh`
///         (which starts anvil, grants roles, then runs this script).
///
///         Deploys:
///           - DEMO  : MockERC20 (18 dec) — underlying for the new market + vault base asset
///           - DEMO  : BetterOracle @ $1.00 — price source for the new market
///           - MIGR  : BetterOracle @ $2000  — candidate's replacement source for Task 1
///           - swap  : MockSwapRouter — oracle-priced base<->WETH swap for the vault split
contract DeployHarness is Script, ForkBase {
    function run() external {
        loadAddresses(); // anvil is already the fork; do not createSelectFork here

        vm.startBroadcast();

        MockERC20 demo = new MockERC20("Demo Token", "DEMO", 18);
        BetterOracle demoSource = new BetterOracle(1e8, 8); // $1.00, 8-dec USD
        BetterOracle migrationSource = new BetterOracle(2000e8, 8); // $2000.00 placeholder for Task 1
        MockSwapRouter router = new MockSwapRouter(oracle);

        vm.stopBroadcast();

        console.log("=== Harness deployed ===");
        console.log("candidate EOA          ", candidate);
        console.log("MockERC20 (DEMO)       ", address(demo));
        console.log("BetterOracle (DEMO src)", address(demoSource));
        console.log("BetterOracle (MIGR src)", address(migrationSource));
        console.log("MockSwapRouter         ", address(router));
        console.log("");
        console.log("oracleMigrationTarget  ", oracleMigrationTarget);
        console.log("(roles granted to candidate by setup.sh / ForkBase)");
    }
}
