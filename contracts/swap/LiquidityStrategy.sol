// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { EnumerableSet } from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import { ILiquidityStrategy } from "../interfaces/ILiquidityStrategy.sol";
import { IFPMM } from "../interfaces/IFPMM.sol";
import { UD60x18, ud } from "prb-math/UD60x18.sol";

/**
 * @title LiquidityStrategy
 * @notice Abstract base contract for implementing different liquidity sourcing strategies.
 *         Manages pool registration, threshold checks, and rebalance triggering logic.
 */
abstract contract LiquidityStrategy is OwnableUpgradeable, ILiquidityStrategy {
  using EnumerableSet for EnumerableSet.AddressSet;

  mapping(address => FPMMConfig) public fpmmPoolConfigs;
  mapping(address => uint256) public tokenPrecisionMultipliers;

  EnumerableSet.AddressSet private fpmmPools;

  /* ==================== Constructor & Initializer ==================== */

  constructor(bool disableInitializers) {
    if (disableInitializers) {
      _disableInitializers();
    }
  }

  function initialize() external initializer {
    __Ownable_init();
  }

  /* ==================== Admin Functions ==================== */

  /**
   * @notice Adds an FPMM pool.
   * @param pool The address of the pool to add.
   * @param threshold The threshold as a fixed-point number with 18 decimals
   * @param cooldown The cooldown period for the next rebalance.
   */
  function addPool(address pool, uint256 threshold, uint256 cooldown) external onlyOwner {
    require(pool != address(0), "Invalid pool");
    require(fpmmPools.add(pool), "Already added");
    require(threshold > 0 && threshold <= 1e18, "Invalid threshold"); // TODO: Confirm
    require(cooldown > 0, "Rebalance cooldown must be greater than 0");

    uint256 decimals0 = IFPMM(pool).decimals0();
    uint256 decimals1 = IFPMM(pool).decimals1();

    require(decimals0 <= 18 && decimals1 <= 18, "Token decimals too large");

    tokenPrecisionMultipliers[IFPMM(pool).token0()] = 10 ** (18 - decimals0);
    tokenPrecisionMultipliers[IFPMM(pool).token1()] = 10 ** (18 - decimals1);

    fpmmPoolConfigs[pool] = FPMMConfig({
      lastRebalance: 0,
      rebalanceThreshold: threshold,
      rebalanceCooldown: cooldown
    });

    emit FPMMPoolAdded(pool, threshold, cooldown);
  }

  /**
   * @notice Removes an FPMM pool.
   * @param pool The address of the pool to remove.
   */
  function removePool(address pool) external onlyOwner {
    require(fpmmPools.remove(pool), "Not added");
    delete fpmmPoolConfigs[pool];
    emit FPMMPoolRemoved(pool);
  }

  /* ==================== Rebalancing ==================== */

  /**
   * @notice Triggers the rebalancing process for a pool.
   *         Obtains the pre-rebalance price, executes rebalancing logic,
   *         updates the pool's state, and emits an event with the pricing information.
   * @param pool The address of the pool to rebalance.
   */
  function rebalance(address pool) external {
    require(fpmmPools.contains(pool), "Not a valid pool");

    FPMMConfig memory config = fpmmPoolConfigs[pool];
    if (block.timestamp <= config.lastRebalance + config.rebalanceCooldown) {
      emit RebalanceSkippedNotCool(pool);
      revert("Rebalance cooldown not elapsed");
    }

    IFPMM fpm = IFPMM(pool);
    (uint256 oraclePrice, uint256 poolPrice) = fpm.getPrices();
    // TODO: Are these checks valid? Can we have 0 oracle price?
    require(oraclePrice > 0 && poolPrice > 0, "Invalid prices");

    UD60x18 oracleP = ud(oraclePrice);
    UD60x18 poolP = ud(poolPrice);
    UD60x18 threshold = ud(config.rebalanceThreshold);

    UD60x18 upperBound = oracleP.mul(ud(1e18).add(threshold));
    UD60x18 lowerBound = oracleP.mul(ud(1e18).sub(threshold));

    PriceDirection priceDirection;

    if (poolP.gt(upperBound)) {
      priceDirection = PriceDirection.ABOVE_ORACLE;
    } else if (poolP.lt(lowerBound)) {
      priceDirection = PriceDirection.BELOW_ORACLE;
    } else {
      emit RebalanceSkippedPriceInRange(pool);
      return;
    }

    fpmmPoolConfigs[pool].lastRebalance = block.timestamp;

    // Execute the rebalance
    _executeRebalance(pool, oraclePrice, priceDirection);

    // Get final price for event emission
    (, uint256 priceAfterRebalance) = fpm.getPrices();
    emit RebalanceExecuted(pool, poolPrice, priceAfterRebalance);
  }

  /* ==================== Internal Functions ==================== */

  /**
   * @notice Contains the specific logic that executes the rebalancing.
   * @param pool The address of the pool to rebalance.
   * @param oraclePrice The off‑chain target price.
   * @param priceDirection The direction of the price movement.
   */
  function _executeRebalance(address pool, uint256 oraclePrice, PriceDirection priceDirection) internal virtual;

  /* ==================== View Functions ==================== */

  /**
   * @notice Checks if a pool is registered.
   * @param pool The address of the pool to check.
   * @return True if the pool is registered, false otherwise.
   */
  function isPoolRegistered(address pool) public view returns (bool) {
    return fpmmPools.contains(pool);
  }

  /**
   * @notice Returns all registered pools.
   * @return An array of pool addresses.
   */
  function getPools() external view returns (address[] memory) {
    return fpmmPools.values();
  }
}
