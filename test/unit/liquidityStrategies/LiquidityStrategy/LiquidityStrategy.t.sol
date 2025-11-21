// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
// solhint-disable max-line-length
pragma solidity ^0.8;

import { LiquidityStrategy_BaseTest } from "./LiquidityStrategy_BaseTest.sol";
import { LiquidityStrategyHarness } from "test/utils/harnesses/LiquidityStrategyHarness.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";
import { FPMM } from "contracts/swap/FPMM.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/libraries/LiquidityStrategyTypes.sol";
import { ILiquidityStrategy } from "contracts/interfaces/ILiquidityStrategy.sol";

contract LiquidityStrategy_Test is LiquidityStrategy_BaseTest {
  LiquidityStrategyHarness public strategy;

  function setUp() public override {
    super.setUp();
    strategy = new LiquidityStrategyHarness(owner);
    strategyAddr = address(strategy);
  }

  /* ============================================================ */
  /* =================== Pool Management Tests ================== */
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

  function test_addPool_whenDebtTokenNotInPool_shouldRevert() public fpmmToken0Debt(18, 18) {
    // Create a random token that's not in the pool
    address wrongToken = address(new MockERC20("WrongToken", "WT", 18));

    vm.prank(owner);
    vm.expectRevert(ILiquidityStrategy.LS_DEBT_TOKEN_NOT_IN_POOL.selector);
    strategy.addPool(address(fpmm), wrongToken, 3600, 50);
  }

  function test_addPool_whenDebtTokenNotInPoolandToken1Debt_shouldRevert() public fpmmToken1Debt(18, 18) {
    // Create a random token that's not in the pool
    address wrongToken = address(new MockERC20("WrongToken", "WT", 18));

    vm.prank(owner);
    vm.expectRevert(ILiquidityStrategy.LS_DEBT_TOKEN_NOT_IN_POOL.selector);
    strategy.addPool(address(fpmm), wrongToken, 3600, 50);
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

  /* ============================================================ */
  /* ================= Determine Action Tests =================== */
  /* ============================================================ */

  function test_determineAction_expansion_isToken0Debt_poolPriceAbove() public fpmmToken0Debt(18, 18) {
    // Set oracle rate to 1:1
    setOracleRate(1e18, 1e18);
    // Provide liquidity with pool price 10% above oracle (110:100 reserves)
    provideFPMMReserves(100e18, 110e18, true);

    vm.prank(owner);
    strategy.addPool(address(fpmm), debtToken, 3600, 50);

    (LQ.Context memory ctx, LQ.Action memory action) = strategy.determineAction(address(fpmm));

    // Should be expansion: add debt (token0), take collateral (token1)
    assertEq(ctx.prices.poolPriceAbove, true);
    assertEq(action.dir, LQ.Direction.Expand);
    assertTrue(action.amountOwedToPool > 0); // Debt in
    assertEq(action.amount0Out, 0); // No debt out
    assertTrue(action.amount1Out > 0); // Collateral out
  }

  function test_determineAction_contraction_isToken0Debt_poolPriceBelow() public fpmmToken0Debt(18, 18) {
    // Set oracle rate to 1:1
    setOracleRate(1e18, 1e18);
    // Provide liquidity with pool price 10% below oracle (100:90 reserves)
    provideFPMMReserves(100e18, 90e18, true);

    vm.prank(owner);
    strategy.addPool(address(fpmm), debtToken, 3600, 50);

    (LQ.Context memory ctx, LQ.Action memory action) = strategy.determineAction(address(fpmm));

    // Should be contraction: add collateral (token1), take debt (token0)
    assertEq(ctx.prices.poolPriceAbove, false);
    assertEq(action.dir, LQ.Direction.Contract);
    assertTrue(action.amountOwedToPool > 0); // Collateral in
    assertTrue(action.amount0Out > 0); // Debt out
    assertEq(action.amount1Out, 0); // No collateral out
  }

  function test_determineAction_contraction_isToken1Debt_poolPriceAbove() public fpmmToken1Debt(18, 18) {
    // Swap token order - now token1 is debt (collToken is token0, debtToken is token1)
    // Set oracle rate to 1:1
    setOracleRate(1e18, 1e18);
    // Provide liquidity with pool price 10% above oracle (110:100 reserves for token0:token1)
    provideFPMMReserves(100e18, 110e18, false);

    vm.prank(owner);
    strategy.addPool(address(fpmm), debtToken, 3600, 50);

    (LQ.Context memory ctx, LQ.Action memory action) = strategy.determineAction(address(fpmm));

    // Should be contraction: take debt (token1) from pool, add collateral (token0)
    assertEq(ctx.prices.poolPriceAbove, true);
    assertEq(action.dir, LQ.Direction.Contract);
    assertTrue(action.amountOwedToPool > 0); // Collateral in
    assertTrue(action.amount1Out > 0); // Debt out (token1)
    assertEq(action.amount0Out, 0);
  }

  function test_determineAction_expansion_isToken1Debt_poolPriceBelow() public fpmmToken1Debt(18, 18) {
    // Swap token order - now token1 is debt (collToken is token0, debtToken is token1)
    // Set oracle rate to 1:1
    setOracleRate(1e18, 1e18);
    // Provide liquidity with pool price 10% below oracle (90:100 reserves for token0:token1)
    provideFPMMReserves(100e18, 90e18, false);

    vm.prank(owner);
    strategy.addPool(address(fpmm), debtToken, 3600, 50);

    (LQ.Context memory ctx, LQ.Action memory action) = strategy.determineAction(address(fpmm));

    // Should be expansion: add debt (token1), take collateral (token0)
    assertEq(ctx.prices.poolPriceAbove, false);
    assertEq(action.dir, LQ.Direction.Expand);
    assertTrue(action.amountOwedToPool > 0); // Debt in
    assertTrue(action.amount0Out > 0); // Collateral out (token0)
    assertEq(action.amount1Out, 0);
  }

  function test_determineAction_withDifferentDecimals() public fpmmToken0Debt(6, 18) {
    // Test with different decimals: debt=6, collateral=18
    setOracleRate(1e18, 1e18);
    // Provide liquidity with pool price 10% above oracle
    provideFPMMReserves(100e6, 110e18, true); // debt has 6 decimals, collateral has 18

    vm.prank(owner);
    strategy.addPool(address(fpmm), debtToken, 3600, 50);

    (, LQ.Action memory action) = strategy.determineAction(address(fpmm));

    // Should handle decimal scaling correctly
    assertEq(action.dir, LQ.Direction.Expand);
    assertTrue(action.amountOwedToPool > 0);
    assertTrue(action.amount1Out > 0);
  }

  /* ============================================================ */
  /* =================== Rebalance Tests ======================== */
  /* ============================================================ */

  function test_rebalance_whenCooldownActive_shouldRevert() public fpmmToken0Debt(18, 18) {
    setOracleRate(1e18, 1e18);
    provideFPMMReserves(100e18, 110e18, true);

    vm.prank(owner);
    strategy.addPool(address(fpmm), debtToken, 3600, 50);

    // First rebalance
    vm.prank(owner);
    strategy.rebalance(address(fpmm));

    // Clear transient storage to simulate new transaction
    strategy.clearTransientStorage(address(fpmm));

    // Try immediate second rebalance - should fail with cooldown
    vm.prank(owner);
    vm.expectRevert(ILiquidityStrategy.LS_COOLDOWN_ACTIVE.selector);
    strategy.rebalance(address(fpmm));
  }

  function test_rebalance_afterCooldown_shouldSucceed() public fpmmToken0Debt(18, 18) {
    setOracleRate(1e18, 1e18);
    provideFPMMReserves(100e18, 110e18, true);

    vm.prank(owner);
    strategy.addPool(address(fpmm), debtToken, 3600, 50);

    // First rebalance
    vm.prank(owner);
    strategy.rebalance(address(fpmm));

    // Clear transient storage and warp past cooldown to simulate new transaction
    strategy.clearTransientStorage(address(fpmm));
    vm.warp(block.timestamp + 3601);

    // Create new imbalance
    swapIn(debtToken, 5e18);

    // Second rebalance should succeed
    vm.prank(owner);
    strategy.rebalance(address(fpmm));
  }

  function test_rebalance_shouldEmitLiquidityMovedEvent() public fpmmToken0Debt(18, 18) {
    setOracleRate(1e18, 1e18);
    provideFPMMReserves(100e18, 110e18, true);

    vm.prank(owner);
    strategy.addPool(address(fpmm), debtToken, 0, 50); // 0 cooldown

    // Expect LiquidityMoved event (only checking indexed fields)
    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Expand, address(0), 0, address(0), 0); // Amounts and addresses will vary

    vm.prank(owner);
    strategy.rebalance(address(fpmm));
  }

  /* ============================================================ */
  /* ============== Hook Called Mechanism Tests ================= */
  /* ============================================================ */

  function test_rebalance_whenHookCalled_shouldSucceed() public fpmmToken0Debt(18, 18) {
    setOracleRate(1e18, 1e18);
    provideFPMMReserves(100e18, 110e18, true);

    vm.prank(owner);
    strategy.addPool(address(fpmm), debtToken, 0, 50);

    vm.prank(owner);
    strategy.rebalance(address(fpmm));
  }

  function test_hook_whenCalledFromNonPool_shouldRevert() public fpmmToken0Debt(18, 18) {
    vm.prank(owner);
    strategy.addPool(address(fpmm), debtToken, 0, 50);

    // Try to call hook from non-pool address
    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        amountOwedToPool: 100e18,
        incentiveBps: 50,
        dir: LQ.Direction.Expand,
        isToken0Debt: true,
        debtToken: debtToken,
        collToken: collToken
      })
    );

    vm.prank(notOwner); // Not the pool
    vm.expectRevert(ILiquidityStrategy.LS_POOL_NOT_FOUND.selector);
    strategy.onRebalance(address(strategy), 0, 100e18, hookData);
  }

  function test_hook_whenSenderIsNotStrategy_shouldRevert() public fpmmToken0Debt(18, 18) {
    vm.prank(owner);
    strategy.addPool(address(fpmm), debtToken, 0, 50);

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        amountOwedToPool: 100e18,
        incentiveBps: 50,
        dir: LQ.Direction.Expand,
        isToken0Debt: true,
        debtToken: debtToken,
        collToken: collToken
      })
    );

    // Call from pool but with wrong sender
    vm.prank(address(fpmm));
    vm.expectRevert(ILiquidityStrategy.LS_INVALID_SENDER.selector);
    strategy.onRebalance(notOwner, 0, 100e18, hookData);
  }

  function test_transientStorage_shouldResetBetweenTransactions() public fpmmToken0Debt(18, 18) {
    setOracleRate(1e18, 1e18);
    provideFPMMReserves(100e18, 110e18, true);

    vm.prank(owner);
    strategy.addPool(address(fpmm), debtToken, 0, 50);

    // First transaction - should succeed
    vm.prank(owner);
    strategy.rebalance(address(fpmm));

    // Simulate a new transaction by:
    // 1. Advancing time to pass cooldown
    vm.warp(block.timestamp + 1);
    // 2. Manually clearing transient storage (simulates EIP-1153 automatic clearing between transactions)
    strategy.clearTransientStorage(address(fpmm));

    // Create a new imbalance by swapping tokens
    swapIn(debtToken, 5e18);

    // Second transaction - transient storage should be cleared
    // So the hook check at the start should NOT revert with LS_CAN_ONLY_REBALANCE_ONCE
    // Instead it should work normally and succeed
    vm.prank(owner);
    strategy.rebalance(address(fpmm));
  }

  function test_rebalance_multiplePools_shouldTrackSeparately() public fpmmToken0Debt(18, 18) {
    // Create a second FPMM pool manually
    address debtToken2;
    address collToken2;

    // Deploy second set of tokens
    uint256 currentNonce = vm.getNonce(address(this));
    address a1 = vm.computeCreateAddress(address(this), currentNonce);
    address a2 = vm.computeCreateAddress(address(this), currentNonce + 1);

    if (a1 < a2) {
      debtToken2 = address(new MockERC20("DebtToken2", "DT2", 18));
      collToken2 = address(new MockERC20("CollateralToken2", "CT2", 18));
    } else {
      collToken2 = address(new MockERC20("CollateralToken2", "CT2", 18));
      debtToken2 = address(new MockERC20("DebtToken2", "DT2", 18));
    }

    FPMM fpmm2 = new FPMM(false);
    fpmm2.initialize(
      debtToken2,
      collToken2,
      oracleAdapter,
      referenceRateFeedID,
      false,
      address(this),
      defaultFPMMParams
    );
    fpmm2.setLiquidityStrategy(strategyAddr, true);

    // Setup both pools with imbalanced reserves
    setOracleRate(1e18, 1e18);
    provideFPMMReserves(100e18, 110e18, true);

    MockERC20(debtToken2).mint(address(fpmm2), 100e18);
    MockERC20(collToken2).mint(address(fpmm2), 110e18);
    fpmm2.mint(address(this));

    // Fund strategy with second token set (first set funded by modifier)
    MockERC20(debtToken2).mint(address(strategy), 1000000e18);
    MockERC20(collToken2).mint(address(strategy), 1000000e18);

    vm.startPrank(owner);
    strategy.addPool(address(fpmm), debtToken, 0, 50);
    strategy.addPool(address(fpmm2), debtToken2, 0, 50);

    // Should be able to rebalance both pools in the same transaction
    // Each pool tracks its own transient storage flag
    strategy.rebalance(address(fpmm));
    strategy.rebalance(address(fpmm2));
    vm.stopPrank();
  }
}
