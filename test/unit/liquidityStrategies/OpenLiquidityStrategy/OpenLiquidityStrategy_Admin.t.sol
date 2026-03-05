// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { OpenLiquidityStrategy_BaseTest } from "./OpenLiquidityStrategy_BaseTest.sol";
import { OpenLiquidityStrategy } from "contracts/liquidityStrategies/OpenLiquidityStrategy.sol";
import { ILiquidityStrategy } from "contracts/interfaces/ILiquidityStrategy.sol";

contract OpenLiquidityStrategy_AdminTest is OpenLiquidityStrategy_BaseTest {
  /* ============================================================ */
  /* =================== Initialization Tests ================== */
  /* ============================================================ */

  function test_initialize_whenValidParameters_shouldSetCorrectly() public {
    address newOwner = makeAddr("NewOwner");

    OpenLiquidityStrategy newStrategy = new OpenLiquidityStrategy(false);
    newStrategy.initialize(newOwner);

    assertEq(newStrategy.owner(), newOwner, "Should set owner correctly");
  }

  function test_initialize_whenZeroOwner_shouldRevert() public {
    OpenLiquidityStrategy newStrategy = new OpenLiquidityStrategy(false);
    vm.expectRevert("LS_INVALID_OWNER()");
    newStrategy.initialize(address(0));
  }

  function test_initialize_whenCalledTwice_shouldRevert() public {
    OpenLiquidityStrategy newStrategy = new OpenLiquidityStrategy(false);
    newStrategy.initialize(owner);
    vm.expectRevert("Initializable: contract is already initialized");
    newStrategy.initialize(owner);
  }

  /* ============================================================ */
  /* =================== Pool Management ======================== */
  /* ============================================================ */

  function test_addPool_whenValidParams_shouldAddPool() public fpmmToken0Debt(18, 18) {
    ILiquidityStrategy.AddPoolParams memory params = _buildAddPoolParams(
      address(fpmm),
      debtToken,
      3600,
      protocolFeeRecipient,
      25,
      25,
      25,
      25
    );
    vm.expectEmit(true, true, true, true);
    emit PoolAdded(address(fpmm), params);

    vm.prank(owner);
    strategy.addPool(params);

    assertTrue(strategy.isPoolRegistered(address(fpmm)));
  }

  function test_addPool_whenPoolIsZero_shouldRevert() public fpmmToken0Debt(18, 18) {
    ILiquidityStrategy.AddPoolParams memory params = _buildAddPoolParams(
      address(0),
      debtToken,
      3600,
      protocolFeeRecipient,
      25,
      25,
      25,
      25
    );
    vm.prank(owner);
    vm.expectRevert(ILiquidityStrategy.LS_POOL_MUST_BE_SET.selector);
    strategy.addPool(params);
  }

  function test_addPool_whenPoolAlreadyExists_shouldRevert() public fpmmToken0Debt(18, 18) {
    ILiquidityStrategy.AddPoolParams memory params = _buildAddPoolParams(
      address(fpmm),
      debtToken,
      3600,
      protocolFeeRecipient,
      25,
      25,
      25,
      25
    );
    vm.prank(owner);
    strategy.addPool(params);

    vm.prank(owner);
    vm.expectRevert(ILiquidityStrategy.LS_POOL_ALREADY_EXISTS.selector);
    strategy.addPool(params);
  }

  function test_addPool_whenCalledByNonOwner_shouldRevert() public fpmmToken0Debt(18, 18) {
    ILiquidityStrategy.AddPoolParams memory params = _buildAddPoolParams(
      address(fpmm),
      debtToken,
      3600,
      protocolFeeRecipient,
      25,
      25,
      25,
      25
    );
    vm.prank(notOwner);
    vm.expectRevert();
    strategy.addPool(params);
  }

  function test_removePool_whenPoolExists_shouldRemovePool() public fpmmToken0Debt(18, 18) {
    ILiquidityStrategy.AddPoolParams memory params = _buildAddPoolParams(
      address(fpmm),
      debtToken,
      3600,
      protocolFeeRecipient,
      25,
      25,
      25,
      25
    );
    vm.prank(owner);
    strategy.addPool(params);

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
    ILiquidityStrategy.AddPoolParams memory params = _buildAddPoolParams(
      address(fpmm),
      debtToken,
      3600,
      protocolFeeRecipient,
      25,
      25,
      25,
      25
    );
    vm.prank(owner);
    strategy.addPool(params);

    vm.expectEmit(true, false, false, true);
    emit RebalanceCooldownSet(address(fpmm), 7200);

    vm.prank(owner);
    strategy.setRebalanceCooldown(address(fpmm), 7200);
  }
}
