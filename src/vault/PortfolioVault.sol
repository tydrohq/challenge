// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626, ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPool, IAaveOracle} from "../interfaces/IAaveV3.sol";
import {MockSwapRouter} from "../harness/MockSwapRouter.sol";

/// @title PortfolioVault (STARTER — implement the TODOs)
/// @notice An ERC-4626 vault that holds a fixed-weight portfolio split across TWO Tydro
///         markets: the base-asset market (underlying == `asset()`) and the WETH market.
///         `targetWeightBBps` is the target share of portfolio VALUE held in the WETH leg
///         (e.g. 7500 = 75% WETH / 25% base). The vault holds two aTokens; share value is
///         expressed in the base asset.
///
/// @dev The harness gives you everything you need:
///        - `pool`     : supply()/withdraw() the two underlyings
///        - `oracle`   : getAssetPrice(asset) — 8-decimal USD
///        - `router`   : swapExactIn(tokenIn, tokenOut, amountIn) at the oracle price
///        - `aTokenA`  : aToken of the base market   (balanceOf == base units held)
///        - `aTokenB`  : aToken of the WETH market    (balanceOf == WETH units held)
///        All underlyings and shares are 18-decimals; the oracle is 8-decimals USD.
///
///      Implement: {totalAssets}, {_deposit}, {_withdraw}. Approvals are wired in the
///      constructor.
contract PortfolioVault is ERC4626, Ownable {
    using SafeERC20 for IERC20;

    uint256 internal constant BPS = 10_000;

    IPool public immutable pool;
    IAaveOracle public immutable oracle;
    MockSwapRouter public immutable router;

    address public immutable underlyingB; // WETH (second market underlying)
    IERC20 public immutable aTokenA; // aToken of the base-asset market
    IERC20 public immutable aTokenB; // aToken of the WETH market

    /// @notice Target weight (bps) of portfolio VALUE held in the WETH leg. 7500 = 75%.
    uint256 public immutable targetWeightBBps;

    constructor(
        IERC20 base,
        IPool _pool,
        IAaveOracle _oracle,
        MockSwapRouter _router,
        address _underlyingB,
        IERC20 _aTokenA,
        IERC20 _aTokenB,
        uint256 _targetWeightBBps
    ) ERC4626(base) ERC20("Tydro Portfolio Vault", "tPV") Ownable(msg.sender) {
        require(_targetWeightBBps <= BPS, "weight>100%");
        pool = _pool;
        oracle = _oracle;
        router = _router;
        underlyingB = _underlyingB;
        aTokenA = _aTokenA;
        aTokenB = _aTokenB;
        targetWeightBBps = _targetWeightBBps;

        IERC20(asset()).forceApprove(address(_pool), type(uint256).max);
        IERC20(asset()).forceApprove(address(_router), type(uint256).max);
        IERC20(_underlyingB).forceApprove(address(_pool), type(uint256).max);
        IERC20(_underlyingB).forceApprove(address(_router), type(uint256).max);
    }

    /// @notice Total portfolio value, expressed in units of `asset()`.
    /// @dev TODO: sum the two aToken positions in base-asset terms. The base leg is 1:1;
    ///      the WETH leg must be converted to base using the oracle.
    function totalAssets() public view override returns (uint256) {
        // TODO(candidate): implement.
        revert("TODO: totalAssets");
    }

    /// @dev TODO: after pulling the deposited base + minting shares (call super first),
    ///      allocate the deposit across the two markets according to `targetWeightBBps`.
    ///      Remember the WETH leg has a different underlying than what was deposited.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        super._deposit(caller, receiver, assets, shares);
        // TODO(candidate): split `assets` across the base market and the WETH market.
        revert("TODO: _deposit allocation");
    }

    /// @dev TODO: source `assets` of base from the two legs (you'll need to unwind the WETH
    ///      leg back into the base asset), then call super to burn shares + pay the receiver.
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        // TODO(candidate): produce `assets` of base from the two markets here.
        revert("TODO: _withdraw unwind");
        // super._withdraw(caller, receiver, owner, assets, shares);
    }
}
