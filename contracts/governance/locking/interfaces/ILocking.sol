// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface ILocking {
  function lock(
    address account,
    address delegate,
    uint96 amount,
    uint32 slope,
    uint32 cliff
  ) external returns (uint256);
}

interface ILockingExtended {
  function lock(
    address account,
    address delegate,
    uint96 amount,
    uint32 slope,
    uint32 cliff
  ) external returns (uint256);

  function getWeek() external view returns (uint256);

  function locked(address account) external view returns (uint96);

  function relock(
    uint256 id,
    address newDelegate,
    uint96 newAmount,
    uint32 newSlope,
    uint32 newCliff
  ) external returns (uint256);

  function withdraw() external;

  function getAvailableForWithdraw(address account) external returns (uint96);
}
