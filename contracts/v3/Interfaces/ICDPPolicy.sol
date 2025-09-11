// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { ILiquidityPolicy } from "./ILiquidityPolicy.sol";

interface ICDPPolicy is ILiquidityPolicy {
  error CDPPolicy_CONSTRUCTOR_ARRAY_LENGTH_MISMATCH();
  error CDPPolicy_INVALID_MAX_REDEMPTION_FEE();

  function setDeptTokenStabilityPool(address debtToken, address stabilityPool) external;
  function setDeptTokenMaxRedemptionFee(address debtToken, uint256 maxRedemptionFee) external;
  function setDeptTokenCollateralRegistry(address debtToken, address collateralRegistry) external;
}
