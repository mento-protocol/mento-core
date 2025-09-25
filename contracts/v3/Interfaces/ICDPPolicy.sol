// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

interface ICDPPolicy {
  error CDPPolicy_CONSTRUCTOR_ARRAY_LENGTH_MISMATCH();

  function setDeptTokenStabilityPool(address debtToken, address stabilityPool) external;

  function setDeptTokenCollateralRegistry(address debtToken, address collateralRegistry) external;
}
