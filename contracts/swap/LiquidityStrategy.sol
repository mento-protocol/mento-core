// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { EnumerableSet } from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import { ILiquidityStrategy } from "../interfaces/ILiquidityStrategy.sol";
import { IReserve } from "../interfaces/IReserve.sol";
import { IFPMM } from "../interfaces/IFPMM.sol";

abstract contract LiquidityStrategy is OwnableUpgradeable, ILiquidityStrategy {
  using EnumerableSet for EnumerableSet.AddressSet;

  mapping(address => FPMMConfig) public fpmmPoolConfigs;
  mapping(address => uint256) public tokenPrecisionMultipliers;

  EnumerableSet.AddressSet private fpmmPools;

  IReserve public reserve;

  constructor(bool disableInitializers) {
    if (disableInitializers) {
      _disableInitializers();
    }
  }

  function initialize(address _reserve) external initializer {
    __Ownable_init();
    setReserve(_reserve);
  }

  function setReserve(address _reserve) public onlyOwner {
    require(_reserve != address(0), "Reserve cannot be the zero address");
    reserve = IReserve(_reserve);
    emit ReserveSet(_reserve);
  }

  /**
   * @notice Adds an FPMM pool.
   * @param pool The address of the pool to add.
   * @param rebalanceThreshold The threshold as a fixed-point number with 18 decimals
   * @param rebalanceCooldown The cooldown period for the next rebalance.
   */
  function addPool(address pool, uint256 rebalanceThreshold, uint256 rebalanceCooldown) external onlyOwner {
    require(pool != address(0), "Pool cannot be the zero address");
    require(fpmmPools.add(pool), "Pool already added");
    require(rebalanceThreshold > 0, "Rebalance threshold must be greater than 0");
    require(rebalanceThreshold <= 1e18, "Rebalance threshold cannot exceed 100%"); // TODO: Confirm
    require(rebalanceCooldown > 0, "Rebalance cooldown must be greater than 0");

    uint256 decimals0 = IFPMM(pool).decimals0();
    uint256 decimals1 = IFPMM(pool).decimals1();

    require(decimals0 <= 18, "Token 0 decimals must be <= 18");
    require(decimals1 <= 18, "Token 1 decimals must be <= 18");

    tokenPrecisionMultipliers[IFPMM(pool).token0()] = 10 ** (18 - decimals0);
    tokenPrecisionMultipliers[IFPMM(pool).token1()] = 10 ** (18 - decimals1);

    fpmmPoolConfigs[pool] = FPMMConfig({
      lastRebalance: 0,
      rebalanceThreshold: rebalanceThreshold,
      rebalanceCooldown: rebalanceCooldown
    });

    emit FPMMPoolAdded(pool, rebalanceThreshold, rebalanceCooldown);
  }

  /**
   * @notice Removes an FPMM pool.
   * @param pool The address of the pool to remove.
   */
  function removePool(address pool) external onlyOwner {
    require(fpmmPools.remove(pool), "Pool is not added");
    delete fpmmPoolConfigs[pool];
    emit FPMMPoolRemoved(pool);
  }

  /**
   * @notice Triggers the rebalancing process for a pool.
   *         It obtains the pre-rebalance price, executes rebalancing logic,
   *         updates the pool's state, and emits an event with the pricing information.
   * @param pool The address of the pool to rebalance.
   */
  function rebalance(address pool) external {
    require(fpmmPools.contains(pool), "Pool is not added");
    if (block.timestamp <= fpmmPoolConfigs[pool].lastRebalance + fpmmPoolConfigs[pool].rebalanceCooldown) {
      emit RebalanceSkippedNotCool(pool);
      revert("Rebalance cooldown not elapsed");
    }

    IFPMM fpm = IFPMM(pool);
    (uint256 oraclePrice, uint256 poolPrice) = fpm.getPrices();
    // TODO: Are these checks valid? Can we have 0 oracle price?
    require(oraclePrice > 0, "Oracle price must be greater than 0");
    require(poolPrice > 0, "Pool price must be greater than 0");

    // TODO: Use PRBMath for precision
    uint256 threshold = fpmmPoolConfigs[pool].rebalanceThreshold;
    uint256 upperThreshold = (oraclePrice * (1e18 + threshold)) / 1e18;
    uint256 lowerThreshold = (oraclePrice * (1e18 - threshold)) / 1e18;

    PriceDirection priceDirection;

    if (poolPrice > upperThreshold) {
      priceDirection = PriceDirection.ABOVE_ORACLE;
    } else if (poolPrice < lowerThreshold) {
      priceDirection = PriceDirection.BELOW_ORACLE;
    } else {
      emit RebalanceSkippedPriceInRange(pool);
      return;
    }

    fpmmPoolConfigs[pool].lastRebalance = block.timestamp;

    // Execute the rebalance
    _executeRebalance(pool, poolPrice, oraclePrice, priceDirection);

    // Get final price for event emission
    (, uint256 priceAfterRebalance) = fpm.getPrices();
    emit Rebalance(pool, poolPrice, priceAfterRebalance);
  }

  /**
   * @notice Contains the specific logic that executes the rebalancing.
   * @dev Implementations should perform any token movements, minting, or burning here.
   * @param pool The address of the pool to rebalance.
   * @param poolPrice The on‑chain price before any action.
   * @param oraclePrice The off‑chain target price.
   * @param priceDirection The direction of the price movement.
   */
  function _executeRebalance(
    address pool,
    uint256 poolPrice,
    uint256 oraclePrice,
    PriceDirection priceDirection
  ) internal virtual;

  /**
   * @notice Handles the completion of a rebalancing operation.
   * @dev This function should be called by the FPMM contract after token transfers are complete.
   * @param data Encoded data containing all necessary information:
   *             - Pool address
   *             - Token out address
   *             - Amount out
   *             - Price direction
   *             - Amount to send from reserve
   */
  function onRebalanceCallback(bytes calldata data) external virtual;
}
