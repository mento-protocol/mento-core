// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { ReserveLiquidityStrategyBaseTest } from "./ReserveLiquidityStrategyBaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/v3/libraries/LiquidityStrategyTypes.sol";

contract ReserveLiquidityStrategyExpansionTest is ReserveLiquidityStrategyBaseTest {
  function setUp() public override {
    super.setUp();
  }

  /* ============================================================ */
  /* ================= Expansion Tests ========================== */
  /* ============================================================ */

  function test_determineAction_whenPoolPriceAboveOracle_shouldReturnExpandAction() public {
    _mockFPMMMetadata(pool1, debtToken, collateralToken);
    _mockFPMMRebalanceIncentive(pool1, 500);
    _mockFPMMPrices(pool1, 1e18, 1e18, 200e18, 100e18, 0, true); // Pool price above

    vm.prank(owner);
    strategy.addPool(pool1, debtToken, 3600, 500);

    (LQ.Context memory ctx, LQ.Action memory action) = strategy.determineAction(pool1);

    assertEq(uint256(action.dir), uint256(LQ.Direction.Expand), "Should expand when pool price above oracle");
    assertTrue(action.amount0Out == 0 || action.amount1Out > 0, "Should have correct token flows for expansion");
    assertTrue(action.amount0Out > 0 || action.amount1Out > 0, "Should have token outflow during expansion");
    assertGt(action.inputAmount, 0, "Should have debt input amount");
  }

  function test_determineAction_whenPoolPriceAboveOracleWithDifferentDecimals_shouldHandleCorrectly() public {
    // Test with 6 decimal collateral (token1) and 18 decimal debt (token0)
    _mockFPMMMetadata(pool1, debtToken, collateralToken);
    vm.mockCall(
      pool1,
      abi.encodeWithSelector(bytes4(keccak256("metadata()"))),
      abi.encode(1e18, 1e6, 100e18, 200e18, debtToken, collateralToken)
    );
    _mockFPMMRebalanceIncentive(pool1, 500);
    _mockFPMMPrices(pool1, 1e18, 1e18, 200e18, 100e18, 0, true);

    vm.prank(owner);
    strategy.addPool(pool1, debtToken, 3600, 500);

    (LQ.Context memory ctx, LQ.Action memory action) = strategy.determineAction(pool1);

    assertTrue(action.amount0Out > 0 || action.amount1Out > 0, "Should have token output in raw units");
    assertGt(action.inputAmount, 0, "Should have debt input in raw units");
  }

  function test_determineAction_whenPoolPriceAboveOracleWithZeroIncentive_shouldReturnCorrectAmounts() public {
    _mockFPMMMetadata(pool1, debtToken, collateralToken);
    _mockFPMMRebalanceIncentive(pool1, 100);
    _mockFPMMPrices(pool1, 1e18, 1e18, 200e18, 100e18, 0, true);

    vm.prank(owner);
    strategy.addPool(pool1, debtToken, 3600, 0); // Zero incentive

    (LQ.Context memory ctx, LQ.Action memory action) = strategy.determineAction(pool1);

    // Formula: X = (OD * RN - ON * RD) / (OD * (2 - i))
    // X = (1e18 * 200e18 - 1e18 * 100e18) / (1e18 * (20000 - 0) / 10000)
    // X = 100e18 / 2 = 50e18
    assertEq(action.amount1Out, 50e18, "Should calculate correct collateral out with zero incentive");
    // Y = X * OD/ON = 50e18 * 1e18/1e18 = 50e18 (debt flows into pool)
    assertEq(action.inputAmount, 50e18, "Should calculate correct debt input amount");
  }

  function test_determineAction_whenPoolPriceAboveOracleWithMaxIncentive_shouldReturnCorrectAmounts() public {
    _mockFPMMMetadata(pool1, debtToken, collateralToken);
    _mockFPMMRebalanceIncentive(pool1, 10000);
    _mockFPMMPrices(pool1, 1e18, 1e18, 200e18, 100e18, 0, true);

    vm.prank(owner);
    strategy.addPool(pool1, debtToken, 3600, 10000); // 100% incentive

    (LQ.Context memory ctx, LQ.Action memory action) = strategy.determineAction(pool1);

    // Formula: X = (OD * RN - ON * RD) / (OD * (2 - i))
    // X = (1e18 * 200e18 - 1e18 * 100e18) / (1e18 * (20000 - 10000) / 10000)
    // X = 100e18 / 1 = 100e18
    assertEq(action.amount1Out, 100e18, "Should calculate correct collateral out with max incentive");
    // Y = X * OD/ON = 100e18 * 1e18/1e18 = 100e18 (debt flows into pool)
    assertEq(action.inputAmount, 100e18, "Should calculate correct debt input amount");
  }

  /* ============================================================ */
  /* ================= Expansion Formula Tests ================== */
  /* ============================================================ */

  function test_formulaValidation_whenPPGreaterThanOP_shouldFollowExactFormula() public {
    // PP > OP: X = (OD * RN - ON * RD) / (OD * (2 - i))
    // Test with specific values that give clean division: RN=400, RD=100, ON=2, OD=1, i=0
    _mockFPMMMetadata(pool1, debtToken, collateralToken);
    _mockFPMMRebalanceIncentive(pool1, 100);
    _mockFPMMPrices(pool1, 2e18, 1e18, 400e18, 100e18, 0, true);

    vm.prank(owner);
    strategy.addPool(pool1, debtToken, 3600, 0);

    (LQ.Context memory ctx, LQ.Action memory action) = strategy.determineAction(pool1);

    // Manual calculation:
    // X = (1e18 * 400e18 - 2e18 * 100e18) / (1e18 * 2)
    // X = (400e18 - 200e18) / 2 = 200e18 / 2 = 100e18
    uint256 expectedX = 100e18;
    assertEq(action.amount1Out, expectedX, "X calculation should match formula");

    // Y = X * OD/ON = 100e18 * 1e18/2e18 = 50e18
    uint256 expectedY = 50e18;
    assertEq(action.inputAmount, expectedY, "Y should equal X * OD/ON");
  }

  function test_YRelationship_shouldAlwaysHoldForExpansion() public {
    // Test Y = X * OD/ON relationship for expansion (PP > OP)
    uint256[3] memory incentives = [uint256(0), 500, 2000];

    for (uint256 i = 0; i < incentives.length; i++) {
      address poolTest = address(uint160(uint256(keccak256(abi.encode("poolTest", i)))));

      _mockFPMMMetadata(poolTest, debtToken, collateralToken);
      _mockFPMMRebalanceIncentive(poolTest, 2000);
      _mockFPMMPrices(poolTest, 3e18, 2e18, 450e18, 150e18, 0, true);

      vm.prank(owner);
      strategy.addPool(poolTest, debtToken, 3600, uint32(incentives[i]));

      (LQ.Context memory ctx, LQ.Action memory action) = strategy.determineAction(poolTest);

      if (action.amount1Out > 0) {
        // Y/X should equal OD/ON (Y is inputAmount, X is amount1Out) within precision limits
        uint256 calculatedRatio = (action.inputAmount * ctx.prices.oracleNum) / action.amount1Out;
        uint256 expectedRatio = ctx.prices.oracleDen;
        // Allow for rounding errors (1 wei difference)
        assertApproxEqAbs(calculatedRatio, expectedRatio, 1, "Y/X ratio should approximately equal OD/ON");
      }
    }
  }
}
