// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { Ownable } from "openzeppelin-contracts-next/contracts/access/Ownable.sol";

import { LiquidityStrategy } from "./LiquidityStrategy.sol";
import { ReserveRebalancer } from "./ReserveRebalancer.sol";
import { ReservePolicy } from "./ReservePolicy.sol";
import { LiquidityStrategyTypes as LQ } from "./libraries/LiquidityStrategyTypes.sol";

contract ReserveLiquidityStrategy is LiquidityStrategy, ReserveRebalancer, ReservePolicy {
  using LQ for LQ.Context;

  /// @notice Constructor
  /// @param _initialOwner the initial owner of the contract
  /// @param _reserve the Mento Protocol Reserve contract
  constructor(address _initialOwner, address _reserve) ReserveRebalancer(_reserve) LiquidityStrategy(_initialOwner) {}

  /* =========================================================== */
  /* ==================== Virtual Functions ==================== */
  /* =========================================================== */

  function _ensurePool(address pool) internal view override(LiquidityStrategy, ReserveRebalancer) {
    LiquidityStrategy._ensurePool(pool);
  }

  function _getReserve(address) internal view override returns (address) {
    return address(reserve);
  }

  function _buildExpansionAction(
    LQ.Context memory ctx,
    uint256 amountIn,
    uint256 amountOut
  ) internal view override(LiquidityStrategy, ReservePolicy) returns (LQ.Action memory action) {
    return ReservePolicy._buildExpansionAction(ctx, amountIn, amountOut);
  }

  function _buildContractionAction(
    LQ.Context memory ctx,
    uint256 amountIn,
    uint256 amountOut
  ) internal view override(LiquidityStrategy, ReservePolicy) returns (LQ.Action memory action) {
    return ReservePolicy._buildContractionAction(ctx, amountIn, amountOut);
  }

  function _execute(
    LQ.Context memory ctx,
    LQ.Action memory action
  ) internal override(LiquidityStrategy, ReserveRebalancer) returns (bool) {
    return ReserveRebalancer._execute(ctx, action);
  }
}
