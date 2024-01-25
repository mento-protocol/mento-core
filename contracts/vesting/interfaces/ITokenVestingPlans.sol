// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface ITokenVestingPlans {
  /**
   * @notice The Plan is the storage in a struct of the tokens that are currently being vested
   * @param token is the token address being timelocked
   * @param amount is the current amount of tokens locked in the vesting plan,
   *  both unclaimed vested and unvested tokens. This parameter is updated each time tokens are redeemed,
   *  reset to the new remaining unvested and unclaimed amount
   * @param start is the start date when token vesting begins or began.
   *  This parameter gets updated each time tokens are redeemed and claimed, reset to the most recent redeem time.
   * @param cliff is an optional field to add a single cliff date prior to which the tokens cannot be redeemed,
   *  this does not change
   * @param rate is the amount of tokens that vest in a period. This parameter is constand for each plan.
   * @param period is the length of time in between each discrete time when tokens vest.
   *  If this is set to 1, then tokens unlocke every second.
   *  Otherwise the period is longer to allow for interval vesting plans.
   * @param vestingAdmin is the adress of the administrator of the plans who can revoke plans at any time prior to
   *  them fully vesting. They may also be allowed to transfer plans on behalf of the beneficiary.
   * @param adminTransferOBO is a toggle that when true allows a vesting admin to transfer plans on behalf of (OBO)
   */
  struct Plan {
    address token;
    uint256 amount;
    uint256 start;
    uint256 cliff;
    uint256 rate;
    uint256 period;
    address vestingAdmin;
    bool adminTransferOBO;
  }

  /**
   * @notice gets the plan struct for a given planId
   * @param planId is the id of the plan to get
   * @return Plan is the struct of the plan
   */
  function plans(uint256 planId) external view returns (Plan memory);

  /**
   * @notice returns the amount of plans owned by `owner`.
   * @param owner is the address to query
   * @return balance is the number of plans owned by `owner`, possibly zero
   */
  function balanceOf(address owner) external view returns (uint256 balance);

  /**
   * @notice returns the `tokenId` plan ID owned by `owner`.
   * @param owner is the address to query
   * @param index is the index of the plan owned by `owner` to query
   */
  function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256 tokenId);

  /**
   * @notice redeems vested tokens from a group of plans
   * @param planIds is the array of planIds to redeem from
   */
  function redeemPlans(uint256[] calldata planIds) external;

  /**
   * @notice gets the balance of a plan
   * @param planId is the NFT token ID and plan Id
   * @param timeStamp is the effective current time stamp,
   *  can be polled for the future for estimating redeemable tokens
   * @param redemptionTime is the time of the request that the user is attemptint to redeem tokens,
   *  which can be prior to the timeStamp, though not beyond it.
   * @return balance is the amount of tokens that are currently redeemable
   * @return remainder is the amount of tokens that are not yet redeemable
   * @return latestUnlock is the most recent time that tokens were unlocked
   */
  function planBalanceOf(
    uint256 planId,
    uint256 timeStamp,
    uint256 redemptionTime
  )
    external
    view
    returns (
      uint256 balance,
      uint256 remainder,
      uint256 latestUnlock
    );
}
