// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
// solhint-disable max-line-length
pragma solidity ^0.8;

import { ReserveLiquidityStrategy_BaseTest } from "./ReserveLiquidityStrategy_BaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/libraries/LiquidityStrategyTypes.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { MockERC20 } from "../../../utils/mocks/MockERC20.sol";
import { FPMM } from "contracts/swap/FPMM.sol";
import { ILiquidityStrategy } from "contracts/interfaces/ILiquidityStrategy.sol";

contract ReserveLiquidityStrategy_IntegrationTest is ReserveLiquidityStrategy_BaseTest {
  // Test variations for multiple scenarios test
  bool[2] internal tokenOrders = [true, false]; // isToken0Debt variations
  bool[2] internal pricePositions = [true, false]; // poolPriceAbove variations

  uint64[3] internal liquiditySourceIncentive = [uint64(0), 0.0025e18, 0.005e18]; // 0%, 0.25%, 0.5% liquidity source incentive
  uint64[3] internal protocolIncentive = [uint64(0), 0.002506265664160401e18, 0.005025125628140703e18]; // 0%, 0.25%, 0.5% protocol incentive

  function setUp() public override {
    super.setUp();
  }

  /* ============================================================ */
  /* ================ Token Order Tests ======================== */
  /* ============================================================ */

  function test_determineAction_whenToken1IsDebt_shouldHandleCorrectly()
    public
    fpmmToken1Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Test when token1 is debt and token0 is collateral (isToken0Debt = false)
    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: 100e18, // token0 (collateral) reserves
      reserveNum: 200e18, // token1 (debt) reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      isToken0Debt: false, // token1 is debt
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0.005e18,
        protocolIncentiveExpansion: 0.005025125628140703e18, // 0.5% * 0.05025125628140703% = 1% total expansion incentive
        liquiditySourceIncentiveContraction: 0.005e18,
        protocolIncentiveContraction: 0.005025125628140703e18 // 0.5% * 0.05025125628140703% = 1% total contraction incentive
      })
    });

    // Mock reserve to have collateral balance for contraction
    vm.mockCall(collToken, abi.encodeWithSelector(IERC20.balanceOf.selector, address(reserve)), abi.encode(1000e18));

    LQ.Action memory action = strategy.determineAction(ctx);

    // When token1 is debt and PP > OP, we still need to contract (remove excess debt)
    // Pool has 200 debt (token1) vs 100 collateral (token0) at 1:1 oracle, so pool price > oracle
    // This means too much debt relative to collateral, so we contract
    assertEq(action.dir, LQ.Direction.Contract, "Should contract when excess debt relative to collateral");
    assertEq(action.amount0Out, 0, "No collateral (token0) should flow out");
    assertGt(action.amount1Out, 0, "Should have debt (token1) flowing out");
    assertGt(action.amountOwedToPool, 0, "Should have collateral input amount");
  }

  function test_determineAction_whenToken0IsCollateral_shouldHandleExpansionCorrectly()
    public
    fpmmToken1Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Test expansion scenario when token0 is collateral (token1 is debt)
    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: 200e18, // token0 (collateral) reserves
      reserveNum: 100e18, // token1 (debt) reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      isToken0Debt: false, // token1 is debt
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0.005e18,
        protocolIncentiveExpansion: 0.005025125628140703e18, // 0.5% * 0.05025125628140703% = 1% total expansion incentive
        liquiditySourceIncentiveContraction: 0.005e18,
        protocolIncentiveContraction: 0.005025125628140703e18 // 0.5% * 0.05025125628140703% = 1% total contraction incentive
      })
    });

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Expand, "Should expand when excess collateral");
    assertGt(action.amount0Out, 0, "Should have collateral (token0) flowing out");
    assertEq(action.amount1Out, 0, "No debt (token1) should flow out");
    assertGt(action.amountOwedToPool, 0, "Should have debt input amount");
  }

  function test_determineAction_whenToken0IsCollateral_shouldHandleContractionCorrectly()
    public
    fpmmToken1Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Test contraction scenario when token0 is collateral (token1 is debt)
    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: 100e18, // token0 (collateral) reserves
      reserveNum: 200e18, // token1 (debt) reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true, // Pool has excess debt relative to collateral
      isToken0Debt: false, // token1 is debt
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0.005e18,
        protocolIncentiveExpansion: 0.005025125628140703e18, // 0.5% * 0.05025125628140703% = 1% total expansion incentive
        liquiditySourceIncentiveContraction: 0.005e18,
        protocolIncentiveContraction: 0.005025125628140703e18 // 0.5% * 0.05025125628140703% = 1% total contraction incentive
      })
    });

    // Mock reserve to have collateral balance for contraction
    vm.mockCall(collToken, abi.encodeWithSelector(IERC20.balanceOf.selector, address(reserve)), abi.encode(1000e18));

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Contract, "Should contract when excess debt");
    assertEq(action.amount0Out, 0, "No collateral (token0) should flow out");
    assertGt(action.amount1Out, 0, "Should have debt (token1) flowing out");
    assertGt(action.amountOwedToPool, 0, "Should have collateral input amount");
  }

  /* ============================================================ */
  /* ============ Token Consistency Tests ====================== */
  /* ============================================================ */

  function test_determineAction_outputConsistency_shouldMatchDirection()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Test that output amounts are consistent with direction
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18,
      reserveNum: 200e18,
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0.005e18,
        protocolIncentiveExpansion: 0.005025125628140703e18, // 0.5% * 0.05025125628140703% = 1% total expansion incentive
        liquiditySourceIncentiveContraction: 0.005e18,
        protocolIncentiveContraction: 0.005025125628140703e18 // 0.5% * 0.05025125628140703% = 1% total contraction incentive
      })
    });

    LQ.Action memory action = strategy.determineAction(ctx);

    // For expansion when token0 is debt: collateral (token1) flows out, debt (token0) flows in via inputAmount
    assertEq(action.dir, LQ.Direction.Expand, "Should expand when pool price above oracle");
    assertEq(action.amount0Out, 0, "No debt should flow out during expansion");
    assertGt(action.amount1Out, 0, "Collateral should flow out during expansion");
    assertGt(action.amountOwedToPool, 0, "Debt should flow in via inputAmount");
  }

  function test_determineAction_outputConsistency_withReversedTokenOrder_shouldMatchDirection()
    public
    fpmmToken1Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Test output consistency with reversed token order
    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: 200e18, // token0 (collateral) reserves
      reserveNum: 100e18, // token1 (debt) reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      isToken0Debt: false, // token1 is debt
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0.005e18,
        protocolIncentiveExpansion: 0.005025125628140703e18, // 0.5% * 0.05025125628140703% = 1% total expansion incentive
        liquiditySourceIncentiveContraction: 0.005e18,
        protocolIncentiveContraction: 0.005025125628140703e18 // 0.5% * 0.05025125628140703% = 1% total contraction incentive
      })
    });

    LQ.Action memory action = strategy.determineAction(ctx);

    // For expansion when token1 is debt: collateral (token0) flows out, debt (token1) flows in via inputAmount
    assertEq(action.dir, LQ.Direction.Expand, "Should expand when pool price above oracle");
    assertGt(action.amount0Out, 0, "Collateral (token0) should flow out during expansion");
    assertEq(action.amount1Out, 0, "No debt (token1) should flow out during expansion");
    assertGt(action.amountOwedToPool, 0, "Debt should flow in via inputAmount");
  }

  function test_determineAction_amountScaling_withDifferentIncentives_shouldBeProportional()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    LQ.Action memory prevAction;
    for (uint256 i = 0; i < liquiditySourceIncentive.length; i++) {
      LQ.Context memory ctx = _createContext({
        reserveDen: 100e18,
        reserveNum: 150e18,
        oracleNum: 1e18,
        oracleDen: 1e18,
        poolPriceAbove: true,
        incentives: LQ.RebalanceIncentives({
          liquiditySourceIncentiveExpansion: liquiditySourceIncentive[i],
          protocolIncentiveExpansion: protocolIncentive[i],
          liquiditySourceIncentiveContraction: liquiditySourceIncentive[i],
          protocolIncentiveContraction: protocolIncentive[i]
        })
      });

      LQ.Action memory action = strategy.determineAction(ctx);

      if (action.amount1Out > 0) {
        assertGt(action.amountOwedToPool, 0, "Should have input amount");

        // Verify amounts increase with incentive (more incentive = more rebalancing)
        if (i > 0) {
          assertGe(action.amount1Out, prevAction.amount1Out, "Higher incentive should yield equal or larger amounts");
        }
        prevAction = action;
      }
    }
  }

  /* ============================================================ */
  /* ================ Complex Integration Tests ================ */
  /* ============================================================ */

  function test_integration_multipleScenarios_withTokenOrderVariations() public {
    for (uint256 i = 0; i < tokenOrders.length; i++) {
      bool isToken0Debt = tokenOrders[i];

      // 1. Deploy tokens in the correct order for this iteration
      address token0;
      address token1;
      address _debtToken;
      address _collToken;

      if (isToken0Debt) {
        token0 = address(new MockERC20("DebtToken", "DT", 18));
        token1 = address(new MockERC20("CollToken", "CT", 18));
        _debtToken = token0;
        _collToken = token1;
      } else {
        token0 = address(new MockERC20("CollToken", "CT", 18));
        token1 = address(new MockERC20("DebtToken", "DT", 18));
        _debtToken = token1;
        _collToken = token0;
      }

      // 2. Create and initialize a new FPMM for this token order
      FPMM testFpmm = new FPMM(false);
      testFpmm.initialize(token0, token1, oracleAdapter, referenceRateFeedID, false, address(this), defaultFPMMParams);
      testFpmm.setLiquidityStrategy(address(strategy), true);
      testFpmm.setRebalanceIncentive(100);

      // 3. Register the tokens with the reserve
      vm.startPrank(owner);
      reserve.registerStableAsset(_debtToken);
      reserve.registerCollateralAsset(_collToken);
      vm.stopPrank();

      // 4. Add this pool to the strategy
      ILiquidityStrategy.AddPoolParams memory params = _buildAddPoolParams(
        address(testFpmm),
        _debtToken,
        100,
        protocolFeeRecipient,
        0,
        0,
        0,
        0
      );
      vm.prank(owner);
      strategy.addPool(params);

      // 5. Mock reserve balance for contraction scenarios
      vm.mockCall(_collToken, abi.encodeWithSelector(IERC20.balanceOf.selector, address(reserve)), abi.encode(1000e18));

      // 6. Now test all combinations for this token order
      for (uint256 j = 0; j < pricePositions.length; j++) {
        for (uint256 k = 0; k < liquiditySourceIncentive.length; k++) {
          // Flip reserves based on poolPriceAbove to ensure mathematically valid scenarios
          // poolPriceAbove=true: reserveNum/reserveDen should be > oracleNum/oracleDen
          // poolPriceAbove=false: reserveNum/reserveDen should be < oracleNum/oracleDen
          bool poolPriceAbove = pricePositions[j];
          uint256 reserveNum = poolPriceAbove ? 180e18 : 120e18;
          uint256 reserveDen = poolPriceAbove ? 120e18 : 180e18;

          // Manually construct the context with proper token addresses
          LQ.Context memory ctx = LQ.Context({
            pool: address(testFpmm),
            reserves: LQ.Reserves({ reserveNum: reserveNum, reserveDen: reserveDen }),
            prices: LQ.Prices({
              oracleNum: 1e18,
              oracleDen: 1e18,
              poolPriceAbove: poolPriceAbove,
              rebalanceThreshold: 500
            }),
            token0: token0,
            token1: token1,
            token0Dec: 1e18,
            token1Dec: 1e18,
            isToken0Debt: isToken0Debt,
            incentives: LQ.RebalanceIncentives({
              liquiditySourceIncentiveExpansion: liquiditySourceIncentive[k],
              protocolIncentiveExpansion: protocolIncentive[k],
              liquiditySourceIncentiveContraction: liquiditySourceIncentive[k],
              protocolIncentiveContraction: protocolIncentive[k]
            })
          });

          LQ.Action memory action = strategy.determineAction(ctx);

          if (action.amount0Out > 0 || action.amount1Out > 0) {
            // Verify basic action properties
            assertTrue(
              action.dir == LQ.Direction.Expand || action.dir == LQ.Direction.Contract,
              "Should have valid direction"
            );

            // Verify token flow consistency with direction
            if (action.dir == LQ.Direction.Expand) {
              // In expansion, debt flows in (inputAmount), collateral flows out
              assertGt(action.amountOwedToPool, 0, "Should have debt input in expansion");
              assertTrue(action.amount0Out > 0 || action.amount1Out > 0, "Should have collateral output in expansion");
            } else {
              // In contraction, collateral flows in (inputAmount), debt flows out
              assertGt(action.amountOwedToPool, 0, "Should have collateral input in contraction");
              assertTrue(action.amount0Out > 0 || action.amount1Out > 0, "Should have debt output in contraction");
            }
          }
        }
      }
    }
  }
}
