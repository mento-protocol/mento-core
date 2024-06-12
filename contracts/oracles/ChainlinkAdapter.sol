// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

import "../interfaces/IChainlinkAdapter.sol";
import "foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";

/**
 * @notice The minimal subset of the SortedOracles interface needed by the
 * adapter.
 * @dev SortedOracles is a Solidity 5.17 contract, thus we can't import the
 * interface directly, so we use a minimal hand-copied one.
 */
interface ISortedOraclesMin {
    function report(address token, uint256 value, address lesserKey, address greaterKey) external;
    function medianTimestamp(address token) external view returns (uint256);
    function getTokenReportExpirySeconds(address token) external view returns (uint256);
}

/**
 * @title ChainlinkAdapter
 * @notice The ChainlinkAdapter relays rate feed data from a Chainlink oracle to
 * the SortedOracles contract. A separate instance should be deployed for each
 * rate feed.
 * @dev Assumes that it itself is the only reporter for the given SortedOracles
 * feed.
 */
contract ChainlinkAdapter is IChainlinkAdapter {
    /// @notice The rateFeedId this adapter relays for.
    address immutable public token;
    /// @notice The address of the SortedOracles contract to report to.
    address immutable public sortedOracles;
    /**
     * @notice The address of the Chainlink aggregator this contract fetches
     * data from.
     */
    address immutable public aggregator;

    error OldTimestamp();
    error ExpiredTimestamp();
    error NegativeAnswer();

    constructor(address _token, address _sortedOracles, address _aggregator) {
        token = _token;
        sortedOracles = _sortedOracles;
        aggregator = _aggregator;
    }

    /**
     * @notice Relays data from the configured Chainlink aggregator to
     * SortedOracles.
     * @dev Checks the answer is non-negative (Chainlink uses `int256` rather
     * than `uint256`.
     * @dev Converts the answer to a Fixidity value, as expected by
     * SortedOracles.
     * @dev Performs checks on the timestamp, will revert if any fails:
     *      - The timestamp should be strictly newer than the most recent
     *      timestamp in SortedOracles.
     *      - The timestamp should not be considered expired by SortedOracles.
     */
    function relay() external {
        ISortedOraclesMin _sortedOracles = ISortedOraclesMin(sortedOracles);
        (, int256 answer,, uint256 timestamp,) = AggregatorV3Interface(aggregator).latestRoundData();

        uint256 lastTimestamp = _sortedOracles.medianTimestamp(token);

        if (lastTimestamp > 0) {
            if (timestamp <= lastTimestamp) {
                revert OldTimestamp();
            }

            if (isTimestampExpired(timestamp)) {
                revert ExpiredTimestamp();
            }
        }

        if (answer < 0) {
            revert NegativeAnswer();
        }

        // TODO: convert answer to Fixidity

        ISortedOraclesMin(sortedOracles).report(token, uint256(answer), address(0), address(0));
    }

    function isTimestampExpired(uint256 timestamp) internal view returns (bool) {
        return block.timestamp - timestamp >= ISortedOraclesMin(sortedOracles).getTokenReportExpirySeconds(token);
    }
}
