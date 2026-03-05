// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { OpenLiquidityStrategy_BaseTest } from "./OpenLiquidityStrategy_BaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/libraries/LiquidityStrategyTypes.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";
import { ILiquidityStrategy } from "contracts/interfaces/ILiquidityStrategy.sol";
import { IOpenLiquidityStrategy } from "contracts/interfaces/IOpenLiquidityStrategy.sol";

contract OpenLiquidityStrategy_RebalanceTest is OpenLiquidityStrategy_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  /* ============================================================ */
  /* ================= Rebalance Function Tests ================= */
  /* ============================================================ */

  function test_rebalance_whenPoolPriceAboveOracle_shouldExpandSuccessfully()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 50, 0.005025125628140703e18)
  {
    // Setup: Pool has 100 debt and 200 collateral (excess collateral)
    provideFPMMReserves(100e18, 200e18, true);
    // Oracle price is 1:1, pool price is 2:1 (pool price above oracle)
    setOracleRate(1e18, 1e18);

    // Expansion: debt flows IN from rebalancer, collateral flows OUT to rebalancer
    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Expand, address(0), 0, address(0), 0);

    vm.prank(rebalancer);
    strategy.rebalance(address(fpmm));
  }

  function test_rebalance_whenPoolPriceBelowOracle_shouldContractSuccessfully()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Setup: Pool has 200 debt and 100 collateral (excess debt)
    provideFPMMReserves(200e18, 100e18, true);
    // Oracle price is 1:1, pool price is 0.5:1 (pool price below oracle)
    setOracleRate(1e18, 1e18);

    // Contraction: collateral flows IN from rebalancer, debt flows OUT to rebalancer
    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Contract, address(0), 0, address(0), 0);

    vm.prank(rebalancer);
    strategy.rebalance(address(fpmm));
  }

  function test_rebalance_whenPoolNotAdded_shouldRevert() public fpmmToken0Debt(18, 18) {
    provideFPMMReserves(100e18, 200e18, true);
    setOracleRate(1e18, 1e18);

    vm.expectRevert("LS_POOL_NOT_FOUND()");
    vm.prank(rebalancer);
    strategy.rebalance(address(fpmm));
  }

  function test_rebalance_whenPoolPriceEqualsOracle_shouldNotRebalance()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Setup: Pool has balanced reserves at 1:1
    provideFPMMReserves(100e18, 100e18, true);
    // Oracle price is also 1:1 (pool price equals oracle)
    setOracleRate(1e18, 1e18);

    vm.expectRevert(ILiquidityStrategy.LS_POOL_NOT_REBALANCEABLE.selector);
    vm.prank(rebalancer);
    strategy.rebalance(address(fpmm));
  }

  function test_rebalance_withZeroIncentive_shouldSucceed() public fpmmToken0Debt(18, 18) addFpmm(0, 0, 0, 0, 0) {
    // Setup: Pool has excess collateral
    provideFPMMReserves(100e18, 200e18, true);
    setOracleRate(1e18, 1e18);

    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Expand, address(0), 0, address(0), 0);

    vm.prank(rebalancer);
    strategy.rebalance(address(fpmm));
  }

  function test_rebalance_withMaxIncentive_shouldSucceed()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Setup: Pool has excess debt
    provideFPMMReserves(200e18, 100e18, true);
    setOracleRate(1e18, 1e18);

    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Contract, address(0), 0, address(0), 0);

    vm.prank(rebalancer);
    strategy.rebalance(address(fpmm));
  }

  /* ============================================================ */
  /* =================== Token Flow Tests ====================== */
  /* ============================================================ */

  function test_rebalance_expansion_shouldTransferDebtFromRebalancerAndCollateralToRebalancer()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Setup: Pool has 100 debt and 200 collateral (excess collateral)
    provideFPMMReserves(100e18, 200e18, true);
    setOracleRate(1e18, 1e18);

    uint256 rebalancerDebtBefore = IERC20(debtToken).balanceOf(rebalancer);
    uint256 rebalancerCollBefore = IERC20(collToken).balanceOf(rebalancer);

    vm.prank(rebalancer);
    strategy.rebalance(address(fpmm));

    uint256 rebalancerDebtAfter = IERC20(debtToken).balanceOf(rebalancer);
    uint256 rebalancerCollAfter = IERC20(collToken).balanceOf(rebalancer);

    // Expansion: rebalancer provides debt to pool, receives collateral from pool
    assertLt(rebalancerDebtAfter, rebalancerDebtBefore, "Rebalancer should send debt tokens");
    assertGt(rebalancerCollAfter, rebalancerCollBefore, "Rebalancer should receive collateral tokens");
  }

  function test_rebalance_contraction_shouldTransferCollateralFromRebalancerAndDebtToRebalancer()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Setup: Pool has 200 debt and 100 collateral (excess debt)
    provideFPMMReserves(200e18, 100e18, true);
    setOracleRate(1e18, 1e18);

    uint256 rebalancerDebtBefore = IERC20(debtToken).balanceOf(rebalancer);
    uint256 rebalancerCollBefore = IERC20(collToken).balanceOf(rebalancer);

    vm.prank(rebalancer);
    strategy.rebalance(address(fpmm));

    uint256 rebalancerDebtAfter = IERC20(debtToken).balanceOf(rebalancer);
    uint256 rebalancerCollAfter = IERC20(collToken).balanceOf(rebalancer);

    // Contraction: rebalancer provides collateral to pool, receives debt from pool
    assertGt(rebalancerDebtAfter, rebalancerDebtBefore, "Rebalancer should receive debt tokens");
    assertLt(rebalancerCollAfter, rebalancerCollBefore, "Rebalancer should send collateral tokens");
  }

  /* ============================================================ */
  /* =============== Reversed Token Order Tests ================ */
  /* ============================================================ */

  function test_rebalance_whenToken1IsDebt_shouldExpandCorrectly()
    public
    fpmmToken1Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Setup: Pool has 200 collateral (token0) and 100 debt (token1) - excess collateral
    provideFPMMReserves(200e18, 100e18, false);
    setOracleRate(1e18, 1e18);

    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Expand, address(0), 0, address(0), 0);

    vm.prank(rebalancer);
    strategy.rebalance(address(fpmm));
  }

  function test_rebalance_whenToken1IsDebt_shouldContractCorrectly()
    public
    fpmmToken1Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Setup: Pool has 100 collateral (token0) and 200 debt (token1) - excess debt
    provideFPMMReserves(100e18, 200e18, false);
    setOracleRate(1e18, 1e18);

    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Contract, address(0), 0, address(0), 0);

    vm.prank(rebalancer);
    strategy.rebalance(address(fpmm));
  }

  /* ============================================================ */
  /* =============== Different Oracle Prices =================== */
  /* ============================================================ */

  function test_rebalance_withHighOraclePrice_shouldContractCorrectly()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Setup: Pool has 100 debt and 100 collateral
    provideFPMMReserves(100e18, 100e18, true);
    // Oracle price is 2:1, pool needs more collateral
    setOracleRate(2e18, 1e18);

    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Contract, address(0), 0, address(0), 0);

    vm.prank(rebalancer);
    strategy.rebalance(address(fpmm));
  }

  function test_rebalance_withLowOraclePrice_shouldExpandCorrectly()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Setup: Pool has 100 debt and 100 collateral
    provideFPMMReserves(100e18, 100e18, true);
    // Oracle price is 1:2, pool has excess collateral
    setOracleRate(1e18, 2e18);

    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Expand, address(0), 0, address(0), 0);

    vm.prank(rebalancer);
    strategy.rebalance(address(fpmm));
  }

  /* ============================================================ */
  /* ================ Clamping Tests =========================== */
  /* ============================================================ */

  function test_rebalance_contraction_whenRebalancerHasNoCollateral_shouldRevert()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    provideFPMMReserves(200e18, 100e18, true);
    setOracleRate(1e18, 1e18);

    // Burn all rebalancer's collateral
    vm.startPrank(rebalancer);
    MockERC20(collToken).transfer(address(1), MockERC20(collToken).balanceOf(rebalancer));
    vm.stopPrank();

    vm.expectRevert(IOpenLiquidityStrategy.OLS_OUT_OF_COLLATERAL.selector);
    vm.prank(rebalancer);
    strategy.rebalance(address(fpmm));
  }

  function test_rebalance_expansion_whenRebalancerHasNoDebt_shouldRevert()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    provideFPMMReserves(100e18, 200e18, true);
    setOracleRate(1e18, 1e18);

    // Burn all rebalancer's debt tokens
    vm.startPrank(rebalancer);
    MockERC20(debtToken).transfer(address(1), MockERC20(debtToken).balanceOf(rebalancer));
    vm.stopPrank();

    vm.expectRevert(IOpenLiquidityStrategy.OLS_OUT_OF_DEBT.selector);
    vm.prank(rebalancer);
    strategy.rebalance(address(fpmm));
  }

  function test_rebalance_contraction_whenRebalancerHasLimitedCollateral_shouldClamp()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Setup: large imbalance requiring lots of collateral
    provideFPMMReserves(1000e18, 100e18, true);
    setOracleRate(1e18, 1e18);

    // Give rebalancer only a small amount of collateral
    vm.startPrank(rebalancer);
    MockERC20(collToken).transfer(address(1), MockERC20(collToken).balanceOf(rebalancer) - 1e18);
    vm.stopPrank();

    uint256 rebalancerCollBefore = IERC20(collToken).balanceOf(rebalancer);
    assertEq(rebalancerCollBefore, 1e18, "Rebalancer should have 1e18 collateral");

    // Should succeed with clamped amounts
    vm.prank(rebalancer);
    strategy.rebalance(address(fpmm));

    // Rebalancer should have spent their collateral (minus what they received as incentive)
    uint256 rebalancerCollAfter = IERC20(collToken).balanceOf(rebalancer);
    assertLt(rebalancerCollAfter, rebalancerCollBefore, "Rebalancer should have spent collateral");
  }

  function test_rebalance_expansion_whenRebalancerHasLimitedDebt_shouldClamp()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Setup: large imbalance requiring lots of debt
    provideFPMMReserves(100e18, 1000e18, true);
    setOracleRate(1e18, 1e18);

    // Give rebalancer only a small amount of debt tokens
    vm.startPrank(rebalancer);
    MockERC20(debtToken).transfer(address(1), MockERC20(debtToken).balanceOf(rebalancer) - 1e18);
    vm.stopPrank();

    uint256 rebalancerDebtBefore = IERC20(debtToken).balanceOf(rebalancer);
    assertEq(rebalancerDebtBefore, 1e18, "Rebalancer should have 1e18 debt tokens");

    // Should succeed with clamped amounts
    vm.prank(rebalancer);
    strategy.rebalance(address(fpmm));

    uint256 rebalancerDebtAfter = IERC20(debtToken).balanceOf(rebalancer);
    assertLt(rebalancerDebtAfter, rebalancerDebtBefore, "Rebalancer should have spent debt tokens");
  }

  /* ============================================================ */
  /* =================== Edge Cases =========================== */
  /* ============================================================ */

  function test_rebalance_withVerySmallImbalance_shouldRevertDueToThreshold()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Very small imbalance (100 vs 101) - below FPMM threshold
    provideFPMMReserves(100e18, 101e18, true);
    setOracleRate(1e18, 1e18);

    vm.expectRevert(ILiquidityStrategy.LS_POOL_NOT_REBALANCEABLE.selector);
    vm.prank(rebalancer);
    strategy.rebalance(address(fpmm));
  }

  function test_rebalance_withLargeImbalance_shouldHandleCorrectly()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Large imbalance (100 vs 1000)
    provideFPMMReserves(100e18, 1000e18, true);
    setOracleRate(1e18, 1e18);

    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Expand, address(0), 0, address(0), 0);

    vm.prank(rebalancer);
    strategy.rebalance(address(fpmm));
  }

  function test_rebalance_whenRebalancedTwiceInSameTx_shouldRevert()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    provideFPMMReserves(100e18, 200e18, true);
    setOracleRate(1e18, 1e18);

    // First rebalance succeeds
    vm.prank(rebalancer);
    strategy.rebalance(address(fpmm));

    // Skew pool again
    provideFPMMReserves(100e18, 200e18, true);

    // Second rebalance in same tx should fail (transient storage hook flag still set)
    vm.expectRevert(abi.encodeWithSelector(ILiquidityStrategy.LS_CAN_ONLY_REBALANCE_ONCE.selector, address(fpmm)));
    vm.prank(rebalancer);
    strategy.rebalance(address(fpmm));
  }

  function test_rebalance_whenRebalancerHasNoApproval_shouldRevert()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    provideFPMMReserves(100e18, 200e18, true);
    setOracleRate(1e18, 1e18);

    address unapprovedRebalancer = makeAddr("UnapprovedRebalancer");
    MockERC20(debtToken).mint(unapprovedRebalancer, 1_000_000e18);
    MockERC20(collToken).mint(unapprovedRebalancer, 1_000_000e18);
    // Note: no approval given

    vm.prank(unapprovedRebalancer);
    vm.expectRevert(); // SafeERC20: transferFrom will fail
    strategy.rebalance(address(fpmm));
  }
}
