// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ForkBase} from "../ForkBase.sol";
import {BetterOracle} from "../../src/harness/BetterOracle.sol";

/// @notice TASK 1 — Migrate the oracle for `oracleMigrationTarget` (the WETH market).
///
///   Run (simulation against the fork):
///     forge script script/tasks/01_MigrateOracle.s.sol
///
///   The harness has already: forked Tydro, granted you (account 0) every ACL role, and
///   derived `oracle` / `pool` / etc. from the provider. You act as `candidate`.
///
///   Your job is the JUDGMENT, not the plumbing:
///     - choose the new price source and the price it should report;
///     - repoint the asset's source on the Aave oracle;
///     - convince yourself the new price actually flows into risk accounting.
contract MigrateOracle is Script, ForkBase {
    function run() external {
        createForkAndLoad();
        grantRolesPranked(candidate);

        // Seeded positions collateralized by `target` — watch their HF recompute below.
        PositionBook memory book = seedPositionBook();

        address target = oracleMigrationTarget;
        console.log("target              ", target);
        console.log("source (before)     ", oracle.getSourceOfAsset(target));
        console.log("price  (before)     ", oracle.getAssetPrice(target));
        logBook("before", book);

        vm.startPrank(candidate);
        // ================= TODO(candidate) =================
        // 1. Deploy a BetterOracle price source for `target`.
        //      Decision: what price (8-dec USD) should it report, and why?
        //      e.g. BetterOracle src = new BetterOracle(<priceE8>, 8);
        //
        // 2. Repoint the Aave oracle at your source:
        //      address[] memory assets  = new address[](1); assets[0]  = target;
        //      address[] memory sources = new address[](1); sources[0] = address(src);
        //      oracle.setAssetSources(assets, sources);
        // ===================================================
        vm.stopPrank();

        console.log("source (after)      ", oracle.getSourceOfAsset(target));
        console.log("price  (after)      ", oracle.getAssetPrice(target));
        logBook("after", book);
        // The seeded book above is your proof that the price feeds RISK, not just storage:
        // a clean (price-continuous) migration leaves every HF unchanged, while a mispriced or
        // wrong-decimals feed moves them. Drop your new feed's price to watch HFs fall.
    }
}
