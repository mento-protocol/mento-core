// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { ITokenVestingPlans } from "contracts/vesting/interfaces/ITokenVestingPlans.sol";
import { MockMentoToken } from "./MockMentoToken.sol";
import { console } from "forge-std-next/Test.sol";

contract MockTokenVestingPlans is ITokenVestingPlans {
  uint256 public balance;
  uint256 public redeemableTokens;
  uint256 public _planBalanceOf;
  address public token;

  ITokenVestingPlans.Plan public plan;

  function setBalanceOf(uint256 _balance) external {
    balance = _balance;
  }

  function balanceOf(address) external view returns (uint256) {
    return balance;
  }

  function tokenOfOwnerByIndex(address, uint256) external pure returns (uint256) {
    return 1;
  }

  function setPlans(ITokenVestingPlans.Plan memory _plan) external {
    plan = _plan;
    token = _plan.token;
  }

  function plans(uint256) external view returns (ITokenVestingPlans.Plan memory) {
    return plan;
  }

  function setRedeemableTokens(uint256 _redeemableTokens) external {
    redeemableTokens = _redeemableTokens;
  }

  function redeemPlans(uint256[] calldata) public {
    MockMentoToken(token).mint(msg.sender, redeemableTokens);
  }

  function setPlanBalanceOf(uint256 _balance) external {
    _planBalanceOf = _balance;
  }

  function planBalanceOf(
    uint256,
    uint256,
    uint256
  )
    public
    view
    returns (
      uint256,
      uint256,
      uint256
    )
  {
    return (_planBalanceOf, 0, 0);
  }
}
