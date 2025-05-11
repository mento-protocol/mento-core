// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { LiquidityStrategy } from "contracts/swap/LiquidityStrategy.sol";

contract MockLiquidityStrategy is LiquidityStrategy {
  constructor() LiquidityStrategy(false) {}

  function _executeRebalance(address pool, uint256 oraclePrice, PriceDirection priceDirection) internal override {}
}
