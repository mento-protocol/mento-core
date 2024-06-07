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
        aggregator.setRoundData(int256(42), uint256(1337));
    }

    // TODO: should actually ingest an 8-decimals value and relay a Fixidity
    // value
    function test_relaysTheRate() public {
        adapter.relay();
        (uint256 medianRate,) = sortedOracles.medianRate(token);
        assertEq(medianRate, 42);
    }

    // TODO: negative cases:
    // - negative int answer
    // - same timestamp
    // - earlier timestamp
    // - expired timestamp (but greater than latest)
}
