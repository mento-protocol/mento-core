// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

// solhint-disable-next-line max-line-length
import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
// solhint-disable-next-line max-line-length
import { EnumerableSetUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/utils/structs/EnumerableSetUpgradeable.sol";
// solhint-disable-next-line max-line-length
import { ReentrancyGuardUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";

import { ILiquidityStrategy } from "../interfaces/ILiquidityStrategy.sol";
import { IFPMM } from "../interfaces/IFPMM.sol";

/**
 * @title LiquidityStrategy
 * @notice Abstract base contract for implementing different liquidity sourcing strategies.
 *         Manages pool registration, threshold checks, and rebalance triggering logic.
 */
abstract contract LiquidityStrategy is ILiquidityStrategy, OwnableUpgradeable, ReentrancyGuardUpgradeable {
  using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

  mapping(address => FPMMConfig) public fpmmPoolConfigs;

  EnumerableSetUpgradeable.AddressSet private fpmmPools;

  uint256 public constant BPS_SCALE = 10_000;

  /* ==================== Constructor ==================== */

  /**
   * @dev Should be called with disable=true in deployments when it's accessed through a Proxy.
   * Call this with disable=false during testing, when used without a proxy.
   * @param disableInitializers Set to true to run `_disableInitializers()` inherited from
   * openzeppelin-contracts-upgradeable/Initializable.sol
   */
  constructor(bool disableInitializers) {
    if (disableInitializers) {
      _disableInitializers();
    }
  }

  /* ==================== Admin Functions ==================== */

  /// @inheritdoc ILiquidityStrategy
  function addPool(address poolAddress, uint256 cooldown, uint256 rebalanceIncentive) external onlyOwner {
    require(poolAddress != address(0), "LS: INVALID_POOL_ADDRESS");
    require(fpmmPools.add(poolAddress), "LS: POOL_ALREADY_ADDED");
    require(rebalanceIncentive > 0 && rebalanceIncentive <= BPS_SCALE, "LS: INVALID_REBALANCE_INCENTIVE");

    fpmmPoolConfigs[poolAddress] = FPMMConfig({
      lastRebalance: 0,
      rebalanceCooldown: cooldown,
      rebalanceIncentive: rebalanceIncentive
    });

    emit FPMMPoolAdded(poolAddress, cooldown, rebalanceIncentive);
  }

  /// @inheritdoc ILiquidityStrategy
  function removePool(address pool) external onlyOwner {
    require(fpmmPools.remove(pool), "LS: UNREGISTERED_POOL");
    delete fpmmPoolConfigs[pool];
    emit FPMMPoolRemoved(pool);
  }

  /**
   * @notice Sets the rebalance incentive in basis points.
   * @param pool The address of the pool to set the rebalance incentive for.
   * @param rebalanceIncentive The rebalance incentive in basis points.
   */
  function setRebalanceIncentive(address pool, uint256 rebalanceIncentive) public onlyOwner {
    FPMMConfig memory config = fpmmPoolConfigs[pool];
    config.rebalanceIncentive = rebalanceIncentive;
    fpmmPoolConfigs[pool] = config;
    emit RebalanceIncentiveSet(pool, rebalanceIncentive);
  }

  /* ==================== Rebalancing ==================== */

  /// @inheritdoc ILiquidityStrategy
  function rebalance(address pool) external nonReentrant {
    require(fpmmPools.contains(pool), "LS: UNREGISTERED_POOL");

    FPMMConfig memory config = fpmmPoolConfigs[pool];
    if (config.lastRebalance > 0 && block.timestamp <= config.lastRebalance + config.rebalanceCooldown) {
      revert("LS: COOLDOWN_ACTIVE");
    }

    IFPMM fpmm = IFPMM(pool);
    // slither-disable-next-line unused-return
    (uint256 oraclePrice, uint256 poolPrice, , ) = fpmm.getPrices();
    require(oraclePrice > 0 && poolPrice > 0, "LS: INVALID_PRICES");

    uint256 upperThresholdBps = fpmm.rebalanceThresholdAbove();
    require(upperThresholdBps > 0 && upperThresholdBps <= BPS_SCALE, "LS: INVALID_UPPER_THRESHOLD");

    uint256 lowerThresholdBps = fpmm.rebalanceThresholdBelow();
    require(lowerThresholdBps > 0 && lowerThresholdBps <= BPS_SCALE, "LS: INVALID_LOWER_THRESHOLD");

    uint256 upperBound = (oraclePrice * (BPS_SCALE + upperThresholdBps)) / BPS_SCALE;
    uint256 lowerBound = (oraclePrice * (BPS_SCALE - lowerThresholdBps)) / BPS_SCALE;

    // slither-disable-next-line uninitialized-local
    PriceDirection priceDirection;

    if (poolPrice >= upperBound) {
      priceDirection = PriceDirection.ABOVE_ORACLE;
    } else if (poolPrice <= lowerBound) {
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
