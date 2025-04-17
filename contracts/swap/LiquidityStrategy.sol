// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { ILiquidityStrategy } from "../interfaces/ILiquidityStrategy.sol";
import { UD60x18, unwrap, wrap } from "prb/math/UD60x18.sol";

// Notes:
// We need to have a reference to the pool, especially if a strategy is used by multiple pools.
// Get price
// The callback is called by the fpmm after it executes the transfer out
// Once we have moved tokens out, we don't want to make anothe call, we need to be sure that no transfers are done so we can see that the
// The callback function calls another function that calls the mint function
// There won't

interface IFPMM {
  function getPrices()
    external
    view
    returns (uint256 reserve0, uint256 reserve1, uint256 oraclePrice, uint256 rebalanceFee);
  function token0() external view returns (address);
  function token1() external view returns (address);
}

abstract contract LiquidityStrategy is Ownable, ILiquidityStrategy {
  // Maps a pool address to its state.


  // Create mapping for pooladdress to rebalancing config
  // - Config can include rebalcing cooldown, rebalancing thresholds (upper and lower), etc.

  mapping(address => PoolState) public poolStates;
  mapping(address => uint256) public tokenPrecisionMultipliers;

  /**
   * @notice Registers a pool to initialize its state.
   * @param pool The address of the pool to register.
   */
  function registerPool(address pool) external onlyOwner {
    require(poolStates[pool].lastRebalance == 0, "Pool already registered");
    poolStates[pool] = PoolState({ lastRebalance: block.timestamp });
  }

  /**
   * @notice Unregisters a pool.
   * @param pool The address of the pool to unregister.
   */
  function unregisterPool(address pool) external onlyOwner {
    delete poolStates[pool];
  }

  /**
   * @notice Triggers the rebalancing process for a pool.
   *         It obtains the pre-rebalance price, executes rebalancing logic,
   *         updates the pool's state, and emits an event with the pricing information.
   * @param pool The address of the pool to rebalance.
   */
  function rebalance(address pool) external {
    // Cast the pool to IFPMM
    // Get the price from the pool
    // Calculate the pool price using the reserves
    // Determine what sort of rebalance to do
    // If pool price is greater than oracle price:
    // - Move stable tokens out of the pool and burn them
    // - FPMM calls the call back function
    // - We move collateral tokens out of the pool, and into the liquidity source
    // If pool price is less than oracle price:
    // - Move collateral tokens out of the pool
    // - FPMM calls the call back function
    // - We mint stable tokens into the pool

    IFPMM fpm = IFPMM(pool);

    (uint256 reserve0, uint256 reserve1, uint256 oraclePrice, uint256 rebalanceFee) = fpm.getPrices();
    uint256 priceBefore = _calculatePoolPrice(reserve0, reserve1, fpm.token0(), fpm.token1());

    _executeRebalance(pool, priceBefore, oraclePrice, callback);

    // 4) read back the new on‑chain price
    uint256 priceAfter = fpm.getPrice();

    poolStates[pool].lastRebalance = block.timestamp;
    emit Rebalance(pool, priceBefore, priceAfter);
  }

  function callback(address pool, uint256 amount0, uint256 amount1) external virtual {
    // TODO: Implement the callback logic
  }


  // TODO: It would be better if the pool just returned the price
  function _calculatePoolPrice(
    uint256 reserve0,
    uint256 reserve1,
    address token0,
    address token1
  ) internal view returns (uint256) {

    // TODO: Confirm that token0 is the stable token)

    require(reserve0 > 0 && reserve1 > 0, "Invalid reserves when calculating pool price");

    uint256 scaledReserve0 = reserve0 * tokenPrecisionMultipliers[token0];
    uint256 scaledReserve1 = reserve1 * tokenPrecisionMultipliers[token1];

    UD60x18 numerator = wrap(scaledReserve1);
    UD60x18 denominator = wrap(scaledReserve0);
 
    // Price = reserve1/reserve0
    uint256 priceScaled = unwrap(numerator.div(denominator));

    // Adjust price for token decimal differences
    return priceScaled / tokenPrecisionMultipliers[token1];
  }

  /**
   * @notice Contains the specific logic that executes the rebalancing.
   * @dev Implementations should perform any token movements, minting, or burning here.
   * @param pool The address of the pool to rebalance.
   * @param priceBefore The on‑chain price before any action.
   * @param oraclePrice The off‑chain target price.
   */
  function _executeRebalance(address pool, uint256 priceBefore, uint256 oraclePrice, function ) internal virtual;
}
