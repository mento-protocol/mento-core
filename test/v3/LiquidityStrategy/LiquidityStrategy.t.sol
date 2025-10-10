// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { Test } from "mento-std/Test.sol";
import { LiquidityStrategyHarness } from "test/utils/harnesses/LiquidityStrategyHarness.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/v3/libraries/LiquidityStrategyTypes.sol";
import { ILiquidityStrategy } from "contracts/v3/interfaces/ILiquidityStrategy.sol";
import { IFPMM } from "contracts/interfaces/IFPMM.sol";
import { IRPool } from "contracts/swap/router/interfaces/IRPool.sol";

contract LiquidityStrategy_Test is Test {
  LiquidityStrategyHarness public strategy;

  // Mock addresses
  address public owner = makeAddr("Owner");
  address public notOwner = makeAddr("NotOwner");
  address public pool1 = makeAddr("Pool1");
  address public pool2 = makeAddr("Pool2");
  address public token0 = makeAddr("Token0");
  address public token1 = makeAddr("Token1");
  address public debtToken;
  address public collateralToken;

  function setUp() public {
    strategy = new LiquidityStrategyHarness(owner);

    // Ensure token0 < token1 for ordering
    debtToken = token0;
    collateralToken = token1;
  }

  /* ============================================================ */
  /* ===================== Helper Functions ===================== */
  /* ============================================================ */

  function _mockFPMMMetadata(address _pool, address _token0, address _token1, uint256 dec0, uint256 dec1) internal {
    bytes memory metadataCalldata = abi.encodeWithSelector(IRPool.metadata.selector);
    vm.mockCall(_pool, metadataCalldata, abi.encode(dec0, dec1, 100e18, 200e18, _token0, _token1));
  }

  function _mockFPMMToken0(address _pool, address _token0) internal {
    bytes memory calldata_ = abi.encodeWithSelector(IRPool.token0.selector);
    vm.mockCall(_pool, calldata_, abi.encode(_token0));
  }

  function _mockFPMMPrices(
    address _pool,
    uint256 oracleNum,
    uint256 oracleDen,
    uint256 reserveNum,
    uint256 reserveDen,
    uint256 diffBps,
    bool poolAbove
  ) internal {
    bytes memory pricesCalldata = abi.encodeWithSelector(IFPMM.getPrices.selector);
    vm.mockCall(_pool, pricesCalldata, abi.encode(oracleNum, oracleDen, reserveNum, reserveDen, diffBps, poolAbove));
  }

  function _mockFPMMRebalanceIncentive(address _pool, uint256 incentive) internal {
    bytes memory incentiveCalldata = abi.encodeWithSelector(IFPMM.rebalanceIncentive.selector);
    vm.mockCall(_pool, incentiveCalldata, abi.encode(incentive));
  }

  function _mockFPMMRebalance(address _pool) internal {
    bytes memory rebalanceCalldata = abi.encodeWithSelector(IFPMM.rebalance.selector);
    vm.mockCall(_pool, rebalanceCalldata, abi.encode());
  }

  /* ============================================================ */
  /* =================== Pool Management Tests ================== */
  /* ============================================================ */

  function test_addPool_whenValidParams_shouldAddPool() public {
    _mockFPMMMetadata(pool1, debtToken, collateralToken, 1e18, 1e18);
    _mockFPMMToken0(pool1, debtToken);
    _mockFPMMRebalanceIncentive(pool1, 100);

    vm.expectEmit(true, true, true, true);
    emit PoolAdded(pool1, true, 3600, 50);

    vm.prank(owner);
    strategy.addPool(pool1, debtToken, 3600, 50);

    assertTrue(strategy.isPoolRegistered(pool1));
  }

  function test_addPool_whenPoolIsZero_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(ILiquidityStrategy.LS_POOL_MUST_BE_SET.selector);
    strategy.addPool(address(0), debtToken, 3600, 50);
  }

  function test_addPool_whenIncentiveTooHigh_shouldRevert() public {
    _mockFPMMMetadata(pool1, debtToken, collateralToken, 1e18, 1e18);
    _mockFPMMToken0(pool1, debtToken);
    _mockFPMMRebalanceIncentive(pool1, 50); // Pool max is 50

    vm.prank(owner);
    vm.expectRevert(ILiquidityStrategy.LS_BAD_INCENTIVE.selector);
    strategy.addPool(pool1, debtToken, 3600, 100); // Trying to set 100
  }

  function test_addPool_whenPoolAlreadyExists_shouldRevert() public {
    _mockFPMMMetadata(pool1, debtToken, collateralToken, 1e18, 1e18);
    _mockFPMMToken0(pool1, debtToken);
    _mockFPMMRebalanceIncentive(pool1, 100);

    vm.prank(owner);
    strategy.addPool(pool1, debtToken, 3600, 50);

    vm.prank(owner);
    vm.expectRevert(ILiquidityStrategy.LS_POOL_ALREADY_EXISTS.selector);
    strategy.addPool(pool1, debtToken, 3600, 50);
  }

  function test_addPool_whenCalledByNonOwner_shouldRevert() public {
    _mockFPMMMetadata(pool1, debtToken, collateralToken, 1e18, 1e18);
    _mockFPMMToken0(pool1, debtToken);
    _mockFPMMRebalanceIncentive(pool1, 100);

    vm.prank(notOwner);
    vm.expectRevert();
    strategy.addPool(pool1, debtToken, 3600, 50);
  }

  function test_removePool_whenPoolExists_shouldRemovePool() public {
    // Add pool first
    _mockFPMMMetadata(pool1, debtToken, collateralToken, 1e18, 1e18);
    _mockFPMMToken0(pool1, debtToken);
    _mockFPMMRebalanceIncentive(pool1, 100);
    vm.prank(owner);
    strategy.addPool(pool1, debtToken, 3600, 50);

    // Remove it
    vm.expectEmit(true, false, false, false);
    emit PoolRemoved(pool1);

    vm.prank(owner);
    strategy.removePool(pool1);

    assertFalse(strategy.isPoolRegistered(pool1));
  }

  function test_removePool_whenPoolDoesNotExist_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(ILiquidityStrategy.LS_POOL_NOT_FOUND.selector);
    strategy.removePool(pool1);
  }

  function test_setRebalanceCooldown_whenPoolExists_shouldUpdateCooldown() public {
    // Add pool
    _mockFPMMMetadata(pool1, debtToken, collateralToken, 1e18, 1e18);
    _mockFPMMToken0(pool1, debtToken);
    _mockFPMMRebalanceIncentive(pool1, 100);
    vm.prank(owner);
    strategy.addPool(pool1, debtToken, 3600, 50);

    // Update cooldown
    vm.expectEmit(true, false, false, true);
    emit RebalanceCooldownSet(pool1, 7200);

    vm.prank(owner);
    strategy.setRebalanceCooldown(pool1, 7200);
  }

  function test_setRebalanceIncentive_whenValid_shouldUpdateIncentive() public {
    // Add pool
    _mockFPMMMetadata(pool1, debtToken, collateralToken, 1e18, 1e18);
    _mockFPMMToken0(pool1, debtToken);
    _mockFPMMRebalanceIncentive(pool1, 100);
    vm.prank(owner);
    strategy.addPool(pool1, debtToken, 3600, 50);

    // Update incentive
    vm.expectEmit(true, false, false, true);
    emit RebalanceIncentiveSet(pool1, 75);

    vm.prank(owner);
    strategy.setRebalanceIncentive(pool1, 75);
  }

  function test_setRebalanceIncentive_whenExceedsPoolCap_shouldRevert() public {
    // Add pool
    _mockFPMMMetadata(pool1, debtToken, collateralToken, 1e18, 1e18);
    _mockFPMMToken0(pool1, debtToken);
    _mockFPMMRebalanceIncentive(pool1, 100);
    vm.prank(owner);
    strategy.addPool(pool1, debtToken, 3600, 50);

    // Try to set incentive above pool cap
    vm.prank(owner);
    vm.expectRevert(ILiquidityStrategy.LS_BAD_INCENTIVE.selector);
    strategy.setRebalanceIncentive(pool1, 150);
  }

  /* ============================================================ */
  /* ================= Determine Action Tests =================== */
  /* ============================================================ */

  function test_determineAction_expansion_isToken0Debt_poolPriceAbove() public {
    _mockFPMMMetadata(pool1, debtToken, collateralToken, 1e18, 1e18);
    _mockFPMMToken0(pool1, debtToken);
    _mockFPMMRebalanceIncentive(pool1, 100);
    _mockFPMMPrices(pool1, 1e18, 1e18, 110e18, 100e18, 1000, true); // Pool price > oracle

    vm.prank(owner);
    strategy.addPool(pool1, debtToken, 3600, 50);

    (LQ.Context memory ctx, LQ.Action memory action) = strategy.determineAction(pool1);

    // Should be expansion: add debt (token0), take collateral (token1)
    assertEq(uint(action.dir), uint(LQ.Direction.Expand));
    assertTrue(action.inputAmount > 0); // Debt in
    assertEq(action.amount0Out, 0); // No debt out
    assertTrue(action.amount1Out > 0); // Collateral out
  }

  function test_determineAction_contraction_isToken0Debt_poolPriceBelow() public {
    _mockFPMMMetadata(pool1, debtToken, collateralToken, 1e18, 1e18);
    _mockFPMMToken0(pool1, debtToken);
    _mockFPMMRebalanceIncentive(pool1, 100);
    _mockFPMMPrices(pool1, 1e18, 1e18, 90e18, 100e18, 1000, false); // Pool price < oracle

    vm.prank(owner);
    strategy.addPool(pool1, debtToken, 3600, 50);

    (LQ.Context memory ctx, LQ.Action memory action) = strategy.determineAction(pool1);

    // Should be contraction: add collateral (token1), take debt (token0)
    assertEq(uint(action.dir), uint(LQ.Direction.Contract));
    assertTrue(action.inputAmount > 0); // Collateral in
    assertTrue(action.amount0Out > 0); // Debt out
    assertEq(action.amount1Out, 0); // No collateral out
  }

  function test_determineAction_expansion_isToken1Debt_poolPriceAbove() public {
    // Swap token order - now token1 is debt
    _mockFPMMMetadata(pool1, collateralToken, debtToken, 1e18, 1e18);
    _mockFPMMToken0(pool1, collateralToken);
    _mockFPMMRebalanceIncentive(pool1, 100);
    _mockFPMMPrices(pool1, 1e18, 1e18, 110e18, 100e18, 1000, true);

    vm.prank(owner);
    strategy.addPool(pool1, debtToken, 3600, 50);

    (LQ.Context memory ctx, LQ.Action memory action) = strategy.determineAction(pool1);

    // Should be contraction: take debt (token1) from pool, add collateral (token0)
    assertEq(uint(action.dir), uint(LQ.Direction.Contract));
    assertTrue(action.inputAmount > 0); // Collateral in
    assertTrue(action.amount1Out > 0); // Debt out (token1)
    assertEq(action.amount0Out, 0);
  }

  function test_determineAction_contraction_isToken1Debt_poolPriceBelow() public {
    // Swap token order - now token1 is debt
    _mockFPMMMetadata(pool1, collateralToken, debtToken, 1e18, 1e18);
    _mockFPMMToken0(pool1, collateralToken);
    _mockFPMMRebalanceIncentive(pool1, 100);
    _mockFPMMPrices(pool1, 1e18, 1e18, 90e18, 100e18, 1000, false);

    vm.prank(owner);
    strategy.addPool(pool1, debtToken, 3600, 50);

    (LQ.Context memory ctx, LQ.Action memory action) = strategy.determineAction(pool1);

    // Should be expansion: add debt (token1), take collateral (token0)
    assertEq(uint(action.dir), uint(LQ.Direction.Expand));
    assertTrue(action.inputAmount > 0); // Debt in
    assertTrue(action.amount0Out > 0); // Collateral out (token0)
    assertEq(action.amount1Out, 0);
  }

  function test_determineAction_withDifferentDecimals() public {
    // Setup with different decimals: token0=6, token1=18
    _mockFPMMMetadata(pool1, debtToken, collateralToken, 1e6, 1e18);
    _mockFPMMToken0(pool1, debtToken);
    _mockFPMMRebalanceIncentive(pool1, 100);
    _mockFPMMPrices(pool1, 1e18, 1e18, 110e18, 100e18, 1000, true);

    vm.prank(owner);
    strategy.addPool(pool1, debtToken, 3600, 50);

    (LQ.Context memory ctx, LQ.Action memory action) = strategy.determineAction(pool1);

    // Should handle decimal scaling correctly
    assertEq(uint(action.dir), uint(LQ.Direction.Expand));
    assertTrue(action.inputAmount > 0);
    assertTrue(action.amount1Out > 0);
  }

  /* ============================================================ */
  /* =================== Rebalance Tests ======================== */
  /* ============================================================ */

  function test_rebalance_whenCooldownActive_shouldRevert() public {
    _mockFPMMMetadata(pool1, debtToken, collateralToken, 1e18, 1e18);
    _mockFPMMToken0(pool1, debtToken);
    _mockFPMMRebalanceIncentive(pool1, 100);
    _mockFPMMPrices(pool1, 1e18, 1e18, 110e18, 100e18, 1000, true);
    _mockFPMMRebalance(pool1);

    vm.prank(owner);
    strategy.addPool(pool1, debtToken, 3600, 50);

    // First rebalance
    vm.prank(owner);
    strategy.rebalance(pool1);

    // Try immediate second rebalance
    vm.prank(owner);
    vm.expectRevert(ILiquidityStrategy.LS_COOLDOWN_ACTIVE.selector);
    strategy.rebalance(pool1);
  }

  function test_rebalance_afterCooldown_shouldSucceed() public {
    _mockFPMMMetadata(pool1, debtToken, collateralToken, 1e18, 1e18);
    _mockFPMMToken0(pool1, debtToken);
    _mockFPMMRebalanceIncentive(pool1, 100);
    _mockFPMMPrices(pool1, 1e18, 1e18, 110e18, 100e18, 1000, true);
    _mockFPMMRebalance(pool1);

    vm.prank(owner);
    strategy.addPool(pool1, debtToken, 3600, 50);

    // First rebalance
    vm.prank(owner);
    strategy.rebalance(pool1);

    // Warp past cooldown
    vm.warp(block.timestamp + 3601);

    // Second rebalance should succeed
    vm.prank(owner);
    strategy.rebalance(pool1);
  }

  function test_rebalance_shouldEmitLiquidityMovedEvent() public {
    _mockFPMMMetadata(pool1, debtToken, collateralToken, 1e18, 1e18);
    _mockFPMMToken0(pool1, debtToken);
    _mockFPMMRebalanceIncentive(pool1, 100);
    _mockFPMMPrices(pool1, 1e18, 1e18, 110e18, 100e18, 1000, true);
    _mockFPMMRebalance(pool1);

    vm.prank(owner);
    strategy.addPool(pool1, debtToken, 0, 50); // 0 cooldown

    // Expect LiquidityMoved event
    vm.expectEmit(true, false, false, false);
    emit LiquidityMoved(pool1, LQ.Direction.Expand, 0, 0, 0); // Amounts will vary

    vm.prank(owner);
    strategy.rebalance(pool1);
  }

  /* ============================================================ */
  /* ======================= Events ============================= */
  /* ============================================================ */

  event PoolAdded(address indexed pool, bool isToken0Debt, uint64 cooldown, uint32 incentiveBps);
  event PoolRemoved(address indexed pool);
  event RebalanceCooldownSet(address indexed pool, uint64 cooldown);
  event RebalanceIncentiveSet(address indexed pool, uint32 incentiveBps);
  event RebalanceExecuted(address indexed pool, uint256 diffBeforeBps, uint256 diffAfterBps);
  event LiquidityMoved(
    address indexed pool,
    LQ.Direction direction,
    uint256 tokenInAmount,
    uint256 tokenOutAmount,
    uint256 incentiveAmount
  );
}
