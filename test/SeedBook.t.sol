// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ForkBase} from "../script/ForkBase.sol";

/// @notice Proves the seeded position book is real, deterministic, and risk-meaningful:
///         positions land at their target HFs (all > 1), borrow-side liquidity exists, and
///         the book reacts to parameter changes the way Task 2 expects — lowering LTV leaves
///         every position untouched, while lowering the liquidation threshold pushes the
///         near-edge position underwater.
contract SeedBookTest is Test, ForkBase {
    // Flattened from the seeded book (storing the struct-with-dynamic-array directly isn't
    // supported by Solidity; setUp's state carries into every test).
    uint256 internal posCount;
    address internal borrower0;
    address internal borrower1;
    uint256 internal hf0;
    uint256 internal hf1;
    uint256 internal target0;
    uint256 internal target1;
    address internal lp;
    address internal borrowAsset;
    uint256 internal lpLiquidity;

    function setUp() public {
        createForkAndLoad();
        grantRolesPranked(candidate); // for the configurator calls below
        PositionBook memory book = seedPositionBook();

        posCount = book.positions.length;
        borrower0 = book.positions[0].user;
        borrower1 = book.positions[1].user;
        hf0 = book.positions[0].healthFactor;
        hf1 = book.positions[1].healthFactor;
        target0 = book.positions[0].targetHfBps;
        target1 = book.positions[1].targetHfBps;
        lp = book.lp;
        borrowAsset = book.borrowAsset;
        lpLiquidity = book.lpLiquidity;
    }

    function test_SeededHfsLandAtTargetsAndAboveOne() public view {
        assertEq(posCount, 2, "two seeded positions");
        // HF target is bps (20000 = 2.0); realized HF is 1e18-scaled (bps * 1e14). Allow 3%
        // for the borrow asset trading slightly off $1 and integer rounding.
        assertGt(hf0, 1e18, "comfortable position solvent");
        assertGt(hf1, 1e18, "near-edge position solvent");
        assertApproxEqRel(hf0, target0 * 1e14, 3e16, "position 0 HF near target");
        assertApproxEqRel(hf1, target1 * 1e14, 3e16, "position 1 HF near target");
        assertGt(hf0, hf1, "a spread, not a clone: position 0 safer than 1");
    }

    function test_BorrowSideLiquidityWasSeeded() public view {
        assertGt(lpLiquidity, 0, "LP supplied borrow-side liquidity");
        assertTrue(borrowAsset != address(0) && lp != candidate, "dedicated LP, real borrow asset");
    }

    function test_LoweringLtvLeavesPositionsUntouched() public {
        (, , uint256 lt0, uint256 bonus0,,,,,,) = dataProvider.getReserveConfigurationData(oracleMigrationTarget);

        // LTV 80% -> 75%, LT and bonus unchanged.
        vm.prank(candidate);
        configurator.configureReserveAsCollateral(oracleMigrationTarget, 7500, lt0, bonus0);

        // LTV is not in the HF formula, so existing positions do not move at all.
        assertEq(currentHf(borrower0), hf0, "comfortable position unchanged by LTV cut");
        assertEq(currentHf(borrower1), hf1, "near-edge position unchanged by LTV cut");
    }

    function test_LoweringLtPushesNearEdgePositionUnderwater() public {
        (, , , uint256 bonus0,,,,,,) = dataProvider.getReserveConfigurationData(oracleMigrationTarget);

        // The dangerous lever: drop LTV+LT to 70% (LT must stay >= LTV). Re-rates open
        // positions immediately.
        vm.prank(candidate);
        configurator.configureReserveAsCollateral(oracleMigrationTarget, 7000, 7000, bonus0);

        assertLt(currentHf(borrower1), 1e18, "near-edge (HF~1.15) position now liquidatable");
        assertGt(currentHf(borrower0), 1e18, "comfortable (HF~2.0) position still solvent");
    }
}
