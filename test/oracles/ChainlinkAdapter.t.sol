// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import "../utils/BaseTest.t.sol";
import "contracts/common/SortedOracles.sol";
import "../mocks/MockAggregatorV3.sol";
import "contracts/interfaces/IChainlinkAdapter.sol";

contract ChainlinkAdapterTest is BaseTest {
    bytes constant OLD_TIMESTAMP_ERROR =
        abi.encodeWithSignature("OldTimestamp()");
    bytes constant EXPIRED_TIMESTAMP_ERROR =
        abi.encodeWithSignature("ExpiredTimestamp()");
    bytes constant NEGATIVE_ANSWER_ERROR =
        abi.encodeWithSignature("NegativeAnswer()");
    SortedOracles sortedOracles;
    MockAggregatorV3 aggregator;
    IChainlinkAdapter adapter;
    address token = address(0xbeef);

    function setUp() public {
        sortedOracles = new SortedOracles(true);
        aggregator = new MockAggregatorV3();
        adapter = IChainlinkAdapter(
            factory.createContract(
                "ChainlinkAdapter",
                abi.encode(token, address(sortedOracles), address(aggregator))
            )
        );
        sortedOracles.addOracle(token, address(adapter));
    }
}

contract ChainlinkAdapterTest_constructor is ChainlinkAdapterTest {
    function test_constructorSetsToken() public {
        address _token = adapter.token();
        assertEq(_token, token);
    }

    function test_constructorSetsSortedOracles() public {
        address _sortedOracles = adapter.sortedOracles();
        assertEq(_sortedOracles, address(sortedOracles));
    }

    function test_constructorSetsAggregator() public {
        address _aggregator = adapter.aggregator();
        assertEq(_aggregator, address(aggregator));
    }
}

contract ChainlinkAdapterTest_relay is ChainlinkAdapterTest {
    function setUp() public {
        super.setUp();
        aggregator.setRoundData(int256(42), uint256(block.timestamp));
    }

    // TODO: should actually ingest an 8-decimals value and relay a Fixidity
    // value
    function test_relaysTheRate() public {
        adapter.relay();
        (uint256 medianRate,) = sortedOracles.medianRate(token);
        assertEq(medianRate, 42);
    }

    function test_revertsOnNegativeAnswer() public {
        aggregator.setRoundData(-42, uint256(1337));
        vm.expectRevert(NEGATIVE_ANSWER_ERROR);
        adapter.relay();
    }

    function test_revertsOnEarlierTimestamp() public {
        vm.prank(address(adapter));
        sortedOracles.report(token, 41, address(0), address(0));
        uint256 latestTimestamp = sortedOracles.medianTimestamp(token);
        aggregator.setRoundData(42, latestTimestamp - 1);
        vm.expectRevert(OLD_TIMESTAMP_ERROR);
        adapter.relay();
    }

    function test_revertsOnRepeatTimestamp() public {
        vm.prank(address(adapter));
        sortedOracles.report(token, 41, address(0), address(0));
        uint256 latestTimestamp = sortedOracles.medianTimestamp(token);
        aggregator.setRoundData(42, latestTimestamp);
        vm.expectRevert(OLD_TIMESTAMP_ERROR);
        adapter.relay();
    }

    function test_revertsOnExpiredTimestamp() public {
        vm.prank(address(adapter));
        sortedOracles.report(token, 41, address(0), address(0));
        uint256 expiry = sortedOracles.getTokenReportExpirySeconds(token);
        aggregator.setRoundData(42, block.timestamp + 1);
        vm.warp(block.timestamp + expiry + 1);
        vm.expectRevert(EXPIRED_TIMESTAMP_ERROR);
        adapter.relay();
    }
}
