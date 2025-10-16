// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { ReserveLiquidityStrategy_BaseTest } from "./ReserveLiquidityStrategy_BaseTest.sol";
import { ReserveLiquidityStrategy } from "contracts/liquidityStrategies/ReserveLiquidityStrategy.sol";
import { ILiquidityStrategy } from "contracts/interfaces/ILiquidityStrategy.sol";

contract ReserveLiquidityStrategy_AdminTest is ReserveLiquidityStrategy_BaseTest {
  event TrustedPoolUpdated(address indexed pool, bool isTrusted);
  event ReserveSet(address indexed oldReserve, address indexed newReserve);

  /* ============================================================ */
  /* =================== Initialization Tests ================== */
  /* ============================================================ */

  function test_constructor_whenValidParameters_shouldSetCorrectly() public {
    // Deploy a new strategy for testing initialization
    address newReserve = makeAddr("NewReserve");
    address newOwner = makeAddr("NewOwner");

    vm.expectEmit(true, true, false, false);
    emit ReserveSet(address(0), newReserve);
    ReserveLiquidityStrategy newStrategy = new ReserveLiquidityStrategy(newOwner, newReserve);

    assertEq(address(newStrategy.reserve()), newReserve, "Should set reserve correctly");
    assertEq(newStrategy.owner(), newOwner, "Should set owner correctly");
  }

  function test_constructor_whenZeroReserve_shouldRevert() public {
    vm.expectRevert("RLS_INVALID_RESERVE()");
    new ReserveLiquidityStrategy(owner, address(0));
  }

  function test_constructor_whenZeroOwner_shouldRevert() public {
    vm.expectRevert("LS_INVALID_OWNER()");
    new ReserveLiquidityStrategy(address(0), reserve);
  }

  /* ============================================================ */
  /* ===================== Reserve Management =================== */
  /* ============================================================ */

  function test_setReserve_whenOwner_shouldUpdateReserve() public {
    address newReserve = makeAddr("NewReserve");

    vm.expectEmit(true, true, false, false);
    emit ReserveSet(reserve, newReserve);

    vm.prank(owner);
    strategy.setReserve(newReserve);

    assertEq(address(strategy.reserve()), newReserve, "Should update reserve address");
  }

  function test_setReserve_whenNotOwner_shouldRevert() public {
    address newReserve = makeAddr("NewReserve");

    vm.prank(notOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    strategy.setReserve(newReserve);
  }

  function test_setReserve_whenZeroAddress_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert("RLS_INVALID_RESERVE()");
    strategy.setReserve(address(0));
  }

  /* ============================================================ */
  /* =================== Pool Management ======================== */
  /* ============================================================ */

  function test_addPool_whenValidParams_shouldAddPool() public fpmmToken0Debt(18, 18) {
    vm.expectEmit(true, true, true, true);
    emit PoolAdded(address(fpmm), true, 3600, 50);

    vm.prank(owner);
    strategy.addPool(address(fpmm), debtToken, 3600, 50);

    assertTrue(strategy.isPoolRegistered(address(fpmm)));
  }

  function test_addPool_whenPoolIsZero_shouldRevert() public fpmmToken0Debt(18, 18) {
    vm.prank(owner);
    vm.expectRevert(ILiquidityStrategy.LS_POOL_MUST_BE_SET.selector);
    strategy.addPool(address(0), debtToken, 3600, 50);
  }

  function test_addPool_whenPoolAlreadyExists_shouldRevert() public fpmmToken0Debt(18, 18) {
    vm.prank(owner);
    strategy.addPool(address(fpmm), debtToken, 3600, 50);

    vm.prank(owner);
    vm.expectRevert(ILiquidityStrategy.LS_POOL_ALREADY_EXISTS.selector);
    strategy.addPool(address(fpmm), debtToken, 3600, 50);
  }

  function test_addPool_whenCalledByNonOwner_shouldRevert() public fpmmToken0Debt(18, 18) {
    vm.prank(notOwner);
    vm.expectRevert();
    strategy.addPool(address(fpmm), debtToken, 3600, 50);
  }

  function test_removePool_whenPoolExists_shouldRemovePool() public fpmmToken0Debt(18, 18) {
    // Add pool first
    vm.prank(owner);
    strategy.addPool(address(fpmm), debtToken, 3600, 50);

    // Remove it
    vm.expectEmit(true, false, false, false);
    emit PoolRemoved(address(fpmm));

    vm.prank(owner);
    strategy.removePool(address(fpmm));

    assertFalse(strategy.isPoolRegistered(address(fpmm)));
  }

  function test_removePool_whenPoolDoesNotExist_shouldRevert() public fpmmToken0Debt(18, 18) {
    vm.prank(owner);
    vm.expectRevert(ILiquidityStrategy.LS_POOL_NOT_FOUND.selector);
    strategy.removePool(address(fpmm));
  }

  function test_setRebalanceCooldown_whenPoolExists_shouldUpdateCooldown() public fpmmToken0Debt(18, 18) {
    // Add pool
    vm.prank(owner);
    strategy.addPool(address(fpmm), debtToken, 3600, 50);

    // Update cooldown
    vm.expectEmit(true, false, false, true);
    emit RebalanceCooldownSet(address(fpmm), 7200);

    vm.prank(owner);
    strategy.setRebalanceCooldown(address(fpmm), 7200);
  }
}
