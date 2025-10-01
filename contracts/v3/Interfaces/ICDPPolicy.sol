// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { ILiquidityPolicy } from "./ILiquidityPolicy.sol";

interface ICDPPolicy is ILiquidityPolicy {
  error CDPPolicy_CONSTRUCTOR_ARRAY_LENGTH_MISMATCH();

  function setDeptTokenStabilityPool(address debtToken, address stabilityPool) external;
  function setDeptTokenCollateralRegistry(address debtToken, address collateralRegistry) external;
}
