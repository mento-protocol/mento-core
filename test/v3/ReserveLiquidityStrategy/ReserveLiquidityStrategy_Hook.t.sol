// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
// solhint-disable max-line-length
pragma solidity ^0.8;

import { ReserveLiquidityStrategy_BaseTest } from "./ReserveLiquidityStrategy_BaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/v3/libraries/LiquidityStrategyTypes.sol";
import { IERC20MintableBurnable } from "contracts/common/IERC20MintableBurnable.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";

contract ReserveLiquidityStrategy_HookTest is ReserveLiquidityStrategy_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  /* ============================================================ */
  /* ====================== Hook Function ======================= */
  /* ============================================================ */

  function test_hook_whenValidExpansionCallback_shouldExecuteCorrectly() public fpmmToken0Debt(18, 18) addFpmm(0, 100) {
    uint256 inputAmount = 100e18;
    uint256 incentiveAmount = 1e18; // 1% = 100 bps
    uint256 amount0Out = 0;
    uint256 amount1Out = 99e18; // collateral out

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        inputAmount: inputAmount,
        incentiveBps: 100,
        dir: LQ.Direction.Expand,
        isToken0Debt: true,
        debtToken: debtToken,
        collateralToken: collToken
      })
    );

    expectERC20Mint(debtToken, address(fpmm), inputAmount - incentiveAmount);
    expectERC20Mint(debtToken, address(strategy), incentiveAmount);
    expectERC20Transfer(collToken, address(reserve), amount1Out);
    vm.prank(address(fpmm));
    strategy.hook(address(strategy), amount0Out, amount1Out, hookData);
  }

  function test_hook_whenValidContractionCallback_shouldExecuteCorrectly()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    uint256 inputAmount = 100e18; // collateral going into pool
    uint256 incentiveAmount = 1e18; // 1% = 100 bps
    uint256 amountToPool = inputAmount - incentiveAmount; // 99e18
    uint256 amount0Out = 99e18; // debt coming out of pool
    uint256 amount1Out = 0;

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        inputAmount: inputAmount,
        incentiveBps: 100,
        dir: LQ.Direction.Contract,
        isToken0Debt: true,
        debtToken: debtToken,
        collateralToken: collToken
      })
    );

    // For contraction:
    // - Collateral goes INTO pool from reserve (via transferExchangeCollateralAsset)
    // - Debt comes OUT of pool and gets burned (Transfer to address(0))

    // Expect reserve transfers of collateral
    expectReserveTransfer(collToken, address(fpmm), amountToPool);
    expectReserveTransfer(collToken, address(strategy), incentiveAmount);
    expectERC20Burn(debtToken, amount0Out);
    vm.prank(address(fpmm));
    strategy.hook(address(strategy), amount0Out, amount1Out, hookData);
  }

  function test_hook_whenUntrustedPool_shouldRevert() public fpmmToken0Debt(18, 18) addFpmm(0, 100) {
    uint256 inputAmount = 100e18;
    uint256 amount0Out = 0;
    uint256 amount1Out = 99e18;

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        inputAmount: inputAmount,
        incentiveBps: 100,
        dir: LQ.Direction.Expand,
        isToken0Debt: true,
        debtToken: debtToken,
        collateralToken: collToken
      })
    );

    // Call from untrusted pool address
    address untrustedPool = makeAddr("untrustedPool");
    vm.prank(untrustedPool);
    vm.expectRevert("LS_POOL_NOT_FOUND()");
    strategy.hook(address(strategy), amount0Out, amount1Out, hookData);
  }

  function test_hook_whenInvalidSender_shouldRevert() public fpmmToken0Debt(18, 18) addFpmm(0, 100) {
    uint256 inputAmount = 100e18;
    uint256 amount0Out = 0;
    uint256 amount1Out = 99e18;

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        inputAmount: inputAmount,
        incentiveBps: 100,
        dir: LQ.Direction.Expand,
        isToken0Debt: true,
        debtToken: debtToken,
        collateralToken: collToken
      })
    );

    vm.prank(address(fpmm));
    vm.expectRevert("LS_INVALID_SENDER()");
    strategy.hook(owner, amount0Out, amount1Out, hookData); // Wrong sender (should be strategy)
  }

  function test_hook_whenReversedTokenOrder_shouldHandleCorrectly() public fpmmToken1Debt(18, 18) addFpmm(0, 100) {
    uint256 inputAmount = 100e18;
    uint256 incentiveAmount = 1e18; // 1% = 100 bps
    uint256 amount0Out = 99e18; // collateral out (token0 is collateral)
    uint256 amount1Out = 0;

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        inputAmount: inputAmount,
        incentiveBps: 100,
        dir: LQ.Direction.Expand,
        isToken0Debt: false, // token1 is debt
        debtToken: debtToken,
        collateralToken: collToken
      })
    );

    expectERC20Mint(debtToken, address(fpmm), inputAmount - incentiveAmount);
    expectERC20Mint(debtToken, address(strategy), incentiveAmount);
    expectERC20Transfer(collToken, address(reserve), amount0Out);
    vm.prank(address(fpmm));
    strategy.hook(address(strategy), amount0Out, amount1Out, hookData);
  }

  // /* ============================================================ */
  // /* ================= Expansion Callback Tests ================ */
  // /* ============================================================ */

  function test_hook_expansionCallback_whenToken0IsDebt_shouldMintAndTransferCorrectly()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    uint256 inputAmount = 200e18;
    uint256 incentiveAmount = 2e18; // 1% = 100 bps
    uint256 amount0Out = 0;
    uint256 amount1Out = 198e18; // collateral out

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        inputAmount: inputAmount,
        incentiveBps: 100,
        dir: LQ.Direction.Expand,
        isToken0Debt: true,
        debtToken: debtToken,
        collateralToken: collToken
      })
    );

    expectERC20Mint(debtToken, address(fpmm), inputAmount - incentiveAmount);
    expectERC20Mint(debtToken, address(strategy), incentiveAmount);
    expectERC20Transfer(collToken, address(reserve), amount1Out);
    vm.prank(address(fpmm));
    strategy.hook(address(strategy), amount0Out, amount1Out, hookData);
  }

  function test_hook_expansionCallback_whenToken1IsDebt_shouldMintAndTransferCorrectly()
    public
    fpmmToken1Debt(18, 18)
    addFpmm(0, 100)
  {
    uint256 inputAmount = 150e18;
    uint256 incentiveAmount = 1.5e18; // 1% = 100 bps
    uint256 amount0Out = 148.5e18; // collateral out
    uint256 amount1Out = 0;

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        inputAmount: inputAmount,
        incentiveBps: 100,
        dir: LQ.Direction.Expand,
        isToken0Debt: false, // token1 is debt
        debtToken: debtToken,
        collateralToken: collToken
      })
    );

    expectERC20Mint(debtToken, address(fpmm), inputAmount - incentiveAmount);
    expectERC20Mint(debtToken, address(strategy), incentiveAmount);
    expectERC20Transfer(collToken, address(reserve), amount0Out);
    vm.prank(address(fpmm));
    strategy.hook(address(strategy), amount0Out, amount1Out, hookData);
  }

  // /* ============================================================ */
  // /* ================ Contraction Callback Tests =============== */
  // /* ============================================================ */

  function test_hook_contractionCallback_whenToken0IsDebt_shouldBurnAndTransferCorrectly()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    uint256 inputAmount = 90e18; // collateral going into pool
    uint256 incentiveAmount = 0.9e18; // 1% = 100 bps
    uint256 amountToPool = inputAmount - incentiveAmount; // 89.1e18
    uint256 amount0Out = 89.1e18; // debt out
    uint256 amount1Out = 0;

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        inputAmount: inputAmount,
        incentiveBps: 100,
        dir: LQ.Direction.Contract,
        isToken0Debt: true,
        debtToken: debtToken,
        collateralToken: collToken
      })
    );

    expectReserveTransfer(collToken, address(fpmm), amountToPool);
    expectReserveTransfer(collToken, address(strategy), incentiveAmount);
    expectERC20Burn(debtToken, amount0Out);
    vm.prank(address(fpmm));
    strategy.hook(address(strategy), amount0Out, amount1Out, hookData);
  }

  function test_hook_contractionCallback_whenToken1IsDebt_shouldBurnAndTransferCorrectly()
    public
    fpmmToken1Debt(18, 18)
    addFpmm(0, 100)
  {
    uint256 inputAmount = 75e18; // collateral going into pool
    uint256 incentiveAmount = 0.75e18; // 1% = 100 bps
    uint256 amountToPool = inputAmount - incentiveAmount; // 74.25e18
    uint256 amount0Out = 0;
    uint256 amount1Out = 74.25e18; // debt out

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        inputAmount: inputAmount,
        incentiveBps: 100,
        dir: LQ.Direction.Contract,
        isToken0Debt: false, // token1 is debt
        debtToken: debtToken,
        collateralToken: collToken
      })
    );

    expectReserveTransfer(collToken, address(fpmm), amountToPool);
    expectReserveTransfer(collToken, address(strategy), incentiveAmount);
    expectERC20Burn(debtToken, amount1Out);
    vm.prank(address(fpmm));
    strategy.hook(address(strategy), amount0Out, amount1Out, hookData);
  }

  function test_hook_contractionCallback_whenReserveTransferFails_shouldRevert()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    uint256 inputAmount = 60e18; // collateral going into pool
    uint256 incentiveAmount = 0.6e18; // 1% = 100 bps
    uint256 amountToPool = inputAmount - incentiveAmount; // 59.4e18
    uint256 amount0Out = 59.4e18; // debt out
    uint256 amount1Out = 0;

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        inputAmount: inputAmount,
        incentiveBps: 100,
        dir: LQ.Direction.Contract,
        isToken0Debt: true,
        debtToken: debtToken,
        collateralToken: collToken
      })
    );

    // Mock reserve transfer to pool to fail
    expectReserveTransferFailure(collToken, address(fpmm), amountToPool);

    vm.prank(address(fpmm));
    vm.expectRevert("RLS_COLLATERAL_TO_POOL_FAILED()");
    strategy.hook(address(strategy), amount0Out, amount1Out, hookData);
  }

  function test_hook_contractionCallback_whenIncentiveTransferFails_shouldRevert()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    uint256 inputAmount = 50e18; // collateral going into pool
    uint256 incentiveAmount = 0.5e18; // 1% = 100 bps
    uint256 amountToPool = inputAmount - incentiveAmount; // 49.5e18
    uint256 amount0Out = 49.5e18; // debt out
    uint256 amount1Out = 0;

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        inputAmount: inputAmount,
        incentiveBps: 100,
        dir: LQ.Direction.Contract,
        isToken0Debt: true,
        debtToken: debtToken,
        collateralToken: collToken
      })
    );

    // Mock first transfer (collateral to pool) to succeed
    expectReserveTransfer(collToken, address(fpmm), amountToPool);
    // Mock second transfer (incentive) to fail
    expectReserveTransferFailure(collToken, address(strategy), incentiveAmount);

    vm.prank(address(fpmm));
    vm.expectRevert("RLS_INCENTIVE_TRANSFER_FAILED()");
    strategy.hook(address(strategy), amount0Out, amount1Out, hookData);
  }

  // /* ============================================================ */
  // /* ==================== Edge Case Tests ====================== */
  // /* ============================================================ */

  function test_hook_withZeroIncentive_shouldExecuteCorrectly() public fpmmToken0Debt(18, 18) addFpmm(0, 0) {
    uint256 inputAmount = 100e18;
    uint256 amount0Out = 0;
    uint256 amount1Out = 100e18; // collateral out

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        inputAmount: inputAmount,
        incentiveBps: 0,
        dir: LQ.Direction.Expand,
        isToken0Debt: true,
        debtToken: debtToken,
        collateralToken: collToken
      })
    );

    // Should mint full amount to pool, nothing to strategy
    expectERC20Mint(debtToken, address(fpmm), inputAmount);
    // Note: With zero incentive (0 bps), no mint to strategy
    expectERC20Transfer(collToken, address(reserve), amount1Out);
    vm.prank(address(fpmm));
    strategy.hook(address(strategy), amount0Out, amount1Out, hookData);
  }

  function test_hook_withMaxIncentive_shouldExecuteCorrectly() public fpmmToken0Debt(18, 18) addFpmm(0, 100) {
    uint256 inputAmount = 1e18; // collateral going into pool
    uint256 incentiveAmount = 1e18; // 100% of input as incentive
    uint256 amountToPool = 0; // Nothing to pool, all goes to incentive
    uint256 amount0Out = 0; // debt out (matches amountToPool)
    uint256 amount1Out = 0;

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        inputAmount: inputAmount,
        incentiveBps: 10000, // 100% = 10000 bps
        dir: LQ.Direction.Contract,
        isToken0Debt: true,
        debtToken: debtToken,
        collateralToken: collToken
      })
    );

    // No collateral to pool since incentive = input
    expectReserveTransfer(collToken, address(fpmm), amountToPool);
    // All collateral goes to strategy as incentive
    expectReserveTransfer(collToken, address(strategy), incentiveAmount);
    // No debt to burn since nothing went to pool
    // expectERC20Burn(debtToken, amount0Out); // amount0Out is 0, so no burn event
    vm.prank(address(fpmm));
    strategy.hook(address(strategy), amount0Out, amount1Out, hookData);
  }
}
