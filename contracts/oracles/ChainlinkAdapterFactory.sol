// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

import "./ChainlinkAdapter.sol";
import "../interfaces/IChainlinkAdapterFactory.sol";

/**
 * @title ChainlinkAdapterFactory
 * @notice The ChainlinkAdapterFactory creates and keeps track of
 * ChainlinkAdapters.
 * TODO: choose a proxy implementation and make this contract upgradeable
 * TODO: make this contract ownable
 */
contract ChainlinkAdapterFactory is IChainlinkAdapterFactory {
  address public sortedOracles;
  mapping(address => ChainlinkAdapter) deployedRelayers;
  address[] public rateFeeds;

  struct RelayerRecord {
    ChainlinkAdapter deployedRelayer;
    uint8 version;
  }

  event RelayerDeployed(address indexed relayerAddress, address indexed rateFeedId, address indexed aggregator);

  error RelayerExists(address relayerAddress, address rateFeedId, address aggregator);

  error UnexpectedAddress(address expected, address returned);

  /**
   * @notice Initializes the factory.
   * @param _sortedOracles The SortedOracles instance deployed relayers should
   * report to.
   */
  constructor(address _sortedOracles) {
    sortedOracles = _sortedOracles;
  }

  function deployRelayer(address rateFeedId, address chainlinkAggregator) public returns (address) {
    address expectedAddress = computedRelayerAddress(rateFeedId, chainlinkAggregator);

    if (address(deployedRelayers[rateFeedId]) == expectedAddress) {
      revert RelayerExists(expectedAddress, rateFeedId, chainlinkAggregator);
    }

    bytes32 salt = getSalt();
    ChainlinkAdapter adapter = new ChainlinkAdapter{ salt: salt }(rateFeedId, sortedOracles, chainlinkAggregator);

    if (address(adapter) != expectedAddress) {
      revert UnexpectedAddress(expectedAddress, address(adapter));
    }

    deployedRelayers[rateFeedId] = adapter;
    rateFeeds.push(rateFeedId);

    emit RelayerDeployed(address(adapter), rateFeedId, chainlinkAggregator);
    return address(adapter);
  }

  function getRelayer(address rateFeedId) public view returns (address) {
    return address(deployedRelayers[rateFeedId]);
  }

  function getRelayers() public view returns (address[] memory) {
      address[] memory relayers = new address[](rateFeeds.length);
      for (uint256 i = 0; i < rateFeeds.length; i++) {
          relayers[i] = address(deployedRelayers[rateFeeds[i]]);
      }
      return relayers;
  }

  function getSalt() internal view returns (bytes32) {
    // For now we're using CREATE2, so a constant salt is enough, as all the
    // data we want to use for the address salt are included in the init
    // code and constructor arguments.
    return keccak256("mento.chainlinkAdapter");
  }

  function computedRelayerAddress(address rateFeedId, address chainlinkAggregator) public returns (address) {
    bytes32 salt = getSalt();
    return
      address(
        uint160(
          uint256(
            keccak256(
              abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(
                  abi.encodePacked(
                    type(ChainlinkAdapter).creationCode,
                    abi.encode(rateFeedId, sortedOracles, chainlinkAggregator)
                  )
                )
              )
            )
          )
        )
      );
  }
}
