// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface ILocking {
  /**
   * @notice locks tokens in veMentoLocking contract.
   * @param account address of the owner of lock
   * @param delegate new delegate address
   * @param amount amount to lock
   * @param slope slope period in weeks
   * @param cliff cliff period in weeks
   * @return lockId lock id
   */
  function lock(
    address account,
    address delegate,
    uint96 amount,
    uint32 slope,
    uint32 cliff
  ) external returns (uint256);
}

interface ILockingExtended {
  /**
   * @notice locks tokens in veMentoLocking contract.
   * @param account address of the owner of lock
   * @param delegate new delegate address
   * @param amount amount to lock
   * @param slope slope period in weeks
   * @param cliff cliff period in weeks
   * @return lockId lock id
   */
  function lock(
    address account,
    address delegate,
    uint96 amount,
    uint32 slope,
    uint32 cliff
  ) external returns (uint256);

  /**
   * @notice returns current week number.
   * @return current week number
   */
  function getWeek() external view returns (uint256);

  /**
   * @notice returns remaining locked amount.
   * @return remaining locked amount of tokens
   */
  function locked(address account) external view returns (uint96);

  /**
   * @notice relocks tokens in veMentoLocking contract.
   * @param lockId lockId
   * @param newDelegate new delegate address
   * @param newAmount amount to lock
   * @param newSlope slope period in weeks
   * @param newCliff cliff period in weeks
   * @return lockId lock id
   */
  function relock(
    uint256 lockId,
    address newDelegate,
    uint96 newAmount,
    uint32 newSlope,
    uint32 newCliff
  ) external returns (uint256);

  /**
   * @notice withdraws redeemable tokens from veMentoLocking contract.
   */
  function withdraw() external;

  /**
   * @notice returns the amount of tokens redeemable from veMentoLocking contract.
   * @param account address of the owner of lock
   * @return amount of tokens redeemable
   */
  function getAvailableForWithdraw(address account) external returns (uint96);
}
