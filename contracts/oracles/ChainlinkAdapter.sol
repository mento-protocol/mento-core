// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

import "../interfaces/IChainlinkAdapter.sol";
import "foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";

interface ISortedOraclesMin {
    function report(address token, uint256 value, address lesserKey, address greaterKey) external;
    function medianTimestamp(address token) external view returns (uint256);
}

contract ChainlinkAdapter is IChainlinkAdapter {
    address immutable public token;
    address immutable public sortedOracles;
    address immutable public aggregator;

    constructor(address _token, address _sortedOracles, address _aggregator) {
        token = _token;
        sortedOracles = _sortedOracles;
        aggregator = _aggregator;
    }

    function relay() external {
        (, int256 answer,, uint256 timestamp,) = AggregatorV3Interface(aggregator).latestRoundData();

        // TODO: checks:
        // - timestamp is > than current
        // - timestamp is fresh enough?
        // - answer is not negative

        // TODO: convert answer to Fixidity

        ISortedOraclesMin(sortedOracles).report(token, uint256(answer), address(0), address(0));
    }
}
