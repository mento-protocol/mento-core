// SPDX-License-Identifier: MIT
pragma solidity >=0.5.17 <0.8.19;
pragma experimental ABIEncoderV2;

import { IBancorExchangeProvider } from "./IBancorExchangeProvider.sol";

interface IGoodDollarExchangeProvider {
  /* ------- Events ------- */

  /**
   * @notice Emitted when the SortedOracles address is updated.
   * @param sortedOracles The address of the SortedOracles contract.
   */
  event SortedOraclesUpdated(address indexed sortedOracles);

  /**
   * @notice Emitted when the ExpansionController address is updated.
   * @param expansionController The address of the ExpansionController contract.
   */
  event ExpansionControllerUpdated(address indexed expansionController);

  /**
   * @notice Emitted when the AVATAR address is updated.
   * @param AVATAR The address of the AVATAR contract.
   */
  event AvatarUpdated(address indexed AVATAR);

  /**
   * @notice Emitted when reserve ratio for exchange is updated.
   * @param exchangeId The id of the exchange.
   * @param reserveRatio The new reserve ratio.
   */
  event ReserveRatioUpdated(bytes32 indexed exchangeId, uint32 reserveRatio);

  /* ------- Functions ------- */

  /**
   * @notice Initializes the contract with the given parameters.
   * @param _broker The address of the Broker contract.
   * @param _reserve The address of the Reserve contract.
   * @param _sortedOracles The address of the SortedOracles contract.
   * @param _expansionController The address of the ExpansionController contract.
   * @param _avatar The address of the GoodDollar DAO contract.
   */
  function initialize(
    address _broker,
    address _reserve,
    address _sortedOracles,
    address _expansionController,
    address _avatar
  ) external;

  /**
   * @notice Creates a new exchange with the given parameters.
   * @param _exchange The PoolExchange struct holding the exchange parameters.
   * @param _usdRateFeed The address of the USD rate feed for the reserve asset.
   * @return exchangeId The id of the newly created exchange.
   */
  function createExchange(IBancorExchangeProvider.PoolExchange calldata _exchange, address _usdRateFeed)
    external
    returns (bytes32 exchangeId);

  /**
   * @notice calculates the amount of tokens to be minted as a result of expansion.
   * @param exchangeId The id of the pool to calculate expansion for.
   * @param expansionRate The rate of expansion.
   * @return amountToMint amount of tokens to be minted as a result of the expansion.
   */
  function mintFromExpansion(bytes32 exchangeId, uint256 expansionRate) external returns (uint256 amountToMint);

  /**
   * @notice calculates the amount of tokens to be minted as a result of the reserve interest.
   * @param exchangeId The id of the pool the reserve interest is added to.
   * @param reserveInterest The amount of reserve tokens collected from interest.
   * @return amount of tokens to be minted as a result of the reserve interest.
   */
  function mintFromInterest(bytes32 exchangeId, uint256 reserveInterest) external returns (uint256);

  /**
   * @notice calculates the reserve ratio needed to mint the reward.
   * @param exchangeId The id of the pool the reward is minted from.
   * @param reward The amount of tokens to be minted as a reward.
   */
  function updateRatioForReward(bytes32 exchangeId, uint256 reward) external;

  /**
   * @notice calculates the current price of the token in USD.
   * @param exchangeId The id of the pool to calculate the price for.
   * @return current price of the token in USD.
   */
  function currentPriceUSD(bytes32 exchangeId) external view returns (uint256);

  /**
   * @notice pauses the Exchange disables minting.
   */
  function pause() external;

  /**
   * @notice unpauses the Exchange enables minting again.
   */
  function unpause() external;
}
