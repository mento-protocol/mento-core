// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { ILiquidityStrategy } from "contracts/interfaces/ILiquidityStrategy.sol";

contract MockFPMM {
  address public token0;
  address public token1;
  uint256 public rebalanceIncentive = 100; // 1%
  uint256 public rebalanceThresholdAbove = 500; // 5%
  uint256 public rebalanceThresholdBelow = 500; // 5%

  uint256 public diffBps = 0;
  bool public poolAbove = false;

  // Price data
  uint256 public oracleNum = 1e18;
  uint256 public oracleDen = 1e18;
  uint256 public reserveNum = 1e18;
  uint256 public reserveDen = 1e18;

  constructor(address _token0, address _token1, bool skipSort) {
    // With the actual FPMM we expect the tokens will be sorted
    // So for our tests we also want to ensure the same

    if (skipSort) {
      // Deliberately don't sort tokens to test mismatch
      token0 = _token0;
      token1 = _token1;
      return;
    } else {
      (token0, token1) = _token0 < _token1 ? (_token0, _token1) : (_token1, _token0);
    }
  }

  function metadata() external view returns (uint256, uint256, uint256, uint256, address, address) {
    return (1e18, 1e18, 0, 0, token0, token1);
  }

  function getPrices() external view returns (uint256, uint256, uint256, uint256, uint256, bool) {
    return (oracleNum, oracleDen, reserveNum, reserveDen, diffBps, poolAbove);
  }

  function setPrices(
    uint256 _oracleNum,
    uint256 _oracleDen,
    uint256 _reserveNum,
    uint256 _reserveDen,
    uint256 _diffBps,
    bool _poolAbove
  ) external {
    oracleNum = _oracleNum;
    oracleDen = _oracleDen;
    reserveNum = _reserveNum;
    reserveDen = _reserveDen;
    diffBps = _diffBps;
    poolAbove = _poolAbove;
  }

  function tokens() external view returns (address, address) {
    return (token0, token1);
  }

  function setDiffBps(uint256 _diffBps, bool _poolAbove) external {
    diffBps = _diffBps;
    poolAbove = _poolAbove;
  }

  function setRebalanceIncentive(uint256 _incentive) external {
    rebalanceIncentive = _incentive;
  }

  function rebalance(uint256 amount0Out, uint256 amount1Out, bytes calldata data) external {
    // Simulate the pool calling back into the strategy's hook
    // In the real FPMM, this would transfer tokens and then call the hook
    ILiquidityStrategy(msg.sender).onRebalance(msg.sender, amount0Out, amount1Out, data);
  }
}
