// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { ReserveLiquidityStrategyBaseTest } from "./ReserveLiquidityStrategyBaseTest.sol";
import { LiquidityTypes as LQ } from "contracts/v3/libraries/LiquidityTypes.sol";

contract ReserveLiquidityStrategyExecutionTest is ReserveLiquidityStrategyBaseTest {
  function setUp() public override {
    super.setUp();

    // Set pool1 as trusted for execution tests
    vm.prank(owner);
    strategy.setTrustedPool(pool1, true);

    _mockFPMMRebalance(pool1);
  }

  /* ============================================================ */
  /* ================= Execute Function Tests =================== */
  /* ============================================================ */

  function test_execute_whenValidExpandAction_shouldSucceed() public {
    LQ.Action memory action = _createAction({
      _pool: pool1,
      _direction: LQ.Direction.Expand,
      _amount0Out: 0,
      _amount1Out: 50e18, // Collateral out
      _inputAmount: 50e18, // Debt in
      _incentiveBps: 500, // 5%
      _isToken0Debt: true
    });

    uint256 incentiveAmount = (50e18 * 500) / 10000; // 2.5e18
    uint256 debtAmount = 50e18; // inputAmount for expansion
    uint256 collateralAmount = 50e18; // amount1Out for expansion

    _expectLiquidityMovedEvent(pool1, LQ.Direction.Expand, debtAmount, collateralAmount, incentiveAmount);

    bool result = strategy.execute(action);

    assertTrue(result, "Execute should return true");
  }

  function test_execute_whenValidContractAction_shouldSucceed() public {
    LQ.Action memory action = _createAction({
      _pool: pool1,
      _direction: LQ.Direction.Contract,
      _amount0Out: 30e18, // Debt out
      _amount1Out: 0,
      _inputAmount: 30e18, // Collateral in
      _incentiveBps: 1000, // 10%
      _isToken0Debt: true
    });

    uint256 incentiveAmount = (30e18 * 1000) / 10000; // 3e18
    uint256 debtAmount = 30e18; // amount0Out for contraction
    uint256 collateralAmount = 30e18; // inputAmount for contraction

    _expectLiquidityMovedEvent(pool1, LQ.Direction.Contract, debtAmount, collateralAmount, incentiveAmount);

    bool result = strategy.execute(action);

    assertTrue(result, "Execute should return true");
  }

  function test_execute_whenWrongLiquiditySource_shouldRevert() public {
    LQ.Action memory action = _createAction({
      _pool: pool1,
      _direction: LQ.Direction.Expand,
      _amount0Out: 0,
      _amount1Out: 50e18,
      _inputAmount: 50e18,
      _incentiveBps: 500,
      _isToken0Debt: true
    });

    // Set to wrong liquidity source
    action.liquiditySource = LQ.LiquiditySource.CDP;

    vm.expectRevert("RLS: WRONG_SOURCE");
    strategy.execute(action);
  }

  function test_execute_whenZeroPool_shouldRevert() public {
    LQ.Action memory action = _createAction({
      _pool: address(0),
      _direction: LQ.Direction.Expand,
      _amount0Out: 0,
      _amount1Out: 50e18,
      _inputAmount: 50e18,
      _incentiveBps: 500,
      _isToken0Debt: true
    });

    vm.expectRevert("RLS: INVALID_POOL");
    strategy.execute(action);
  }

  function test_execute_whenUntrustedPool_shouldRevert() public {
    LQ.Action memory action = _createAction({
      _pool: pool2, // pool2 is not trusted
      _direction: LQ.Direction.Expand,
      _amount0Out: 0,
      _amount1Out: 50e18,
      _inputAmount: 50e18,
      _incentiveBps: 500,
      _isToken0Debt: true
    });

    vm.expectRevert("RLS: UNTRUSTED_POOL");
    strategy.execute(action);
  }

  function test_execute_withZeroIncentive_shouldSucceed() public {
    LQ.Action memory action = _createAction({
      _pool: pool1,
      _direction: LQ.Direction.Expand,
      _amount0Out: 0,
      _amount1Out: 100e18,
      _inputAmount: 100e18,
      _incentiveBps: 0, // Zero incentive
      _isToken0Debt: true
    });

    _expectLiquidityMovedEvent(pool1, LQ.Direction.Expand, 100e18, 100e18, 0);

    bool result = strategy.execute(action);

    assertTrue(result, "Execute should succeed with zero incentive");
  }

  function test_execute_withMaxIncentive_shouldSucceed() public {
    LQ.Action memory action = _createAction({
      _pool: pool1,
      _direction: LQ.Direction.Contract,
      _amount0Out: 100e18,
      _amount1Out: 0,
      _inputAmount: 100e18,
      _incentiveBps: 10000, // 100% incentive
      _isToken0Debt: true
    });

    uint256 incentiveAmount = 100e18; // 100% of input
    _expectLiquidityMovedEvent(pool1, LQ.Direction.Contract, 100e18, 100e18, incentiveAmount);

    bool result = strategy.execute(action);

    assertTrue(result, "Execute should succeed with max incentive");
  }

  /* ============================================================ */
  /* ================= Callback Data ====================== */
  /* ============================================================ */

  function test_execute_shouldEncodeCallbackDataCorrectly() public {
    uint256 inputAmount = 60e18;
    uint256 incentiveBps = 800; // 8%
    LQ.Direction direction = LQ.Direction.Contract;
    bool isToken0Debt = true;

    LQ.Action memory action = _createAction({
      _pool: pool1,
      _direction: direction,
      _amount0Out: 60e18,
      _amount1Out: 0,
      _inputAmount: inputAmount,
      _incentiveBps: incentiveBps,
      _isToken0Debt: isToken0Debt
    });

    uint256 expectedIncentiveAmount = (inputAmount * incentiveBps) / 10000;

    bytes memory expectedHookData = abi.encode(inputAmount, expectedIncentiveAmount, direction, isToken0Debt);

    vm.expectCall(
      pool1,
      abi.encodeWithSelector(
        bytes4(keccak256("rebalance(uint256,uint256,bytes)")),
        action.amount0Out,
        action.amount1Out,
        expectedHookData
      )
    );

    strategy.execute(action);
  }
}
