// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { ReserveLiquidityStrategy_BaseTest } from "./ReserveLiquidityStrategy_BaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/libraries/LiquidityStrategyTypes.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { MockERC20 } from "../../../utils/mocks/MockERC20.sol";

contract ReserveLiquidityStrategy_RebalanceTest is ReserveLiquidityStrategy_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  /* ============================================================ */
  /* ================= Rebalance Function Tests ================= */
  /* ============================================================ */

  function test_rebalance_whenPoolPriceAboveOracle_shouldExpandSuccessfully()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    // Setup: Pool has 100 debt and 200 collateral (excess collateral)
    provideFPMMReserves(100e18, 200e18, true);
    // Oracle price is 1:1, pool price is 2:1 (pool price above oracle)
    setOracleRate(1e18, 1e18);

    // Mint collateral to reserve
    MockERC20(collToken).mint(address(reserve), 1000e18);

    // Rebalance should expand (remove excess collateral)
    // Expansion: debt flows IN, collateral flows OUT
    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Expand, address(0), 0, address(0), 0);

    strategy.rebalance(address(fpmm));
  }

  function test_rebalance_whenPoolPriceBelowOracle_shouldContractSuccessfully()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    // Setup: Pool has 200 debt and 100 collateral (excess debt)
    provideFPMMReserves(200e18, 100e18, true);
    // Oracle price is 1:1, pool price is 0.5:1 (pool price below oracle)
    setOracleRate(1e18, 1e18);

    // Mint collateral to reserve for contraction
    MockERC20(collToken).mint(address(reserve), 1000e18);

    // Rebalance should contract (add collateral to pool)
    // Contraction: collateral flows IN, debt flows OUT
    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Contract, address(0), 0, address(0), 0);

    strategy.rebalance(address(fpmm));
  }

  function test_rebalance_whenPoolNotAdded_shouldRevert() public fpmmToken0Debt(18, 18) {
    // Don't add pool to strategy

    // Setup pool state
    provideFPMMReserves(100e18, 200e18, true);
    setOracleRate(1e18, 1e18);

    vm.expectRevert("LS_POOL_NOT_FOUND()");
    strategy.rebalance(address(fpmm));
  }

  function test_rebalance_whenPoolPriceEqualsOracle_shouldNotRebalance() public fpmmToken0Debt(18, 18) addFpmm(0, 100) {
    // Setup: Pool has balanced reserves at 1:1
    provideFPMMReserves(100e18, 100e18, true);
    // Oracle price is also 1:1 (pool price equals oracle)
    setOracleRate(1e18, 1e18);

    // Mint collateral to reserve
    MockERC20(collToken).mint(address(reserve), 1000e18);

    // Rebalance should not execute any action (no events should be emitted, should revert)
    vm.expectRevert("OneOutputAmountRequired()");
    strategy.rebalance(address(fpmm));
  }

  function test_rebalance_withZeroIncentive_shouldSucceed() public fpmmToken0Debt(18, 18) addFpmm(0, 0) {
    // Setup: Pool has excess collateral
    provideFPMMReserves(100e18, 200e18, true);
    setOracleRate(1e18, 1e18);

    // Mint collateral to reserve
    MockERC20(collToken).mint(address(reserve), 1000e18);

    // Should expand even with zero incentive
    // Expansion: debt flows IN, collateral flows OUT
    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Expand, address(0), 0, address(0), 0);

    strategy.rebalance(address(fpmm));
  }

  function test_rebalance_withMaxIncentive_shouldSucceed() public fpmmToken0Debt(18, 18) addFpmm(0, 100) {
    // Setup: Pool has excess debt
    provideFPMMReserves(200e18, 100e18, true);
    setOracleRate(1e18, 1e18);

    // Mint collateral to reserve
    MockERC20(collToken).mint(address(reserve), 1000e18);

    // Should contract with incentive
    // Contraction: collateral flows IN, debt flows OUT
    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Contract, address(0), 0, address(0), 0);

    strategy.rebalance(address(fpmm));
  }

  /* ============================================================ */
  /* =================== Token Flow Tests ====================== */
  /* ============================================================ */

  function test_rebalance_expansion_shouldMintDebtAndTransferCollateralToReserve()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    // Setup: Pool has 100 debt and 200 collateral (excess collateral)
    provideFPMMReserves(100e18, 200e18, true);
    setOracleRate(1e18, 1e18);

    // Mint collateral to reserve
    MockERC20(collToken).mint(address(reserve), 1000e18);

    // Get balances before
    uint256 strategyDebtBefore = IERC20(debtToken).balanceOf(address(strategy));
    uint256 strategyCollBefore = IERC20(collToken).balanceOf(address(strategy));

    strategy.rebalance(address(fpmm));

    // Strategy should have more debt (minted as incentive) and less collateral (transferred to reserve)
    uint256 strategyDebtAfter = IERC20(debtToken).balanceOf(address(strategy));
    uint256 strategyCollAfter = IERC20(collToken).balanceOf(address(strategy));

    // In expansion, debt is minted (strategy gets incentive), collateral flows from pool to reserve
    assertGe(strategyDebtAfter, strategyDebtBefore, "Strategy should receive debt incentive");
    assertLe(strategyCollAfter, strategyCollBefore, "Strategy should transfer collateral");
  }

  function test_rebalance_contraction_shouldBurnDebtAndTransferCollateralFromReserve()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    // Setup: Pool has 200 debt and 100 collateral (excess debt)
    provideFPMMReserves(200e18, 100e18, true);
    setOracleRate(1e18, 1e18);

    // Mint collateral to reserve
    MockERC20(collToken).mint(address(reserve), 1000e18);

    // Get balances before
    uint256 strategyDebtBefore = IERC20(debtToken).balanceOf(address(strategy));
    uint256 strategyCollBefore = IERC20(collToken).balanceOf(address(strategy));

    strategy.rebalance(address(fpmm));

    // Strategy should have less debt (burned) and more collateral (from reserve as incentive)
    uint256 strategyDebtAfter = IERC20(debtToken).balanceOf(address(strategy));
    uint256 strategyCollAfter = IERC20(collToken).balanceOf(address(strategy));

    // In contraction, debt is burned, collateral flows from reserve (strategy gets incentive)
    assertLe(strategyDebtAfter, strategyDebtBefore, "Strategy debt should decrease (burned)");
    assertGe(strategyCollAfter, strategyCollBefore, "Strategy should receive collateral incentive");
  }

  /* ============================================================ */
  /* =============== Reversed Token Order Tests ================ */
  /* ============================================================ */

  function test_rebalance_whenToken1IsDebt_shouldExpandCorrectly() public fpmmToken1Debt(18, 18) addFpmm(0, 100) {
    // Setup: Pool has 200 collateral (token0) and 100 debt (token1) - excess collateral
    provideFPMMReserves(200e18, 100e18, false);
    // Oracle price 1:1, pool has excess collateral
    setOracleRate(1e18, 1e18);

    // Mint collateral to reserve
    MockERC20(collToken).mint(address(reserve), 1000e18);

    // Should expand (remove excess collateral)
    // Expansion: debt flows IN, collateral flows OUT
    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Expand, address(0), 0, address(0), 0);

    strategy.rebalance(address(fpmm));
  }

  function test_rebalance_whenToken1IsDebt_shouldContractCorrectly() public fpmmToken1Debt(18, 18) addFpmm(0, 100) {
    // Setup: Pool has 100 collateral (token0) and 200 debt (token1) - excess debt
    provideFPMMReserves(100e18, 200e18, false);
    // Oracle price 1:1, pool has excess debt
    setOracleRate(1e18, 1e18);

    // Mint collateral to reserve
    MockERC20(collToken).mint(address(reserve), 1000e18);

    // Should contract (add collateral to pool)
    // Contraction: collateral flows IN, debt flows OUT
    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Contract, address(0), 0, address(0), 0);

    strategy.rebalance(address(fpmm));
  }

  /* ============================================================ */
  /* =============== Different Oracle Prices =================== */
  /* ============================================================ */

  function test_rebalance_withHighOraclePrice_shouldContractCorrectly() public fpmmToken0Debt(18, 18) addFpmm(0, 100) {
    // Setup: Pool has 100 debt and 100 collateral
    provideFPMMReserves(100e18, 100e18, true);
    // Oracle price is 2:1 (2 collateral per 1 debt), pool needs more collateral
    setOracleRate(2e18, 1e18);

    // Mint collateral to reserve
    MockERC20(collToken).mint(address(reserve), 1000e18);

    // Should contract (add collateral)
    // Contraction: collateral flows IN, debt flows OUT
    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Contract, address(0), 0, address(0), 0);

    strategy.rebalance(address(fpmm));
  }

  function test_rebalance_withLowOraclePrice_shouldExpandCorrectly() public fpmmToken0Debt(18, 18) addFpmm(0, 100) {
    // Setup: Pool has 100 debt and 100 collateral
    provideFPMMReserves(100e18, 100e18, true);
    // Oracle price is 1:2 (0.5 collateral per 1 debt), pool has excess collateral
    setOracleRate(1e18, 2e18);

    // Mint collateral to reserve
    MockERC20(collToken).mint(address(reserve), 1000e18);

    // Should expand (remove excess collateral)
    // Expansion: debt flows IN, collateral flows OUT
    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Expand, address(0), 0, address(0), 0);

    strategy.rebalance(address(fpmm));
  }

  /* ============================================================ */
  /* =================== Edge Cases =========================== */
  /* ============================================================ */

  function test_rebalance_withVerySmallImbalance_shouldRevertDueToThreshold()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    // Setup: Pool has very small imbalance (100 vs 101) - below FPMM threshold
    provideFPMMReserves(100e18, 101e18, true);
    setOracleRate(1e18, 1e18);

    // Mint collateral to reserve
    MockERC20(collToken).mint(address(reserve), 1000e18);

    // Should revert due to FPMM threshold (price difference too small)
    vm.expectRevert("PriceDifferenceTooSmall()");
    strategy.rebalance(address(fpmm));
  }

  function test_rebalance_withLargeImbalance_shouldHandleCorrectly() public fpmmToken0Debt(18, 18) addFpmm(0, 100) {
    // Setup: Pool has large imbalance (100 vs 1000)
    provideFPMMReserves(100e18, 1000e18, true);
    setOracleRate(1e18, 1e18);

    // Mint collateral to reserve
    MockERC20(collToken).mint(address(reserve), 10000e18);

    // Should expand to remove excess collateral
    // Expansion: debt flows IN, collateral flows OUT
    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Expand, address(0), 0, address(0), 0);

    strategy.rebalance(address(fpmm));
  }
}
