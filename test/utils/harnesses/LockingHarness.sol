// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { Locking } from "contracts/governance/locking/Locking.sol";

contract LockingHarness is Locking {
  uint32 public blockNumberMocked;
  uint32 public epochShift;

  constructor(bool disableInitializers) Locking(disableInitializers) {}

  function incrementBlock(uint32 _amount) external {
    blockNumberMocked = blockNumberMocked + _amount;
  }

  function reduceBlock(uint32 _amount) external {
    blockNumberMocked = blockNumberMocked - _amount;
  }

  function getBlockNumber() internal view override returns (uint32) {
    return blockNumberMocked;
  }

  function getMaxSlopePeriod() public pure returns (uint32) {
    return MAX_SLOPE_PERIOD;
  }

  function getMaxCliffPeriod() public pure returns (uint32) {
    return MAX_CLIFF_PERIOD;
  }

  function getLockTest(
    uint96 amount,
    uint32 slope,
    uint32 cliff
  ) external view returns (uint96 lockAmount, uint96 lockSlope) {
    (lockAmount, lockSlope) = getLock(amount, slope, cliff);
  }

  function _getEpochShift(uint32) internal view override returns (uint32) {
    if (_isPreL2Transition(getBlockNumber())) {
      return epochShift;
    }
    return l2EpochShift;
  }

  function setEpochShift(uint32 _epochShift) external {
    epochShift = _epochShift;
  }

  function setBlock(uint32 _block) external {
    blockNumberMocked = _block;
  }

  function blockTillNextPeriod() external view returns (uint256) {
    uint256 currentWeek = this.getWeek();
    if (_isPreL2Transition(getBlockNumber())) {
      return (WEEK * (currentWeek + startingPointWeek + 1)) + _getEpochShift(getBlockNumber()) - getBlockNumber();
    }
    return
      (L2_WEEK * uint256(int256(currentWeek) + l2StartingPointWeek + 1)) +
      _getEpochShift(getBlockNumber()) -
      getBlockNumber();
  }

  function setStatingPointWeek(uint32 _week) external {
    startingPointWeek = _week;
  }
}
