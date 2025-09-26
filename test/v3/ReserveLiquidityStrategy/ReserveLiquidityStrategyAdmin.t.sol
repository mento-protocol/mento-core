// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { ReserveLiquidityStrategyBaseTest } from "./ReserveLiquidityStrategyBaseTest.sol";
import { ReserveLiquidityStrategy } from "contracts/v3/ReserveLiquidityStrategy.sol";

contract ReserveLiquidityStrategyAdminTest is ReserveLiquidityStrategyBaseTest {
  event TrustedPoolUpdated(address indexed pool, bool isTrusted);
  event ReserveSet(address indexed oldReserve, address indexed newReserve);

  /* ============================================================ */
  /* =================== Initialization Tests ================== */
  /* ============================================================ */

  function test_initialize_whenValidParameters_shouldSetCorrectly() public {
    // Deploy a new strategy for testing initialization
    ReserveLiquidityStrategy newStrategy = new ReserveLiquidityStrategy();
    address newReserve = makeAddr("NewReserve");
    address newOwner = makeAddr("NewOwner");

    vm.expectEmit(true, true, false, false);
    emit ReserveSet(address(0), newReserve);

    newStrategy.initialize(newReserve, newOwner);

    assertEq(address(newStrategy.reserve()), newReserve, "Should set reserve correctly");
    assertEq(newStrategy.owner(), newOwner, "Should set owner correctly");
  }

  function test_initialize_whenZeroReserve_shouldRevert() public {
    ReserveLiquidityStrategy newStrategy = new ReserveLiquidityStrategy();

    vm.expectRevert("RLS: INVALID_RESERVE");
    newStrategy.initialize(address(0), owner);
  }

  function test_initialize_whenZeroOwner_shouldRevert() public {
    ReserveLiquidityStrategy newStrategy = new ReserveLiquidityStrategy();

    vm.expectRevert("RLS: INVALID_OWNER");
    newStrategy.initialize(reserve, address(0));
  }

  function test_initialize_whenAlreadyInitialized_shouldRevert() public {
    vm.expectRevert("Initializable: contract is already initialized");
    strategy.initialize(reserve, owner);
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
    vm.expectRevert("RLS: INVALID_RESERVE");
    strategy.setReserve(address(0));
  }

  /* ============================================================ */
  /* =================== Pool Management ======================== */
  /* ============================================================ */

  function test_setTrustedPool_whenOwner_shouldUpdateTrustedStatus() public {
    assertFalse(strategy.trustedPools(pool1), "Pool should initially be untrusted");

    vm.expectEmit(true, false, false, true);
    emit TrustedPoolUpdated(pool1, true);

    vm.prank(owner);
    strategy.setTrustedPool(pool1, true);

    assertTrue(strategy.trustedPools(pool1), "Pool should now be trusted");
  }

  function test_setTrustedPool_whenNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    strategy.setTrustedPool(pool1, true);
  }

  function test_setTrustedPool_whenZeroAddress_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert("RLS: INVALID_POOL");
    strategy.setTrustedPool(address(0), true);
  }
}
