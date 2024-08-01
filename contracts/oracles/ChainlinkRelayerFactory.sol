// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { ChainlinkRelayerV1 } from "./ChainlinkRelayerV1.sol";
import { IChainlinkRelayerFactory } from "../interfaces/IChainlinkRelayerFactory.sol";

/**
 * @title ChainlinkRelayerFactory
 * @notice The ChainlinkRelayerFactory creates and keeps track of ChainlinkRelayers.
 */
contract ChainlinkRelayerFactory is IChainlinkRelayerFactory, OwnableUpgradeable {
  /// @notice Address of the SortedOracles contract.
  address public sortedOracles;

  /// @notice Maps a rate feed ID to the relayer contract most recently deployed by this contract.
  mapping(address rateFeedId => ChainlinkRelayerV1 relayer) public deployedRelayers;

  /**
   * @notice List of rate feed IDs for which a relayer has been deployed.
   * @dev Used to enumerate the `deployedRelayer` mapping.
   */
  address[] public rateFeeds;

  /**
   * @notice Emitted when a relayer is deployed.
   * @param relayerAddress Address of the newly deployed relayer.
   * @param rateFeedId Rate feed ID for which the relayer will report.
   * @param chainlinkAggregator Address of the Chainlink aggregator the relayer will fetch prices from.
   */
  event RelayerDeployed(
    address indexed relayerAddress,
    address indexed rateFeedId,
    address indexed chainlinkAggregator
  );

  /**
   * @notice Emitted when a relayer is removed.
   * @param relayerAddress Address of the removed relayer.
   * @param rateFeedId Rate feed ID for which the relayer reported.
   */
  event RelayerRemoved(address indexed relayerAddress, address indexed rateFeedId);

  /**
   * @notice Thrown when trying to deploy a relayer to an address that already has code.
   * @param contractAddress Address at which the relayer could not be deployed.
   * @param rateFeedId Rate feed ID for which the relayer would have reported.
   * @param chainlinkAggregator Address of the Chainlink aggregator the relayer would have fetched prices from.
   */
  error ContractAlreadyExists(address contractAddress, address rateFeedId, address chainlinkAggregator);

  /**
   * @notice Thrown when trying to deploy a relayer for a rate feed ID that already has a relayer.
   * @param rateFeedId The rate feed ID for which a relayer already exists.
   * @dev A new relayer *can* be deployed for the same rate feed ID, but only with a different
   *      chainlink aggregator or bytecode with `redeployRelayer`.
   */
  error RelayerForFeedExists(address rateFeedId);

  /**
   * @notice Thrown when the sanity check to verify the CREATE2 address computation fails.
   * @param expectedAddress The address expected by local computation of the CREATE2 address.
   * @param returnedAddress The address actually returned by CREATE2.
   */
  error UnexpectedAddress(address expectedAddress, address returnedAddress);

  /**
   * @notice Thrown when trying to remove a relayer for a rate feed ID that doesn't have a relayer.
   * @param rateFeedId The rate feed ID.
   */
  error NoRelayerForRateFeedId(address rateFeedId);

  /**
   * @notice Constructor for the logic contract.
   * @param disable If `true`, disables the initializer.
   * @dev This contract is meant to be deployed with an upgradeable proxy in
   * front of it. Set `disable` to `true` in production environments to disable
   * contract initialization on the logic contract, only allowing initialization
   * on the proxy.
   */
  constructor(bool disable) {
    if (disable) {
      _disableInitializers();
    }
  }

  /**
   * @notice Initializes the factory.
   * @param _sortedOracles The SortedOracles instance deployed relayers should report to.
   */
  function initialize(address _sortedOracles) external initializer {
    __Ownable_init();
    sortedOracles = _sortedOracles;
  }

  /**
   * @notice Deploys a new relayer contract.
   * @param rateFeedId The rate feed ID for which the relayer will report.
   * @param chainlinkAggregator The Chainlink aggregator from which the relayer will fetch prices.
   * @return relayerAddress The address of the newly deployed relayer contract.
   */
  function deployRelayer(
    address rateFeedId,
    address chainlinkAggregator
  ) public onlyOwner returns (address relayerAddress) {
    address expectedAddress = computedRelayerAddress(rateFeedId, chainlinkAggregator);

    if (address(deployedRelayers[rateFeedId]) == expectedAddress || expectedAddress.code.length > 0) {
      revert ContractAlreadyExists(expectedAddress, rateFeedId, chainlinkAggregator);
    }

    if (address(deployedRelayers[rateFeedId]) != address(0)) {
      revert RelayerForFeedExists(rateFeedId);
    }

    bytes32 salt = _getSalt();
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
      revert NoRelayerForRateFeedId(rateFeedId);
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

    emit RelayerRemoved(relayerAddress, rateFeedId);
  }

  /**
   * @notice Removes the current relayer and redeploys a new one with a different
   *         Chainlink aggregator (and/or different bytecode if the factory
   *         has been upgraded since the last deployment of the relayer).
   * @param rateFeedId The rate feed for which the relayer should be redeployed.
   * @param chainlinkAggregator Address of the Chainlink aggregator the new relayer version will fetch prices from.
   * @return relayerAddress The address of the newly deployed relayer contract.
   */
  function redeployRelayer(
    address rateFeedId,
    address chainlinkAggregator
  ) external onlyOwner returns (address relayerAddress) {
    removeRelayer(rateFeedId);
    return deployRelayer(rateFeedId, chainlinkAggregator);
  }

  /**
   * @notice Returns the address of the currently deployed relayer for a given rate feed ID.
   * @param rateFeedId The rate feed ID whose relayer we want to get.
   * @return relayerAddress Address of the relayer contract.
   */
  function getRelayer(address rateFeedId) public view returns (address relayerAddress) {
    return address(deployedRelayers[rateFeedId]);
  }

  /**
   * @notice Returns a list of all currently deployed relayers.
   * @return relayerAddresses An array of all relayer contract addresses.
   */
  function getRelayers() public view returns (address[] memory relayerAddresses) {
    address[] memory relayers = new address[](rateFeeds.length);
    for (uint256 i = 0; i < rateFeeds.length; i++) {
      relayers[i] = address(deployedRelayers[rateFeeds[i]]);
    }
    return relayers;
  }

  /**
   * @notice Returns the salt used for CREATE2 deployment of relayer contracts.
   * @return salt The `bytes32` constant `keccak256("mento.chainlinkRelayer")`.
   * @dev We're using CREATE2 and all the data we want to use for address
   *      generation is included in the init code and constructor arguments, so a
   *      constant salt is enough.
   */
  function _getSalt() internal pure returns (bytes32 salt) {
    return keccak256("mento.chainlinkRelayer");
  }

  /**
   * @notice Computes the expected CREATE2 address for given relayer parameters.
   * @param rateFeedId The rate feed ID.
   * @param chainlinkAggregator Address of the Chainlink aggregator.
   * @dev See https://eips.ethereum.org/EIPS/eip-1014.
   */
  function computedRelayerAddress(address rateFeedId, address chainlinkAggregator) public view returns (address) {
    bytes32 salt = _getSalt();
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
