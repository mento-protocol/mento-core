// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
pragma solidity ^0.8;

import { FPMM } from "contracts/swap/FPMM.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";

interface ILiquidityStrategyHook {
  function onRebalance(address sender, uint256 amount0Out, uint256 amount1Out, bytes calldata data) external;
}

contract MockLiquidityStrategy is ILiquidityStrategyHook {
  FPMM public fpmm;
  address public token0;
  address public token1;

  bool public lastRebalanceSuccessful;
  uint256 public amountUsedForRebalance0;
  uint256 public amountUsedForRebalance1;

  // For testing different behaviors
  bool public shouldFail;
  bool public shouldPartiallyRebalance;
  bool public shouldUseExactRequiredAmounts;
  bool public shouldMovePrice;
  uint256 public profitPercentage;

  constructor(address _fpmm, address _token0, address _token1) {
    fpmm = FPMM(_fpmm);
    token0 = _token0;
    token1 = _token1;

    // Default settings
    shouldFail = false;
    shouldPartiallyRebalance = false;
    shouldUseExactRequiredAmounts = true;
    shouldMovePrice = true;
    profitPercentage = 0;
  }

  function setShouldFail(bool _shouldFail) external {
    shouldFail = _shouldFail;
  }

  function setProfitPercentage(uint256 _profitPercentage) external {
    profitPercentage = _profitPercentage;
  }

  function setShouldMovePrice(bool _shouldMovePrice) external {
    shouldMovePrice = _shouldMovePrice;
  }

  // Execute a flash loan to rebalance the pool
  function executeRebalance(uint256 amount0Out, uint256 amount1Out) external {
    fpmm.rebalance(amount0Out, amount1Out, "Rebalance operation");
  }

  // The hook function that gets called during the flash loan
  function onRebalance(address, uint256 amount0, uint256 amount1, bytes calldata) external override {
    require(msg.sender == address(fpmm), "Not called by FPMM");

    if (shouldFail) {
      // For testing failure scenarios
      revert("MockRebalancer: Forced failure");
    }

    (uint256 dec0, uint256 dec1, , , , ) = fpmm.metadata();

    (uint256 oraclePriceNumerator, uint256 oraclePriceDenominator, , , , , ) = fpmm.getRebalancingState();

    // Calculate amounts needed for rebalancing
    uint256 token0ToAdd;
    uint256 token1ToAdd;

    if (shouldMovePrice) {
      token0ToAdd = convertWithRate(amount1, dec1, dec0, oraclePriceDenominator, oraclePriceNumerator);
      token1ToAdd = convertWithRate(amount0, dec0, dec1, oraclePriceNumerator, oraclePriceDenominator);
      if (profitPercentage > 0) {
        token0ToAdd = (token0ToAdd * (10000 - profitPercentage)) / 10000;
        token1ToAdd = (token1ToAdd * (10000 - profitPercentage)) / 10000;
      }
    } else {
      token0ToAdd = amount0;
      token1ToAdd = amount1;
    }
    // Transfer tokens back to FPMM
    if (token0ToAdd > 0) {
      IERC20(token0).transfer(address(fpmm), token0ToAdd);
    }
    if (token1ToAdd > 0) {
      IERC20(token1).transfer(address(fpmm), token1ToAdd);
    }
  }

  function convertWithRate(
    uint256 amount,
    uint256 fromDecimals,
    uint256 toDecimals,
    uint256 numerator,
    uint256 denominator
  ) public pure returns (uint256) {
    return (amount * numerator * toDecimals) / (denominator * fromDecimals);
  }
}
