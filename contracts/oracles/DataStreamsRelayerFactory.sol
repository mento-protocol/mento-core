// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { DataStreamsRelayerV1 } from "./DataStreamsRelayerV1.sol";
import { IDataStreamsRelayer } from "../interfaces/IDataStreamsRelayer.sol";
import { IDataStreamsRelayerFactory } from "../interfaces/IDataStreamsRelayerFactory.sol";

/**
 * @title DataStreamsRelayerFactory
 * @notice The DataStreamsRelayerFactory creates and keeps track of DataStreamsRelayerV1 instances.
 * @dev Mirrors ChainlinkRelayerFactory in structure, with the following additions:
 *      - Stores verifierProxy address, which is forwarded to every deployed relayer.
 *      - deployRelayer() accepts StreamLeg[] and maxStaleness instead of ChainlinkAggregator[].
 *      - ingest() is a permissionless router: rateFeedId → relayer → relay(signedReports).
 *        This is the entry point called as a state-changing pre-step in swap transactions.
 */
contract DataStreamsRelayerFactory is IDataStreamsRelayerFactory, OwnableUpgradeable {
  /// @notice Address of the SortedOracles contract deployed relayers will report to.
  address public sortedOracles;

  /// @notice Address of the Chainlink Data Streams VerifierProxy.
  address public verifierProxy;

  /// @notice Maps a rate feed ID to the relayer contract most recently deployed by this contract.
  mapping(address rateFeedId => DataStreamsRelayerV1 relayer) public deployedRelayers;

  /**
   * @notice List of rate feed IDs for which a relayer has been deployed.
   * @dev Used to enumerate the `deployedRelayers` mapping.
   */
  address[] public rateFeeds;

  /**
   * @notice Account that is allowed to deploy relayers.
   */
  address public relayerDeployer;

  /**
   * @notice Thrown when trying to deploy a relayer to an address that already has code.
   * @param contractAddress Address at which the relayer could not be deployed.
   * @param rateFeedId Rate feed ID for which the relayer would have reported.
   */
  error ContractAlreadyExists(address contractAddress, address rateFeedId);

  /**
   * @notice Thrown when trying to deploy a relayer for a rate feed ID that already has a relayer.
   * @param rateFeedId The rate feed ID for which a relayer already exists.
   */
  error RelayerForFeedExists(address rateFeedId);

  /**
   * @notice Thrown when the sanity check to verify the CREATE2 address computation fails.
   * @param expectedAddress The address expected by local computation of the CREATE2 address.
   * @param returnedAddress The address actually returned by CREATE2.
   */
  error UnexpectedAddress(address expectedAddress, address returnedAddress);

  /**
   * @notice Thrown when trying to remove or redeploy a relayer for a rate feed ID that has none.
   * @param rateFeedId The rate feed ID.
   */
  error NoRelayerForRateFeedId(address rateFeedId);

  /// @notice Thrown when a non-deployer tries to call a deployer-only function.
  error NotAllowed();

  /// @notice Modifier to restrict a function to the deployer or owner.
  modifier onlyDeployer() {
    if (msg.sender != relayerDeployer && msg.sender != owner()) revert NotAllowed();
    _;
  }

  /**
   * @notice Constructor for the logic contract.
   * @param disable If `true`, disables the initializer.
   * @dev This contract is meant to be deployed with an upgradeable proxy in
   * front of it. Set `disable` to `true` in production environments to disable
   * contract initialization on the logic contract, only allowing initialization
   * on the proxy.
   */
  constructor(bool disable) {
    if (disable) _disableInitializers();
  }

  /**
   * @notice Initializes the factory.
   * @param _sortedOracles The SortedOracles instance deployed relayers should report to.
   * @param _verifierProxy The Chainlink Data Streams VerifierProxy address.
   * @param _relayerDeployer Initial deployer address (in addition to owner).
   */
  function initialize(address _sortedOracles, address _verifierProxy, address _relayerDeployer) external initializer {
    __Ownable_init();
    sortedOracles = _sortedOracles;
    verifierProxy = _verifierProxy;
    relayerDeployer = _relayerDeployer;
  }

  /**
   * @notice Sets the address of the relayer deployer.
   * @param newRelayerDeployer The address of the new relayer deployer.
   */
  function setRelayerDeployer(address newRelayerDeployer) external onlyOwner {
    address oldRelayerDeployer = relayerDeployer;
    relayerDeployer = newRelayerDeployer;
    emit RelayerDeployerUpdated(newRelayerDeployer, oldRelayerDeployer);
  }

  /**
   * @notice Deploys a new DataStreamsRelayerV1 contract.
   * @dev Relayers are immutable per config: the CREATE2 address is derived from the constructor
   *      args (rateFeedId, description, spread, staleness, legs). Two relayers with byte-identical
   *      params therefore collide at the same address. Reconfiguring a feed via redeployRelayer must
   *      change at least one arg; redeploying with identical params after removeRelayer reverts
   *      ContractAlreadyExists (the old contract still has code at that address). You cannot "reset"
   *      a relayer to byte-identical params — vary a param (e.g. the description) to get a new one.
   * @param rateFeedId The rate feed ID for which the relayer will report.
   * @param rateFeedDescription Human-readable description of the rate feed, i.e. "USD/CHF".
   * @param maxTimestampSpread Max difference in seconds between the earliest and latest
   *        observationsTimestamp across all legs. Must be 0 for single-leg relayers.
   * @param maxStaleness Max age in seconds of a report's observationsTimestamp relative to block.timestamp.
   * @param legs Array of StreamLeg structs defining the price composition path.
   * @return relayerAddress The address of the newly deployed relayer contract.
   */
  function deployRelayer(
    address rateFeedId,
    string calldata rateFeedDescription,
    uint256 maxTimestampSpread,
    uint256 maxStaleness,
    IDataStreamsRelayer.StreamLeg[] calldata legs
  ) public onlyDeployer returns (address relayerAddress) {
    if (address(deployedRelayers[rateFeedId]) != address(0)) revert RelayerForFeedExists(rateFeedId);

    address expectedAddress = computeRelayerAddress(
      rateFeedId,
      rateFeedDescription,
      maxTimestampSpread,
      maxStaleness,
      legs
    );
    if (expectedAddress.code.length > 0) revert ContractAlreadyExists(expectedAddress, rateFeedId);

    DataStreamsRelayerV1 relayer = new DataStreamsRelayerV1{ salt: _getSalt() }(
      rateFeedId,
      rateFeedDescription,
      sortedOracles,
      verifierProxy,
      maxTimestampSpread,
      maxStaleness,
      legs
    );

    if (address(relayer) != expectedAddress) revert UnexpectedAddress(expectedAddress, address(relayer));

    deployedRelayers[rateFeedId] = relayer;
    rateFeeds.push(rateFeedId);

    emit RelayerDeployed(address(relayer), rateFeedId, rateFeedDescription, legs);
    return address(relayer);
  }

  /**
   * @notice Removes a relayer from the list of deployed relayers.
   * @param rateFeedId The rate feed whose relayer should be removed.
   */
  function removeRelayer(address rateFeedId) public onlyDeployer {
    address relayerAddress = address(deployedRelayers[rateFeedId]);
    if (relayerAddress == address(0)) revert NoRelayerForRateFeedId(rateFeedId);

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
   * @notice Removes the current relayer and redeploys a new one with updated parameters.
   * @param rateFeedId The rate feed ID for which the relayer will report.
   * @param rateFeedDescription Human-readable description of the rate feed, i.e. "USD/CHF".
   * @param maxTimestampSpread Max difference in seconds between the earliest and latest
   *        observationsTimestamp across all legs. Must be 0 for single-leg relayers.
   * @param maxStaleness Max age in seconds of a report's observationsTimestamp relative to block.timestamp.
   * @param legs Array of StreamLeg structs defining the price composition path.
   * @return relayerAddress The address of the newly deployed relayer contract.
   */
  function redeployRelayer(
    address rateFeedId,
    string calldata rateFeedDescription,
    uint256 maxTimestampSpread,
    uint256 maxStaleness,
    IDataStreamsRelayer.StreamLeg[] calldata legs
  ) external onlyDeployer returns (address relayerAddress) {
    removeRelayer(rateFeedId);
    return deployRelayer(rateFeedId, rateFeedDescription, maxTimestampSpread, maxStaleness, legs);
  }

  /**
   * @notice Routes signed reports to the registered relayer for a given rateFeedId.
   * @dev Permissionless. Resolves rateFeedId → relayer → relay(signedReports).
   *      Called as a state-changing pre-step in swap transactions before the view oracle read.
   *      Also callable standalone by arbitrageurs or recovery bots to refresh a stale feed.
   * @param rateFeedId The Mento rateFeedId whose relayer should receive the reports.
   * @param signedReports Signed report payloads from the Data Streams API, one per leg in leg order.
   * @param parameterPayload Fee parameter payload forwarded to the VerifierProxy. Empty bytes on Celo.
   */
  function ingest(address rateFeedId, bytes[] calldata signedReports, bytes calldata parameterPayload) external {
    DataStreamsRelayerV1 relayer = deployedRelayers[rateFeedId];
    if (address(relayer) == address(0)) revert NoRelayerForRateFeedId(rateFeedId);
    relayer.relay(signedReports, parameterPayload);
  }

  /**
   * @notice Returns the address of the currently deployed relayer for a given rate feed ID.
   * @param rateFeedId The rate feed ID whose relayer we want to get.
   * @return relayerAddress Address of the relayer contract.
   */
  function getRelayer(address rateFeedId) external view returns (address relayerAddress) {
    return address(deployedRelayers[rateFeedId]);
  }

  /**
   * @notice Returns a list of all currently deployed relayers.
   * @return relayerAddresses An array of all relayer contract addresses.
   */
  function getRelayers() external view returns (address[] memory relayerAddresses) {
    address[] memory relayers = new address[](rateFeeds.length);
    // slither-disable-next-line cache-array-length
    for (uint256 i = 0; i < rateFeeds.length; i++) {
      relayers[i] = address(deployedRelayers[rateFeeds[i]]);
    }
    return relayers;
  }

  /**
   * @notice Computes the expected CREATE2 address for given relayer parameters.
   * @param rateFeedId The rate feed ID.
   * @param rateFeedDescription The human-readable description of the reported rate feed.
   * @param maxTimestampSpread Max difference in seconds between the earliest and latest
   *        observationsTimestamp across all legs.
   * @param maxStaleness Max age in seconds of a report's observationsTimestamp relative to block.timestamp.
   * @param legs Array of StreamLeg structs defining the price composition path.
   * @dev See https://eips.ethereum.org/EIPS/eip-1014.
   */
  function computeRelayerAddress(
    address rateFeedId,
    string calldata rateFeedDescription,
    uint256 maxTimestampSpread,
    uint256 maxStaleness,
    IDataStreamsRelayer.StreamLeg[] calldata legs
  ) public view returns (address) {
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
                    type(DataStreamsRelayerV1).creationCode,
                    abi.encode(
                      rateFeedId,
                      rateFeedDescription,
                      sortedOracles,
                      verifierProxy,
                      maxTimestampSpread,
                      maxStaleness,
                      legs
                    )
                  )
                )
              )
            )
          )
        )
      );
  }

  /**
   * @notice Returns the salt used for CREATE2 deployment of relayer contracts.
   * @return salt The `bytes32` constant `keccak256("mento.dataStreamsRelayer")`.
   * @dev We're using CREATE2 and all the data we want to use for address
   *      generation is included in the init code and constructor arguments, so a
   *      constant salt is enough.
   */
  function _getSalt() internal pure returns (bytes32 salt) {
    return keccak256("mento.dataStreamsRelayer");
  }
}
