// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.5.13;

contract MockAggregatorV3 {
    int256 _answer;
    uint256 _updatedAt;

    function setRoundData(int256 answer, uint256 updatedAt) external {
        _answer = answer;
        _updatedAt = updatedAt;
    }

    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (
            uint80(0),
            _answer,
            uint256(0),
            _updatedAt,
            uint80(0)
        );
    }
}
