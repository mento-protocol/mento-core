// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { ITokenVestingPlans } from "./interfaces/ITokenVestingPlans.sol";
import { ILockingExtended } from "../governance/locking/interfaces/ILocking.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";

contract VestingLock {
  address public immutable beneficiary;

  address public immutable hedgeyVestingContract;
  address public immutable veMentoLockingContract;

  uint32 public immutable lockingSlopeEndWeek;
  uint32 public immutable lockingCliffEndWeek;

  address public mentoToken;

  uint256 public planId;
  uint256 public veMentoLockId;

  uint256 public totalAmountToLock;
  uint256 public totalUnlockedTokens;

  constructor(
    address _beneficiary,
    address _hedgeyVestingContract,
    address _veMentoLockingContract,
    uint32 _lockingCliffEndWeek,
    uint32 _lockingSlopeEndWeek
  ) {
    require(_beneficiary != address(0), "VestingLock: beneficiary is zero address");
    require(_hedgeyVestingContract != address(0), "VestingLock: hedgeyVestingContract is zero address");
    require(_veMentoLockingContract != address(0), "VestingLock: veMentoLockingContract is zero address");
    require(_lockingCliffEndWeek > 0, "VestingLock: lockingCliffEndWeek is zero");
    require(_lockingSlopeEndWeek > 0, "VestingLock: lockingSlopeEndWeek is zero");
    require(
      _lockingSlopeEndWeek > _lockingCliffEndWeek,
      "VestingLock: lockingSlopeEndWeek is smaller lockingCliffEndWeek"
    );
    beneficiary = _beneficiary;
    hedgeyVestingContract = _hedgeyVestingContract;
    veMentoLockingContract = _veMentoLockingContract;
    lockingCliffEndWeek = _lockingCliffEndWeek;
    lockingSlopeEndWeek = _lockingSlopeEndWeek;
  }

  /**
   * @notice Sets the plan id for the vesting lock and configures variables based on the plan struct.
   */
  function initializeVestingPlan() public {
    require(planId == 0, "VestingLock: plan id already set");
    require(
      ITokenVestingPlans(hedgeyVestingContract).balanceOf(address(this)) == 1,
      "VestingLock: None or too many plans configured"
    );
    planId = ITokenVestingPlans(hedgeyVestingContract).tokenOfOwnerByIndex(address(this), 0);
    ITokenVestingPlans.Plan memory plan = ITokenVestingPlans(hedgeyVestingContract).plans(planId);

    mentoToken = plan.token;
    totalAmountToLock = plan.amount / 2;

    IERC20(mentoToken).approve(veMentoLockingContract, totalAmountToLock);
  }

  /**
   * @notice Redeems the vested tokens, locks tokens from Year 1&2 in veMentoLocking contract,
   *         and transfers avilable tokens to the beneficiary.
   */
  function redeem() public {
    require(planId != 0, "VestingLock: no plan id set");
    require(msg.sender == beneficiary, "VestingLock: only beneficiary can redeem");

    uint256[] memory planIds = new uint256[](1);
    planIds[0] = planId;

    ITokenVestingPlans(hedgeyVestingContract).redeemPlans(planIds);
    uint256 mentoTokenBalance = IERC20(mentoToken).balanceOf(address(this));

    uint256 amountToLock = calculateAmountToLock(mentoTokenBalance);
    totalUnlockedTokens += mentoTokenBalance;

    if (amountToLock > 0) {
      lockTokens(amountToLock);
    }

    ILockingExtended(veMentoLockingContract).withdraw();
    uint256 amountToTransfer = IERC20(mentoToken).balanceOf(address(this));
    if (amountToTransfer > 0) {
      require(IERC20(mentoToken).transfer(beneficiary, amountToTransfer), "VestingLock: transfer failed");
    }
  }

  /**
   * @notice returns the amount of tokens not yet vested.
   */
  function getLockedHedgeyBalance() public view returns (uint256) {
    require(planId != 0, "VestingLock: no plan id set");
    return ((totalAmountToLock * 2) - totalUnlockedTokens);
  }

  /**
   * @notice returns the amount of tokens redeemable from hedgey contract.
   */
  function getRedeemableHedgeyBalance() public view returns (uint256) {
    require(planId != 0, "VestingLock: no plan id set");

    (uint256 balance, , ) = ITokenVestingPlans(hedgeyVestingContract).planBalanceOf(
      planId,
      block.timestamp,
      block.timestamp
    );
    return (balance);
  }

  /**
   * @notice returns the amount of tokens locked in veMentoLocking contract.
   */
  function getLockedVeMentoBalance() public view returns (uint256) {
    return (ILockingExtended(veMentoLockingContract).locked(address(this)));
  }

  /**
   * @notice returns the amount of tokens redeemable from veMentoLocking contract.
   */
  function getRedeemableVeMentoBalance() public returns (uint256) {
    return (uint256(ILockingExtended(veMentoLockingContract).getAvailableForWithdraw(address(this))));
  }

  /**
   * @notice locks/relocks tokens in veMentoLocking contract.
   * @param amountToLock the amount of tokens to lock.
   */
  function lockTokens(uint256 amountToLock) internal {
    (uint256 cliff, uint256 slope) = calculateSlopeAndCliff();
    if (veMentoLockId != 0) {
      uint256 currentAmount = getLockedVeMentoBalance();

      veMentoLockId = ILockingExtended(veMentoLockingContract).relock(
        veMentoLockId,
        beneficiary,
        uint96(amountToLock) + uint96(currentAmount),
        uint32(slope),
        uint32(cliff)
      );
    } else {
      veMentoLockId = ILockingExtended(veMentoLockingContract).lock(
        address(this),
        beneficiary,
        uint96(amountToLock),
        uint32(slope),
        uint32(cliff)
      );
    }
  }

  /**
   * @notice Calculates the amount of tokens to lock in veMentoLocking contract.
   * @param vestedAmount the amount of tokens vested from hedgey.
   * @return amountToLock the amount of tokens to lock.
   */
  function calculateAmountToLock(uint256 vestedAmount) internal view returns (uint256 amountToLock) {
    require(vestedAmount > 0, "VestingLock: no vested tokens");
    uint256 _totalAmountToLock = totalAmountToLock;
    uint256 currentWeek = ILockingExtended(veMentoLockingContract).getWeek();

    if (totalUnlockedTokens <= _totalAmountToLock && currentWeek < lockingSlopeEndWeek) {
      amountToLock = _totalAmountToLock - totalUnlockedTokens;
      amountToLock = min(amountToLock, vestedAmount);

      return (amountToLock);
    } else {
      return (0);
    }
  }

  /**
   * @notice Calculates the slope and cliff for lock.
   * @return cliff in weeks for lock.
   * @return slope in weeks for lock.
   */
  function calculateSlopeAndCliff() internal view returns (uint256 cliff, uint256 slope) {
    uint256 currentWeek = ILockingExtended(veMentoLockingContract).getWeek();
    if (currentWeek < lockingCliffEndWeek) {
      cliff = lockingCliffEndWeek - currentWeek;
    } else {
      cliff = 0;
    }

    if (currentWeek < lockingSlopeEndWeek) {
      slope = min(lockingSlopeEndWeek - currentWeek, lockingSlopeEndWeek - lockingCliffEndWeek);
    } else {
      slope = 0;
    }
    return (cliff, slope);
  }

  /**
   * @dev Returns the smallest of two numbers.
   */
  function min(uint256 a, uint256 b) internal pure returns (uint256) {
    return a < b ? a : b;
  }
}
