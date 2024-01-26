pragma solidity ^0.8.0;

import "../../contracts/governance/locking/Locking.sol";
import { ILockingExtended } from "contracts/governance/locking/interfaces/ILocking.sol";
import { MockMentoToken } from "./MockMentoToken.sol";

contract MockLocking {
  function initiateData(
    uint256 idLock,
    LibBrokenLine.Line memory line,
    address locker,
    address delegate
  ) external {}
}

contract MockLockingExtended is ILockingExtended {
  uint256 public week;
  uint256 public lockId;
  address public withdrawToken;

  uint96 public lockedAmount;
  uint256 public withdrawAmount;
  uint256 public relockAmount;
  uint256 public rebalanceAmount;

  function setWeek(uint256 _week) external {
    week = _week;
  }

  function getWeek() public view returns (uint256) {
    return week;
  }

  function setLockedAmount(uint96 _lockedAmount) external {
    lockedAmount = _lockedAmount;
  }

  function locked(address) external view override returns (uint96) {
    return lockedAmount;
  }

  function relock(
    uint256,
    address,
    uint96 newAmount,
    uint32,
    uint32
  ) external returns (uint256) {
    MockMentoToken(withdrawToken).transferFrom(msg.sender, address(this), newAmount - lockedAmount);
    lockedAmount = newAmount;
    return lockId + 1;
  }

  function lock(
    address,
    address,
    uint96 amount,
    uint32,
    uint32
  ) external returns (uint256) {
    MockMentoToken(withdrawToken).transferFrom(msg.sender, address(this), amount);
    lockedAmount = amount;
    return lockId + 1;
  }

  function setWithdraw(uint256 amount, address token) external {
    withdrawAmount = amount;
    withdrawToken = token;
  }

  function getAvailableForWithdraw(address) external view returns (uint96) {
    return uint96(withdrawAmount);
  }

  function withdraw() external {
    MockMentoToken(withdrawToken).mint(msg.sender, withdrawAmount);
  }
}
