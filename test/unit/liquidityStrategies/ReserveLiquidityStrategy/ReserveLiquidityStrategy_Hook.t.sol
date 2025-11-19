// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
// solhint-disable max-line-length
pragma solidity ^0.8;

import { ReserveLiquidityStrategy_BaseTest } from "./ReserveLiquidityStrategy_BaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/libraries/LiquidityStrategyTypes.sol";

contract ReserveLiquidityStrategy_HookTest is ReserveLiquidityStrategy_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  /* ============================================================ */
  /* ====================== Hook Function ======================= */
  /* ============================================================ */

  function test_hook_whenValidExpansionCallback_shouldExecuteCorrectly() public fpmmToken0Debt(18, 18) addFpmm(0, 100) {
    uint256 amountOwedToPool = 100e18;
    uint256 amount0Out = 0;
    uint256 amount1Out = 100e18; // collateral out

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        amountOwedToPool: amountOwedToPool,
        incentiveBps: 100,
        dir: LQ.Direction.Expand,
        isToken0Debt: true,
        debtToken: debtToken,
        collToken: collToken
      })
    );

    // Full amount to pool, no incentive splitting
    // Order: collateral to reserve first, then debt to pool
    expectERC20Transfer(collToken, address(reserve), amount1Out);
    expectERC20Mint(debtToken, address(fpmm), amountOwedToPool);
    vm.prank(address(fpmm));
    strategy.onRebalance(address(strategy), amount0Out, amount1Out, hookData);
  }

  function test_hook_whenValidContractionCallback_shouldExecuteCorrectly()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    uint256 amountOwedToPool = 100e18; // collateral going into pool
    uint256 amount0Out = 100e18; // debt coming out of pool
    uint256 amount1Out = 0;

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        amountOwedToPool: amountOwedToPool,
        incentiveBps: 100,
        dir: LQ.Direction.Contract,
        isToken0Debt: true,
        debtToken: debtToken,
        collToken: collToken
      })
    );

    // For contraction:
    // - Full collateral amount goes to pool from reserve
    // - Debt comes OUT of pool and gets burned

    expectReserveTransfer(collToken, address(fpmm), amountOwedToPool);
    expectERC20Burn(debtToken, amount0Out);
    vm.prank(address(fpmm));
    strategy.onRebalance(address(strategy), amount0Out, amount1Out, hookData);
  }

  function test_hook_whenUntrustedPool_shouldRevert() public fpmmToken0Debt(18, 18) addFpmm(0, 100) {
    uint256 amountOwedToPool = 100e18;
    uint256 amount0Out = 0;
    uint256 amount1Out = 100e18;

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        amountOwedToPool: amountOwedToPool,
        incentiveBps: 100,
        dir: LQ.Direction.Expand,
        isToken0Debt: true,
        debtToken: debtToken,
        collToken: collToken
      })
    );

    // Call from untrusted pool address
    address untrustedPool = makeAddr("untrustedPool");
    vm.prank(untrustedPool);
    vm.expectRevert("LS_POOL_NOT_FOUND()");
    strategy.onRebalance(address(strategy), amount0Out, amount1Out, hookData);
  }

  function test_hook_whenInvalidSender_shouldRevert() public fpmmToken0Debt(18, 18) addFpmm(0, 100) {
    uint256 amountOwedToPool = 100e18;
    uint256 amount0Out = 0;
    uint256 amount1Out = 100e18;

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        amountOwedToPool: amountOwedToPool,
        incentiveBps: 100,
        dir: LQ.Direction.Expand,
        isToken0Debt: true,
        debtToken: debtToken,
        collToken: collToken
      })
    );

    vm.prank(address(fpmm));
    vm.expectRevert("LS_INVALID_SENDER()");
    strategy.onRebalance(owner, amount0Out, amount1Out, hookData); // Wrong sender (should be strategy)
  }

  function test_hook_whenReversedTokenOrder_shouldHandleCorrectly() public fpmmToken1Debt(18, 18) addFpmm(0, 100) {
    uint256 amountOwedToPool = 100e18;
    uint256 amount0Out = 100e18; // collateral out (token0 is collateral)
    uint256 amount1Out = 0;

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        amountOwedToPool: amountOwedToPool,
        incentiveBps: 100,
        dir: LQ.Direction.Expand,
        isToken0Debt: false, // token1 is debt
        debtToken: debtToken,
        collToken: collToken
      })
    );

    expectERC20Transfer(collToken, address(reserve), amount0Out);
    expectERC20Mint(debtToken, address(fpmm), amountOwedToPool);
    vm.prank(address(fpmm));
    strategy.onRebalance(address(strategy), amount0Out, amount1Out, hookData);
  }

  /* ============================================================ */
  /* ================= Expansion Callback Tests ================ */
  /* ============================================================ */

  function test_hook_expansionCallback_whenToken0IsDebt_shouldMintAndTransferCorrectly()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    uint256 amountOwedToPool = 200e18;
    uint256 amount0Out = 0;
    uint256 amount1Out = 200e18; // collateral out

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        amountOwedToPool: amountOwedToPool,
        incentiveBps: 100,
        dir: LQ.Direction.Expand,
        isToken0Debt: true,
        debtToken: debtToken,
        collToken: collToken
      })
    );

    expectERC20Transfer(collToken, address(reserve), amount1Out);
    expectERC20Mint(debtToken, address(fpmm), amountOwedToPool);
    vm.prank(address(fpmm));
    strategy.onRebalance(address(strategy), amount0Out, amount1Out, hookData);
  }

  function test_hook_expansionCallback_whenToken1IsDebt_shouldMintAndTransferCorrectly()
    public
    fpmmToken1Debt(18, 18)
    addFpmm(0, 100)
  {
    uint256 amountOwedToPool = 150e18;
    uint256 amount0Out = 150e18; // collateral out
    uint256 amount1Out = 0;

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        amountOwedToPool: amountOwedToPool,
        incentiveBps: 100,
        dir: LQ.Direction.Expand,
        isToken0Debt: false, // token1 is debt
        debtToken: debtToken,
        collToken: collToken
      })
    );

    expectERC20Transfer(collToken, address(reserve), amount0Out);
    expectERC20Mint(debtToken, address(fpmm), amountOwedToPool);
    vm.prank(address(fpmm));
    strategy.onRebalance(address(strategy), amount0Out, amount1Out, hookData);
  }

  /* ============================================================ */
  /* ================ Contraction Callback Tests =============== */
  /* ============================================================ */

  function test_hook_contractionCallback_whenToken0IsDebt_shouldBurnAndTransferCorrectly()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    uint256 amountOwedToPool = 90e18; // collateral going into pool
    uint256 amount0Out = 90e18; // debt out
    uint256 amount1Out = 0;

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        amountOwedToPool: amountOwedToPool,
        incentiveBps: 100,
        dir: LQ.Direction.Contract,
        isToken0Debt: true,
        debtToken: debtToken,
        collToken: collToken
      })
    );

    expectReserveTransfer(collToken, address(fpmm), amountOwedToPool);
    expectERC20Burn(debtToken, amount0Out);
    vm.prank(address(fpmm));
    strategy.onRebalance(address(strategy), amount0Out, amount1Out, hookData);
  }

  function test_hook_contractionCallback_whenToken1IsDebt_shouldBurnAndTransferCorrectly()
    public
    fpmmToken1Debt(18, 18)
    addFpmm(0, 100)
  {
    uint256 amountOwedToPool = 75e18; // collateral going into pool
    uint256 amount0Out = 0;
    uint256 amount1Out = 75e18; // debt out

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        amountOwedToPool: amountOwedToPool,
        incentiveBps: 100,
        dir: LQ.Direction.Contract,
        isToken0Debt: false, // token1 is debt
        debtToken: debtToken,
        collToken: collToken
      })
    );

    expectReserveTransfer(collToken, address(fpmm), amountOwedToPool);
    expectERC20Burn(debtToken, amount1Out);
    vm.prank(address(fpmm));
    strategy.onRebalance(address(strategy), amount0Out, amount1Out, hookData);
  }

  function test_hook_contractionCallback_whenReserveTransferFails_shouldRevert()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    uint256 amountOwedToPool = 60e18; // collateral going into pool
    uint256 amount0Out = 60e18; // debt out
    uint256 amount1Out = 0;

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        amountOwedToPool: amountOwedToPool,
        incentiveBps: 100,
        dir: LQ.Direction.Contract,
        isToken0Debt: true,
        debtToken: debtToken,
        collToken: collToken
      })
    );

    // Mock reserve transfer to pool to fail
    expectReserveTransferFailure(collToken, address(fpmm), amountOwedToPool);

    vm.prank(address(fpmm));
    vm.expectRevert("RLS_COLLATERAL_TO_POOL_FAILED()");
    strategy.onRebalance(address(strategy), amount0Out, amount1Out, hookData);
  }

  /* ============================================================ */
  /* ==================== Edge Case Tests ====================== */
  /* ============================================================ */

  function test_hook_withZeroIncentive_shouldExecuteCorrectly() public fpmmToken0Debt(18, 18) addFpmm(0, 0) {
    uint256 amountOwedToPool = 100e18;
    uint256 amount0Out = 0;
    uint256 amount1Out = 100e18; // collateral out

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        amountOwedToPool: amountOwedToPool,
        incentiveBps: 0,
        dir: LQ.Direction.Expand,
        isToken0Debt: true,
        debtToken: debtToken,
        collToken: collToken
      })
    );

    // Full amount to pool
    expectERC20Transfer(collToken, address(reserve), amount1Out);
    expectERC20Mint(debtToken, address(fpmm), amountOwedToPool);
    vm.prank(address(fpmm));
    strategy.onRebalance(address(strategy), amount0Out, amount1Out, hookData);
  }

  function test_hook_withMaxIncentive_shouldExecuteCorrectly() public fpmmToken0Debt(18, 18) addFpmm(0, 100) {
    uint256 amountOwedToPool = 1e18; // collateral going into pool
    uint256 amount0Out = 1e18; // debt out
    uint256 amount1Out = 0;

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        amountOwedToPool: amountOwedToPool,
        incentiveBps: 10000, // 100% = 10000 bps
        dir: LQ.Direction.Contract,
        isToken0Debt: true,
        debtToken: debtToken,
        collToken: collToken
      })
    );

    // Full amount goes to pool
    expectReserveTransfer(collToken, address(fpmm), amountOwedToPool);
    expectERC20Burn(debtToken, amount0Out);
    vm.prank(address(fpmm));
    strategy.onRebalance(address(strategy), amount0Out, amount1Out, hookData);
  }
}
