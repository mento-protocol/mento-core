// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
// solhint-disable func-name-mixedcase

interface ICDPPolicy {
  error CDPPolicy_CONSTRUCTOR_ARRAY_LENGTH_MISMATCH();
  error CDPPolicy_STABILITY_POOL_BALANCE_TOO_LOW();
  error CDPPolicy_INVALID_STABILITY_POOL_PERCENTAGE();

  /**
   * @notice Returns the name of the CDP policy
   * @return The name of the CDP policy
   */
  function name() external view returns (string memory);

  /**
   * @notice Returns the stability pool address for a given debt token
   * @param debtToken The debt token address
   * @return The stability pool address
   */
  function deptTokenStabilityPool(address debtToken) external view returns (address);

  /**
   * @notice Returns the collateral registry address for a given debt token
   * @param debtToken The debt token address
   * @return The collateral registry address
   */
  function deptTokenCollateralRegistry(address debtToken) external view returns (address);

  /**
   * @notice Returns the redemption beta for a given debt token
   * @param debtToken The debt token address
   * @return The redemption beta
   */
  function deptTokenRedemptionBeta(address debtToken) external view returns (uint256);

  /**
   * @notice Returns the stability pool percentage for a given debt token
   * @param debtToken The debt token address
   * @return The stability pool percentage
   */
  function deptTokenStabilityPoolPercentage(address debtToken) external view returns (uint256);

  /**
   * @notice Returns the scaler for basis point to liquityv2 redemption fee conversion
   * liquityv2 redemption fee is in 1e18
   * @return Scaler for basis point to liquityv2 fee conversion
   */
  function BPS_TO_FEE_SCALER() external view returns (uint256);

  /**
   * @notice Returns the denominator for basis point calculations (10000 = 100%)
   * @return Denominator for basis points
   */
  function BPS_DENOMINATOR() external view returns (uint256);

  /**
   * @notice Sets the stability pool address for a given debt token
   * @param debtToken The debt token address
   * @param stabilityPool The stability pool address
   */
  function setDeptTokenStabilityPool(address debtToken, address stabilityPool) external;

  function setDeptTokenCollateralRegistry(address debtToken, address collateralRegistry) external;

  /**
   * @notice Sets the redemption beta for a given debt token
   * @param debtToken The debt token address
   * @param redemptionBeta The redemption beta
   */
  function setDeptTokenRedemptionBeta(address debtToken, uint256 redemptionBeta) external;

  /**
   * @notice Sets the stability pool liquidity percentage for a given debt token
   * @param debtToken The debt token address
   * @param stabilityPoolPercentage The stability pool percentage
   */
  function setDeptTokenStabilityPoolPercentage(address debtToken, uint256 stabilityPoolPercentage) external;

  /**
   * @notice Determines if the policy should act based on the current context.
   * @param ctx The context containing pool, reserves, prices, and other relevant data.
   * @return shouldAct True if the policy should take action, false otherwise.
   * @return action The action to be taken if shouldAct is true.
   */
  function determineAction(LQ.Context memory ctx) external view returns (bool shouldAct, LQ.Action memory action);
}
