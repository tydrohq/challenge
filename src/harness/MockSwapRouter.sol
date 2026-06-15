// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAaveOracle} from "../interfaces/IAaveV3.sol";

/// @title MockSwapRouter
/// @notice Oracle-priced spot swap for the harness: exchanges one token for another at the
///         Aave oracle price, with no fee and no slippage. Assumes both tokens are
///         18-decimals, and must be pre-funded with inventory of the token it pays out.
contract MockSwapRouter {
    using SafeERC20 for IERC20;

    IAaveOracle public immutable oracle;

    constructor(IAaveOracle _oracle) {
        oracle = _oracle;
    }

    /// @notice Quote: how much `tokenOut` for `amountIn` of `tokenIn`, at oracle mid-price.
    ///         Both tokens assumed 18-dec; oracle prices are 8-dec USD and cancel.
    function quote(address tokenIn, address tokenOut, uint256 amountIn) public view returns (uint256) {
        uint256 pIn = oracle.getAssetPrice(tokenIn);
        uint256 pOut = oracle.getAssetPrice(tokenOut);
        require(pIn > 0 && pOut > 0, "no price");
        return (amountIn * pIn) / pOut;
    }

    /// @notice Swap `amountIn` of `tokenIn` for `tokenOut` at the oracle price.
    ///         Pulls `tokenIn` from caller, sends `tokenOut` from inventory.
    function swapExactIn(address tokenIn, address tokenOut, uint256 amountIn)
        external
        returns (uint256 amountOut)
    {
        amountOut = quote(tokenIn, tokenOut, amountIn);
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
    }
}
