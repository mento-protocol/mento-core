// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;
// solhint-disable max-line-length

import { CDPPolicy } from "contracts/v3/CDPPolicy.sol";
import { LiquidityTypes as LQ } from "contracts/v3/libraries/LiquidityTypes.sol";
import { ICollateralRegistry } from "bold/Interfaces/ICollateralRegistry.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";
import { IStabilityPool } from "bold/Interfaces/IStabilityPool.sol";
import { console } from "forge-std/console.sol";
import { uints, addresses } from "mento-std/Array.sol";
import { Test } from "forge-std/Test.sol";
contract CDPPolicyTest is Test {
  error CDPPolicy_CONSTRUCTOR_ARRAY_LENGTH_MISMATCH();
  error CDPPolicy_INVALID_STABILITY_POOL_PERCENTAGE();

  CDPPolicy public policy;

  MockERC20 public debtToken6;
  MockERC20 public collateralToken6;

  MockERC20 public debtToken18;
  MockERC20 public collateralToken18;

  address collateralRegistry = makeAddr("collateralRegistry");
  address stabilityPool = makeAddr("stabilityPool");
  address fpmm = makeAddr("fpmm");

  LQ.Context public ctx;

  function setUp() public {
    policy = new CDPPolicy(new address[](0), new address[](0), new address[](0), new uint256[](0), new uint256[](0));
    debtToken6 = new MockERC20("DebtToken6", "DT6", 6);
    collateralToken6 = new MockERC20("CollateralToken6", "CT6", 6);
    debtToken18 = new MockERC20("DebtToken18", "DT18", 18);
    collateralToken18 = new MockERC20("CollateralToken18", "CT18", 18);
  }

  /**
   * @notice Set up the policy
   * @param debtToken The debt token
   * @param stabilityPoolPercentage The stability pool percentage
   */
  modifier _setUpPolicy(MockERC20 debtToken, uint256 stabilityPoolPercentage) {
    policy.setDeptTokenStabilityPool(address(debtToken), stabilityPool);
    policy.setDeptTokenCollateralRegistry(address(debtToken), collateralRegistry);
    policy.setDeptTokenRedemptionBeta(address(debtToken), 1);
    policy.setDeptTokenStabilityPoolPercentage(address(debtToken), stabilityPoolPercentage);
    setStabilityPoolMinBoldAfterRebalance(1 * 10 ** debtToken.decimals());
    _;
  }

  /**
   * @notice Bounds the fuzz parameters for the test
   * @param oracleNumerator The oracle numerator
   * @param reserve0 The reserve0
   * @param reserve1 The reserve1
   * @param poolPriceAbove The pool price above
   */
  modifier _boundFuzzParams(uint256 oracleNumerator, uint256 reserve0, uint256 reserve1, bool poolPriceAbove) {
    // price range from 0.001 to 100_000
    oracleNumerator = bound(oracleNumerator, 1e15, 1e23);
    uint256 oracleDenominator = 1e18;
    reserve0 = bound(reserve0, 100e18, 100_000_000e18);

    if (poolPriceAbove) {
      uint256 reserve1LowerBound = (reserve0 * oracleNumerator * 110) / (oracleDenominator * 100);
      reserve1 = bound(reserve1, reserve1LowerBound, reserve1LowerBound * 5);
    } else {
      uint256 reserve1UpperBound = (reserve0 * oracleNumerator * 90) / (oracleDenominator * 100);

      reserve1 = bound(reserve1, (reserve1UpperBound * 1) / 5, reserve1UpperBound);
    }

    ctx.reserves = LQ.Reserves({ reserveNum: reserve1, reserveDen: reserve0 });

    ctx.prices = LQ.Prices({
      oracleNum: oracleNumerator,
      oracleDen: oracleDenominator,
      poolPriceAbove: poolPriceAbove,
      diffBps: 200
    });
    _;
  }

  /* ---------- Constructor ---------- */

  function test_constructor_whenArrayLengthsMismatch_shouldRevert() public {
    vm.expectRevert(abi.encodeWithSelector(CDPPolicy_CONSTRUCTOR_ARRAY_LENGTH_MISMATCH.selector));
    policy = new CDPPolicy(new address[](2), new address[](0), new address[](0), new uint256[](0), new uint256[](0));
  }

  function test_constructor_shouldSetCorrectState() public {
    address[] memory debtTokens = addresses(address(debtToken6), address(debtToken18));
    address[] memory stabilityPools = addresses(stabilityPool, stabilityPool);
    address[] memory collateralRegistries = addresses(collateralRegistry, collateralRegistry);
    uint256[] memory redemptionBetas = uints(1, 2);
    uint256[] memory stabilityPoolPercentages = uints(100, 200);
    policy = new CDPPolicy(debtTokens, stabilityPools, collateralRegistries, redemptionBetas, stabilityPoolPercentages);
    assertEq(policy.deptTokenStabilityPool(address(debtToken6)), stabilityPool);
    assertEq(policy.deptTokenCollateralRegistry(address(debtToken6)), collateralRegistry);
    assertEq(policy.deptTokenStabilityPool(address(debtToken18)), stabilityPool);
    assertEq(policy.deptTokenCollateralRegistry(address(debtToken18)), collateralRegistry);
    assertEq(policy.deptTokenRedemptionBeta(address(debtToken6)), 1);
    assertEq(policy.deptTokenRedemptionBeta(address(debtToken18)), 2);
    assertEq(policy.deptTokenStabilityPoolPercentage(address(debtToken6)), 100);
    assertEq(policy.deptTokenStabilityPoolPercentage(address(debtToken18)), 200);
  }

  /* ----------- Setters ---------- */

  function test_setDeptTokenStabilityPool_whenNotOwner_shouldRevert() public {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("notOwner"));
    policy.setDeptTokenStabilityPool(address(debtToken6), stabilityPool);
  }

  function test_setDeptTokenStabilityPool_whenCalledByOwner_shouldSucceed() public {
    policy.setDeptTokenStabilityPool(address(debtToken6), makeAddr("newStabilityPool"));
    assertEq(policy.deptTokenStabilityPool(address(debtToken6)), makeAddr("newStabilityPool"));
  }

  function test_setDeptTokenCollateralRegistry_whenNotOwner_shouldRevert() public {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("notOwner"));
    policy.setDeptTokenCollateralRegistry(address(debtToken6), collateralRegistry);
  }

  function test_setDeptTokenCollateralRegistry_whenCalledByOwner_shouldSucceed() public {
    policy.setDeptTokenCollateralRegistry(address(debtToken6), makeAddr("newCollateralRegistry"));
    assertEq(policy.deptTokenCollateralRegistry(address(debtToken6)), makeAddr("newCollateralRegistry"));
  }

  function test_setDeptTokenRedemptionBeta_whenNotOwner_shouldRevert() public {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("notOwner"));
    policy.setDeptTokenRedemptionBeta(address(debtToken6), 1);
  }

  function test_setDeptTokenRedemptionBeta_whenCalledByOwner_shouldSucceed() public {
    policy.setDeptTokenRedemptionBeta(address(debtToken6), 1);
    assertEq(policy.deptTokenRedemptionBeta(address(debtToken6)), 1);
  }

  function test_setDeptTokenStabilityPoolPercentage_whenNotOwner_shouldRevert() public {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("notOwner"));
    policy.setDeptTokenStabilityPoolPercentage(address(debtToken6), 1);
  }

  function test_setDeptTokenStabilityPoolPercentage_whenCalledByOwner_shouldSucceed() public {
    policy.setDeptTokenStabilityPoolPercentage(address(debtToken6), 500);
    assertEq(policy.deptTokenStabilityPoolPercentage(address(debtToken6)), 500);
  }

  function test_setDeptTokenStabilityPoolPercentage_whenInvalidPercentage_shouldRevert() public {
    vm.expectRevert(abi.encodeWithSelector(CDPPolicy_INVALID_STABILITY_POOL_PERCENTAGE.selector));
    policy.setDeptTokenStabilityPoolPercentage(address(debtToken6), 10001);

    vm.expectRevert(abi.encodeWithSelector(CDPPolicy_INVALID_STABILITY_POOL_PERCENTAGE.selector));
    policy.setDeptTokenStabilityPoolPercentage(address(debtToken6), 0);
  }

  /* ---------- Determine Action Math Tests ---------- */

  /* ============================================================ */
  /* ================ Expansion Full liquidity ================== */
  /* ============================================================ */

  function test_whenToken0DebtPoolPriceAboveAndEnoughLiquidityInStabilityPool_shouldExpandAndBringPriceBackToOraclePrice()
    public
    _setUpPolicy(debtToken18, 9000)
  {
    /*
      struct Context {
        address pool;
        Reserves reserves;
        Prices prices;
        address token0;
        address token1;
        uint128 incentiveBps;
        uint64 token0Dec;
        uint64 token1Dec;
        bool isToken0Debt;
    }
  */

    uint256 reserve0 = 1_000_000 * 1e18; // usdfx
    uint256 reserve1 = 1_500_000 * 1e6; // usdc

    LQ.Context memory ctx;

    ctx.token0 = address(debtToken18);
    ctx.token1 = address(collateralToken6);
    ctx.token0Dec = 1e18;
    ctx.token1Dec = 1e6;

    ctx.isToken0Debt = true;
    ctx.reserves = LQ.Reserves({
      reserveNum: reserve1 * 1e12, // reserve token 1 (1M) USDC
      reserveDen: reserve0 // reserve token 0 (1.5M) usdfx
    });
    ctx.pool = fpmm;

    // USDC/USD rate
    ctx.prices = LQ.Prices({
      oracleNum: 999884980000000000,
      oracleDen: 1e18,
      poolPriceAbove: true,
      diffBps: 5_000 // 50%
    });
    ctx.incentiveBps = 50; // 0.5%

    // enough to cover the full expansion
    setStabilityPoolBalance(address(debtToken18), 1_000_000 * 1e18);
    (, LQ.Action memory action) = policy.determineAction(ctx);

    // amount out in token 1 := (OD*RN - ON*RD)/(OD*(2-i)) = 250684.220551
    uint256 expectedAmount1Out = 250684220551;
    uint256 expectedAmount0Out = 0;
    // input amount in token 0 := (amountOut * OD * (1-i))/ON = 249459.492279046935978576
    uint256 expectedInputAmount = 249459492279046935978576;

    assertEq(action.amount1Out, expectedAmount1Out);
    assertEq(action.amount0Out, expectedAmount0Out);
    assertEq(action.inputAmount, expectedInputAmount);
  }

  /* ---------- Determine Action Fuzz Tests ---------- */

  struct FuzzTestContext {
    uint256 stabilityPoolBalance;
    uint256 priceDifferenceBefore;
    uint256 priceDifferenceAfter;
    uint256 reserve0After;
    uint256 reserve1After;
    bool reservePriceAboveOraclePriceBefore;
    bool reservePriceAboveOraclePriceAfter;
  }
  /* ============================================================ */
  /* ================ Expansion Full liquidity ================== */
  /* ============================================================ */

  /// forge-config: default.fuzz.runs = 10000
  function test_FUZZ_whenToken0DebtPoolPriceAboveAndEnoughLiquidityInStabilityPool_shouldExpandAndBringPriceBackToOraclePrice(
    uint256 oracleNumerator,
    uint256 reserve0,
    uint256 reserve1
  ) public _setUpPolicy(debtToken18, 9000) _boundFuzzParams(oracleNumerator, reserve0, reserve1, true) {
    FuzzTestContext memory testContext;

    ctx.pool = fpmm;
    ctx.token0 = address(debtToken18);
    ctx.token1 = address(collateralToken18);
    ctx.token0Dec = 1e18;
    ctx.token1Dec = 1e18;
    ctx.isToken0Debt = true;
    ctx.incentiveBps = 50;

    // enough to cover the full expansion
    testContext.stabilityPoolBalance = 1e18 + (ctx.reserves.reserveNum * ctx.prices.oracleDen) / ctx.prices.oracleNum;
    setStabilityPoolBalance(address(debtToken18), testContext.stabilityPoolBalance);

    (testContext.priceDifferenceBefore, testContext.reservePriceAboveOraclePriceBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );
    assertTrue(testContext.reservePriceAboveOraclePriceBefore);
    assertTrue(testContext.priceDifferenceBefore >= 999); // at least 10% above the oracle price

    (bool shouldAct, LQ.Action memory action) = policy.determineAction(ctx);

    assertTrue(shouldAct);
    assertEq(uint256(action.dir), uint256(LQ.Direction.Expand));
    assertEq(action.amount0Out, 0);
    assertTrue(action.amount1Out > 0);
    assertTrue(action.inputAmount > 0);

    testContext.reserve0After = ctx.reserves.reserveDen + action.inputAmount;
    testContext.reserve1After = ctx.reserves.reserveNum - action.amount1Out;

    (testContext.priceDifferenceAfter, testContext.reservePriceAboveOraclePriceAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      testContext.reserve1After,
      testContext.reserve0After
    );
    assert(testContext.priceDifferenceAfter == 0);
    assertIncentive(
      ctx.incentiveBps,
      false,
      action.amount1Out,
      action.inputAmount,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      false
    );
  }

  /// forge-config: default.fuzz.runs = 10000
  function test_FUZZ_whenToken1DebtPoolPriceBelowAndEnoughLiquidityInStabilityPool_shouldExpandAndBringPriceBackToOraclePrice(
    uint256 oracleNumerator,
    uint256 reserve0,
    uint256 reserve1
  ) public _setUpPolicy(debtToken18, 9000) _boundFuzzParams(oracleNumerator, reserve0, reserve1, false) {
    FuzzTestContext memory testContext;
    ctx.pool = fpmm;
    ctx.token0 = address(collateralToken6);
    ctx.token1 = address(debtToken18);
    ctx.token0Dec = 1e6;
    ctx.token1Dec = 1e18;
    ctx.isToken0Debt = false;
    ctx.incentiveBps = 50;

    testContext.stabilityPoolBalance = 1e18 + (ctx.reserves.reserveDen * ctx.prices.oracleNum) / ctx.prices.oracleDen;
    setStabilityPoolBalance(address(debtToken18), testContext.stabilityPoolBalance);

    (testContext.priceDifferenceBefore, testContext.reservePriceAboveOraclePriceBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );
    assertTrue(!testContext.reservePriceAboveOraclePriceBefore);
    assertTrue(testContext.priceDifferenceBefore >= 999); // at least 10% above the oracle price

    (bool shouldAct, LQ.Action memory action) = policy.determineAction(ctx);

    assertTrue(shouldAct);
    assertEq(uint256(action.dir), uint256(LQ.Direction.Expand));
    assertTrue(action.amount0Out > 0);
    assertTrue(action.amount1Out == 0);
    assertTrue(action.inputAmount > 0);

    testContext.reserve0After = ctx.reserves.reserveDen - action.amount0Out * (1e18 / ctx.token0Dec);
    testContext.reserve1After = ctx.reserves.reserveNum + action.inputAmount;

    (testContext.priceDifferenceAfter, testContext.reservePriceAboveOraclePriceAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      testContext.reserve1After,
      testContext.reserve0After
    );
    assert(testContext.priceDifferenceAfter == 0);
    assertIncentive(
      ctx.incentiveBps,
      true,
      action.amount0Out * (1e18 / ctx.token0Dec),
      action.inputAmount,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      false
    );
  }

  /* ============================================================ */
  /* ============== Expansion Partial liquidity ================= */
  /* ============================================================ */

  /// forge-config: default.fuzz.runs = 10000
  function test_FUZZ_whenToken0DebtPoolPriceAboveAndLimitedLiquidityInStabilityPool_shouldExpandAndBringPriceCloserToOraclePrice(
    uint256 oracleNumerator,
    uint256 reserve0,
    uint256 reserve1
  ) public _setUpPolicy(debtToken6, 9000) _boundFuzzParams(oracleNumerator, reserve0, reserve1, true) {
    FuzzTestContext memory testContext;

    ctx.pool = fpmm;
    ctx.token0 = address(debtToken6);
    ctx.token1 = address(collateralToken18);
    ctx.token0Dec = 1e6;
    ctx.token1Dec = 1e18;
    ctx.isToken0Debt = true;
    ctx.incentiveBps = 50;

    // enough to cover the full expansion
    testContext.stabilityPoolBalance = calculateTargetStabilityPoolBalance(ctx, 0.9e18); // stability pool holds 90% of target amount to rebalance fully
    setStabilityPoolBalance(address(debtToken6), testContext.stabilityPoolBalance);

    (testContext.priceDifferenceBefore, testContext.reservePriceAboveOraclePriceBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );
    assert(testContext.reservePriceAboveOraclePriceBefore);
    assert(testContext.priceDifferenceBefore >= 999); // at least 10% above the oracle price

    (bool shouldAct, LQ.Action memory action) = policy.determineAction(ctx);

    assert(shouldAct);
    assertEq(uint256(action.dir), uint256(LQ.Direction.Expand));
    assertEq(action.amount0Out, 0);
    assertTrue(action.amount1Out > 0);
    assertTrue(action.inputAmount > 0);

    testContext.reserve0After = ctx.reserves.reserveDen + action.inputAmount;
    testContext.reserve1After = ctx.reserves.reserveNum - action.amount1Out;

    (testContext.priceDifferenceAfter, testContext.reservePriceAboveOraclePriceAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      testContext.reserve1After,
      testContext.reserve0After
    );
    // price difference should be greater than 0
    assert(testContext.priceDifferenceAfter < testContext.priceDifferenceBefore);
    // reserve price should be still above oracle price
    assert(testContext.reservePriceAboveOraclePriceAfter);
    assertIncentive(
      ctx.incentiveBps,
      false,
      action.amount1Out,
      action.inputAmount * (1e18 / ctx.token0Dec),
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      false
    );
  }

  /// forge-config: default.fuzz.runs = 10000
  function test_FUZZ_whenToken1DebtPoolPriceBelowAndLimitedLiquidityInStabilityPool_shouldExpandAndBringPriceCloserToOraclePrice(
    uint256 oracleNumerator,
    uint256 reserve0,
    uint256 reserve1
  ) public _setUpPolicy(debtToken6, 9000) _boundFuzzParams(oracleNumerator, reserve0, reserve1, false) {
    FuzzTestContext memory testContext;
    ctx.pool = fpmm;
    ctx.token0 = address(collateralToken18);
    ctx.token1 = address(debtToken6);
    ctx.token0Dec = 1e18;
    ctx.token1Dec = 1e6;
    ctx.isToken0Debt = false;
    ctx.incentiveBps = 50;

    testContext.stabilityPoolBalance = calculateTargetStabilityPoolBalance(ctx, 0.8e18); // stability pool holds 90% of target amount to rebalance fully
    setStabilityPoolBalance(address(debtToken6), testContext.stabilityPoolBalance);

    (testContext.priceDifferenceBefore, testContext.reservePriceAboveOraclePriceBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );
    assert(!testContext.reservePriceAboveOraclePriceBefore);
    assert(testContext.priceDifferenceBefore >= 999); // at least 10% above the oracle price

    (bool shouldAct, LQ.Action memory action) = policy.determineAction(ctx);

    assert(shouldAct);
    assertEq(uint256(action.dir), uint256(LQ.Direction.Expand));
    assert(action.amount0Out > 0);
    assert(action.amount1Out == 0);
    assert(action.inputAmount > 0);

    testContext.reserve0After = ctx.reserves.reserveDen - action.amount0Out;
    testContext.reserve1After = ctx.reserves.reserveNum + action.inputAmount * (1e18 / ctx.token1Dec);

    (testContext.priceDifferenceAfter, testContext.reservePriceAboveOraclePriceAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      testContext.reserve1After,
      testContext.reserve0After
    );
    // price difference should be less than before
    assert(testContext.priceDifferenceAfter < testContext.priceDifferenceBefore);
    assert(0 < testContext.priceDifferenceAfter);
    // reserve price should still be below oracle price
    assert(!testContext.reservePriceAboveOraclePriceAfter);
    assertIncentive(
      ctx.incentiveBps,
      true,
      action.amount0Out,
      action.inputAmount * (1e18 / ctx.token1Dec),
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      false
    );
  }

  /* ============================================================ */
  /* =============== Contraction target liquidity =============== */
  /* ============================================================ */

  /// forge-config: default.fuzz.runs = 10000
  function test_FUZZ_whenToken0DebtPoolPriceBelowAndRedemptionFeeEqualToIncentive_shouldContractAndBringPriceBackToOraclePrice(
    uint256 oracleNumerator,
    uint256 reserve0,
    uint256 reserve1
  ) public _setUpPolicy(debtToken18, 9000) _boundFuzzParams(oracleNumerator, reserve0, reserve1, false) {
    FuzzTestContext memory testContext;

    ctx.pool = fpmm;
    ctx.token0 = address(debtToken18);
    ctx.token1 = address(collateralToken6);
    ctx.token0Dec = 1e18;
    ctx.token1Dec = 1e6;
    ctx.isToken0Debt = true;
    ctx.incentiveBps = 50;

    (testContext.priceDifferenceBefore, testContext.reservePriceAboveOraclePriceBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );

    assert(!testContext.reservePriceAboveOraclePriceBefore);
    assert(testContext.priceDifferenceBefore >= 999); // at least 10% above the oracle price

    mockGetRedemptionRateWithDecay(0.0025 * 1e18); // 0.25%
    // ensure redemption fractions is below 0.25% resulting in total redemption fee less than 0.5%
    uint256 totalSupply = calculateTargetSupply(ctx, 0.0025 * 1e18);
    setTokenTotalSupply(address(debtToken18), totalSupply);

    (bool shouldAct, LQ.Action memory action) = policy.determineAction(ctx);

    assertTrue(shouldAct);
    assertEq(uint256(action.dir), uint256(LQ.Direction.Contract));
    assert(action.amount0Out > 0);
    assert(action.amount1Out == 0);
    assert(action.inputAmount > 0);

    testContext.reserve0After = ctx.reserves.reserveDen - action.amount0Out;
    testContext.reserve1After = ctx.reserves.reserveNum + action.inputAmount * (1e18 / ctx.token1Dec);

    (testContext.priceDifferenceAfter, testContext.reservePriceAboveOraclePriceAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      testContext.reserve1After,
      testContext.reserve0After
    );

    // price difference should be less than before
    assert(testContext.priceDifferenceAfter == 0);
    assertIncentive(
      ctx.incentiveBps,
      true,
      action.amount0Out,
      action.inputAmount * (1e18 / ctx.token1Dec),
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      false
    );
  }

  /// forge-config: default.fuzz.runs = 10000
  function test_FUZZ_whenToken1DebtPoolPriceAboveAndRedemptionFeeEqualToIncentive_shouldContractAndBringPriceBackToOraclePrice(
    uint256 oracleNumerator,
    uint256 reserve0,
    uint256 reserve1
  ) public _setUpPolicy(debtToken6, 9000) _boundFuzzParams(oracleNumerator, reserve0, reserve1, true) {
    FuzzTestContext memory testContext;

    ctx.pool = fpmm;
    ctx.token0 = address(collateralToken18);
    ctx.token1 = address(debtToken6);
    ctx.token0Dec = 1e18;
    ctx.token1Dec = 1e6;
    ctx.isToken0Debt = false;
    ctx.incentiveBps = 50;

    (testContext.priceDifferenceBefore, testContext.reservePriceAboveOraclePriceBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );

    assert(testContext.reservePriceAboveOraclePriceBefore);
    assert(testContext.priceDifferenceBefore >= 999); // at least 10% above the oracle price

    mockGetRedemptionRateWithDecay(0.0025 * 1e18); // 0.25%
    uint256 totalSupply = calculateTargetSupply(ctx, 0.0025 * 1e18);
    setTokenTotalSupply(address(debtToken6), totalSupply);

    (bool shouldAct, LQ.Action memory action) = policy.determineAction(ctx);
    assertTrue(shouldAct);
    assertEq(uint256(action.dir), uint256(LQ.Direction.Contract));
    assert(action.amount0Out == 0);
    assert(action.amount1Out > 0);
    assert(action.inputAmount > 0);

    testContext.reserve0After = ctx.reserves.reserveDen + action.inputAmount;
    testContext.reserve1After = ctx.reserves.reserveNum - action.amount1Out * (1e18 / ctx.token1Dec);

    (testContext.priceDifferenceAfter, testContext.reservePriceAboveOraclePriceAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      testContext.reserve1After,
      testContext.reserve0After
    );
    assert(testContext.priceDifferenceAfter == 0);
    assertIncentive(
      ctx.incentiveBps,
      false,
      action.amount1Out * (1e18 / ctx.token1Dec),
      action.inputAmount,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      false
    );
  }

  /* ============================================================ */
  /* ============== Contraction non-target liquidity ============ */
  /* ============================================================ */

  /// forge-config: default.fuzz.runs = 10000
  function test_FUZZ_whenToken0DebtPoolPriceBelowAndRedemptionFeeLessIncentive_shouldContractAndBringPriceAboveOraclePrice(
    uint256 oracleNumerator,
    uint256 reserve0,
    uint256 reserve1
  ) public _setUpPolicy(debtToken18, 9000) _boundFuzzParams(oracleNumerator, reserve0, reserve1, false) {
    FuzzTestContext memory testContext;

    ctx.pool = fpmm;
    ctx.token0 = address(debtToken18);
    ctx.token1 = address(collateralToken6);
    ctx.token0Dec = 1e18;
    ctx.token1Dec = 1e6;
    ctx.isToken0Debt = true;
    ctx.incentiveBps = 50;

    (testContext.priceDifferenceBefore, testContext.reservePriceAboveOraclePriceBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );

    assert(!testContext.reservePriceAboveOraclePriceBefore);
    assert(testContext.priceDifferenceBefore >= 999); // at least 10% above the oracle price

    mockGetRedemptionRateWithDecay(0.0025 * 1e18); // 0.25%
    uint256 totalSupply = calculateTargetSupply(ctx, 0.001 * 1e18); // 0.1% resulting in redemption fee beeing 0.25% + 0.1% = 0.35%
    setTokenTotalSupply(address(debtToken18), totalSupply);

    (bool shouldAct, LQ.Action memory action) = policy.determineAction(ctx);
    assertTrue(shouldAct);
    assertEq(uint256(action.dir), uint256(LQ.Direction.Contract));
    assert(action.amount0Out > 0);
    assert(action.amount1Out == 0);
    assert(action.inputAmount > 0);

    testContext.reserve0After = ctx.reserves.reserveDen - action.amount0Out;
    testContext.reserve1After = ctx.reserves.reserveNum + action.inputAmount * (1e18 / ctx.token1Dec);

    (testContext.priceDifferenceAfter, testContext.reservePriceAboveOraclePriceAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      testContext.reserve1After,
      testContext.reserve0After
    );
    assert(testContext.priceDifferenceAfter >= 0);
    assert(testContext.reservePriceAboveOraclePriceAfter);
    assertIncentive(
      ctx.incentiveBps,
      true,
      action.amount0Out,
      action.inputAmount * (1e18 / ctx.token1Dec),
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      true
    );
  }

  /// forge-config: default.fuzz.runs = 10000
  function test_FUZZ_whenToken0DebtPoolPriceBelowAndRedemptionFeeMoreThanIncentive_shouldContractAndBringPriceCloserToOraclePrice(
    uint256 oracleNumerator,
    uint256 reserve0,
    uint256 reserve1
  ) public _setUpPolicy(debtToken6, 9000) _boundFuzzParams(oracleNumerator, reserve0, reserve1, false) {
    FuzzTestContext memory testContext;

    ctx.pool = fpmm;
    ctx.token0 = address(debtToken6);
    ctx.token1 = address(collateralToken18);
    ctx.token0Dec = 1e6;
    ctx.token1Dec = 1e18;
    ctx.isToken0Debt = true;
    ctx.incentiveBps = 50;

    (testContext.priceDifferenceBefore, testContext.reservePriceAboveOraclePriceBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );

    assert(!testContext.reservePriceAboveOraclePriceBefore);
    assert(testContext.priceDifferenceBefore >= 999); // at least 10% above the oracle price

    mockGetRedemptionRateWithDecay(0.0025 * 1e18); // 0.25%
    uint256 totalSupply = calculateTargetSupply(ctx, 0.003 * 1e18); // 0.3% resulting in redemption fee beeing 0.25% + 0.3% = 0.55%
    setTokenTotalSupply(address(debtToken6), totalSupply);

    (bool shouldAct, LQ.Action memory action) = policy.determineAction(ctx);
    assertTrue(shouldAct);
    assertEq(uint256(action.dir), uint256(LQ.Direction.Contract));
    assert(action.amount0Out > 0);
    assert(action.amount1Out == 0);
    assert(action.inputAmount > 0);

    testContext.reserve0After = ctx.reserves.reserveDen - action.amount0Out * (1e18 / ctx.token0Dec);
    testContext.reserve1After = ctx.reserves.reserveNum + action.inputAmount;

    (testContext.priceDifferenceAfter, testContext.reservePriceAboveOraclePriceAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      testContext.reserve1After,
      testContext.reserve0After
    );
    assert(testContext.priceDifferenceAfter >= 0);
    assert(!testContext.reservePriceAboveOraclePriceAfter);
    assertIncentive(
      ctx.incentiveBps,
      true,
      action.amount0Out * (1e18 / ctx.token0Dec),
      action.inputAmount,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      false
    );
  }

  /// forge-config: default.fuzz.runs = 10000
  function test_FUZZ_whenToken1DebtPoolPriceAboveAndRedemptionFeeLessIncentive_shouldContractAndBringPriceBelowOraclePrice(
    uint256 oracleNumerator,
    uint256 reserve0,
    uint256 reserve1
  ) public _setUpPolicy(debtToken18, 9000) _boundFuzzParams(oracleNumerator, reserve0, reserve1, true) {
    FuzzTestContext memory testContext;

    ctx.pool = fpmm;
    ctx.token0 = address(collateralToken6);
    ctx.token1 = address(debtToken18);
    ctx.token0Dec = 1e6;
    ctx.token1Dec = 1e18;
    ctx.isToken0Debt = false;
    ctx.incentiveBps = 50;

    (testContext.priceDifferenceBefore, testContext.reservePriceAboveOraclePriceBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );

    assert(testContext.reservePriceAboveOraclePriceBefore);
    assert(testContext.priceDifferenceBefore >= 999); // at least 10% above the oracle price

    mockGetRedemptionRateWithDecay(0.0025 * 1e18); // 0.25%
    uint256 totalSupply = calculateTargetSupply(ctx, 0.001 * 1e18); // 0.1% resulting in redemption fee beeing 0.25% + 0.1% = 0.35%
    setTokenTotalSupply(address(debtToken18), totalSupply);

    (bool shouldAct, LQ.Action memory action) = policy.determineAction(ctx);
    assertTrue(shouldAct);
    assertEq(uint256(action.dir), uint256(LQ.Direction.Contract));
    assert(action.amount0Out == 0);
    assert(action.amount1Out > 0);
    assert(action.inputAmount > 0);

    testContext.reserve0After = ctx.reserves.reserveDen + action.inputAmount * (1e18 / ctx.token0Dec);
    testContext.reserve1After = ctx.reserves.reserveNum - action.amount1Out * (1e18 / ctx.token1Dec);

    (testContext.priceDifferenceAfter, testContext.reservePriceAboveOraclePriceAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      testContext.reserve1After,
      testContext.reserve0After
    );
    assert(testContext.priceDifferenceAfter >= 0);
    assert(!testContext.reservePriceAboveOraclePriceAfter);
    assertIncentive(
      ctx.incentiveBps,
      false,
      action.amount1Out,
      action.inputAmount * (1e18 / ctx.token0Dec),
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      true
    );
  }

  /// forge-config: default.fuzz.runs = 10000
  function test_FUZZ_whenToken1DebtPoolPriceAboveAndRedemptionFeeMoreThanIncentive_shouldContractAndBringPriceCloserToOraclePrice(
    uint256 oracleNumerator,
    uint256 reserve0,
    uint256 reserve1
  ) public _setUpPolicy(debtToken18, 9000) _boundFuzzParams(oracleNumerator, reserve0, reserve1, true) {
    FuzzTestContext memory testContext;

    ctx.pool = fpmm;
    ctx.token0 = address(collateralToken6);
    ctx.token1 = address(debtToken18);
    ctx.token0Dec = 1e6;
    ctx.token1Dec = 1e18;
    ctx.isToken0Debt = false;
    ctx.incentiveBps = 50;

    (testContext.priceDifferenceBefore, testContext.reservePriceAboveOraclePriceBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );

    assert(testContext.reservePriceAboveOraclePriceBefore);
    assert(testContext.priceDifferenceBefore >= 999); // at least 10% above the oracle price

    mockGetRedemptionRateWithDecay(0.0025 * 1e18); // 0.25%
    uint256 totalSupply = calculateTargetSupply(ctx, 0.003 * 1e18); // 0.3% resulting in redemption fee beeing 0.25% + 0.3% = 0.55%
    setTokenTotalSupply(address(debtToken18), totalSupply);

    (bool shouldAct, LQ.Action memory action) = policy.determineAction(ctx);
    assertTrue(shouldAct);
    assertEq(uint256(action.dir), uint256(LQ.Direction.Contract));
    assert(action.amount0Out == 0);
    assert(action.amount1Out > 0);
    assert(action.inputAmount > 0);

    testContext.reserve0After = ctx.reserves.reserveDen + action.inputAmount * (1e18 / ctx.token0Dec);
    testContext.reserve1After = ctx.reserves.reserveNum - action.amount1Out * (1e18 / ctx.token1Dec);

    (testContext.priceDifferenceAfter, testContext.reservePriceAboveOraclePriceAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      testContext.reserve1After,
      testContext.reserve0After
    );
    assert(testContext.priceDifferenceAfter < testContext.priceDifferenceBefore);
    assert(testContext.reservePriceAboveOraclePriceAfter);
    assertIncentive(
      ctx.incentiveBps,
      false,
      action.amount1Out,
      action.inputAmount * (1e18 / ctx.token0Dec),
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      false
    );
  }

  /* ============================================================ */

  function test_whenPoolPriceAboveAndToken0Debt_() public {
    /*
      struct Context {
        address pool;
        Reserves reserves;
        Prices prices;
        address token0;
        address token1;
        uint128 incentiveBps;
        uint64 token0Dec;
        uint64 token1Dec;
        bool isToken0Debt;
    }
  */
    uint256 reserve0 = 1_000_000 * 1e18; // usdfx
    uint256 reserve1 = 1_500_000 * 1e6; // usdc

    LQ.Context memory ctx;

    ctx.token0 = address(debtToken18);
    ctx.token1 = address(collateralToken6);
    ctx.token0Dec = 1e18;
    ctx.token1Dec = 1e6;

    ctx.isToken0Debt = true;
    ctx.reserves = LQ.Reserves({
      reserveNum: reserve1 * 1e12, // reserve token 1 (1M) USDC
      reserveDen: reserve0 // reserve token 0 (1.5M) usdfx
    });

    ctx.pool = fpmm;

    ctx.prices = LQ.Prices({
      oracleNum: 999884980000000000,
      oracleDen: 1e18,
      poolPriceAbove: true,
      diffBps: 5_000 // 50%
    });
    ctx.incentiveBps = 50; // 0.5%

    policy.setDeptTokenStabilityPool(address(debtToken18), stabilityPool);
    policy.setDeptTokenCollateralRegistry(address(debtToken18), collateralRegistry);
    policy.setDeptTokenRedemptionBeta(address(debtToken18), 1);
    policy.setDeptTokenStabilityPoolPercentage(address(debtToken18), 9000); // 90%

    // enough to cover the full expansion
    setStabilityPoolBalance(address(debtToken18), 1_000_000 * 1e18);
    setStabilityPoolMinBoldAfterRebalance(1e18);

    (, LQ.Action memory action) = policy.determineAction(ctx);

    reserve0 -= action.amount0Out;
    reserve1 -= action.amount1Out;
    reserve0 += action.inputAmount;

    assertEq(uint256(action.dir), uint256(LQ.Direction.Expand));
    assertEq(action.amount0Out, 0);
  }

  function test_whenPoolPriceBelow() public {
    LQ.Context memory ctx;
    ctx.pool = fpmm;

    uint256 reserve0 = 1_500_000 * 1e18; // usdfx
    console.log("reserve0", reserve0);
    uint256 reserve1 = 1_000_000 * 1e6; // usdc
    console.log("reserve1", reserve1);
    ctx.reserves = LQ.Reserves({
      reserveNum: reserve1 * 1e12, // reserve token 1 (1M) USDC
      reserveDen: reserve0 // reserve token 0 (1.5M) usdfx
    });

    ctx.prices = LQ.Prices({
      oracleNum: 999884980000000000,
      oracleDen: 1e18,
      poolPriceAbove: false,
      diffBps: 1_000 // 10%
    });

    ctx.token0 = address(debtToken18);
    ctx.token1 = address(collateralToken6);
    ctx.incentiveBps = 50; // 0.5%
    ctx.token0Dec = 1e18;
    ctx.token1Dec = 1e6;
    ctx.isToken0Debt = true;

    policy.setDeptTokenStabilityPool(address(debtToken18), stabilityPool);
    policy.setDeptTokenCollateralRegistry(address(debtToken18), collateralRegistry);
    policy.setDeptTokenRedemptionBeta(address(debtToken18), 1);
    setTokenTotalSupply(address(debtToken18), 10_000_000 * 1e18);
    mockGetRedemptionRateWithDecay(3e15); // 0.3%

    setStabilityPoolBalance(address(collateralToken6), 100_000 * 1e6);

    (, LQ.Action memory action) = policy.determineAction(ctx);

    reserve0 -= action.amount0Out;
    reserve1 -= action.amount1Out;
    uint256 inputAmount = (action.inputAmount * (10_000 - action.incentiveBps)) / 10_000;
    reserve0 += inputAmount;
  }

  /* ============================================================ */
  /* ==================== Helper Functions ====================== */
  /* ============================================================ */

  /**
   * @notice Set the minimum balance of the stability pool after rebalance
   * @param minBalance The minimum balance of the stability pool after rebalance
   */
  function setStabilityPoolMinBoldAfterRebalance(uint256 minBalance) public {
    console.log("minBalance", minBalance);
    vm.mockCall(
      address(stabilityPool),
      abi.encodeWithSelector(IStabilityPool.MIN_BOLD_AFTER_REBALANCE.selector),
      abi.encode(minBalance)
    );
  }

  /**
   * @notice Set the balance of the stability pool
   * @param token The address of the token
   * @param balance The balance of the stability pool
   */
  function setStabilityPoolBalance(address token, uint256 balance) public {
    MockERC20(token).setBalance(stabilityPool, balance);
  }

  /**
   * @notice Set the total supply of a token
   * @param token The address of the token
   * @param totalSupply The total supply of the token
   */
  function setTokenTotalSupply(address token, uint256 totalSupply) public {
    MockERC20(token).setTotalSupply(totalSupply);
  }

  /**
   * @notice Mock the redemption rate with decay
   * @param redemptionRate The redemption rate with decay
   */
  function mockGetRedemptionRateWithDecay(uint256 redemptionRate) public {
    vm.mockCall(
      address(collateralRegistry),
      abi.encodeWithSelector(ICollateralRegistry.getRedemptionRateWithDecay.selector),
      abi.encode(redemptionRate)
    );
  }

  /**
   * @notice Calculate the price difference between the oracle price and the reserve price
   * @param oracleNumerator The numerator of the oracle price
   * @param oracleDenominator The denominator of the oracle price
   * @param reserveNumerator The numerator of the reserve price
   * @param reserveDenominator The denominator of the reserve price
   * @return priceDifference The price difference in bps
   * @return reservePriceAboveOraclePrice True if the reserve price is above the oracle price, false otherwise
   */
  function calculatePriceDifference(
    uint256 oracleNumerator,
    uint256 oracleDenominator,
    uint256 reserveNumerator,
    uint256 reserveDenominator
  ) internal view returns (uint256 priceDifference, bool reservePriceAboveOraclePrice) {
    uint256 oracleCrossProduct = oracleNumerator * reserveDenominator;
    uint256 reserveCrossProduct = reserveNumerator * oracleDenominator;

    reservePriceAboveOraclePrice = reserveCrossProduct > oracleCrossProduct;
    uint256 absolutePriceDiff = reservePriceAboveOraclePrice
      ? reserveCrossProduct - oracleCrossProduct
      : oracleCrossProduct - reserveCrossProduct;
    priceDifference = (absolutePriceDiff * LQ.BASIS_POINTS_DENOMINATOR) / oracleCrossProduct;
  }

  /**
   * @notice Assert the incentive is within the allowed range
   * @param incentiveBps The incentive in bps
   * @param isToken0Out True if the token taken out is token0, false otherwise
   * @param amountOut The amount of the token taken out
   * @param amountIn The amount of the token added
   * @param oracleNumerator The numerator of the oracle price
   * @param oracleDenominator The denominator of the oracle price
   * @param isCheapContraction True if the rebalance is a cheap contraction (redemption fee with less than 50bps)
   */
  function assertIncentive(
    uint256 incentiveBps,
    bool isToken0Out,
    uint256 amountOut,
    uint256 amountIn,
    uint256 oracleNumerator,
    uint256 oracleDenominator,
    bool isCheapContraction
  ) public {
    uint256 amountOutInOtherToken;
    if (isToken0Out) {
      amountOutInOtherToken = (amountOut * oracleNumerator) / oracleDenominator;
    } else {
      amountOutInOtherToken = (amountOut * oracleDenominator) / oracleNumerator;
    }
    uint256 incentive = ((amountOutInOtherToken - amountIn) * 10_000) / amountOutInOtherToken;
    // we allow 1bp difference due to rounding
    if (isCheapContraction) {
      assert(incentive <= incentiveBps);
    } else {
      assertApproxEqAbs(incentive, incentiveBps, 1);
    }
  }

  /**
   * @notice Calculate the target supply such that the redemption fraction is equal to the target fraction
   * @param ctx The context of the policy
   * @param targetFraction the redemption fraction to target
   * @return targetSupply
   */
  function calculateTargetSupply(
    LQ.Context memory ctx,
    uint256 targetFraction
  ) internal view returns (uint256 targetSupply) {
    uint256 amountOut;
    if (ctx.prices.poolPriceAbove) {
      uint256 numerator = ctx.prices.oracleDen *
        ctx.reserves.reserveNum -
        ctx.prices.oracleNum *
        ctx.reserves.reserveDen;
      uint256 denominator = (ctx.prices.oracleDen * (2 * LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps)) /
        LQ.BASIS_POINTS_DENOMINATOR;
      amountOut = LQ.convertWithRateScaling(1, 1e18, ctx.token1Dec, numerator, denominator);
    } else {
      uint256 numerator = ctx.prices.oracleNum *
        ctx.reserves.reserveDen -
        ctx.prices.oracleDen *
        ctx.reserves.reserveNum;
      uint256 denominator = (ctx.prices.oracleNum * (2 * LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps)) /
        LQ.BASIS_POINTS_DENOMINATOR;

      amountOut = LQ.convertWithRateScaling(1, 1e18, ctx.token0Dec, numerator, denominator);
    }

    targetSupply = (amountOut * 1e18) / targetFraction;
  }

  /**
   * @notice Calculate the stability pool balance in order to cover a percentage of the target amount needed to rebalance
   * @param ctx The context of the policy
   * @param stabilityPoolPercentage The percentage of the target amount to calculate
   * @return stabilityPoolBalance
   */
  function calculateTargetStabilityPoolBalance(
    LQ.Context memory ctx,
    uint256 stabilityPoolPercentage
  ) internal view returns (uint256 stabilityPoolBalance) {
    if (ctx.prices.poolPriceAbove) {
      uint256 numerator = ctx.prices.oracleDen *
        ctx.reserves.reserveNum -
        ctx.prices.oracleNum *
        ctx.reserves.reserveDen;
      uint256 denominator = (ctx.prices.oracleDen * (2 * LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps)) /
        LQ.BASIS_POINTS_DENOMINATOR;
      uint256 amountOut = LQ.convertWithRateScaling(1, 1e18, ctx.token1Dec, numerator, denominator);

      stabilityPoolBalance = LQ.convertWithRateScalingAndFee(
        amountOut,
        ctx.token1Dec,
        ctx.token0Dec,
        ctx.prices.oracleDen,
        ctx.prices.oracleNum,
        LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps,
        LQ.BASIS_POINTS_DENOMINATOR
      );
    } else {
      uint256 numerator = ctx.prices.oracleNum *
        ctx.reserves.reserveDen -
        ctx.prices.oracleDen *
        ctx.reserves.reserveNum;
      uint256 denominator = (ctx.prices.oracleNum * (2 * LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps)) /
        LQ.BASIS_POINTS_DENOMINATOR;

      uint256 amountOut = LQ.convertWithRateScaling(1, 1e18, ctx.token0Dec, numerator, denominator);

      stabilityPoolBalance = LQ.convertWithRateScalingAndFee(
        amountOut,
        ctx.token0Dec,
        ctx.token1Dec,
        ctx.prices.oracleNum,
        ctx.prices.oracleDen,
        LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps,
        LQ.BASIS_POINTS_DENOMINATOR
      );
    }
    address debtToken = ctx.isToken0Debt ? ctx.token0 : ctx.token1;
    stabilityPoolBalance = (stabilityPoolBalance * stabilityPoolPercentage) / 1e18;
    uint256 a = IStabilityPool(stabilityPool).MIN_BOLD_AFTER_REBALANCE() + stabilityPoolBalance;
    uint256 b = (stabilityPoolBalance *
      LQ.BASIS_POINTS_DENOMINATOR +
      policy.deptTokenStabilityPoolPercentage(debtToken) -
      1) / LQ.BASIS_POINTS_DENOMINATOR;

    // take the higher of the two
    stabilityPoolBalance = a > b ? a : b;
  }
}
