// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
// solhint-disable max-line-length
pragma solidity ^0.8;

import { ReserveLiquidityStrategyBaseTest } from "./ReserveLiquidityStrategyBaseTest.sol";
import { LiquidityTypes as LQ } from "contracts/v3/libraries/LiquidityTypes.sol";
import { IERC20MintableBurnable } from "contracts/common/IERC20MintableBurnable.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";

contract ReserveLiquidityStrategyHooksTest is ReserveLiquidityStrategyBaseTest {
  function setUp() public override {
    super.setUp();

    // Set pool1 as trusted for hook tests
    vm.prank(owner);
    strategy.setTrustedPool(pool1, true);

    // Setup token metadata mock
    _mockFPMMTokens(pool1, token0, token1);
  }

  /* ============================================================ */
  /* ====================== Hook Function ======================= */
  /* ============================================================ */

  function test_hook_whenValidExpansionCallback_shouldExecuteCorrectly() public {
    uint256 inputAmount = 100e18;
    uint256 incentiveAmount = 5e18; // 5%
    uint256 amount0Out = 0;
    uint256 amount1Out = 95e18; // collateral out
    bool isToken0Debt = true;

    bytes memory hookData = abi.encode(inputAmount, incentiveAmount, LQ.Direction.Expand, isToken0Debt);

    // Mock the minting of debt tokens
    _mockDebtTokenMint(token0);

    // Mock collateral transfer
    _mockCollateralTransfer(token1);

    // Call hook from pool1 as if it's during FPMM rebalance
    vm.prank(pool1);
    strategy.hook(address(strategy), amount0Out, amount1Out, hookData);
  }

  function test_hook_whenValidContractionCallback_shouldExecuteCorrectly() public {
    uint256 inputAmount = 80e18;
    uint256 incentiveAmount = 4e18; // 5%
    uint256 amount0Out = 76e18; // debt out
    uint256 amount1Out = 0;
    bool isToken0Debt = true;

    bytes memory hookData = abi.encode(inputAmount, incentiveAmount, LQ.Direction.Contract, isToken0Debt);

    // Mock debt token burning
    _mockDebtTokenBurn(token0);

    // Mock reserve transfers
    _mockReserveTransfer(reserve);

    // Mock token1 as collateral (for contraction, collateral goes IN)
    _mockIsCollateralAsset(reserve, token1, true);
    _mockIsStableAsset(reserve, token1, false);

    // Call hook from pool1 as if it's during FPMM rebalance
    vm.prank(pool1);
    strategy.hook(address(strategy), amount0Out, amount1Out, hookData);
  }

  function test_hook_whenUntrustedPool_shouldRevert() public {
    bytes memory hookData = abi.encode(100e18, 5e18, LQ.Direction.Expand, true);

    // Call from pool2 which is not trusted
    vm.prank(pool2);
    vm.expectRevert("RLS: UNTRUSTED_POOL");
    strategy.hook(address(strategy), 0, 95e18, hookData);
  }

  function test_hook_whenInvalidSender_shouldRevert() public {
    bytes memory hookData = abi.encode(100e18, 5e18, LQ.Direction.Expand, true);

    vm.prank(pool1);
    vm.expectRevert("RLS: INVALID_SENDER");
    strategy.hook(notOwner, 0, 95e18, hookData); // Wrong sender
  }

  function test_hook_whenReversedTokenOrder_shouldHandleCorrectly() public {
    uint256 inputAmount = 120e18;
    uint256 incentiveAmount = 6e18;
    uint256 amount0Out = 114e18; // collateral out (token0 is collateral)
    uint256 amount1Out = 0;
    bool isToken0Debt = false; // token1 is debt

    bytes memory hookData = abi.encode(inputAmount, incentiveAmount, LQ.Direction.Expand, isToken0Debt);

    // Mock token operations for reversed order
    _mockDebtTokenMint(token1); // token1 is debt
    _mockCollateralTransfer(token0); // token0 is collateral

    vm.prank(pool1);
    strategy.hook(address(strategy), amount0Out, amount1Out, hookData);
  }

  /* ============================================================ */
  /* ================= Expansion Callback Tests ================ */
  /* ============================================================ */

  function test_hook_expansionCallback_whenToken0IsDebt_shouldMintAndTransferCorrectly() public {
    uint256 inputAmount = 200e18;
    uint256 incentiveAmount = 10e18; // 5%
    uint256 amount0Out = 0;
    uint256 amount1Out = 190e18; // collateral out
    bool isToken0Debt = true;

    bytes memory hookData = abi.encode(inputAmount, incentiveAmount, LQ.Direction.Expand, isToken0Debt);

    // Mock the calls
    _mockDebtTokenMint(token0);
    _mockCollateralTransfer(token1);

    vm.prank(pool1);
    strategy.hook(address(strategy), amount0Out, amount1Out, hookData);

    // Test passes if no revert occurs
  }

  function test_hook_expansionCallback_whenToken1IsDebt_shouldMintAndTransferCorrectly() public {
    uint256 inputAmount = 150e18;
    uint256 incentiveAmount = 7.5e18; // 5%
    uint256 amount0Out = 142.5e18; // collateral out
    uint256 amount1Out = 0;
    bool isToken0Debt = false; // token1 is debt

    bytes memory hookData = abi.encode(inputAmount, incentiveAmount, LQ.Direction.Expand, isToken0Debt);

    // Mock the calls
    _mockDebtTokenMint(token1);
    _mockCollateralTransfer(token0);

    vm.prank(pool1);
    strategy.hook(address(strategy), amount0Out, amount1Out, hookData);

    // Test passes if no revert occurs
  }

  /* ============================================================ */
  /* ================ Contraction Callback Tests =============== */
  /* ============================================================ */

  function test_hook_contractionCallback_whenToken0IsDebt_shouldBurnAndTransferCorrectly() public {
    uint256 inputAmount = 90e18;
    uint256 incentiveAmount = 4.5e18; // 5%
    uint256 amount0Out = 85.5e18; // debt out
    uint256 amount1Out = 0;
    bool isToken0Debt = true;

    bytes memory hookData = abi.encode(inputAmount, incentiveAmount, LQ.Direction.Contract, isToken0Debt);

    // Expected calls
    vm.expectCall(
      token0,
      abi.encodeWithSelector(IERC20MintableBurnable.burn.selector, 85.5e18) // debt burn
    );
    vm.expectCall(
      reserve,
      abi.encodeWithSelector(IReserve.transferExchangeCollateralAsset.selector, token1, pool1, 85.5e18) // collateral to pool
    );
    vm.expectCall(
      reserve,
      abi.encodeWithSelector(IReserve.transferExchangeCollateralAsset.selector, token1, address(strategy), 4.5e18) // incentive to strategy
    );

    // Mock the calls
    _mockDebtTokenBurn(token0); // token0 is debt
    _mockReserveTransfer(reserve);
    // Mock token1 as collateral (for contraction, collateral goes IN)
    _mockIsCollateralAsset(reserve, token1, true);
    _mockIsStableAsset(reserve, token1, false);

    vm.prank(pool1);
    strategy.hook(address(strategy), amount0Out, amount1Out, hookData);
  }

  function test_hook_contractionCallback_whenToken1IsDebt_shouldBurnAndTransferCorrectly() public {
    uint256 inputAmount = 75e18;
    uint256 incentiveAmount = 3.75e18; // 5%
    uint256 amount0Out = 0;
    uint256 amount1Out = 71.25e18; // debt out
    bool isToken0Debt = false; // token1 is debt

    bytes memory hookData = abi.encode(inputAmount, incentiveAmount, LQ.Direction.Contract, isToken0Debt);

    // Expected calls for reversed token order
    vm.expectCall(
      token1,
      abi.encodeWithSelector(IERC20MintableBurnable.burn.selector, 71.25e18) // debt burn
    );
    vm.expectCall(
      reserve,
      abi.encodeWithSelector(IReserve.transferExchangeCollateralAsset.selector, token0, pool1, 71.25e18) // collateral to pool
    );
    vm.expectCall(
      reserve,
      abi.encodeWithSelector(IReserve.transferExchangeCollateralAsset.selector, token0, address(strategy), 3.75e18) // incentive to strategy
    );

    // Mock the calls
    _mockDebtTokenBurn(token1); // token1 is debt
    _mockReserveTransfer(reserve);
    // Mock token0 as collateral (for contraction, collateral goes IN)
    _mockIsCollateralAsset(reserve, token0, true);
    _mockIsStableAsset(reserve, token0, false);

    vm.prank(pool1);
    strategy.hook(address(strategy), amount0Out, amount1Out, hookData);
  }

  function test_hook_contractionCallback_whenReserveTransferFails_shouldRevert() public {
    uint256 inputAmount = 60e18;
    uint256 incentiveAmount = 3e18;
    uint256 amount0Out = 57e18;
    uint256 amount1Out = 0;
    bool isToken0Debt = true;

    bytes memory hookData = abi.encode(inputAmount, incentiveAmount, LQ.Direction.Contract, isToken0Debt);

    // Mock debt burning to succeed
    _mockDebtTokenBurn(token0);

    // Mock token1 as collateral
    _mockIsCollateralAsset(reserve, token1, true);
    _mockIsStableAsset(reserve, token1, false);

    // Mock reserve transfer to fail for collateral to pool
    bytes memory transferCalldata = abi.encodeWithSelector(
      IReserve.transferExchangeCollateralAsset.selector,
      token1,
      pool1,
      57e18
    );
    vm.mockCall(reserve, transferCalldata, abi.encode(false)); // Return false for failure

    vm.prank(pool1);
    vm.expectRevert("RLS: COLLATERAL_TO_POOL_FAILED");
    strategy.hook(address(strategy), amount0Out, amount1Out, hookData);
  }

  function test_hook_contractionCallback_whenIncentiveTransferFails_shouldRevert() public {
    uint256 inputAmount = 50e18;
    uint256 incentiveAmount = 2.5e18;
    uint256 amount0Out = 47.5e18;
    uint256 amount1Out = 0;
    bool isToken0Debt = true;

    bytes memory hookData = abi.encode(inputAmount, incentiveAmount, LQ.Direction.Contract, isToken0Debt);

    // Mock debt burning to succeed
    _mockDebtTokenBurn(token0);

    // Mock token1 as collateral
    _mockIsCollateralAsset(reserve, token1, true);
    _mockIsStableAsset(reserve, token1, false);

    // Mock first transfer (collateral to pool) to succeed, second (incentive) to fail
    vm.mockCall(
      reserve,
      abi.encodeWithSelector(IReserve.transferExchangeCollateralAsset.selector, token1, pool1, 47.5e18),
      abi.encode(true)
    );
    vm.mockCall(
      reserve,
      abi.encodeWithSelector(IReserve.transferExchangeCollateralAsset.selector, token1, address(strategy), 2.5e18),
      abi.encode(false) // Fail incentive transfer
    );

    vm.prank(pool1);
    vm.expectRevert("RLS: INCENTIVE_TRANSFER_FAILED");
    strategy.hook(address(strategy), amount0Out, amount1Out, hookData);
  }

  /* ============================================================ */
  /* ==================== Edge Case Tests ====================== */
  /* ============================================================ */

  function test_hook_withZeroIncentive_shouldExecuteCorrectly() public {
    uint256 inputAmount = 100e18;
    uint256 incentiveAmount = 0; // Zero incentive
    uint256 amount0Out = 0;
    uint256 amount1Out = 100e18;
    bool isToken0Debt = true;

    bytes memory hookData = abi.encode(inputAmount, incentiveAmount, LQ.Direction.Expand, isToken0Debt);

    // Mock calls - should mint full amount to pool, nothing to strategy
    vm.expectCall(token0, abi.encodeWithSelector(IERC20MintableBurnable.mint.selector, pool1, 100e18));
    // Note: With zero incentive, no mint call to strategy address should happen

    _mockDebtTokenMint(token0);
    _mockCollateralTransfer(token1);

    vm.prank(pool1);
    strategy.hook(address(strategy), amount0Out, amount1Out, hookData);
  }

  function test_hook_withMaxIncentive_shouldExecuteCorrectly() public {
    uint256 inputAmount = 50e18;
    uint256 incentiveAmount = 50e18; // 100% incentive
    uint256 amount0Out = 50e18;
    uint256 amount1Out = 0;
    bool isToken0Debt = true;

    bytes memory hookData = abi.encode(inputAmount, incentiveAmount, LQ.Direction.Contract, isToken0Debt);

    // Mock calls - for contraction with 100% incentive
    vm.expectCall(token0, abi.encodeWithSelector(IERC20MintableBurnable.burn.selector, 50e18));
    // No collateral to pool since incentive = input
    vm.expectCall(reserve, abi.encodeWithSelector(IReserve.transferExchangeCollateralAsset.selector, token1, pool1, 0));
    vm.expectCall(
      reserve,
      abi.encodeWithSelector(IReserve.transferExchangeCollateralAsset.selector, token1, address(strategy), 50e18)
    );

    _mockDebtTokenBurn(token0);
    _mockReserveTransfer(reserve);

    // Mock token1 as collateral (for contraction, collateral goes IN)
    _mockIsCollateralAsset(reserve, token1, true);
    _mockIsStableAsset(reserve, token1, false);

    vm.prank(pool1);
    strategy.hook(address(strategy), amount0Out, amount1Out, hookData);
  }
}
