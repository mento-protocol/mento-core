// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity 0.8.18;

import { Test } from "forge-std-next/Test.sol";
import { console } from "forge-std-next/console.sol";
import { Vm } from "forge-std-next/Vm.sol";
import { Arrays } from "test/utils/Arrays.sol";
import { VestingLock } from "contracts/vesting/VestingLock.sol";
import { ITokenVestingPlans } from "contracts/vesting/interfaces/ITokenVestingPlans.sol";
import { MockTokenVestingPlans } from "../mocks/MockTokenVestingPlans.sol";
import { MockLockingExtended } from "../mocks/MockLocking.sol";
import { MockMentoToken } from "../mocks/MockMentoToken.sol";

contract VestingLockTest is Test {
  uint32 public cliffEndWeek = 104; // ~ 2 years
  uint32 public slopeEndWeek = 208; // ~ 4 years

  MockTokenVestingPlans public mockTokenVestingPlans = new MockTokenVestingPlans();
  MockLockingExtended public mockLocking = new MockLockingExtended();
  MockMentoToken public mentoToken = new MockMentoToken();

  address public beneficiary = actor("beneficary");
  address public nonBeneficiary = actor("nonBeneficiary");
  address public hedgeyVestingAddr = address(mockTokenVestingPlans);
  address public veMentoLockingAddr = address(mockLocking);
  address public mentoTokenAddr = address(mentoToken);

  ITokenVestingPlans.Plan public basicPlan =
    ITokenVestingPlans.Plan(mentoTokenAddr, 40_000 * 1e18, 1, 1, 1, 1, actor("admin"), false);

  VestingLock public vestingLock;

  /* ---------- Utils ---------- */

  function actor(string memory name) public returns (address) {
    uint256 pk = uint256(keccak256(bytes(name)));
    address addr = vm.addr(pk);
    vm.label(addr, name);
    return addr;
  }

  function skipWeeks(uint256 numberOfWeeks) public {
    mockLocking.setWeek(numberOfWeeks);

    uint256 withdrawable = ((basicPlan.amount * numberOfWeeks) / slopeEndWeek) - vestingLock.totalUnlockedTokens();

    mockTokenVestingPlans.setRedeemableTokens(withdrawable);
    mockLocking.setWeek(numberOfWeeks);

    mockLocking.setWithdraw(0, mentoTokenAddr);
    if (vestingLock.planId() == 0) {
      vestingLock.initializeVestingPlan();
    }
  }
}

/* ---------- Constructor ---------- */

contract VestingLockTest_constructor is VestingLockTest {
  function test_constructor_whenBeneficiaryIsZero_shouldRevert() public {
    vm.expectRevert("VestingLock: beneficiary is zero address");
    vestingLock = new VestingLock(address(0), hedgeyVestingAddr, veMentoLockingAddr, cliffEndWeek, slopeEndWeek);
  }

  function test_constructor_whenHedgeyVestingContractIsZero_shouldRevert() public {
    vm.expectRevert("VestingLock: hedgeyVestingContract is zero address");
    vestingLock = new VestingLock(beneficiary, address(0), veMentoLockingAddr, cliffEndWeek, slopeEndWeek);
  }

  function test_constructor_whenVeMentoLockingContractIsZero_shouldRevert() public {
    vm.expectRevert("VestingLock: veMentoLockingContract is zero address");
    vestingLock = new VestingLock(beneficiary, hedgeyVestingAddr, address(0), cliffEndWeek, slopeEndWeek);
  }

  function test_constructor_whenLockingCliffEndWeekIsZero_shouldRevert() public {
    vm.expectRevert("VestingLock: lockingCliffEndWeek is zero");
    vestingLock = new VestingLock(beneficiary, hedgeyVestingAddr, veMentoLockingAddr, 0, slopeEndWeek);
  }

  function test_constructor_whenLockingSlopeEndWeekIsZero_shouldRevert() public {
    vm.expectRevert("VestingLock: lockingSlopeEndWeek is zero");
    vestingLock = new VestingLock(beneficiary, hedgeyVestingAddr, veMentoLockingAddr, cliffEndWeek, 0);
  }

  function test_constructor_whenLockingSlopeEndWeekIsSmallerThanLockingCliffEndWeek_shouldRevert() public {
    vm.expectRevert("VestingLock: lockingSlopeEndWeek is smaller than lockingCliffEndWeek");
    vestingLock = new VestingLock(beneficiary, hedgeyVestingAddr, veMentoLockingAddr, 10, 5);
  }

  function test_constructor_shouldSetStateVariables() public {
    vestingLock = new VestingLock(beneficiary, hedgeyVestingAddr, veMentoLockingAddr, cliffEndWeek, slopeEndWeek);

    assertEq(vestingLock.beneficiary(), beneficiary);
    assertEq(vestingLock.hedgeyVestingContract(), hedgeyVestingAddr);
    assertEq(vestingLock.veMentoLockingContract(), veMentoLockingAddr);
    assertEq(vestingLock.lockingCliffEndWeek(), cliffEndWeek);
    assertEq(vestingLock.lockingSlopeEndWeek(), slopeEndWeek);
  }
}

contract VestingLockTest_initializeVestingPlan is VestingLockTest {
  function setUp() public {
    mockTokenVestingPlans.setBalanceOf(1);
    mockTokenVestingPlans.setPlans(basicPlan);
    vestingLock = new VestingLock(beneficiary, hedgeyVestingAddr, veMentoLockingAddr, cliffEndWeek, slopeEndWeek);
  }

  function test_initializeVestingPlan_whenPlanIdAlreadySet_shouldRevert() public {
    vestingLock.initializeVestingPlan();
    vm.expectRevert("VestingLock: plan id already set");
    vestingLock.initializeVestingPlan();
  }

  function test_initializeVestingPlan_whenNoPlanConfigured_shouldRevert() public {
    mockTokenVestingPlans.setBalanceOf(0);
    vm.expectRevert("VestingLock: None or too many plans configured");
    vestingLock.initializeVestingPlan();
  }

  function test_initializeVestingPlan_whenTooManyPlansConfigured_shouldRevert() public {
    mockTokenVestingPlans.setBalanceOf(2);
    vm.expectRevert("VestingLock: None or too many plans configured");
    vestingLock.initializeVestingPlan();
  }

  function test_initializeVestingPlan_whenPlanConfigured_shouldSetPlanIdAndStateVariables() public {
    mockTokenVestingPlans.setBalanceOf(1);
    mockTokenVestingPlans.setPlans(basicPlan);
    vestingLock.initializeVestingPlan();

    assertEq(vestingLock.planId(), 1);
    assertEq(vestingLock.mentoToken(), mentoTokenAddr);
    assertEq(vestingLock.totalAmountToLock(), basicPlan.amount / 2);
  }
}

contract VestingLockTest_redeem is VestingLockTest {
  function setUp() public {
    mockTokenVestingPlans.setBalanceOf(1);
    mockTokenVestingPlans.setPlans(basicPlan);
    vestingLock = new VestingLock(beneficiary, hedgeyVestingAddr, veMentoLockingAddr, cliffEndWeek, slopeEndWeek);
  }

  function test_redeem_whenNoVestingPlan_shouldRevert() public {
    vm.expectRevert("VestingLock: no plan id set");
    vestingLock.redeem();
  }

  function test_redeem_whenCallerNotBeneficiary_shouldRevert() public {
    vestingLock.initializeVestingPlan();
    vm.prank(nonBeneficiary);
    vm.expectRevert("VestingLock: only beneficiary can redeem");
    vestingLock.redeem();
  }

  function test_redeem_whenBeforeCliffEndAndFirstRedeem_shouldLockAll() public {
    uint256 hedgeyRedeemableAmount = 10_000 * 1e18;

    uint256 currentWeek = 52;

    // because currentWeek is pre cliffEndWeek 105
    uint32 cliff = uint32(cliffEndWeek - currentWeek);
    // full 2 year slope period since currentWeek is pre slopeStart(cliffEndWeek)
    uint32 slope = uint32(slopeEndWeek - cliffEndWeek);

    mockTokenVestingPlans.setRedeemableTokens(hedgeyRedeemableAmount);
    mockLocking.setWeek(currentWeek);
    mockLocking.setWithdraw(0, mentoTokenAddr);

    vestingLock.initializeVestingPlan();
    uint256 planId = vestingLock.planId();
    uint256 lockIdBefore = vestingLock.veMentoLockId();
    assertEq(lockIdBefore, 0);

    vm.prank(beneficiary);
    vm.expectCall( // ensure redeemPlans is called with correct parameters
      hedgeyVestingAddr,
      abi.encodeWithSelector(ITokenVestingPlans.redeemPlans.selector, Arrays.uints(planId))
    );
    vm.expectCall( // ensure lock is called with correct parameters
      veMentoLockingAddr,
      abi.encodeWithSelector(
        MockLockingExtended.lock.selector,
        address(vestingLock),
        beneficiary,
        hedgeyRedeemableAmount,
        slope,
        cliff
      )
    );
    // ensure no tokens are transferred to beneficiary
    vm.expectCall(mentoTokenAddr, abi.encodeWithSelector(mentoToken.transfer.selector), 0);

    vestingLock.redeem();

    assertEq(mentoToken.balanceOf(beneficiary), 0);
    assertEq(vestingLock.totalUnlockedTokens(), 10_000 * 1e18);
    assertEq(mentoToken.balanceOf(address(vestingLock)), 0);
  }

  function test_redeem_whenBeforeCliffEndAndNotFirstRedeem_shouldRelockAll() public {
    skipWeeks(52);
    vm.prank(beneficiary);
    vestingLock.redeem();

    assertEq(vestingLock.totalUnlockedTokens(), basicPlan.amount / 4);

    skipWeeks(52 + 26); // 1.5 Years

    uint256 planId = vestingLock.planId();
    uint32 slope = uint32(slopeEndWeek - cliffEndWeek);
    uint32 cliff = uint32(cliffEndWeek - (52 + 26));

    vm.expectCall( // ensure redeemPlans is called with correct parameters
      hedgeyVestingAddr,
      abi.encodeWithSelector(ITokenVestingPlans.redeemPlans.selector, Arrays.uints(planId))
    );
    vm.expectCall( // ensure relock is called with correct parameters
      veMentoLockingAddr,
      abi.encodeWithSelector(
        MockLockingExtended.relock.selector,
        vestingLock.veMentoLockId(),
        beneficiary,
        (basicPlan.amount * 3) / 8, // (52+26)/208 ~ 3/8
        slope,
        cliff
      )
    );
    // ensure no tokens are transferred to beneficiary
    vm.expectCall(mentoTokenAddr, abi.encodeWithSelector(mentoToken.transfer.selector), 0);
    vm.prank(beneficiary);
    vestingLock.redeem();

    assertEq(mentoToken.balanceOf(beneficiary), 0);
    assertEq(vestingLock.totalUnlockedTokens(), 15_000 * 1e18);
    assertEq(mentoToken.balanceOf(address(vestingLock)), 0);
  }

  function test_redeem_whenAtCliffEndAndFirstRedeem_shouldLockAllWithNoCliff() public {
    uint256 hedgeyRedeemableAmount = 20_000 * 1e18;

    uint256 currentWeek = 104;

    // 0 cliff because currentWeek is cliffEndWeek
    uint32 cliff = uint32(cliffEndWeek - currentWeek);
    // full 2 year slope period since currentWeek is pre slopeStart(cliffEndWeek)
    uint32 slope = uint32(slopeEndWeek - cliffEndWeek);

    mockTokenVestingPlans.setRedeemableTokens(hedgeyRedeemableAmount);
    mockLocking.setWeek(currentWeek);
    mockLocking.setWithdraw(0, mentoTokenAddr);

    vestingLock.initializeVestingPlan();
    uint256 planId = vestingLock.planId();
    uint256 lockIdBefore = vestingLock.veMentoLockId();
    assertEq(lockIdBefore, 0);

    vm.prank(beneficiary);
    vm.expectCall( // ensure redeemPlans is called with correct parameters
      hedgeyVestingAddr,
      abi.encodeWithSelector(ITokenVestingPlans.redeemPlans.selector, Arrays.uints(planId))
    );
    vm.expectCall( // ensure lock is called with correct parameters
      veMentoLockingAddr,
      abi.encodeWithSelector(
        MockLockingExtended.lock.selector,
        address(vestingLock),
        beneficiary,
        hedgeyRedeemableAmount,
        slope,
        cliff
      )
    );
    // ensure no tokens are transferred to beneficiary
    vm.expectCall(mentoTokenAddr, abi.encodeWithSelector(mentoToken.transfer.selector), 0);
    vestingLock.redeem();

    assertEq(mentoToken.balanceOf(beneficiary), 0 * 1e18);
    assertEq(vestingLock.totalUnlockedTokens(), 20_000 * 1e18);
    assertEq(mentoToken.balanceOf(address(vestingLock)), 0);
  }

  function test_redeem_whenAtCliffEndAndNotFirstRedeem_shouldRelockAll() public {
    skipWeeks(52); // year 1
    vm.prank(beneficiary);
    vestingLock.redeem();

    assertEq(vestingLock.totalUnlockedTokens(), basicPlan.amount / 4);

    skipWeeks(104); // year 2

    uint256 planId = vestingLock.planId();

    // full 2 year slope period since currentWeek is pre slopeStart(cliffEndWeek)
    uint32 slope = uint32(slopeEndWeek - cliffEndWeek);
    // 0 cliff because currentWeek is cliffEndWeek
    uint32 cliff = uint32(cliffEndWeek - (52 + 52));

    vm.expectCall( // ensure redeemPlans is called with correct parameters
      hedgeyVestingAddr,
      abi.encodeWithSelector(ITokenVestingPlans.redeemPlans.selector, Arrays.uints(planId))
    );
    vm.expectCall( // ensure relock is called with correct parameters
      veMentoLockingAddr,
      abi.encodeWithSelector(
        MockLockingExtended.relock.selector,
        vestingLock.veMentoLockId(),
        beneficiary,
        (basicPlan.amount) / 2, // (52+52)/208 ~ 1/2
        slope,
        cliff
      )
    );
    // ensure no tokens are transferred to beneficiary
    vm.expectCall(mentoTokenAddr, abi.encodeWithSelector(mentoToken.transfer.selector), 0);
    vm.prank(beneficiary);
    vestingLock.redeem();

    assertEq(mentoToken.balanceOf(beneficiary), 0);
    assertEq(vestingLock.totalUnlockedTokens(), 20_000 * 1e18);
    assertEq(mentoToken.balanceOf(address(vestingLock)), 0);
  }

  function test_redeem_whenAfterCliffEndAndFirstRedeem_shouldLockHalfWithSlopeRemainderAndTransferRest() public {
    uint256 hedgeyRedeemableAmount = 30_000 * 1e18;

    uint256 currentWeek = 156;
    uint32 cliff = uint32(0); // because currentWeek is greater cliffEndWeek 0
    uint32 slope = uint32(slopeEndWeek - currentWeek); // 1 year slope period since currentWeek is Year 3

    mockTokenVestingPlans.setRedeemableTokens(hedgeyRedeemableAmount);
    mockLocking.setWeek(currentWeek);
    mockLocking.setWithdraw(0, mentoTokenAddr);

    vestingLock.initializeVestingPlan();
    uint256 planId = vestingLock.planId();
    uint256 lockIdBefore = vestingLock.veMentoLockId();
    assertEq(lockIdBefore, 0);

    vm.prank(beneficiary);
    vm.expectCall( // ensure redeemPlans is called with correct parameters
      hedgeyVestingAddr,
      abi.encodeWithSelector(ITokenVestingPlans.redeemPlans.selector, Arrays.uints(planId))
    );
    vm.expectCall( // ensure lock is called with correct parameters
      veMentoLockingAddr,
      abi.encodeWithSelector(
        MockLockingExtended.lock.selector,
        address(vestingLock),
        beneficiary,
        20_000 * 1e18, // only tokens from  year 1&2 are locked
        slope,
        cliff
      )
    );
    // ensure year 3 vested tokens are transferred to beneficiary
    vm.expectCall(mentoTokenAddr, abi.encodeWithSelector(mentoToken.transfer.selector, beneficiary, 10_000 * 1e18), 1);
    vestingLock.redeem();

    assertEq(mentoToken.balanceOf(beneficiary), 10_000 * 1e18);
    assertEq(vestingLock.totalUnlockedTokens(), 30_000 * 1e18);
    assertEq(mentoToken.balanceOf(address(vestingLock)), 0);
  }

  function test_redeem_whenAfterCliffEndAndNotFirstRedeem_shouldRelockReminderAndTransferAvailable() public {
    skipWeeks(78); // last redeem at 1.5 Years
    vm.prank(beneficiary);
    vestingLock.redeem();

    assertEq(vestingLock.totalUnlockedTokens(), (basicPlan.amount * 3) / 8);

    uint256 currentWeek = 156; // Year 3
    skipWeeks(currentWeek);

    uint256 planId = vestingLock.planId();
    uint32 slope = uint32(slopeEndWeek - currentWeek); // slopePeriod remainder
    uint32 cliff = uint32(cliffEndWeek - (52 + 52)); // 0 because currentWeek is larger cliffEndWeek

    vm.expectCall( // ensure redeemPlans is called with correct parameters
      hedgeyVestingAddr,
      abi.encodeWithSelector(ITokenVestingPlans.redeemPlans.selector, Arrays.uints(planId))
    );
    vm.expectCall( // ensure relock is called with correct parameters
      veMentoLockingAddr,
      abi.encodeWithSelector(
        MockLockingExtended.relock.selector,
        vestingLock.veMentoLockId(),
        beneficiary,
        (basicPlan.amount) / 2, // (52+52)/208 ~ 1/2
        slope,
        cliff
      )
    );
    // ensure year 3 vested tokens are transferred to beneficiary
    vm.expectCall(mentoTokenAddr, abi.encodeWithSelector(mentoToken.transfer.selector, beneficiary, 10_000 * 1e18), 1);

    vm.prank(beneficiary);
    vestingLock.redeem();

    assertEq(mentoToken.balanceOf(beneficiary), 10_000 * 1e18);
    assertEq(vestingLock.totalUnlockedTokens(), 30_000 * 1e18);
    assertEq(mentoToken.balanceOf(address(vestingLock)), 0);
  }

  function test_redeem_whenAfterSlopeEndAndFirstRedeem_shouldTransferAll() public {
    skipWeeks(208); // redeem at 4 Years
    uint256 planId = vestingLock.planId();

    vm.expectCall( // ensure redeemPlans is called with correct parameters
      hedgeyVestingAddr,
      abi.encodeWithSelector(ITokenVestingPlans.redeemPlans.selector, Arrays.uints(planId))
    );
    // ensure no tokens are locked
    vm.expectCall(veMentoLockingAddr, abi.encodeWithSelector(mockLocking.lock.selector), 0);
    // ensure vested tokens are transferred to beneficiary
    vm.expectCall(mentoTokenAddr, abi.encodeWithSelector(mentoToken.transfer.selector, beneficiary, 40_000 * 1e18), 1);

    vm.prank(beneficiary);
    vestingLock.redeem();

    assertEq(mentoToken.balanceOf(beneficiary), basicPlan.amount);
    assertEq(vestingLock.totalUnlockedTokens(), basicPlan.amount);
    assertEq(mentoToken.balanceOf(address(vestingLock)), 0);
  }

  function test_redeem_whenAfterSlopeEndAndNotFirstRedeem_shouldRedeemFromLockAndTransferAll() public {
    skipWeeks(104); // first redeem at Year 2
    vm.prank(beneficiary);
    vestingLock.redeem();

    skipWeeks(208); // second redeem at Year 2

    // set withdrawable amount to 20_000 since 20_000 was locked for 2 years
    mockLocking.setWithdraw(20_000 * 1e18, mentoTokenAddr);

    uint256 planId = vestingLock.planId();

    vm.expectCall( // ensure redeemPlans is called with correct parameters
      hedgeyVestingAddr,
      abi.encodeWithSelector(ITokenVestingPlans.redeemPlans.selector, Arrays.uints(planId))
    );
    // ensure no tokens are locked
    vm.expectCall(veMentoLockingAddr, abi.encodeWithSelector(mockLocking.lock.selector), 0);
    // ensure contract withdraws from lock
    vm.expectCall(veMentoLockingAddr, abi.encodeWithSelector(mockLocking.withdraw.selector), 1);
    // ensure vested tokens are transferred to beneficiary
    vm.expectCall(mentoTokenAddr, abi.encodeWithSelector(mentoToken.transfer.selector, beneficiary, 40_000 * 1e18), 1);

    vm.prank(beneficiary);
    vestingLock.redeem();

    assertEq(mentoToken.balanceOf(beneficiary), basicPlan.amount);
    assertEq(vestingLock.totalUnlockedTokens(), basicPlan.amount);
    assertEq(mentoToken.balanceOf(address(vestingLock)), 0);
  }
}

contract VestingLockTest_getLockedHedgeyBalance is VestingLockTest {
  function setUp() public {
    mockTokenVestingPlans.setBalanceOf(1);
    mockTokenVestingPlans.setPlans(basicPlan);
    vestingLock = new VestingLock(beneficiary, hedgeyVestingAddr, veMentoLockingAddr, cliffEndWeek, slopeEndWeek);
  }

  function test_getLockedHedgeyBalance_whenNoVestingPlan_shouldReturnZero() public {
    vm.expectRevert("VestingLock: no plan id set");
    vestingLock.getLockedHedgeyBalance();
  }

  function test_getLockedHedgeyBalance_whenNoRedeem_shouldReturnTotalAmount() public {
    vestingLock.initializeVestingPlan();
    assertEq(vestingLock.getLockedHedgeyBalance(), basicPlan.amount);
  }

  function test_getLockedHedgeyBalance_whenRedeemed_shouldReturnCorrectAmount() public {
    vestingLock.initializeVestingPlan();
    skipWeeks(104);

    vm.prank(beneficiary);
    vestingLock.redeem();

    assertEq(vestingLock.getLockedHedgeyBalance(), basicPlan.amount / 2);

    skipWeeks(208);

    vm.prank(beneficiary);
    vestingLock.redeem();

    assertEq(vestingLock.getLockedHedgeyBalance(), 0);
  }
}

contract VestingLockTest_getRedeemableHedgeyBalance is VestingLockTest {
  function setUp() public {
    mockTokenVestingPlans.setBalanceOf(1);
    mockTokenVestingPlans.setPlans(basicPlan);
    vestingLock = new VestingLock(beneficiary, hedgeyVestingAddr, veMentoLockingAddr, cliffEndWeek, slopeEndWeek);
  }

  function test_getRedeemableHedgeyBalance_whenNoVestingPlan_shouldReturnZero() public {
    vm.expectRevert("VestingLock: no plan id set");
    vestingLock.getRedeemableHedgeyBalance();
  }

  function test_getRedeemableHedgeyBalance_whenPlanConfigured_shouldReturnPlanBalanceOf() public {
    vestingLock.initializeVestingPlan();

    mockTokenVestingPlans.setPlanBalanceOf(10_000 * 1e18);
    assertEq(vestingLock.getRedeemableHedgeyBalance(), 10_000 * 1e18);

    mockTokenVestingPlans.setPlanBalanceOf(40_000 * 1e18);
    assertEq(vestingLock.getRedeemableHedgeyBalance(), 40_000 * 1e18);
  }
}

contract VestingLockTest_getLockedVeMentoBalance is VestingLockTest {
  function setUp() public {
    mockTokenVestingPlans.setBalanceOf(1);
    mockTokenVestingPlans.setPlans(basicPlan);
    vestingLock = new VestingLock(beneficiary, hedgeyVestingAddr, veMentoLockingAddr, cliffEndWeek, slopeEndWeek);
  }

  function test_getLockedVeMentoBalance_whenConfigured_shouldReturnLockingLocked() public {
    vestingLock.initializeVestingPlan();

    mockLocking.setLockedAmount(10_000 * 1e18);
    assertEq(vestingLock.getLockedVeMentoBalance(), 10_000 * 1e18);

    mockLocking.setLockedAmount(40_000 * 1e18);
    assertEq(vestingLock.getLockedVeMentoBalance(), 40_000 * 1e18);
  }
}

contract VestingLockTest_getRedeemableVeMentoBalance is VestingLockTest {
  function setUp() public {
    mockTokenVestingPlans.setBalanceOf(1);
    mockTokenVestingPlans.setPlans(basicPlan);
    vestingLock = new VestingLock(beneficiary, hedgeyVestingAddr, veMentoLockingAddr, cliffEndWeek, slopeEndWeek);
  }

  function test_getRedeemableVeMentoBalance_whenConfigured_shouldReturnLockingAvailableForWithdraw() public {
    vestingLock.initializeVestingPlan();

    mockLocking.setWithdraw(10_000 * 1e18, mentoTokenAddr);
    assertEq(vestingLock.getRedeemableVeMentoBalance(), 10_000 * 1e18);

    mockLocking.setWithdraw(40_000 * 1e18, mentoTokenAddr);
    assertEq(vestingLock.getRedeemableVeMentoBalance(), 40_000 * 1e18);
  }
}
