// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { Test } from "mento-std/Test.sol";
import { TimelockController } from "contracts/governance/TimelockController.sol";

/**
 * @title TimelockControllerTest
 * @notice Unit tests for Mento's TimelockController — a thin wrapper around OZ's
 *         TimelockControllerUpgradeable that adds a separate canceller address
 *         with the CANCELLER_ROLE at init time.
 */
contract TimelockControllerTest is Test {
  TimelockController public timelock;

  address public admin = makeAddr("admin");
  address public proposer = makeAddr("proposer");
  address public executor = makeAddr("executor");
  address public canceller = makeAddr("canceller");
  address public stranger = makeAddr("stranger");
  address public target = makeAddr("target");

  bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
  bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
  bytes32 public constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");
  bytes32 public constant TIMELOCK_ADMIN_ROLE = keccak256("TIMELOCK_ADMIN_ROLE");

  uint256 public constant MIN_DELAY = 2 days;

  function setUp() public virtual {
    timelock = new TimelockController();

    address[] memory proposers = new address[](1);
    proposers[0] = proposer;
    address[] memory executors = new address[](1);
    executors[0] = executor;

    timelock.__MentoTimelockController_init(MIN_DELAY, proposers, executors, admin, canceller);
  }

  // ============ Initialization ============

  function test_init_setsMinDelay() public view {
    assertEq(timelock.getMinDelay(), MIN_DELAY);
  }

  function test_init_proposerHasProposerRole() public view {
    assertTrue(timelock.hasRole(PROPOSER_ROLE, proposer));
  }

  function test_init_proposerAutomaticallyHasCancellerRole() public view {
    // OZ gives CANCELLER_ROLE to all proposers during init
    assertTrue(timelock.hasRole(CANCELLER_ROLE, proposer));
  }

  function test_init_cancellerHasCancellerRole() public view {
    // Mento-specific: additional canceller address passed at init
    assertTrue(timelock.hasRole(CANCELLER_ROLE, canceller));
  }

  function test_init_cancellerDoesNotHaveProposerRole() public view {
    // Canceller can only cancel, not schedule
    assertFalse(timelock.hasRole(PROPOSER_ROLE, canceller));
  }

  function test_init_executorHasExecutorRole() public view {
    assertTrue(timelock.hasRole(EXECUTOR_ROLE, executor));
  }

  function test_init_strangerHasNoRoles() public view {
    assertFalse(timelock.hasRole(PROPOSER_ROLE, stranger));
    assertFalse(timelock.hasRole(EXECUTOR_ROLE, stranger));
    assertFalse(timelock.hasRole(CANCELLER_ROLE, stranger));
    assertFalse(timelock.hasRole(TIMELOCK_ADMIN_ROLE, stranger));
  }

  function test_init_timelockOwnedByItself() public view {
    // The timelock contract itself always holds TIMELOCK_ADMIN_ROLE
    assertTrue(timelock.hasRole(TIMELOCK_ADMIN_ROLE, address(timelock)));
  }

  // ============ Scheduling ============

  function _scheduleOp() internal returns (bytes32 id) {
    bytes32 predecessor = bytes32(0);
    bytes32 salt = bytes32(uint256(1));
    uint256 delay = MIN_DELAY;

    vm.prank(proposer);
    timelock.schedule(target, 0, "", predecessor, salt, delay);
    id = timelock.hashOperation(target, 0, "", predecessor, salt);
  }

  function test_schedule_onlyProposerCanSchedule() public {
    vm.prank(stranger);
    vm.expectRevert();
    timelock.schedule(target, 0, "", bytes32(0), bytes32(uint256(1)), MIN_DELAY);
  }

  function test_schedule_cancellerCannotSchedule() public {
    vm.prank(canceller);
    vm.expectRevert();
    timelock.schedule(target, 0, "", bytes32(0), bytes32(uint256(1)), MIN_DELAY);
  }

  function test_schedule_operationIsQueued() public {
    bytes32 id = _scheduleOp();
    assertTrue(timelock.isOperationPending(id));
    assertFalse(timelock.isOperationReady(id));
    assertFalse(timelock.isOperationDone(id));
  }

  function test_schedule_operationReadyAfterDelay() public {
    bytes32 id = _scheduleOp();

    vm.warp(block.timestamp + MIN_DELAY);
    assertTrue(timelock.isOperationReady(id));
  }

  function test_schedule_revertsBelowMinDelay() public {
    vm.prank(proposer);
    vm.expectRevert();
    timelock.schedule(target, 0, "", bytes32(0), bytes32(uint256(1)), MIN_DELAY - 1);
  }

  // ============ Execution ============

  function test_execute_onlyExecutorCanExecute() public {
    _scheduleOp();
    vm.warp(block.timestamp + MIN_DELAY);

    vm.prank(stranger);
    vm.expectRevert();
    timelock.execute(target, 0, "", bytes32(0), bytes32(uint256(1)));
  }

  function test_execute_revertsBeforeDelay() public {
    _scheduleOp();

    vm.prank(executor);
    vm.expectRevert();
    timelock.execute(target, 0, "", bytes32(0), bytes32(uint256(1)));
  }

  function test_execute_succeedsAfterDelay() public {
    bytes32 id = _scheduleOp();
    vm.warp(block.timestamp + MIN_DELAY);

    vm.prank(executor);
    // target is a bare address with no code — call with empty calldata succeeds
    timelock.execute(target, 0, "", bytes32(0), bytes32(uint256(1)));

    assertTrue(timelock.isOperationDone(id));
  }

  // ============ Cancellation ============

  function test_cancel_proposerCanCancel() public {
    bytes32 id = _scheduleOp();
    assertTrue(timelock.isOperationPending(id));

    vm.prank(proposer);
    timelock.cancel(id);

    assertFalse(timelock.isOperation(id));
  }

  function test_cancel_cancellerCanCancel() public {
    bytes32 id = _scheduleOp();

    vm.prank(canceller);
    timelock.cancel(id);

    assertFalse(timelock.isOperation(id));
  }

  function test_cancel_strangerCannotCancel() public {
    bytes32 id = _scheduleOp();

    vm.prank(stranger);
    vm.expectRevert();
    timelock.cancel(id);

    assertTrue(timelock.isOperationPending(id));
  }

  function test_cancel_executorCannotCancel() public {
    bytes32 id = _scheduleOp();

    vm.prank(executor);
    vm.expectRevert();
    timelock.cancel(id);
  }

  function test_cancel_revertsForUnknownOperation() public {
    vm.prank(canceller);
    vm.expectRevert();
    timelock.cancel(bytes32(uint256(999)));
  }

  // ============ Re-initialization guard ============

  function test_init_cannotInitializeTwice() public {
    address[] memory proposers;
    address[] memory executors;
    vm.expectRevert();
    timelock.__MentoTimelockController_init(1 days, proposers, executors, admin, canceller);
  }
}
