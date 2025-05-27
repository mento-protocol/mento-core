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
import { UD60x18, ud } from "prb-math/UD60x18.sol";

/**
 * @title LiquidityStrategy
 * @notice Abstract base contract for implementing different liquidity sourcing strategies.
 *         Manages pool registration, threshold checks, and rebalance triggering logic.
 */
abstract contract LiquidityStrategy is ILiquidityStrategy, OwnableUpgradeable, ReentrancyGuardUpgradeable {
  using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

  mapping(address => FPMMConfig) public fpmmPoolConfigs;

  EnumerableSetUpgradeable.AddressSet private fpmmPools;

  uint256 constant SCALE = 1e18;
  uint256 constant BPS_SCALE = 10_000;

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
  function addPool(address poolAddress, uint256 cooldown) external onlyOwner {
    require(poolAddress != address(0), "LS: INVALID_POOL_ADDRESS");
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
    require(fpmmPools.contains(pool), "LS: UNREGISTERED_POOL");

    FPMMConfig memory config = fpmmPoolConfigs[pool];
    if (config.lastRebalance > 0 && block.timestamp <= config.lastRebalance + config.rebalanceCooldown) {
      revert("LS: COOLDOWN_ACTIVE");
    }

    IFPMM fpmm = IFPMM(pool);
    (uint256 oraclePrice, uint256 poolPrice, , ) = fpmm.getPrices();
    require(oraclePrice > 0 && poolPrice > 0, "LS: INVALID_PRICES");

    uint256 rawUpperThresholdBps = fpmm.rebalanceThresholdAbove();
    require(rawUpperThresholdBps > 0 && rawUpperThresholdBps <= 10_000, "LS: INVALID_UPPER_THRESHOLD");

    uint256 rawLowerThresholdBps = fpmm.rebalanceThresholdBelow();
    require(rawLowerThresholdBps > 0 && rawLowerThresholdBps <= 10_000, "LS: INVALID_LOWER_THRESHOLD");

    // Convert basis points to scaled decimals (e.g. 10000 bps = 1.0)
    uint256 upperThreshold = (rawUpperThresholdBps * SCALE) / BPS_SCALE;
    uint256 lowerThreshold = (rawLowerThresholdBps * SCALE) / BPS_SCALE;

    // Calculate bounds
    uint256 upperBound = (oraclePrice * (SCALE + upperThreshold)) / SCALE;
    uint256 lowerBound = (oraclePrice * (SCALE - lowerThreshold)) / SCALE;

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
