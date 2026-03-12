// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { OpenLiquidityStrategy_BaseTest } from "./OpenLiquidityStrategy_BaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/libraries/LiquidityStrategyTypes.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";
import { IOpenLiquidityStrategy } from "contracts/interfaces/IOpenLiquidityStrategy.sol";

contract OpenLiquidityStrategy_DetermineActionTest is OpenLiquidityStrategy_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  /* ============================================================ */
  /* ========= determineAction with sufficient balance ========== */
  /* ============================================================ */

  function test_determineAction_expansion_whenCallerHasSufficientDebt_shouldReturnAction()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Pool price above oracle => expansion (debt flows in)
    provideFPMMReserves(100e18, 200e18, true);
    setOracleRate(1e18, 1e18);

    // Call determineAction as the rebalancer who has tokens
    vm.prank(rebalancer);
    (, LQ.Action memory action) = strategy.determineAction(address(fpmm));

    assertEq(uint8(action.dir), uint8(LQ.Direction.Expand));
    assertTrue(action.amount1Out > 0, "Should have collateral out");
    assertTrue(action.amountOwedToPool > 0, "Should owe debt to pool");
  }

  function test_determineAction_contraction_whenCallerHasSufficientCollateral_shouldReturnAction()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Pool price below oracle => contraction (collateral flows in)
    provideFPMMReserves(200e18, 100e18, true);
    setOracleRate(1e18, 1e18);

    vm.prank(rebalancer);
    (, LQ.Action memory action) = strategy.determineAction(address(fpmm));

    assertEq(uint8(action.dir), uint8(LQ.Direction.Contract));
    assertTrue(action.amount0Out > 0, "Should have debt out");
    assertTrue(action.amountOwedToPool > 0, "Should owe collateral to pool");
  }

  /* ============================================================ */
  /* ========== determineAction with zero balance =============== */
  /* ============================================================ */

  function test_determineAction_expansion_whenCallerHasNoDebt_shouldRevert()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    provideFPMMReserves(100e18, 200e18, true);
    setOracleRate(1e18, 1e18);

    // Caller with no debt tokens
    address caller = makeAddr("NoDebtCaller");

    vm.expectRevert(IOpenLiquidityStrategy.OLS_OUT_OF_DEBT.selector);
    vm.prank(caller);
    strategy.determineAction(address(fpmm));
  }

  function test_determineAction_contraction_whenCallerHasNoCollateral_shouldRevert()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    provideFPMMReserves(200e18, 100e18, true);
    setOracleRate(1e18, 1e18);

    // Caller with no collateral tokens
    address caller = makeAddr("NoCollateralCaller");

    vm.expectRevert(IOpenLiquidityStrategy.OLS_OUT_OF_COLLATERAL.selector);
    vm.prank(caller);
    strategy.determineAction(address(fpmm));
  }

  /* ============================================================ */
  /* ========== determineAction with limited balance ============ */
  /* ============================================================ */

  function test_determineAction_expansion_whenCallerHasLimitedDebt_shouldClamp()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Large imbalance requiring lots of debt
    provideFPMMReserves(100e18, 1000e18, true);
    setOracleRate(1e18, 1e18);

    // Caller with only 1e18 debt tokens
    address limitedCaller = makeAddr("LimitedDebtCaller");
    MockERC20(debtToken).mint(limitedCaller, 1e18);

    vm.prank(limitedCaller);
    (, LQ.Action memory clampedAction) = strategy.determineAction(address(fpmm));

    // Full-balance caller for comparison
    vm.prank(rebalancer);
    (, LQ.Action memory fullAction) = strategy.determineAction(address(fpmm));

    assertEq(uint8(clampedAction.dir), uint8(LQ.Direction.Expand));
    // Clamped amounts should be less than full amounts
    assertTrue(clampedAction.amountOwedToPool < fullAction.amountOwedToPool, "Clamped debt should be less");
    assertTrue(
      clampedAction.amount1Out < fullAction.amount1Out || clampedAction.amount0Out < fullAction.amount0Out,
      "Clamped output should be less"
    );
  }

  function test_determineAction_contraction_whenCallerHasLimitedCollateral_shouldClamp()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Large imbalance requiring lots of collateral
    provideFPMMReserves(1000e18, 100e18, true);
    setOracleRate(1e18, 1e18);

    // Caller with only 1e18 collateral tokens
    address limitedCaller = makeAddr("LimitedCollateralCaller");
    MockERC20(collToken).mint(limitedCaller, 1e18);

    vm.prank(limitedCaller);
    (, LQ.Action memory clampedAction) = strategy.determineAction(address(fpmm));

    // Full-balance caller for comparison
    vm.prank(rebalancer);
    (, LQ.Action memory fullAction) = strategy.determineAction(address(fpmm));

    assertEq(uint8(clampedAction.dir), uint8(LQ.Direction.Contract));
    assertTrue(clampedAction.amountOwedToPool < fullAction.amountOwedToPool, "Clamped collateral should be less");
  }

  /* ============================================================ */
  /* ==== determineAction matches rebalance execution =========== */
  /* ============================================================ */

  function test_determineAction_shouldMatchRebalanceExecution_expansion()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    provideFPMMReserves(100e18, 200e18, true);
    setOracleRate(1e18, 1e18);

    // Preview via determineAction
    vm.prank(rebalancer);
    (, LQ.Action memory previewAction) = strategy.determineAction(address(fpmm));

    // Execute actual rebalance and compare token flows
    uint256 rebalancerDebtBefore = IERC20(debtToken).balanceOf(rebalancer);
    uint256 rebalancerCollBefore = IERC20(collToken).balanceOf(rebalancer);

    vm.prank(rebalancer);
    strategy.rebalance(address(fpmm));

    uint256 debtSpent = rebalancerDebtBefore - IERC20(debtToken).balanceOf(rebalancer);
    uint256 collReceived = IERC20(collToken).balanceOf(rebalancer) - rebalancerCollBefore;

    // The debt spent should match the action's amountOwedToPool
    assertEq(debtSpent, previewAction.amountOwedToPool, "Debt spent should match preview");
    // Collateral received = amount from pool - protocol incentive
    assertTrue(collReceived > 0, "Should have received collateral");
  }

  function test_determineAction_shouldMatchRebalanceExecution_contraction()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    provideFPMMReserves(200e18, 100e18, true);
    setOracleRate(1e18, 1e18);

    // Preview via determineAction
    vm.prank(rebalancer);
    (, LQ.Action memory previewAction) = strategy.determineAction(address(fpmm));

    // Execute actual rebalance and compare token flows
    uint256 rebalancerCollBefore = IERC20(collToken).balanceOf(rebalancer);
    uint256 rebalancerDebtBefore = IERC20(debtToken).balanceOf(rebalancer);

    vm.prank(rebalancer);
    strategy.rebalance(address(fpmm));

    uint256 collSpent = rebalancerCollBefore - IERC20(collToken).balanceOf(rebalancer);
    uint256 debtReceived = IERC20(debtToken).balanceOf(rebalancer) - rebalancerDebtBefore;

    assertEq(collSpent, previewAction.amountOwedToPool, "Collateral spent should match preview");
    assertTrue(debtReceived > 0, "Should have received debt tokens");
  }

  /* ============================================================ */
  /* ============ determineAction with token1 as debt =========== */
  /* ============================================================ */

  function test_determineAction_expansion_whenToken1IsDebt_shouldWork()
    public
    fpmmToken1Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Token1 is debt: excess collateral in token0
    provideFPMMReserves(200e18, 100e18, false);
    setOracleRate(1e18, 1e18);

    vm.prank(rebalancer);
    (, LQ.Action memory action) = strategy.determineAction(address(fpmm));

    assertEq(uint8(action.dir), uint8(LQ.Direction.Expand));
    assertTrue(action.amountOwedToPool > 0);
  }

  function test_determineAction_contraction_whenToken1IsDebt_shouldWork()
    public
    fpmmToken1Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Token1 is debt: excess debt in token1
    provideFPMMReserves(100e18, 200e18, false);
    setOracleRate(1e18, 1e18);

    vm.prank(rebalancer);
    (, LQ.Action memory action) = strategy.determineAction(address(fpmm));

    assertEq(uint8(action.dir), uint8(LQ.Direction.Contract));
    assertTrue(action.amountOwedToPool > 0);
  }
}
