// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { LiquidityStrategy } from "contracts/swap/LiquidityStrategy.sol";

contract MockLiquidityStrategy is LiquidityStrategy {
  constructor() LiquidityStrategy(false) {}

  function initialize() external initializer {
    __Ownable_init();
  }

  function _executeRebalance(
    address pool,
    uint256 oraclePriceNumerator,
    uint256 oraclePriceDenominator,
    PriceDirection priceDirection
  ) internal override {}
}
