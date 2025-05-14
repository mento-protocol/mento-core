// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { IFPMM } from "contracts/interfaces/IFPMM.sol";
import { Test } from "mento-std/Test.sol";

import { MockERC20 } from "test/utils/mocks/MockERC20.sol";

interface IFPMMCallee {
  function hook(address, uint256, uint256, bytes calldata) external;
}

contract MockFPMMPool is IFPMM, Test {
  uint256 public oraclePrice;
  uint256 public poolPrice;
  uint256 public reserve0;
  uint256 public reserve1;
  address public hookTarget;
  uint256 public rebalanceThreshold;

  MockERC20 public token0_;
  MockERC20 public token1_;

  constructor(address _hookTarget, address _token0, address _token1) {
    hookTarget = _hookTarget;
    token0_ = MockERC20(_token0);
    token1_ = MockERC20(_token1);
    reserve0 = 1000 * 10 ** 18;
    reserve1 = 1000 * 10 ** 18;
    oraclePrice = 1 * 10 ** 18;
    poolPrice = 1 * 10 ** 18;
    rebalanceThreshold = 100;
  }

  function setPrices(uint256 o, uint256 p) external {
    oraclePrice = o;
    poolPrice = p;
  }

  function setReserves(uint256 _r0, uint256 _r1) external {
    reserve0 = _r0;
    reserve1 = _r1;
  }

  function getPrices() external view returns (uint256 o, uint256 p) {
    return (oraclePrice, poolPrice);
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

  function decimals0() external view returns (uint256) {
    return 18;
  }

  function decimals1() external view returns (uint256) {
    return 18;
  }

  function protocolFee() external view returns (uint256) {
    return 9000;
  }

  function metadata() external view returns (uint256, uint256, uint256, uint256, address, address) {
    return (0, 0, 0, 0, address(token0_), address(token1_));
  }

  function setRebalanceThreshold(uint256 _threshold) external {
    rebalanceThreshold = _threshold;
  }

  function rebalance(uint256 amount0Out, uint256 amount1Out, address recipient, bytes calldata data) external override {
    require(msg.sender == hookTarget, "MockFPMMPool: Caller not strategy");
    require(recipient == hookTarget, "MockFPMMPool: Recipient not strategy");

    if (amount0Out > 0) {
      token0_.transfer(recipient, amount0Out);
    }

    if (amount1Out > 0) {
      token1_.transfer(recipient, amount1Out);
    }

    IFPMMCallee(recipient).hook(address(this), amount0Out, amount1Out, data);
  }
}
