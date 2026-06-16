// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ForkBase} from "./ForkBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @notice Launch sanity check: prints the reserve list and, per asset, its symbol, price
///         source, oracle price, and key config; then seeds the deterministic position book
///         and prints, for the target market, its available liquidity / caps+usage and the
///         health factor of each seeded position. Proves the fork + derivation + seeded book
///         all work before a candidate starts. Run: `forge script script/ReadState.s.sol`.
contract ReadState is Script, ForkBase {
    function run() external {
        createForkAndLoad();
        PositionBook memory book = seedPositionBook();

        console.log("=== Tydro fork state ===");
        console.log("provider     ", address(provider));
        console.log("pool         ", address(pool));
        console.log("configurator ", address(configurator));
        console.log("oracle       ", address(oracle));
        console.log("aclManager   ", address(acl));
        console.log("aclAdmin     ", aclAdmin);
        console.log("baseCurrency unit (expect 1e8):", oracle.BASE_CURRENCY_UNIT());
        console.log("");

        address[] memory reserves = pool.getReservesList();
        console.log("reserves:", reserves.length);
        for (uint256 i = 0; i < reserves.length; i++) {
            address a = reserves[i];
            string memory sym = _symbol(a);
            (
                uint256 decimals,
                uint256 ltv,
                uint256 lt,
                uint256 bonus,
                uint256 rf,
                bool collateral,
                bool borrowing,
                ,
                bool active,
                bool frozen
            ) = dataProvider.getReserveConfigurationData(a);
            console.log("--------------------------------------------------");
            console.log(string.concat("[", sym, "] "), a);
            console.log("  source ", oracle.getSourceOfAsset(a));
            console.log("  price  ", oracle.getAssetPrice(a));
            console.log("  dec/ltv/lt/bonus/rf:", decimals, ltv, lt);
            console.log("                       ", bonus, rf);
            console.log("  collateral/borrow/active/frozen:", collateral, borrowing, active);
            console.log("                                   ", frozen);
        }

        _printTargetMarket(book);
    }

    /// @notice §3b — target-market depth + the seeded book, so "why does my borrow revert" is a
    ///         5-second read and the candidate can watch the book move before/after a change.
    function _printTargetMarket(PositionBook memory book) internal view {
        address t = oracleMigrationTarget;
        console.log("==================================================");
        console.log(string.concat("=== Target market [", _symbol(t), "] depth ==="), t);
        _printDepth(t);

        console.log("=== Seed book ===");
        console.log(string.concat("  borrow asset [", _symbol(book.borrowAsset), "] depth:"), book.borrowAsset);
        _printDepth(book.borrowAsset);
        console.log("  LP / liquidity supplied:", book.lp, book.lpLiquidity);
        logBook("seeded", book);
    }

    /// @dev Available underlying liquidity + supply/borrow caps vs. current usage (whole tokens).
    function _printDepth(address asset) internal view {
        (address aToken,, address vDebt) = dataProvider.getReserveTokensAddresses(asset);
        uint256 unit = 10 ** IERC20Metadata(asset).decimals();
        (uint256 borrowCap, uint256 supplyCap) = _caps(asset);
        console.log("    available liquidity (underlying):", IERC20(asset).balanceOf(aToken));
        console.log("    supplyCap / supplied (whole):", supplyCap, IERC20(aToken).totalSupply() / unit);
        console.log("    borrowCap / borrowed (whole):", borrowCap, IERC20(vDebt).totalSupply() / unit);
    }

    /// @dev getReserveCaps(asset) -> (borrowCap, supplyCap); not in the trimmed interface.
    function _caps(address asset) internal view returns (uint256 borrowCap, uint256 supplyCap) {
        (bool ok, bytes memory data) =
            address(dataProvider).staticcall(abi.encodeWithSignature("getReserveCaps(address)", asset));
        require(ok, "getReserveCaps failed");
        (borrowCap, supplyCap) = abi.decode(data, (uint256, uint256));
    }

    function _symbol(address token) internal view returns (string memory) {
        try IERC20Metadata(token).symbol() returns (string memory s) {
            return s;
        } catch {
            return "?";
        }
    }
}
