// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { MockERC20 } from "./MockERC20.sol";

contract MockStabilityPool {
  address public debtToken;

  constructor(address _debtToken) {
    debtToken = _debtToken;
  }

  function swapCollateralForStable(uint256 amountCollIn, uint256 amountStableOut) external {
    require(
      MockERC20(debtToken).balanceOf(address(this)) >= amountStableOut,
      "StabilityPoolMock: Insufficient balance"
    );
    MockERC20(debtToken).transfer(msg.sender, amountStableOut);
  }
}
