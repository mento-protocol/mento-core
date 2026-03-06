// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
// solhint-disable max-line-length
pragma solidity ^0.8;

import { OpenLiquidityStrategy_BaseTest } from "./OpenLiquidityStrategy_BaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/libraries/LiquidityStrategyTypes.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";

contract OpenLiquidityStrategy_HookTest is OpenLiquidityStrategy_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  /* ============================================================ */
  /* ====================== Hook Function ======================= */
  /* ============================================================ */

  function test_hook_whenValidExpansionCallback_shouldTransferToAndFromRebalancer()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 0.005e18, 0.005e18, 0.005e18, 0.005e18)
  {
    uint256 amountOwedToPool = 100e18;
    uint256 amount0Out = 0;
    uint256 amount1Out = 100e18; // collateral out from pool

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        amountOwedToPool: amountOwedToPool,
        dir: LQ.Direction.Expand,
        isToken0Debt: true,
        debtToken: debtToken,
        collToken: collToken
      })
    );

    uint256 protocolIncentive = (amount1Out * 0.005e18) / 1e18;
    uint256 toRebalancer = amount1Out - protocolIncentive;

    // Fund strategy (simulating pool sending tokens during callback)
    MockERC20(collToken).mint(address(strategy), amount1Out);

    uint256 feeRecipientCollBefore = IERC20(collToken).balanceOf(protocolFeeRecipient);
    uint256 rebalancerCollBefore = IERC20(collToken).balanceOf(rebalancer);
    uint256 rebalancerDebtBefore = IERC20(debtToken).balanceOf(rebalancer);
    uint256 fpmmDebtBefore = IERC20(debtToken).balanceOf(address(fpmm));

    strategy.setRebalancerForTesting(rebalancer);
    vm.prank(address(fpmm));
    strategy.onRebalance(address(strategy), amount0Out, amount1Out, hookData);

    // Protocol fee recipient gets collateral incentive
    assertEq(IERC20(collToken).balanceOf(protocolFeeRecipient) - feeRecipientCollBefore, protocolIncentive);
    // Rebalancer gets remaining collateral
    assertEq(IERC20(collToken).balanceOf(rebalancer) - rebalancerCollBefore, toRebalancer);
    // Rebalancer's debt decreases (pulled to pool)
    assertEq(rebalancerDebtBefore - IERC20(debtToken).balanceOf(rebalancer), amountOwedToPool);
    // Pool receives debt
    assertEq(IERC20(debtToken).balanceOf(address(fpmm)) - fpmmDebtBefore, amountOwedToPool);
  }

  function test_hook_whenValidContractionCallback_shouldTransferToAndFromRebalancer()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 0.005e18, 0.005e18, 0.005e18, 0.005e18)
  {
    uint256 amountOwedToPool = 100e18; // collateral going into pool
    uint256 amount0Out = 100e18; // debt coming out of pool
    uint256 amount1Out = 0;

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        amountOwedToPool: amountOwedToPool,
        dir: LQ.Direction.Contract,
        isToken0Debt: true,
        debtToken: debtToken,
        collToken: collToken
      })
    );

    uint256 protocolIncentive = (amount0Out * 0.005e18) / 1e18;
    uint256 toRebalancer = amount0Out - protocolIncentive;

    // Fund strategy (simulating pool sending tokens during callback)
    MockERC20(debtToken).mint(address(strategy), amount0Out);

    uint256 feeRecipientDebtBefore = IERC20(debtToken).balanceOf(protocolFeeRecipient);
    uint256 rebalancerDebtBefore = IERC20(debtToken).balanceOf(rebalancer);
    uint256 rebalancerCollBefore = IERC20(collToken).balanceOf(rebalancer);
    uint256 fpmmCollBefore = IERC20(collToken).balanceOf(address(fpmm));

    strategy.setRebalancerForTesting(rebalancer);
    vm.prank(address(fpmm));
    strategy.onRebalance(address(strategy), amount0Out, amount1Out, hookData);

    // Protocol fee recipient gets debt incentive
    assertEq(IERC20(debtToken).balanceOf(protocolFeeRecipient) - feeRecipientDebtBefore, protocolIncentive);
    // Rebalancer gets remaining debt
    assertEq(IERC20(debtToken).balanceOf(rebalancer) - rebalancerDebtBefore, toRebalancer);
    // Rebalancer's collateral decreases (pulled to pool)
    assertEq(rebalancerCollBefore - IERC20(collToken).balanceOf(rebalancer), amountOwedToPool);
    // Pool receives collateral
    assertEq(IERC20(collToken).balanceOf(address(fpmm)) - fpmmCollBefore, amountOwedToPool);
  }

  function test_hook_whenUntrustedPool_shouldRevert()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 0.005e18, 0.005e18, 0.005e18, 0.005e18)
  {
    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        amountOwedToPool: 100e18,
        dir: LQ.Direction.Expand,
        isToken0Debt: true,
        debtToken: debtToken,
        collToken: collToken
      })
    );

    address untrustedPool = makeAddr("untrustedPool");
    vm.prank(untrustedPool);
    vm.expectRevert("LS_POOL_NOT_FOUND()");
    strategy.onRebalance(address(strategy), 0, 100e18, hookData);
  }

  function test_hook_whenInvalidSender_shouldRevert()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 0.005e18, 0.005e18, 0.005e18, 0.005e18)
  {
    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        amountOwedToPool: 100e18,
        dir: LQ.Direction.Expand,
        isToken0Debt: true,
        debtToken: debtToken,
        collToken: collToken
      })
    );

    vm.prank(address(fpmm));
    vm.expectRevert("LS_INVALID_SENDER()");
    strategy.onRebalance(owner, 0, 100e18, hookData); // Wrong sender
  }

  /* ============================================================ */
  /* ================= Expansion Callback Tests ================ */
  /* ============================================================ */

  function test_hook_expansionCallback_whenToken1IsDebt_shouldTransferCorrectly()
    public
    fpmmToken1Debt(18, 18)
    addFpmm(0, 0.005e18, 0.005e18, 0.005e18, 0.005e18)
  {
    uint256 amountOwedToPool = 150e18;
    uint256 amount0Out = 150e18; // collateral out (token0 is collateral)
    uint256 amount1Out = 0;

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        amountOwedToPool: amountOwedToPool,
        dir: LQ.Direction.Expand,
        isToken0Debt: false,
        debtToken: debtToken,
        collToken: collToken
      })
    );

    uint256 protocolIncentive = (amount0Out * 0.005e18) / 1e18;
    uint256 toRebalancer = amount0Out - protocolIncentive;

    MockERC20(collToken).mint(address(strategy), amount0Out);

    uint256 feeRecipientCollBefore = IERC20(collToken).balanceOf(protocolFeeRecipient);
    uint256 rebalancerCollBefore = IERC20(collToken).balanceOf(rebalancer);
    uint256 rebalancerDebtBefore = IERC20(debtToken).balanceOf(rebalancer);
    uint256 fpmmDebtBefore = IERC20(debtToken).balanceOf(address(fpmm));

    strategy.setRebalancerForTesting(rebalancer);
    vm.prank(address(fpmm));
    strategy.onRebalance(address(strategy), amount0Out, amount1Out, hookData);

    assertEq(IERC20(collToken).balanceOf(protocolFeeRecipient) - feeRecipientCollBefore, protocolIncentive);
    assertEq(IERC20(collToken).balanceOf(rebalancer) - rebalancerCollBefore, toRebalancer);
    assertEq(rebalancerDebtBefore - IERC20(debtToken).balanceOf(rebalancer), amountOwedToPool);
    assertEq(IERC20(debtToken).balanceOf(address(fpmm)) - fpmmDebtBefore, amountOwedToPool);
  }

  /* ============================================================ */
  /* ================ Contraction Callback Tests =============== */
  /* ============================================================ */

  function test_hook_contractionCallback_whenToken1IsDebt_shouldTransferCorrectly()
    public
    fpmmToken1Debt(18, 18)
    addFpmm(0, 0.005e18, 0.005e18, 0.005e18, 0.005e18)
  {
    uint256 amountOwedToPool = 75e18; // collateral going into pool
    uint256 amount0Out = 0;
    uint256 amount1Out = 75e18; // debt out (token1 is debt)

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        amountOwedToPool: amountOwedToPool,
        dir: LQ.Direction.Contract,
        isToken0Debt: false,
        debtToken: debtToken,
        collToken: collToken
      })
    );

    uint256 protocolIncentive = (amount1Out * 0.005e18) / 1e18;
    uint256 toRebalancer = amount1Out - protocolIncentive;

    MockERC20(debtToken).mint(address(strategy), amount1Out);

    uint256 feeRecipientDebtBefore = IERC20(debtToken).balanceOf(protocolFeeRecipient);
    uint256 rebalancerDebtBefore = IERC20(debtToken).balanceOf(rebalancer);
    uint256 rebalancerCollBefore = IERC20(collToken).balanceOf(rebalancer);
    uint256 fpmmCollBefore = IERC20(collToken).balanceOf(address(fpmm));

    strategy.setRebalancerForTesting(rebalancer);
    vm.prank(address(fpmm));
    strategy.onRebalance(address(strategy), amount0Out, amount1Out, hookData);

    assertEq(IERC20(debtToken).balanceOf(protocolFeeRecipient) - feeRecipientDebtBefore, protocolIncentive);
    assertEq(IERC20(debtToken).balanceOf(rebalancer) - rebalancerDebtBefore, toRebalancer);
    assertEq(rebalancerCollBefore - IERC20(collToken).balanceOf(rebalancer), amountOwedToPool);
    assertEq(IERC20(collToken).balanceOf(address(fpmm)) - fpmmCollBefore, amountOwedToPool);
  }

  /* ============================================================ */
  /* ==================== Edge Case Tests ====================== */
  /* ============================================================ */

  function test_hook_withZeroIncentive_shouldTransferAllToRebalancer()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 0, 0, 0, 0)
  {
    uint256 amountOwedToPool = 100e18;
    uint256 amount0Out = 0;
    uint256 amount1Out = 100e18; // collateral out

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        amountOwedToPool: amountOwedToPool,
        dir: LQ.Direction.Expand,
        isToken0Debt: true,
        debtToken: debtToken,
        collToken: collToken
      })
    );

    MockERC20(collToken).mint(address(strategy), amount1Out);

    uint256 feeRecipientCollBefore = IERC20(collToken).balanceOf(protocolFeeRecipient);
    uint256 rebalancerCollBefore = IERC20(collToken).balanceOf(rebalancer);
    uint256 rebalancerDebtBefore = IERC20(debtToken).balanceOf(rebalancer);
    uint256 fpmmDebtBefore = IERC20(debtToken).balanceOf(address(fpmm));

    strategy.setRebalancerForTesting(rebalancer);
    vm.prank(address(fpmm));
    strategy.onRebalance(address(strategy), amount0Out, amount1Out, hookData);

    // No protocol incentive
    assertEq(IERC20(collToken).balanceOf(protocolFeeRecipient), feeRecipientCollBefore);
    // Full amount to rebalancer
    assertEq(IERC20(collToken).balanceOf(rebalancer) - rebalancerCollBefore, amount1Out);
    // Debt pulled from rebalancer to pool
    assertEq(rebalancerDebtBefore - IERC20(debtToken).balanceOf(rebalancer), amountOwedToPool);
    assertEq(IERC20(debtToken).balanceOf(address(fpmm)) - fpmmDebtBefore, amountOwedToPool);
  }

  function test_hook_whenRebalancerInsufficientApproval_shouldRevert()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 0.005e18, 0.005e18, 0.005e18, 0.005e18)
  {
    uint256 amountOwedToPool = 100e18;
    uint256 amount0Out = 0;
    uint256 amount1Out = 100e18;

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        amountOwedToPool: amountOwedToPool,
        dir: LQ.Direction.Expand,
        isToken0Debt: true,
        debtToken: debtToken,
        collToken: collToken
      })
    );

    // Revoke rebalancer's debt token approval
    vm.prank(rebalancer);
    MockERC20(debtToken).approve(address(strategy), 0);

    MockERC20(collToken).mint(address(strategy), amount1Out);
    strategy.setRebalancerForTesting(rebalancer);
    vm.prank(address(fpmm));
    vm.expectRevert(); // SafeERC20: transferFrom will fail
    strategy.onRebalance(address(strategy), amount0Out, amount1Out, hookData);
  }
}
