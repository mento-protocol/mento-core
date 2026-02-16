// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { MockERC20 } from "./MockERC20.sol";

import { ISystemParams } from "bold/src/Interfaces/ISystemParams.sol";

contract MockStabilityPool {
  address public debtToken;
  address public collToken;
  uint256 public MIN_BOLD_AFTER_REBALANCE;
  uint256 internal totalBoldDeposits;

  ISystemParams public systemParams;

  constructor(address _debtToken, address _collToken, address _systemParams) {
    debtToken = _debtToken;
    collToken = _collToken;
    systemParams = ISystemParams(_systemParams);
  }

  function setMIN_BOLD_AFTER_REBALANCE(uint256 _MIN_BOLD_AFTER_REBALANCE) external {
    MIN_BOLD_AFTER_REBALANCE = _MIN_BOLD_AFTER_REBALANCE;
  }

  function swapCollateralForStable(uint256 amountCollIn, uint256 amountStableOut) external {
    MockERC20(collToken).transferFrom(msg.sender, address(this), amountCollIn);
    require(
      MockERC20(debtToken).balanceOf(address(this)) >= amountStableOut,
      "StabilityPoolMock: Insufficient balance"
    );
    MockERC20(debtToken).transfer(msg.sender, amountStableOut);
  }

  function setTotalBoldDeposits(uint256 _newTotalBoldDeposits) external {
    totalBoldDeposits = _newTotalBoldDeposits;
  }

  function getTotalBoldDeposits() external view returns (uint256) {
    return totalBoldDeposits;
  }
}
