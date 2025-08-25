// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { LiquidityTypes as LQ } from "../libraries/LiquidityTypes.sol";

interface ILiquidityStrategy {
  /**
   * @notice Executes a liquidity action based on the provided action data.
   * @param action The action data to execute.
   * @return ok True if the execution was successful, false otherwise.
   */
  function execute(LQ.Action calldata action) external returns (bool ok);
}
