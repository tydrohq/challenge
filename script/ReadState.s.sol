// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ForkBase} from "./ForkBase.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @notice Launch sanity check: prints the reserve list and, per asset, its symbol, price
///         source, oracle price, and key config. Proves the fork + derivation work before a
///         candidate starts. Run: `forge script script/ReadState.s.sol`.
contract ReadState is Script, ForkBase {
    function run() external {
        createForkAndLoad();

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
    }

    function _symbol(address token) internal view returns (string memory) {
        try IERC20Metadata(token).symbol() returns (string memory s) {
            return s;
        } catch {
            return "?";
        }
    }
}
