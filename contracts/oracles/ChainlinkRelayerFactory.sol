// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { ChainlinkRelayerV1 } from "./ChainlinkRelayerV1.sol";
import { IChainlinkRelayerFactory } from "../interfaces/IChainlinkRelayerFactory.sol";

/**
 * @title ChainlinkRelayerFactory
 * @notice The ChainlinkRelayerFactory creates and keeps track of
 * ChainlinkRelayers.
 * TODO: choose a proxy implementation and make this contract upgradeable
 * TODO: make this contract ownable
 */
contract ChainlinkRelayerFactory is IChainlinkRelayerFactory, OwnableUpgradeable {
  /// @notice Address of the SortedOracles contract.
  address public sortedOracles;
  /// @notice Maps a rate feed ID to the relayer most recently deployed by this contract.
  mapping(address => ChainlinkRelayerV1) public deployedRelayers;
  /**
   * @notice List of rate feed IDs for which a relayer has been deployed.
   * @dev Used to enumrate the `deployedRelayer` mapping.
   */
  address[] public rateFeeds;

  /**
   * @notice Emitted when a relayer is deployed.
   * @param relayerAddress Address of the newly deployed relayer.
   * @param rateFeedId Rate feed for which the relayer will report.
   * @param aggregator Address of the Chainlink aggregator the relayer will fetch prices from.
   */
  event RelayerDeployed(address indexed relayerAddress, address indexed rateFeedId, address indexed aggregator);
  /**
   * @notice Emitted when a relayer is removed.
   * @param rateFeedId The rate feed for which the relayer reported.
   * @param relayerAddress Address of the removed relayer.
   */
  event RelayerRemoved(address indexed rateFeedId, address indexed relayerAddress);

  /**
   * @notice Used when trying to deploy or redeploy a relayer to an address that already has code.
   * @param relayerAddress Address at which the relayer would have been deployed.
   * @param rateFeedId The rate feed for which the relayer would have reported.
   * @param aggregator Address of the Chainlink aggregator the relayer would have fetched prices from.
   */
  error RelayerExists(address relayerAddress, address rateFeedId, address aggregator);

  /**
   * @notice Used when trying to deploy a relayer for a rate feed that already has a relayer.
   * @param rateFeedId The specified rate feed.
   * @dev A relayer can be deployed for the same rate feed but with a different
   * aggregator or bytecode with `redeployRelayer`.
   */
  error RelayerForFeedExists(address rateFeedId);

  /**
   * @notice Used when the sanity check to verify CREATE2 address computation fails.
   * @param expected The address expected by local computation of the CREATE2 address.
   * @param returned The address returned by CREATE2.
   */
  error UnexpectedAddress(address expected, address returned);

  /**
   * @notice Used when trying to remove a relayer for a rate feed that doesn't
   * have a relayer.
   * @param rateFeedId The rate feed ID.
   */
  error NoSuchRelayer(address rateFeedId);

  constructor(bool disable) {
    if (disable) {
      _disableInitializers();
    }
  }

  /**
   * @notice Initializes the factory.
   * @param _sortedOracles The SortedOracles instance deployed relayers should
   * report to.
   */
  function initialize(address _sortedOracles) external initializer {
    __Ownable_init();
    sortedOracles = _sortedOracles;
  }

  /**
   * @notice Deploys a new relayer contract.
   * @param rateFeedId The rate feed for which the relayer will report.
   * @param chainlinkAggregator The Chainlink aggregator from which the relayer
   * will fetch prices.
   * @return The address of the newly deployed relayer contract.
   */
  function deployRelayer(address rateFeedId, address chainlinkAggregator) public onlyOwner returns (address) {
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

  /**
   * @notice Removes a relayer from the list of deployed relayers.
   * @param rateFeedId The rate feed whose relayer should be removed.
   */
  function removeRelayer(address rateFeedId) public onlyOwner {
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

  /**
   * @notice Removes the current relayer and redeploys a new one with a
   * different Chainlink aggregator (and/or different bytecode if the factory
   * has been upgraded since the last deployment of the relayer).
   * @param rateFeedId The rate feed for which the relayer should be redeployed.
   * @param chainlinkAggregator Address of the Chainlink aggregator the new
   * version of the relayer will fetch prices from.
   * @return The address of the newly deployed relayer contract.
   */
  function redeployRelayer(address rateFeedId, address chainlinkAggregator) external onlyOwner returns (address) {
    removeRelayer(rateFeedId);
    return deployRelayer(rateFeedId, chainlinkAggregator);
  }

  /**
   * @notice Returns the address of the current relayer deployed for the given
   * rate feed ID.
   * @param rateFeedId The rate feed ID.
   * @return Address of the relayer contract.
   */
  function getRelayer(address rateFeedId) public view returns (address) {
    return address(deployedRelayers[rateFeedId]);
  }

  /**
   * @notice Returns a list of currently deployed relayers.
   * @return An array of relayer contract addresses.
   */
  function getRelayers() public view returns (address[] memory) {
    address[] memory relayers = new address[](rateFeeds.length);
    for (uint256 i = 0; i < rateFeeds.length; i++) {
      relayers[i] = address(deployedRelayers[rateFeeds[i]]);
    }
    return relayers;
  }

  /**
   * @notice Returns the salt used for CREATE2 deployment of relayer contracts.
   * @return The `bytes32` constant `keccak256("mento.chainlinkRelayer")`.
   * @dev We're using CREATE2 and all the data we want to use for address
   * generation is included in the init code and constructor arguments, so a
   * constant salt is enough.
   */
  function getSalt() internal view returns (bytes32) {
    return keccak256("mento.chainlinkRelayer");
  }

  /**
   * @notice Computes the expected CREATE2 address for given relayer parameters.
   * @param rateFeedId The rate feed ID.
   * @param chainlinkAggregator Address of the Chainlink aggregator.
   * @dev See https://eips.ethereum.org/EIPS/eip-1014.
   */
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
