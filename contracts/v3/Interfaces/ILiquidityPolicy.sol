// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { LiquidityTypes as LQ } from "../libraries/LiquidityTypes.sol";

interface ILiquidityPolicy {
  /// @notice Returns the name of the liquidity policy.
  function name() external view returns (string memory liquidityPolicyName);

  /**
   * @notice Determines if the policy should act based on the current context.
   * @param ctx The context containing pool, reserves, prices, and other relevant data.
   * @return shouldAct True if the policy should take action, false otherwise.
   * @return action The action to be taken if shouldAct is true.
   */
  function determineAction(LQ.Context memory ctx) external view returns (bool shouldAct, LQ.Action memory action);
}
