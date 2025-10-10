// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface ICDPLiquidityStrategy {
  error CDPLS_STABILITY_POOL_BALANCE_TOO_LOW();
  error CDPLS_INVALID_STABILITY_POOL_PERCENTAGE();
  error CDPLS_COLLATERAL_REGISTRY_IS_ZERO();
  error CDPLS_STABILITY_POOL_IS_ZERO();

  struct CDPConfig {
    address stabilityPool;
    address collateralRegistry;
    uint256 redemptionBeta;
    uint256 stabilityPoolPercentage;
  }

  function addPool(
    address pool,
    address debtToken,
    uint64 cooldown,
    uint32 incentiveBps,
    address stabilityPool,
    address collateralRegistry,
    uint256 redemptionBeta,
    uint256 stabilityPoolPercentage
  ) external;

  function removePool(address pool) external;

  function setCDPConfig(address pool, CDPConfig calldata config) external;

  function getCDPConfig(address pool) external view returns (CDPConfig memory);
}
