// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { EnumerableSet } from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import { ReentrancyGuard } from "openzeppelin-contracts-next/contracts/security/ReentrancyGuard.sol";
import { IERC20Metadata } from "openzeppelin-contracts-next/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { ILiquidityStrategy } from "../interfaces/ILiquidityStrategy.sol";
import { IFPMM } from "../interfaces/IFPMM.sol";
import { UD60x18, ud } from "prb-math/UD60x18.sol";

/**
 * @title LiquidityStrategy
 * @notice Abstract base contract for implementing different liquidity sourcing strategies.
 *         Manages pool registration, threshold checks, and rebalance triggering logic.
 */
abstract contract LiquidityStrategy is OwnableUpgradeable, ILiquidityStrategy, ReentrancyGuard {
  using EnumerableSet for EnumerableSet.AddressSet;

  mapping(address => FPMMConfig) public fpmmPoolConfigs;

  EnumerableSet.AddressSet private fpmmPools;

  /* ==================== Constructor ==================== */

  constructor(bool disableInitializers) {
    if (disableInitializers) {
      _disableInitializers();
    }
  }

  /* ==================== Admin Functions ==================== */

  /// @inheritdoc ILiquidityStrategy
  function addPool(address poolAddress, uint256 cooldown) external onlyOwner {
    require(poolAddress != address(0), "LS: INVALID_POOL_ADDRESS");
    require(cooldown > 0, "LS: ZERO_COOLDOWN_PERIOD");
    require(fpmmPools.add(poolAddress), "LS: POOL_ALREADY_ADDED");

    fpmmPoolConfigs[poolAddress] = FPMMConfig({ lastRebalance: 0, rebalanceCooldown: cooldown });

    emit FPMMPoolAdded(poolAddress, cooldown);
  }

  /// @inheritdoc ILiquidityStrategy
  function removePool(address pool) external onlyOwner {
    require(fpmmPools.remove(pool), "LS: UNREGISTERED_POOL");
    delete fpmmPoolConfigs[pool];
    emit FPMMPoolRemoved(pool);
  }

  /* ==================== Rebalancing ==================== */

  /// @inheritdoc ILiquidityStrategy
  function rebalance(address pool) external nonReentrant {
    require(isPoolRegistered(pool), "LS: UNREGISTERED_POOL");

    FPMMConfig memory config = fpmmPoolConfigs[pool];
    if (config.lastRebalance > 0 && block.timestamp <= config.lastRebalance + config.rebalanceCooldown) {
      revert("LS: COOLDOWN_ACTIVE");
    }

    IFPMM fpmm = IFPMM(pool);
    (uint256 oraclePrice, uint256 poolPrice, , ) = fpmm.getPrices();
    require(oraclePrice > 0 && poolPrice > 0, "LS: INVALID_PRICES");

    uint256 rawBps = fpmm.rebalanceThreshold();
    require(rawBps > 0 && rawBps <= 10_000, "LS: INVALID_THRESHOLD");

    UD60x18 oracleP = ud(oraclePrice);
    UD60x18 poolP = ud(poolPrice);

    UD60x18 threshold = ud(rawBps).div(ud(10_000));
    UD60x18 upperBound = oracleP.mul(ud(1e18).add(threshold));
    UD60x18 lowerBound = oracleP.mul(ud(1e18).sub(threshold));

    PriceDirection priceDirection;

    if (poolP.gte(upperBound)) {
      priceDirection = PriceDirection.ABOVE_ORACLE;
    } else if (poolP.lte(lowerBound)) {
      priceDirection = PriceDirection.BELOW_ORACLE;
    } else {
      revert("LS: PRICE_IN_RANGE");
    }

    _executeRebalance(pool, oraclePrice, priceDirection);
    fpmmPoolConfigs[pool].lastRebalance = block.timestamp;

    // slither-disable-next-line unused-return
    (, uint256 poolPriceAfterRebalance, , ) = fpmm.getPrices();
    emit RebalanceExecuted(pool, poolPrice, poolPriceAfterRebalance);
  }

  /* ==================== View Functions ==================== */

  /// @inheritdoc ILiquidityStrategy
  function isPoolRegistered(address pool) public view returns (bool) {
    return fpmmPools.contains(pool);
  }

  /// @inheritdoc ILiquidityStrategy
  function getPools() external view returns (address[] memory) {
    return fpmmPools.values();
  }

  /* ==================== Internal Functions ==================== */

  /**
   * @notice Contains the strategy-specific logic that executes the rebalancing.
   * @param pool The address of the pool to rebalance.
   * @param oraclePrice The off‑chain target price.
   * @param priceDirection The direction of the price movement.
   */
  function _executeRebalance(address pool, uint256 oraclePrice, PriceDirection priceDirection) internal virtual;
}
