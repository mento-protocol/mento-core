// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
pragma solidity ^0.8;

import { IFPMMCallee } from "contracts/interfaces/IFPMMCallee.sol";
import { FPMM } from "contracts/swap/FPMM.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
contract MockLiquidityStrategy is IFPMMCallee {
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
  bool public shouldImprovePrice;
  uint256 public profitPercentage;
  address public rebalanceRecipient;

  constructor(address _fpmm, address _token0, address _token1) {
    fpmm = FPMM(_fpmm);
    token0 = _token0;
    token1 = _token1;

    // Default settings
    shouldFail = false;
    shouldPartiallyRebalance = false;
    shouldUseExactRequiredAmounts = true;
    shouldImprovePrice = true;
    profitPercentage = 0;
    rebalanceRecipient = address(this);
  }

  function setShouldFail(bool _shouldFail) external {
    shouldFail = _shouldFail;
  }

  function setProfitPercentage(uint256 _profitPercentage) external {
    profitPercentage = _profitPercentage;
  }

  function setShouldImprovePrice(bool _shouldImprovePrice) external {
    shouldImprovePrice = _shouldImprovePrice;
  }

  function setRebalanceRecipient(address _rebalanceRecipient) external {
    rebalanceRecipient = _rebalanceRecipient;
  }

  // Execute a flash loan to rebalance the pool
  function executeRebalance(uint256 amount0Out, uint256 amount1Out) external {
    fpmm.rebalance(amount0Out, amount1Out, rebalanceRecipient, "Rebalance operation");
  }

  // The hook function that gets called during the flash loan
  function hook(address, uint256 amount0, uint256 amount1, bytes calldata) external override {
    require(msg.sender == address(fpmm), "Not called by FPMM");

    if (shouldFail) {
      // For testing failure scenarios
      revert("MockRebalancer: Forced failure");
    }

    (uint256 oraclePrice, uint256 reservePrice, uint256 decimals0, uint256 decimals1) = fpmm.getPrices();

    // Calculate amounts needed for rebalancing
    uint256 token0ToAdd;
    uint256 token1ToAdd;

    if (shouldImprovePrice) {
      if (reservePrice > oraclePrice) {
        token0ToAdd = fpmm.convertWithRate(amount1, decimals1, decimals0, 1e18, oraclePrice);
        if (profitPercentage > 0) {
          token0ToAdd = (token0ToAdd * (100 - profitPercentage)) / 100;
        }
      } else {
        token1ToAdd = fpmm.convertWithRate(amount0, decimals0, decimals1, oraclePrice, 1e18);
        if (profitPercentage > 0) {
          token1ToAdd = (token1ToAdd * (100 - profitPercentage)) / 100;
        }
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
}
