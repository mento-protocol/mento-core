// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface ICDPPolicy {
  error CDPPolicy_CONSTRUCTOR_ARRAY_LENGTH_MISMATCH();
  error CDPPolicy_STABILITY_POOL_BALANCE_TOO_LOW();
  error CDPPolicy_INVALID_STABILITY_POOL_PERCENTAGE();

  function setDeptTokenStabilityPool(address debtToken, address stabilityPool) external;

  function setDeptTokenCollateralRegistry(address debtToken, address collateralRegistry) external;
}
