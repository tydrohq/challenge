// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockERC20
/// @notice Mintable test token used as the underlying for the new market (and as the
///         vault's base asset). Decimals are configurable; the harness uses 18 to avoid
///         incidental 6-decimal complexity.
contract MockERC20 is ERC20 {
    uint8 private immutable _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @notice Open mint — test token only.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
