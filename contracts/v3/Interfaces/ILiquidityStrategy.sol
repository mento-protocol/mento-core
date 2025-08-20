// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { LiquidityTypes as LQ } from "../libraries/LiquidityTypes.sol";

interface ILiquidityStrategy {
  /**
   * @notice Executes a liquidity action based on the provided action data.
   * @param action The action data to execute.
   * @param data Additional data required for execution (if any).
   * @return ok True if the execution was successful, false otherwise.
   */
  function execute(LQ.Action calldata action, bytes calldata data) external returns (bool ok);
}
