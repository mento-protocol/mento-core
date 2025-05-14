// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, reentrancy
pragma solidity ^0.8;

import { IFPMMCallee } from "contracts/interfaces/IFPMMCallee.sol";
import { FPMM } from "contracts/swap/FPMM.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
import { MockExchange } from "./MockExchange.sol";

contract ArbitrageFlashLoanReceiver is IFPMMCallee {
  FPMM public fpmm;
  MockExchange public exchange;
  address public token0;
  address public token1;
  uint256 public profit0;
  uint256 public profit1;

  constructor(address _fpmm, address _exchange, address _token0, address _token1) {
    fpmm = FPMM(_fpmm);
    exchange = MockExchange(_exchange);
    token0 = _token0;
    token1 = _token1;
  }

  function executeArbitrage(bool borrowToken0, uint256 borrowAmount) external {
    // Initiate flash loan
    if (borrowToken0) {
      fpmm.swap(borrowAmount, 0, address(this), "Arbitrage opportunity");
    } else {
      fpmm.swap(0, borrowAmount, address(this), "Arbitrage opportunity");
    }

    // Send profits to sender
    if (profit0 > 0) {
      IERC20(token0).transfer(msg.sender, profit0);
    }
    if (profit1 > 0) {
      IERC20(token1).transfer(msg.sender, profit1);
    }
  }

  function hook(address, uint256 amount0, uint256 amount1, bytes calldata) external override {
    require(msg.sender == address(fpmm), "Not called by FPMM");

    if (amount0 > 0) {
      IERC20(token0).approve(address(exchange), amount0);

      uint256 token1Received = exchange.swapToken0ForToken1(amount0);

      uint256 token1ToRepay = amount0; // Simplified, in real world would use getAmountOut

      // If our arbitrage was successful, we should have more token1 than needed for repayment
      require(token1Received > token1ToRepay, "Arbitrage not profitable");

      // Repay the flash loan
      IERC20(token1).transfer(address(fpmm), token1ToRepay);

      // Record profit
      profit1 = token1Received - token1ToRepay;
    } else if (amount1 > 0) {
      IERC20(token1).approve(address(exchange), amount1);

      uint256 token0Received = exchange.swapToken1ForToken0(amount1);

      uint256 token0ToRepay = amount1; // Simplified, in real world would use getAmountOut

      // If our arbitrage was successful, we should have more token0 than needed for repayment
      require(token0Received > token0ToRepay, "Arbitrage not profitable");

      // Repay the flash loan
      IERC20(token0).transfer(address(fpmm), token0ToRepay);

      // Record profit
      profit0 = token0Received - token0ToRepay;
    }
  }
}
