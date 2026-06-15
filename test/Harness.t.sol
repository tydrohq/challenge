// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ForkBase} from "../script/ForkBase.sol";

/// @notice Proves the harness itself works: the fork loads, contracts derive from the
///         provider, and the candidate EOA can make an admin-gated write without reverting
///         (the single most important UX requirement) while a non-admin cannot.
contract HarnessTest is Test, ForkBase {
    function setUp() public {
        createForkAndLoad();
        grantRolesPranked(candidate);
    }

    function test_ForkLoadedAndDerived() public view {
        assertEq(oracle.BASE_CURRENCY_UNIT(), 1e8, "base currency should be USD 1e8");
        assertGt(pool.getReservesList().length, 0, "reserves should be populated");
        assertTrue(address(configurator) != address(0) && address(acl) != address(0));
    }

    function test_CandidateCanCallAdminGatedFn() public {
        // setSupplyCap is pool-admin gated; the candidate holds the role after setup.
        vm.prank(candidate);
        configurator.setSupplyCap(oracleMigrationTarget, 90_000);
        (, uint256 supplyCap) = _caps(oracleMigrationTarget);
        assertEq(supplyCap, 90_000, "admin write should take effect");
    }

    function test_NonAdminCannotCallAdminGatedFn() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        configurator.setSupplyCap(oracleMigrationTarget, 90_000);
    }

    function _caps(address asset) internal view returns (uint256 borrowCap, uint256 supplyCap) {
        (bool ok, bytes memory data) = address(dataProvider).staticcall(
            abi.encodeWithSignature("getReserveCaps(address)", asset)
        );
        require(ok, "getReserveCaps failed");
        (borrowCap, supplyCap) = abi.decode(data, (uint256, uint256));
    }
}
