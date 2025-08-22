// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { Test } from "mento-std/Test.sol";

import { MockERC20 } from "test/utils/mocks/MockERC20.sol";

interface IFPMMCallee {
  function hook(address, uint256, uint256, bytes calldata) external;
}

contract MockFPMMPool is Test {
  uint256 public oraclePriceNumerator;
  uint256 public oraclePriceDenominator;
  uint256 public poolPriceNumerator;
  uint256 public poolPriceDenominator;
  uint256 public priceDifference;
  bool public reservePriceAboveOraclePrice;

  uint256 public reserve0;
  uint256 public reserve1;
  address public hookTarget;
  uint256 public rebalanceThresholdAbove;
  uint256 public rebalanceThresholdBelow;

  MockERC20 public token0_;
  MockERC20 public token1_;

  constructor(address _hookTarget, address _token0, address _token1) {
    hookTarget = _hookTarget;
    token0_ = MockERC20(_token0);
    token1_ = MockERC20(_token1);
    reserve0 = 1000e18;
    reserve1 = 1000e18;

    oraclePriceNumerator = 1e18;
    oraclePriceDenominator = 1e18;
    poolPriceNumerator = 1e18;
    poolPriceDenominator = 1e18;
    priceDifference = 0;
    reservePriceAboveOraclePrice = false;

    rebalanceThresholdAbove = 100;
    rebalanceThresholdBelow = 100;
  }

  function setPrices(
    uint256 oNumerator,
    uint256 oDenominator,
    uint256 pNumerator,
    uint256 pDenominator,
    uint256 pDiff,
    bool rAboveO
  ) external {
    oraclePriceNumerator = oNumerator;
    oraclePriceDenominator = oDenominator;
    poolPriceNumerator = pNumerator;
    poolPriceDenominator = pDenominator;
    priceDifference = pDiff;
    reservePriceAboveOraclePrice = rAboveO;
  }

  function setReserves(uint256 _r0, uint256 _r1) external {
    reserve0 = _r0;
    reserve1 = _r1;
  }

  function getPrices() external view returns (uint256, uint256, uint256, uint256, uint256, bool) {
    return (
      oraclePriceNumerator,
      oraclePriceDenominator,
      poolPriceNumerator,
      poolPriceDenominator,
      priceDifference,
      reservePriceAboveOraclePrice
    );
  }

  function getReserves() external view returns (uint256, uint256, uint256) {
    return (reserve0, reserve1, block.timestamp);
  }

  function token0() external view returns (address) {
    return address(token0_);
  }

  function token1() external view returns (address) {
    return address(token1_);
  }

  function decimals0() external pure returns (uint256) {
    return 1e18;
  }

  function decimals1() external pure returns (uint256) {
    return 1e18;
  }

  function protocolFee() external pure returns (uint256) {
    return 9000;
  }

  function rebalanceIncentive() external pure returns (uint256) {
    return 100;
  }

  function metadata() external view returns (uint256, uint256, uint256, uint256, address, address) {
    return (10 ** token0_.decimals(), 10 ** token1_.decimals(), reserve0, reserve1, address(token0_), address(token1_));
  }

  function setRebalanceThreshold(uint256 _thresholdAbove, uint256 _thresholdBelow) external {
    rebalanceThresholdAbove = _thresholdAbove;
    rebalanceThresholdBelow = _thresholdBelow;
  }

  function rebalance(uint256 amount0Out, uint256 amount1Out, bytes calldata data) external {
    require(msg.sender == hookTarget, "MockFPMMPool: Caller not strategy");

    if (amount0Out > 0) {
      token0_.transfer(msg.sender, amount0Out);
    }

    if (amount1Out > 0) {
      token1_.transfer(msg.sender, amount1Out);
    }

    IFPMMCallee(msg.sender).hook(msg.sender, amount0Out, amount1Out, data);
  }
}
