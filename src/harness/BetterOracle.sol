// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title BetterOracle
/// @notice A clear, settable Chainlink-style price feed for the harness. Named for the
///         Task-1 story ("migrate WETH onto a better oracle"); also used as the price source
///         for any newly listed market. Prices are denominated in USD at 8 decimals to match
///         Aave's base currency (BASE_CURRENCY_UNIT == 1e8 on Tydro). The hiring team /
///         candidate can move the price at runtime via {setAnswer} to exercise depeg /
///         oracle-migration / price-shock scenarios.
contract BetterOracle {
    int256 private _answer;
    uint8 public immutable decimals;

    event AnswerUpdated(int256 indexed current);

    /// @param answer_ initial price, 8-decimal USD (e.g. 2000e8 == $2000.00).
    /// @param decimals_ feed decimals; pass 8 to match Aave base currency.
    constructor(int256 answer_, uint8 decimals_) {
        _answer = answer_;
        decimals = decimals_;
    }

    /// @notice Latest price, 8-decimal USD. This is what AaveOracle reads.
    function latestAnswer() external view returns (int256) {
        return _answer;
    }

    /// @notice Full Chainlink round struct, in case any consumer reads it.
    ///         roundId and answeredInRound are stubbed to 0.
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, _answer, block.timestamp, block.timestamp, 0);
    }

    /// @notice Move the price (8-decimal USD). Used to simulate price changes / depegs.
    function setAnswer(int256 answer_) external {
        _answer = answer_;
        emit AnswerUpdated(answer_);
    }
}
