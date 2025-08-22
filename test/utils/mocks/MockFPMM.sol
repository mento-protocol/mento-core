// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

contract MockFPMM {
  address public token0;
  address public token1;
  uint256 public rebalanceIncentive = 100; // 1%
  uint256 public rebalanceThresholdAbove = 500; // 5%
  uint256 public rebalanceThresholdBelow = 500; // 5%

  uint256 public diffBps = 0;
  bool public poolAbove = false;

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
    return (1e18, 1e18, 1e18, 1e18, diffBps, poolAbove);
  }

  function setDiffBps(uint256 _diffBps, bool _poolAbove) external {
    diffBps = _diffBps;
    poolAbove = _poolAbove;
  }

  function setRebalanceIncentive(uint256 _incentive) external {
    rebalanceIncentive = _incentive;
  }
}
