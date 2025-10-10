// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { ReserveLiquidityStrategyBaseTest } from "./ReserveLiquidityStrategyBaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/v3/libraries/LiquidityStrategyTypes.sol";

contract ReserveLiquidityStrategyContractionTest is ReserveLiquidityStrategyBaseTest {
  function setUp() public override {
    super.setUp();
  }

  /* ============================================================ */
  /* ================= Contraction Tests ======================== */
  /* ============================================================ */

  function test_determineAction_whenPoolPriceBelowOracle_shouldReturnContractAction() public {
    // Pool has excess token0 (debt): 200 token0 vs 100 token1 at 1:1 oracle price
    _mockFPMMMetadata(pool1, debtToken, collateralToken);
    _mockFPMMRebalanceIncentive(pool1, 500);
    _mockFPMMPrices(pool1, 1e18, 1e18, 100e18, 200e18, 0, false); // Pool price below

    vm.prank(owner);
    strategy.addPool(pool1, debtToken, 3600, 500);

    (LQ.Context memory ctx, LQ.Action memory action) = strategy.determineAction(pool1);

    assertEq(uint256(action.dir), uint256(LQ.Direction.Contract), "Should contract when pool price below oracle");
    assertEq(action.amount1Out, 0, "No collateral should flow out during contraction");
    assertGt(action.amount0Out, 0, "Debt should flow out during contraction");
    assertGt(action.inputAmount, 0, "Should have collateral input amount");
  }

  function test_determineAction_whenPoolPriceBelowOracleWithDifferentDecimals_shouldHandleCorrectly() public {
    // Test with 6 decimal collateral (token1) and 18 decimal debt (token0)
    _mockFPMMMetadata(pool1, debtToken, collateralToken);
    vm.mockCall(
      pool1,
      abi.encodeWithSelector(bytes4(keccak256("metadata()"))),
      abi.encode(1e18, 1e6, 200e18, 100e18, debtToken, collateralToken)
    );
    _mockFPMMRebalanceIncentive(pool1, 500);
    _mockFPMMPrices(pool1, 1e18, 1e18, 100e18, 200e18, 0, false);

    vm.prank(owner);
    strategy.addPool(pool1, debtToken, 3600, 500);

    (LQ.Context memory ctx, LQ.Action memory action) = strategy.determineAction(pool1);

    assertGt(action.amount0Out, 0, "Should have debt output in raw units");
    assertGt(action.inputAmount, 0, "Should have collateral input in raw units");
    // Verify the input is in 6-decimal scale
    assertLt(action.inputAmount, 1e12, "Collateral input should be in 6-decimal scale");
  }

  function test_determineAction_whenPoolPriceBelowOracleWithZeroIncentive_shouldReturnCorrectAmounts() public {
    _mockFPMMMetadata(pool1, debtToken, collateralToken);
    _mockFPMMRebalanceIncentive(pool1, 100);
    _mockFPMMPrices(pool1, 1e18, 1e18, 100e18, 200e18, 0, false);

    vm.prank(owner);
    strategy.addPool(pool1, debtToken, 3600, 0); // Zero incentive

    (LQ.Context memory ctx, LQ.Action memory action) = strategy.determineAction(pool1);

    // Formula: Y = (ON * RD - OD * RN) / (ON * (2 - i))
    // Y = (1e18 * 200e18 - 1e18 * 100e18) / (1e18 * 2)
    // Y = 100e18 / 2 = 50e18 (token0 to remove)
    assertEq(action.amount0Out, 50e18, "Should calculate correct debt out");
    // X = Y * (ON/OD) * (1 - i) = 50e18 * (1e18/1e18) * 1 = 50e18 (token1 to add)
    assertEq(action.inputAmount, 50e18, "Should calculate correct collateral input amount");
  }

  function test_determineAction_whenPoolPriceBelowOracleWithMaxIncentive_shouldReturnCorrectAmounts() public {
    _mockFPMMMetadata(pool1, debtToken, collateralToken);
    _mockFPMMRebalanceIncentive(pool1, 10000);
    _mockFPMMPrices(pool1, 1e18, 1e18, 100e18, 200e18, 0, false);

    vm.prank(owner);
    strategy.addPool(pool1, debtToken, 3600, 10000); // 100% incentive

    (LQ.Context memory ctx, LQ.Action memory action) = strategy.determineAction(pool1);

    // denominator = (OD * (2 * 10000 - incentiveBps)) / 10000
    // With 100% incentive: denominator = (1e18 * (20000 - 10000)) / 10000 = 1e18
    // numerator = ON * RD - OD * RN = 1e18 * 200e18 - 1e18 * 100e18 = 100e18
    // token1In = numerator / denominator = 100e18 / 1e18 = 100e18
    // token0Out = token1In * (OD / ON) = 100e18 * (1e18 / 1e18) = 100e18
    assertEq(action.amount0Out, 100e18, "Should calculate correct debt out");
    assertEq(action.inputAmount, 100e18, "Should calculate correct collateral input amount with 100% incentive");
  }

  /* ============================================================ */
  /* ================= Contraction Formula Tests =============== */
  /* ============================================================ */

  function test_formulaValidation_whenPPLessThanOP_shouldFollowExactFormula() public {
    // PP < OP: Y = (ON * RD - OD * RN) / (ON * (2 - i))
    // Test with specific values that give clean division: RN=100, RD=500, ON=2, OD=1, i=0
    _mockFPMMMetadata(pool1, debtToken, collateralToken);
    _mockFPMMRebalanceIncentive(pool1, 100);
    _mockFPMMPrices(pool1, 2e18, 1e18, 100e18, 500e18, 0, false);

    vm.prank(owner);
    strategy.addPool(pool1, debtToken, 3600, 0);

    (LQ.Context memory ctx, LQ.Action memory action) = strategy.determineAction(pool1);

    // Manual calculation:
    // Y = (2e18 * 500e18 - 1e18 * 100e18) / (2e18 * 2)
    // Y = (1000e18 - 100e18) / 4e18 = 900e18 / 4e18 = 225e18
    uint256 expectedY = 225e18;
    assertEq(action.amount0Out, expectedY, "Y calculation should match formula (token0 out)");

    // X = Y * (ON/OD) * (1 - i) = 225e18 * (2e18/1e18) * 1 = 450e18
    uint256 expectedX = 450e18;
    assertEq(action.inputAmount, expectedX, "X should equal Y * (ON/OD) * (1 - i)");
  }

  function test_YRelationship_shouldAlwaysHoldForContraction() public {
    // token1In / token0Out = ON / OD (independent of incentive)
    uint256[3] memory incentives = [uint256(0), 1500, 5000];

    for (uint256 i = 0; i < incentives.length; i++) {
      address poolTest = address(uint160(uint256(keccak256(abi.encode("poolTestContract", i)))));

      _mockFPMMMetadata(poolTest, debtToken, collateralToken);
      _mockFPMMRebalanceIncentive(poolTest, 5000);
      _mockFPMMPrices(poolTest, 3e18, 2e18, 150e18, 450e18, 0, false);

      vm.prank(owner);
      strategy.addPool(poolTest, debtToken, 3600, uint32(incentives[i]));

      (LQ.Context memory ctx, LQ.Action memory action) = strategy.determineAction(poolTest);

      if (action.inputAmount > 0) {
        // In new architecture: token0Out = token1In * (OD / ON)
        // So: token1In / token0Out = ON / OD
        uint256 calculatedRatio = (action.inputAmount * ctx.prices.oracleDen) /
          (action.amount0Out * ctx.prices.oracleNum);
        uint256 expectedRatio = 1;
        // Allow for rounding errors
        assertApproxEqAbs(calculatedRatio, expectedRatio, 1, "token1In / token0Out should equal ON / OD");
      }
    }
  }
}
