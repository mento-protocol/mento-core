// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

import "./ChainlinkRelayerV1.sol";
import "../interfaces/IChainlinkRelayerFactory.sol";

/**
 * @title ChainlinkRelayerFactory
 * @notice The ChainlinkRelayerFactory creates and keeps track of
 * ChainlinkRelayers.
 * TODO: choose a proxy implementation and make this contract upgradeable
 * TODO: make this contract ownable
 */
contract ChainlinkRelayerFactory is IChainlinkRelayerFactory {
  address public sortedOracles;
  mapping(address => ChainlinkRelayerV1) deployedRelayers;
  address[] public rateFeeds;

  struct RelayerRecord {
    ChainlinkRelayerV1 deployedRelayer;
    uint8 version;
  }

  event RelayerDeployed(address indexed relayerAddress, address indexed rateFeedId, address indexed aggregator);
  event RelayerRemoved(address indexed rateFeedId, address indexed relayerAddress);

  error RelayerExists(address relayerAddress, address rateFeedId, address aggregator);

  error RelayerForFeedExists(address rateFeedId);

  error UnexpectedAddress(address expected, address returned);

  error NoSuchRelayer(address rateFeedId);

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

    if (address(deployedRelayers[rateFeedId]) == expectedAddress || expectedAddress.code.length > 0) {
      revert RelayerExists(expectedAddress, rateFeedId, chainlinkAggregator);
    }

    if (address(deployedRelayers[rateFeedId]) != address(0)) {
      revert RelayerForFeedExists(rateFeedId);
    }

    bytes32 salt = getSalt();
    ChainlinkRelayerV1 relayer = new ChainlinkRelayerV1{ salt: salt }(rateFeedId, sortedOracles, chainlinkAggregator);

    if (address(relayer) != expectedAddress) {
      revert UnexpectedAddress(expectedAddress, address(relayer));
    }

    deployedRelayers[rateFeedId] = relayer;
    rateFeeds.push(rateFeedId);

    emit RelayerDeployed(address(relayer), rateFeedId, chainlinkAggregator);
    return address(relayer);
  }

  function removeRelayer(address rateFeedId) public {
    address relayerAddress = address(deployedRelayers[rateFeedId]);

    if (relayerAddress == address(0)) {
      revert NoSuchRelayer(rateFeedId);
    }

    delete deployedRelayers[rateFeedId];

    uint256 lastRateFeedIndex = rateFeeds.length - 1;

    for (uint256 i = 0; i <= lastRateFeedIndex; i++) {
      if (rateFeeds[i] == rateFeedId) {
        rateFeeds[i] = rateFeeds[lastRateFeedIndex];
        rateFeeds.pop();
        break;
      }
    }

    emit RelayerRemoved(rateFeedId, relayerAddress);
  }

  function redeployRelayer(address rateFeedId, address chainlinkAggregator) external returns (address) {
    removeRelayer(rateFeedId);
    return deployRelayer(rateFeedId, chainlinkAggregator);
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
    return keccak256("mento.chainlinkRelayer");
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
                    type(ChainlinkRelayerV1).creationCode,
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
