// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IGoodDollarExchangeProvider {
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

  /**
   * @notice calculates the amount of tokens to be minted as a result of expansion.
   * @param exchangeId The id of the pool to calculate expansion for.
   * @param expansionRate The rate of expansion.
   * @return amountToMint amount of tokens to be minted as a result of the expansion.
   */
  function calculateExpansion(bytes32 exchangeId, uint32 expansionRate) external returns (uint256 amountToMint);

  /**
   * @notice calculates the amount of tokens to be minted as a result of the reserve interest.
   * @param exchangeId The id of the pool the reserve interest is added to.
   * @param reserveInterest The amount of reserve tokens collected from interest.
   * @return amount of tokens to be minted as a result of the reserve interest.
   */
  function calculateInterest(bytes32 exchangeId, uint256 reserveInterest) external returns (uint256);

  /**
   * @notice calculates the reserve ratio needed to mint the reward.
   * @param exchangeId The id of the pool the reward is minted from.
   * @param reward The amount of tokens to be minted as a reward.
   */
  function calculateRatioForReward(bytes32 exchangeId, uint256 reward) external;

  function currentPriceUSD(bytes32 exchangeId) external view returns (uint256);

  function pause() external;

  function unpause() external;
}
