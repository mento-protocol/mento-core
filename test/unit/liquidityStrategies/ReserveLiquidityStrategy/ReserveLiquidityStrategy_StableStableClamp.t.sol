// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, max-line-length
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { ReserveLiquidityStrategy_BaseTest } from "./ReserveLiquidityStrategy_BaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/libraries/LiquidityStrategyTypes.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { ILiquidityStrategy } from "contracts/interfaces/ILiquidityStrategy.sol";
import { IReserveLiquidityStrategy } from "contracts/interfaces/IReserveLiquidityStrategy.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";

contract ReserveLiquidityStrategy_StableStableClampTest is ReserveLiquidityStrategy_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  /* ============================================================ */
  /* ================ Setup Modifiers ============================ */
  /* ============================================================ */

  /// @notice Register collToken as a stable asset (stable/stable pool)
  modifier addFpmmStableStable(
    uint32 cooldown,
    uint64 liquiditySourceIncentiveExpansion,
    uint64 protocolIncentiveExpansion,
    uint64 liquiditySourceIncentiveContraction,
    uint64 protocolIncentiveContraction
  ) {
    uint64 fpmmIncentive = liquiditySourceIncentiveExpansion + protocolIncentiveExpansion >=
      liquiditySourceIncentiveContraction + protocolIncentiveContraction
      ? liquiditySourceIncentiveExpansion + protocolIncentiveExpansion
      : liquiditySourceIncentiveContraction + protocolIncentiveContraction;

    fpmmIncentive = fpmmIncentive / 1e14;
    fpmm.setRebalanceIncentive(fpmmIncentive);

    ILiquidityStrategy.AddPoolParams memory params = _buildAddPoolParams(
      address(fpmm),
      debtToken,
      cooldown,
      protocolFeeRecipient,
      liquiditySourceIncentiveExpansion,
      protocolIncentiveExpansion,
      liquiditySourceIncentiveContraction,
      protocolIncentiveContraction
    );

    vm.startPrank(owner);
    strategy.addPool(params);
    // Register both tokens as stable assets
    reserve.registerStableAsset(debtToken);
    reserve.registerStableAsset(collToken);
    vm.stopPrank();
    _;
  }

  /// @notice Register collToken as both stable and collateral (dual-registered)
  modifier addFpmmDualRegistered(
    uint32 cooldown,
    uint64 liquiditySourceIncentiveExpansion,
    uint64 protocolIncentiveExpansion,
    uint64 liquiditySourceIncentiveContraction,
    uint64 protocolIncentiveContraction
  ) {
    uint64 fpmmIncentive = liquiditySourceIncentiveExpansion + protocolIncentiveExpansion >=
      liquiditySourceIncentiveContraction + protocolIncentiveContraction
      ? liquiditySourceIncentiveExpansion + protocolIncentiveExpansion
      : liquiditySourceIncentiveContraction + protocolIncentiveContraction;

    fpmmIncentive = fpmmIncentive / 1e14;
    fpmm.setRebalanceIncentive(fpmmIncentive);

    ILiquidityStrategy.AddPoolParams memory params = _buildAddPoolParams(
      address(fpmm),
      debtToken,
      cooldown,
      protocolFeeRecipient,
      liquiditySourceIncentiveExpansion,
      protocolIncentiveExpansion,
      liquiditySourceIncentiveContraction,
      protocolIncentiveContraction
    );

    vm.startPrank(owner);
    strategy.addPool(params);
    reserve.registerStableAsset(debtToken);
    // Register collToken as BOTH stable and collateral
    reserve.registerStableAsset(collToken);
    reserve.registerCollateralAsset(collToken);
    MockERC20(collToken).mint(address(reserve), 1000000e18);
    vm.stopPrank();
    _;
  }

  /* ============================================================ */
  /* ====== Stable/Collateral Contraction (existing behavior) ==== */
  /* ============================================================ */

  function test_contraction_stableCollateral_shouldClampOnReserveBalance()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 0, 0, 0, 0)
  {
    // Existing behavior: collToken is collateral, so contraction clamps on reserve balance
    LQ.Context memory ctx = _createContext({
      reserveDen: 300e18,
      reserveNum: 100e18,
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0,
        protocolIncentiveExpansion: 0,
        liquiditySourceIncentiveContraction: 0,
        protocolIncentiveContraction: 0
      })
    });

    // Reserve has only 10e18 collateral, much less than the ideal contraction amount
    vm.mockCall(collToken, abi.encodeWithSelector(IERC20.balanceOf.selector, address(reserve)), abi.encode(10e18));

    LQ.Action memory action = strategy.determineAction(ctx);

    // Should be clamped to 10e18 collateral
    assertEq(action.amountOwedToPool, 10e18, "Collateral should be clamped to reserve balance");
    // Debt out should be recalculated based on clamped collateral
    assertEq(action.amount0Out, 10e18, "Debt out should match clamped collateral at 1:1 rate");
  }

  function test_contraction_stableCollateral_shouldRevertWhenZeroBalance()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 0, 0, 0, 0)
  {
    LQ.Context memory ctx = _createContext({
      reserveDen: 300e18,
      reserveNum: 100e18,
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0,
        protocolIncentiveExpansion: 0,
        liquiditySourceIncentiveContraction: 0,
        protocolIncentiveContraction: 0
      })
    });

    // Reserve has zero collateral
    vm.mockCall(collToken, abi.encodeWithSelector(IERC20.balanceOf.selector, address(reserve)), abi.encode(0));

    vm.expectRevert(IReserveLiquidityStrategy.RLS_RESERVE_OUT_OF_COLLATERAL.selector);
    strategy.determineAction(ctx);
  }

  /* ============================================================ */
  /* ====== Stable/Stable Contraction (new behavior) ============ */
  /* ============================================================ */

  function test_contraction_stableStable_shouldNotClampOnReserveBalance()
    public
    fpmmToken0Debt(18, 18)
    addFpmmStableStable(0, 0, 0, 0, 0)
  {
    // Stable/stable pool: collToken is a stable asset, so minting is unlimited
    // Even with zero reserve balance, contraction should return ideal amounts
    LQ.Context memory ctx = _createContext({
      reserveDen: 300e18,
      reserveNum: 100e18,
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0,
        protocolIncentiveExpansion: 0,
        liquiditySourceIncentiveContraction: 0,
        protocolIncentiveContraction: 0
      })
    });

    // No reserve balance mocking needed - stable tokens are minted, not transferred

    LQ.Action memory action = strategy.determineAction(ctx);

    // Formula: Y = (TN*RD - TD*RN) / (TN + TD * (1 - i) * ON/OD)
    // TN = 0.95e18, TD = 1e18, RD = 300e18, RN = 100e18, ON/OD = 1, i = 0
    // Y = (0.95e18 * 300e18 - 1e18 * 100e18) / (0.95e18 + 1e18 * 1 * 1)
    // Y = (285e36 - 100e36) / (0.95e18 + 1e18) = 185e36 / 1.95e18 = 94871794871794871794
    uint256 expectedDebtOut = 94871794871794871794;
    uint256 expectedCollIn = 94871794871794871794; // same as debt at 1:1 rate with 0 fees

    assertEq(action.amount0Out, expectedDebtOut, "Debt out should be ideal (unclamped)");
    assertEq(action.amountOwedToPool, expectedCollIn, "Collateral in should be ideal (unclamped)");
  }

  function test_contraction_stableStable_withIncentive_shouldNotClamp()
    public
    fpmmToken0Debt(18, 18)
    addFpmmStableStable(0, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    LQ.Context memory ctx = _createContext({
      reserveDen: 300e18,
      reserveNum: 100e18,
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0.005e18,
        protocolIncentiveExpansion: 0.005025125628140703e18,
        liquiditySourceIncentiveContraction: 0.005e18,
        protocolIncentiveContraction: 0.005025125628140703e18
      })
    });

    LQ.Action memory action = strategy.determineAction(ctx);

    // With ~1% total contraction incentive and no clamping, ideal amounts should be returned
    assertGt(action.amount0Out, 0, "Should have debt out");
    assertGt(action.amountOwedToPool, 0, "Should have collateral in");

    // Verify that the amounts are NOT clamped - they should be larger than any small reserve balance
    // would allow. The ideal collateral-in should be close to ~94e18 (unclamped)
    assertGt(action.amountOwedToPool, 50e18, "Collateral in should not be clamped to a small balance");
  }

  function test_contraction_stableStable_shouldReturnSameAsUnclampedFormula()
    public
    fpmmToken0Debt(18, 18)
    addFpmmStableStable(0, 0, 0, 0, 0)
  {
    // Compare stable/stable contraction with the ideal formula
    // Since there's no clamping, the amounts should match what you'd get
    // from the base LiquidityStrategy (no override)
    LQ.Context memory ctx = _createContext({
      reserveDen: 200e18,
      reserveNum: 100e18,
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0,
        protocolIncentiveExpansion: 0,
        liquiditySourceIncentiveContraction: 0,
        protocolIncentiveContraction: 0
      })
    });

    LQ.Action memory action = strategy.determineAction(ctx);

    // Formula: Y = (TN*RD - TD*RN) / (TN + TD * (1 - i) * ON/OD)
    // TN = 0.95e18, TD = 1e18, RD = 200e18, RN = 100e18, ON/OD = 1, i = 0
    // Y = (0.95e18 * 200e18 - 1e18 * 100e18) / (0.95e18 + 1e18)
    // Y = (190e36 - 100e36) / 1.95e18 = 90e36 / 1.95e18 = 46153846153846153846
    assertEq(action.amount0Out, 46153846153846153846, "Debt out should match formula exactly");
    assertEq(action.amountOwedToPool, 46153846153846153846, "Collateral in should match formula exactly");
  }

  function test_contraction_stableStable_whenToken1IsDebt_shouldNotClamp()
    public
    fpmmToken1Debt(18, 18)
    addFpmmStableStable(0, 0, 0, 0, 0)
  {
    // Reversed token order: token1 is debt and token0 is collateral.
    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: 100e18,
      reserveNum: 300e18,
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      isToken0Debt: false,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0,
        protocolIncentiveExpansion: 0,
        liquiditySourceIncentiveContraction: 0,
        protocolIncentiveContraction: 0
      })
    });

    LQ.Action memory action = strategy.determineAction(ctx);

    // Formula: Y = (TD*RN - TN*RD) / (TN * (1 - i) * OD/ON + TD)
    // TN = 1.05e18, TD = 1e18, RN = 300e18, RD = 100e18, OD/ON = 1, i = 0
    // Y = (1e18 * 300e18 - 1.05e18 * 100e18) / (1.05e18 + 1e18)
    // Y = (300e36 - 105e36) / 2.05e18 = 195e36 / 2.05e18 = 95121951219512195121
    uint256 expectedDebtOut = 95121951219512195121;

    assertEq(action.dir, LQ.Direction.Contract, "Should contract when token1 debt is in excess");
    assertEq(action.amount0Out, 0, "No collateral should flow out during contraction");
    assertEq(action.amount1Out, expectedDebtOut, "Debt out should be ideal (unclamped)");
    assertEq(action.amountOwedToPool, expectedDebtOut, "Collateral in should be ideal (unclamped)");
  }

  /* ============================================================ */
  /* ====== Dual-Registered Token (stable + collateral) ========= */
  /* ============================================================ */

  function test_contraction_dualRegistered_shouldFollowStableFirstSemantics()
    public
    fpmmToken0Debt(18, 18)
    addFpmmDualRegistered(0, 0, 0, 0, 0)
  {
    // collToken is registered as both stable and collateral.
    // _clampContraction checks isStableAsset first, so it should NOT clamp.
    LQ.Context memory ctx = _createContext({
      reserveDen: 300e18,
      reserveNum: 100e18,
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0,
        protocolIncentiveExpansion: 0,
        liquiditySourceIncentiveContraction: 0,
        protocolIncentiveContraction: 0
      })
    });

    // collToken is also registered as collateral, but the stable-first check means
    // we should still get the ideal (unclamped) amounts.
    LQ.Action memory action = strategy.determineAction(ctx);

    // Same expected values as the stable/stable test above
    uint256 expectedDebtOut = 94871794871794871794;
    uint256 expectedCollIn = 94871794871794871794;

    assertEq(action.amount0Out, expectedDebtOut, "Dual-registered should follow stable-first semantics");
    assertEq(action.amountOwedToPool, expectedCollIn, "Dual-registered should not clamp on reserve balance");
  }

  function test_contraction_dualRegistered_withLowReserveBalance_shouldStillNotClamp()
    public
    fpmmToken0Debt(18, 18)
    addFpmmDualRegistered(0, 0, 0, 0, 0)
  {
    // Explicitly verify that even with a very low reserve balance,
    // dual-registered (stable+collateral) uses stable semantics (no clamp)
    LQ.Context memory ctx = _createContext({
      reserveDen: 200e18,
      reserveNum: 100e18,
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0,
        protocolIncentiveExpansion: 0,
        liquiditySourceIncentiveContraction: 0,
        protocolIncentiveContraction: 0
      })
    });

    // Mock a tiny reserve balance - if collateral semantics were used, this would clamp
    vm.mockCall(collToken, abi.encodeWithSelector(IERC20.balanceOf.selector, address(reserve)), abi.encode(1e18));

    LQ.Action memory action = strategy.determineAction(ctx);

    // Should be unclamped (stable-first)
    assertEq(action.amount0Out, 46153846153846153846, "Should not clamp despite low reserve balance");
    assertEq(action.amountOwedToPool, 46153846153846153846, "Collateral in should be ideal");
  }

  /* ============================================================ */
  /* ====== Unregistered collToken should revert ================= */
  /* ============================================================ */

  function test_contraction_unregisteredCollToken_shouldRevert() public fpmmToken0Debt(18, 18) {
    // Register pool but do NOT register collToken as either stable or collateral
    fpmm.setRebalanceIncentive(0);

    ILiquidityStrategy.AddPoolParams memory params = _buildAddPoolParams(
      address(fpmm),
      debtToken,
      0,
      protocolFeeRecipient,
      0,
      0,
      0,
      0
    );

    vm.startPrank(owner);
    strategy.addPool(params);
    reserve.registerStableAsset(debtToken);
    // collToken is NOT registered
    vm.stopPrank();

    LQ.Context memory ctx = _createContext({
      reserveDen: 200e18,
      reserveNum: 100e18,
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0,
        protocolIncentiveExpansion: 0,
        liquiditySourceIncentiveContraction: 0,
        protocolIncentiveContraction: 0
      })
    });

    vm.expectRevert(IReserveLiquidityStrategy.RLS_TOKEN_IN_NOT_SUPPORTED.selector);
    strategy.determineAction(ctx);
  }
}
