// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { ILiquidityPolicy } from "./ILiquidityPolicy.sol";
import { LiquidityTypes as LQ } from "../libraries/LiquidityTypes.sol";

interface ICDPPolicy is ILiquidityPolicy {
  error CDPPolicy_CONSTRUCTOR_ARRAY_LENGTH_MISMATCH();
  error CDPPolicy_STABILITY_POOL_BALANCE_TOO_LOW();
  error CDPPolicy_INVALID_STABILITY_POOL_PERCENTAGE();
  error CDPPolicy_AMOUNT_OUT_IS_0();
  error CDPPolicy_AMOUNT_IN_IS_0();

  function setDeptTokenStabilityPool(address debtToken, address stabilityPool) external;
  function setDeptTokenCollateralRegistry(address debtToken, address collateralRegistry) external;
  function setDeptTokenRedemptionBeta(address debtToken, uint256 redemptionBeta) external;
  function setDeptTokenStabilityPoolPercentage(address debtToken, uint256 stabilityPoolPercentage) external;
  function determineAction(LQ.Context memory ctx) external view returns (bool shouldAct, LQ.Action memory action);
}
