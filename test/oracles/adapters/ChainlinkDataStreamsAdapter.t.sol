// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8.19;

import { Test } from "mento-std/Test.sol";

import { MockVerifierProxy } from "test/utils/mocks/MockVerifierProxy.sol";
import { ChainlinkDataStreamsAdapter } from "contracts/oracles/adapters/ChainlinkDataStreamsAdapter.sol";

/// @notice Direct tests for the adapter's interface contract (provider id, fee handling,
///         normalization). The decode/binding paths (V3/V8 slots, WrongFeedId, UnsupportedSchema,
///         ReportTooShort, InvalidPrice) are exercised end-to-end via the relayer test suite.
contract ChainlinkDataStreamsAdapterTest is Test {
  MockVerifierProxy verifierProxy;
  ChainlinkDataStreamsAdapter adapter;

  bytes32 feedIdV3 = 0x0003000000000000000000000000000000000000000000000000000000000001;

  function setUp() public {
    vm.warp(100_000);
    verifierProxy = new MockVerifierProxy();
    adapter = new ChainlinkDataStreamsAdapter(address(verifierProxy));
  }

  function _v3Report(bytes32 feedId, int192 price) internal view returns (bytes memory) {
    return
      abi.encode(
        feedId,
        uint32(0),
        uint32(block.timestamp),
        uint192(0),
        uint192(0),
        uint32(block.timestamp + 1000),
        price,
        int192(0),
        int192(0)
      );
  }

  function _updateData(bytes memory report) internal pure returns (bytes memory) {
    bytes[] memory reports = new bytes[](1);
    reports[0] = report;
    return abi.encode(reports);
  }

  function test_provider() public view {
    assertEq(adapter.provider(), bytes32("chainlink-data-streams"));
  }

  function test_verificationFee_isZero() public view {
    assertEq(adapter.verificationFee(hex"deadbeef"), 0);
  }

  function test_verify_returnsNormalizedArrays() public {
    bytes32[] memory feedIds = new bytes32[](1);
    feedIds[0] = feedIdV3;
    int192 price = 5e17;

    (uint256[] memory prices, uint256[] memory obsTs, uint256[] memory expiries) = adapter.verify(
      feedIds,
      _updateData(_v3Report(feedIdV3, price))
    );

    assertEq(prices.length, 1);
    assertEq(prices[0], uint256(uint192(price)));
    assertEq(obsTs[0], block.timestamp);
    assertEq(expiries[0], block.timestamp + 1000);
  }

  function test_verify_revertsOnNonZeroValue() public {
    bytes32[] memory feedIds = new bytes32[](1);
    feedIds[0] = feedIdV3;
    bytes memory updateData = _updateData(_v3Report(feedIdV3, 5e17));

    vm.deal(address(this), 1 ether);
    vm.expectRevert(abi.encodeWithSignature("UnexpectedFee()"));
    adapter.verify{ value: 1 }(feedIds, updateData);
  }

  function test_verify_revertsOnLegCountMismatch() public {
    bytes32[] memory feedIds = new bytes32[](2);
    feedIds[0] = feedIdV3;
    feedIds[1] = feedIdV3;

    vm.expectRevert(abi.encodeWithSignature("LegCountMismatch()"));
    adapter.verify(feedIds, _updateData(_v3Report(feedIdV3, 5e17))); // 1 report for 2 feeds
  }
}
