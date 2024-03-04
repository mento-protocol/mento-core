// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "../libs/LibBrokenLine.sol";

/**
 * @title INextVersionLock
 * @notice Interface that a new version of the locking contract must implement to be able to migrate locks
 */

interface INextVersionLock {
  /**
   * @notice Initiates the lock in the new version of the locking contract
   * @param idLock Lock id of lock to safe
   * @param line line of the lock id to safe
   * @param locker Lock owner
   * @param delegate Lock delegate
   */
  function initiateData(
    uint256 idLock,
    LibBrokenLine.Line memory line,
    address locker,
    address delegate
  ) external;
}
