// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;
// solhint-disable max-line-length

import { CDPPolicy } from "contracts/v3/CDPPolicy.sol";
import { ICDPPolicy } from "contracts/v3/Interfaces/ICDPPolicy.sol";
import { LiquidityTypes as LQ } from "contracts/v3/libraries/LiquidityTypes.sol";
import { ICollateralRegistry } from "bold/Interfaces/ICollateralRegistry.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";
import { IStabilityPool } from "bold/Interfaces/IStabilityPool.sol";
import { uints, addresses } from "mento-std/Array.sol";
import { Test } from "forge-std/Test.sol";

contract CDPPolicyTest is Test {
  /* ========== VARIABLES ========== */

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
    policy = new CDPPolicy(
      address(this),
      new address[](0),
      new address[](0),
      new address[](0),
      new uint256[](0),
      new uint256[](0)
    );
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

  function test_constructor_whenConstructorArrayLengthMismatch_shouldRevert() public {
    vm.expectRevert(abi.encodeWithSelector(ICDPPolicy.CDPPolicy_ConstructorArrayLengthMismatch.selector));
    policy = new CDPPolicy(
      address(this),
      new address[](2),
      new address[](0),
      new address[](0),
      new uint256[](0),
      new uint256[](0)
    );
  }

  function test_constructor_shouldSetCorrectState() public {
    address[] memory debtTokens = addresses(address(debtToken6), address(debtToken18));
    address[] memory stabilityPools = addresses(stabilityPool, stabilityPool);
    address[] memory collateralRegistries = addresses(collateralRegistry, collateralRegistry);
    uint256[] memory redemptionBetas = uints(1, 2);
    uint256[] memory stabilityPoolPercentages = uints(100, 200);
    policy = new CDPPolicy(
      address(this),
      debtTokens,
      stabilityPools,
      collateralRegistries,
      redemptionBetas,
      stabilityPoolPercentages
    );
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
    vm.expectRevert(abi.encodeWithSelector(ICDPPolicy.CDPPolicy_InvalidStabilityPoolPercentage.selector));
    policy.setDeptTokenStabilityPoolPercentage(address(debtToken6), 10001);

    vm.expectRevert(abi.encodeWithSelector(ICDPPolicy.CDPPolicy_InvalidStabilityPoolPercentage.selector));
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
    uint256 reserve0 = 1_000_000 * 1e18; // usdfx
    uint256 reserve1 = 1_500_000 * 1e6; // usdc

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

  function test_whenToken1DebtPoolPriceBelowAndEnoughLiquidityInStabilityPool_shouldExpandAndBringPriceBackToOraclePrice()
    public
    _setUpPolicy(debtToken6, 9000)
  {
    uint256 reserve0 = 1_300_000 * 1e18; // usdm
    uint256 reserve1 = 1_000_000 * 1e6; // eurm

    ctx.token0 = address(collateralToken18);
    ctx.token1 = address(debtToken6);
    ctx.token0Dec = 1e18;
    ctx.token1Dec = 1e6;

    ctx.isToken0Debt = false;
    ctx.reserves = LQ.Reserves({
      reserveNum: reserve1 * 1e12, // reserve token 1 (1M) EURM
      reserveDen: reserve0 // reserve token 0 (1.3M) USDM
    });
    ctx.pool = fpmm;

    // USDC/USD rate
    ctx.prices = LQ.Prices({
      oracleNum: 863549230000000000000000 / 1e6, // USDC/EUR rate
      oracleDen: 1e18,
      poolPriceAbove: false,
      diffBps: 5_000 // 50%
    });
    ctx.incentiveBps = 50; // 0.5%

    // enough to cover the full expansion
    setStabilityPoolBalance(address(debtToken6), 1_000_000 * 1e6);
    (, LQ.Action memory action) = policy.determineAction(ctx);

    // amount out in token 0 := (ON*RD-OD*RN)/(ON*(2-i)) = 71172.145133890686084197
    uint256 expectedAmount0Out = 71172145133890686084197;
    uint256 expectedAmount1Out = 0;
    // input amount in token 1 := (amountOut * ON * (1-i))/OD = 61153.347872

    uint256 expectedInputAmount = 61153347872;

    assertEq(action.amount1Out, expectedAmount1Out);
    assertEq(action.amount0Out, expectedAmount0Out);
    assertEq(action.inputAmount, expectedInputAmount);
  }

  /* ============================================================ */
  /* ============== Expansion Partial liquidity ================= */
  /* ============================================================ */

  function test_whenToken0DebtPoolPriceAboveAndNotEnoughLiquidityInStabilityPool_shouldExpandAndBringPriceCloserToOraclePrice()
    public
    _setUpPolicy(debtToken18, 9000)
  {
    uint256 reserve0 = 1_000_000 * 1e18; // usdfx
    uint256 reserve1 = 1_500_000 * 1e6; // usdc

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

    // enough to cover 90% of the target amount
    uint256 stabilityPoolBalance = calculateTargetStabilityPoolBalance(0.9e18);
    setStabilityPoolBalance(address(debtToken18), stabilityPoolBalance);
    (, LQ.Action memory action) = policy.determineAction(ctx);

    // target amount out in token 1 := (OD*RN - ON*RD)/(OD*(2-i)) = 250684.220551
    // since we only have limited liquidity:
    // amount out in token 1 := (224513.5430511422423807184 * ON * 1) / (OD * (1-i)) = 225615.798495
    uint256 expectedAmount1Out = 225615798495;
    uint256 expectedAmount0Out = 0;
    // input amount in token 0 := (amountOut * OD * (1-i))/ON = 249459.492279046935978576
    // available stability pool balance = 249459.492279046935978576 * 0.9 = 224513.5430511422423807184
    uint256 expectedInputAmount = 224513543051142242380718;

    // since we only have liquidity for 90% of the target amount, the input amount should be 90% of the target amount
    assertEq(action.amount1Out, expectedAmount1Out);
    assertEq(action.amount0Out, expectedAmount0Out);
    assertEq(action.inputAmount, expectedInputAmount);
  }

  function test_whenToken1DebtPoolPriceBelowAndNotEnoughLiquidityInStabilityPool_shouldExpandAndBringPriceCloserToOraclePrice()
    public
    _setUpPolicy(debtToken6, 9000)
  {
    uint256 reserve0 = 1_300_000 * 1e18; // usdm
    uint256 reserve1 = 1_000_000 * 1e6; // eurm

    ctx.token0 = address(collateralToken18);
    ctx.token1 = address(debtToken6);
    ctx.token0Dec = 1e18;
    ctx.token1Dec = 1e6;

    ctx.isToken0Debt = false;
    ctx.reserves = LQ.Reserves({
      reserveNum: reserve1 * 1e12, // reserve token 1 (1M) EURM
      reserveDen: reserve0 // reserve token 0 (1.3M) USDM
    });
    ctx.pool = fpmm;

    // USDC/USD rate
    ctx.prices = LQ.Prices({
      oracleNum: 863549230000000000000000 / 1e6, // USDC/EUR rate
      oracleDen: 1e18,
      poolPriceAbove: false,
      diffBps: 5_000 // 50%
    });
    ctx.incentiveBps = 50; // 0.5%

    // enough to cover 90% of the target amount
    uint256 stabilityPoolBalance = calculateTargetStabilityPoolBalance(0.9e18);
    setStabilityPoolBalance(address(debtToken6), stabilityPoolBalance);
    (, LQ.Action memory action) = policy.determineAction(ctx);

    // amount out in token 0 := (ON*RD-OD*RN)/(ON*(2-i)) = 71172.145133890686084197
    // since we only have limited liquidity:
    // amount out in token 0 := (55038013084 * OD * 1) / (ON * (1-i)) = 64054.930619381539786439
    uint256 expectedAmount0Out = 64054930619381539786439;
    uint256 expectedAmount1Out = 0;
    // input amount in token 1 := (amountOut * ON * (1-i))/OD = 61153.347872
    // available stability pool balance =  61153.347872 * 0.9 = 55038.013084
    uint256 expectedInputAmount = 55038013084;

    assertEq(action.amount1Out, expectedAmount1Out);
    assertEq(action.amount0Out, expectedAmount0Out);
    assertEq(action.inputAmount, expectedInputAmount);
  }

  /* ============================================================ */
  /* ============== Contraction target liquidity ================ */
  /* ============================================================ */

  function test_determineAction_whenToken0DebtPoolPriceBelowAndRedemptionFeeEqualToIncentive_shouldContractAndBringPriceBackToOraclePrice()
    public
    _setUpPolicy(debtToken18, 9000)
  {
    uint256 reserve0 = 7_089_031 * 1e18; // brl.m 1.3Mio in $
    uint256 reserve1 = 1_000_000 * 1e6; // usd.m 1Mio in $

    ctx.token0 = address(debtToken18);
    ctx.token1 = address(collateralToken6);
    ctx.token0Dec = 1e18;
    ctx.token1Dec = 1e6;

    ctx.isToken0Debt = true;
    ctx.reserves = LQ.Reserves({
      reserveNum: reserve1 * 1e12, // reserve token 1 (1M) usd.m
      reserveDen: reserve0 // reserve token 0 (1.3M) brl.m
    });
    ctx.pool = fpmm;

    ctx.prices = LQ.Prices({
      oracleNum: 1e18,
      oracleDen: 5476912800000000000,
      poolPriceAbove: false,
      diffBps: 5_000 // 50%
    });
    ctx.incentiveBps = 50; // 0.5%

    mockGetRedemptionRateWithDecay(0.0025 * 1e18); // 0.25%
    uint256 totalSupply = calculateTargetSupply(0.0025 * 1e18); // 0.25% resulting in redemption fee being 0.25% + 0.25% = 0.5%
    setTokenTotalSupply(address(debtToken18), totalSupply);

    (, LQ.Action memory action) = policy.determineAction(ctx);

    // amount out in token 0 := (ON*RD - OD*RN)/(ON*(2-i)) = 808079.298245614035087719
    uint256 expectedAmount0Out = 808079298245614035087719;
    uint256 expectedAmount1Out = 0;
    // input amount in token 1 := (amountOut * ON * (1-i))/OD = 146805.131123
    uint256 expectedInputAmount = 146805131123;

    assertEq(uint256(action.dir), uint256(LQ.Direction.Contract));
    assertEq(action.amount0Out, expectedAmount0Out);
    assertEq(action.amount1Out, expectedAmount1Out);
    assertEq(action.inputAmount, expectedInputAmount);
  }

  function test_determineAction_whenToken1DebtPoolPriceAboveAndRedemptionFeeEqualToIncentive_shouldContractAndBringPriceBackToOraclePrice()
    public
    _setUpPolicy(debtToken6, 9000)
  {
    uint256 reserve0 = 10_000_000 * 1e18; // usd.m
    uint256 reserve1 = 14_500_000 * 1e6; // chf.m

    ctx.token0 = address(collateralToken18);
    ctx.token1 = address(debtToken6);
    ctx.token0Dec = 1e18;
    ctx.token1Dec = 1e6;

    ctx.isToken0Debt = false;
    ctx.reserves = LQ.Reserves({
      reserveNum: reserve1 * 1e12, // reserve token 1 (14.5M) chf.m
      reserveDen: reserve0 // reserve token 0 (10M) usd.m
    });
    ctx.pool = fpmm;

    ctx.prices = LQ.Prices({
      oracleNum: 1e18,
      oracleDen: 1242930830000000000,
      poolPriceAbove: true,
      diffBps: 5_000 // 50%
    });
    ctx.incentiveBps = 50; // 0.5%

    mockGetRedemptionRateWithDecay(0.0025 * 1e18); // 0.25%
    uint256 totalSupply = calculateTargetSupply(0.0025 * 1e18); // 0.25% resulting in redemption fee being 0.25% + 0.25% = 0.5%
    setTokenTotalSupply(address(debtToken6), totalSupply);

    (, LQ.Action memory action) = policy.determineAction(ctx);

    uint256 expectedAmount0Out = 0;
    // amount out in token 1 := (OD*RN - ON*RD)/(OD*(2-i)) = 3_235_338.342946
    uint256 expectedAmount1Out = 3235338342946;
    // input amount in token 1 := (amountOut * OD * (1-i))/ON = 4_001_195.263069052943054100
    uint256 expectedInputAmount = 4001195263069052943054100;

    assertEq(uint256(action.dir), uint256(LQ.Direction.Contract));
    assertEq(action.amount0Out, expectedAmount0Out);
    assertEq(action.amount1Out, expectedAmount1Out);
    assertEq(action.inputAmount, expectedInputAmount);
  }

  /* ============================================================ */
  /* ============== Contraction non-target liquidity ============ */
  /* ============================================================ */

  function test_determineAction_whenToken0DebtPoolPriceBelowAndRedemptionFeeLessIncentive_shouldContractAndBringPriceAboveOraclePrice()
    public
    _setUpPolicy(debtToken6, 9000)
  {
    uint256 reserve0 = 10_956_675_007 * 1e6; // ngnm 7.5 mio in $
    uint256 reserve1 = 6_000_000 * 1e18; // usdm 6 mio in $

    ctx.token0 = address(debtToken6);
    ctx.token1 = address(collateralToken18);
    ctx.token0Dec = 1e6;
    ctx.token1Dec = 1e18;

    ctx.isToken0Debt = true;
    ctx.reserves = LQ.Reserves({
      reserveNum: reserve1, // reserve token 1 usdm
      reserveDen: reserve0 * 1e12 // reserve token 0 ngnm
    });
    ctx.pool = fpmm;

    ctx.prices = LQ.Prices({
      oracleNum: 684510000000000,
      oracleDen: 1e18,
      poolPriceAbove: false,
      diffBps: 5_000 // 50%
    });
    ctx.incentiveBps = 50; // 0.5%

    mockGetRedemptionRateWithDecay(0.0025 * 1e18); // 0.25%
    uint256 totalSupply = calculateTargetSupply(0.0015 * 1e18); // 0.15% resulting in redemption fee being 0.25% + 0.15% = 0.4%
    setTokenTotalSupply(address(debtToken6), totalSupply);

    (, LQ.Action memory action) = policy.determineAction(ctx);

    // amount out in token 0 := (ON*RD - OD*RN)/(ON*(2-i)) = 1_098_386_357.591375
    uint256 expectedAmount0Out = 1098386357591375;
    uint256 expectedAmount1Out = 0;
    // input amount in token 1 := (amountOut * ON * (1-0.004))/OD = 748_849.019852332612845000
    // 0.004 = 0.4% redemption fee
    uint256 expectedInputAmount = 748849019852332612845000;

    assertEq(uint256(action.dir), uint256(LQ.Direction.Contract));

    assertEq(action.amount0Out, expectedAmount0Out);
    assertEq(action.amount1Out, expectedAmount1Out);
    assertEq(action.inputAmount, expectedInputAmount);
  }

  function test_determineAction_whenToken1DebtPoolPriceAboveAndRedemptionFeeLessIncentive_shouldContractAndBringPriceBelowOraclePrice()
    public
    _setUpPolicy(debtToken18, 9000)
  {
    uint256 reserve0 = 555_555 * 1e6; // 555555 usd.m
    uint256 reserve1 = 43_629_738 * 1e18; // php.m 750k in $

    ctx.token0 = address(collateralToken6);
    ctx.token1 = address(debtToken18);
    ctx.token0Dec = 1e6;
    ctx.token1Dec = 1e18;

    ctx.isToken0Debt = false;
    ctx.reserves = LQ.Reserves({
      reserveNum: reserve1, // reserve token 1 php.m
      reserveDen: reserve0 * 1e12 // reserve token 0 usd.m
    });
    ctx.pool = fpmm;

    ctx.prices = LQ.Prices({
      oracleNum: 1e18,
      oracleDen: 17190990000000000,
      poolPriceAbove: true,
      diffBps: 5_000 // 50%
    });
    ctx.incentiveBps = 50; // 0.5%

    mockGetRedemptionRateWithDecay(0.0025 * 1e18); // 0.25%
    uint256 totalSupply = calculateTargetSupply(0.001 * 1e18); // 0.1% resulting in redemption fee being 0.25% + 0.1% = 0.35%
    setTokenTotalSupply(address(debtToken18), totalSupply);

    (, LQ.Action memory action) = policy.determineAction(ctx);

    uint256 expectedAmount0Out = 0;
    // amount out in token 1 := (OD*RN - ON*RD)/(OD*(2-i)) = 5_670_726.837208791926748374
    uint256 expectedAmount1Out = 5670726837208791926748374;
    // input amount in token 0 := (amountOut * OD * (1-0.0035))/ON = 97_144.209421
    // 0.0035 = 0.35% redemption fee
    uint256 expectedInputAmount = 97144209421;

    assertEq(uint256(action.dir), uint256(LQ.Direction.Contract));
    assertEq(action.amount0Out, expectedAmount0Out);
    assertEq(action.amount1Out, expectedAmount1Out);
    assertEq(action.inputAmount, expectedInputAmount);
  }

  function test_determineAction_whenToken0DebtPoolPriceBelowAndRedemptionFeeGreaterIncentive_shouldContractAndBringPriceCloserToOraclePrice()
    public
    _setUpPolicy(debtToken6, 9000)
  {
    uint256 reserve0 = 10_956_675_007 * 1e6; // ngnm 7.5 mio in $
    uint256 reserve1 = 6_000_000 * 1e18; // usdm 6 mio in $

    ctx.token0 = address(debtToken6);
    ctx.token1 = address(collateralToken18);
    ctx.token0Dec = 1e6;
    ctx.token1Dec = 1e18;

    ctx.isToken0Debt = true;
    ctx.reserves = LQ.Reserves({
      reserveNum: reserve1, // reserve token 1 usdm
      reserveDen: reserve0 * 1e12 // reserve token 0 ngnm
    });
    ctx.pool = fpmm;

    ctx.prices = LQ.Prices({
      oracleNum: 684510000000000,
      oracleDen: 1e18,
      poolPriceAbove: false,
      diffBps: 5_000 // 50%
    });
    ctx.incentiveBps = 50; // 0.5%

    mockGetRedemptionRateWithDecay(0.0025 * 1e18); // 0.25%
    uint256 totalSupply = calculateTargetSupply(0.0035 * 1e18); // 0.35% resulting in redemption fee being 0.25% + 0.35% = 0.6%
    setTokenTotalSupply(address(debtToken6), totalSupply);

    (, LQ.Action memory action) = policy.determineAction(ctx);

    // target amount out in token 0 := (ON*RD - OD*RN)/(ON*(2-i)) = 1_098_386_357.591375
    // since redemption fee for target amount is greater than incentive.
    // we will redeem an amount that results in a redemption fee equal to incentive.
    // maximum amount that can be redeemed is: totalSupply * redemptionBeta * (incentive - decayedBaseFee) =
    // = 313824673597535714 * 1 * (0.005 - 0.0025) =  784_561_683.993839
    uint256 expectedAmount0Out = 784561683993839;
    uint256 expectedAmount1Out = 0;
    // input amount in token 1 := (amountOut * ON * (1-0.0025 - amountOut / totalSupply))/OD = 534_355.116719069620757590
    uint256 expectedInputAmount = 534355116719069620757590;

    assertEq(uint256(action.dir), uint256(LQ.Direction.Contract));
    assertEq(action.amount0Out, expectedAmount0Out);
    assertEq(action.amount1Out, expectedAmount1Out);
    assertEq(action.inputAmount, expectedInputAmount);
  }

  function test_determineAction_whenToken1DebtPoolPriceAboveAndRedemptionFeeGreaterIncentive_shouldContractAndBringPriceCloserToOraclePrice()
    public
    _setUpPolicy(debtToken18, 9000)
  {
    uint256 reserve0 = 555_555 * 1e6; // 555555 usd.m
    uint256 reserve1 = 43_629_738 * 1e18; // php.m 750k in $

    ctx.token0 = address(collateralToken6);
    ctx.token1 = address(debtToken18);
    ctx.token0Dec = 1e6;
    ctx.token1Dec = 1e18;

    ctx.isToken0Debt = false;
    ctx.reserves = LQ.Reserves({
      reserveNum: reserve1, // reserve token 1 php.m
      reserveDen: reserve0 * 1e12 // reserve token 0 usd.m
    });
    ctx.pool = fpmm;

    ctx.prices = LQ.Prices({
      oracleNum: 1e18,
      oracleDen: 17190990000000000,
      poolPriceAbove: true,
      diffBps: 5_000 // 50%
    });
    ctx.incentiveBps = 50; // 0.5%

    mockGetRedemptionRateWithDecay(0.0025 * 1e18); // 0.25%
    uint256 totalSupply = calculateTargetSupply(0.005 * 1e18); // 0.5% resulting in redemption fee being 0.25% + 0.5% = 0.75%
    setTokenTotalSupply(address(debtToken18), totalSupply);

    (, LQ.Action memory action) = policy.determineAction(ctx);

    uint256 expectedAmount0Out = 0;
    // amount out in token 1 := (OD*RN - ON*RD)/(OD*(2-i)) = 5_670_726.837208791926748374
    // since redemption fee for target amount is greater than incentive.
    // we will redeem an amount that results in a redemption fee equal to incentive.
    // maximum amount that can be redeemed is: totalSupply * redemptionBeta * (incentive - decayedBaseFee) =
    // = 1134145367441758385349674800 * 1 * (0.005 - 0.0025) =  2_835_363.418604395963374187
    uint256 expectedAmount1Out = 2835363418604395963374187;
    // input amount in token 1 := (amountOut * ON * (1-0.0025 - amountOut / totalSupply))/OD = 484_989.90654
    uint256 expectedInputAmount = 48498990654;

    assertEq(uint256(action.dir), uint256(LQ.Direction.Contract));
    assertEq(action.amount0Out, expectedAmount0Out);
    assertEq(action.amount1Out, expectedAmount1Out);
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
    testContext.stabilityPoolBalance = calculateTargetStabilityPoolBalance(0.9e18); // stability pool holds 90% of target amount to rebalance fully
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

    testContext.stabilityPoolBalance = calculateTargetStabilityPoolBalance(0.8e18); // stability pool holds 90% of target amount to rebalance fully
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
    uint256 totalSupply = calculateTargetSupply(0.0025 * 1e18);
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
    uint256 totalSupply = calculateTargetSupply(0.0025 * 1e18);
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
    uint256 totalSupply = calculateTargetSupply(0.001 * 1e18); // 0.1% resulting in redemption fee beeing 0.25% + 0.1% = 0.35%
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
    uint256 totalSupply = calculateTargetSupply(0.003 * 1e18); // 0.3% resulting in redemption fee beeing 0.25% + 0.3% = 0.55%
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
    uint256 totalSupply = calculateTargetSupply(0.001 * 1e18); // 0.1% resulting in redemption fee beeing 0.25% + 0.1% = 0.35%
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
    uint256 totalSupply = calculateTargetSupply(0.003 * 1e18); // 0.3% resulting in redemption fee beeing 0.25% + 0.3% = 0.55%
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
  /* ==================== Helper Functions ====================== */
  /* ============================================================ */

  /**
   * @notice Set the minimum balance of the stability pool after rebalance
   * @param minBalance The minimum balance of the stability pool after rebalance
   */
  function setStabilityPoolMinBoldAfterRebalance(uint256 minBalance) public {
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
  ) internal pure returns (uint256 priceDifference, bool reservePriceAboveOraclePrice) {
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
  ) public pure {
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
   * @param targetFraction the redemption fraction to target
   * @return targetSupply
   */
  function calculateTargetSupply(uint256 targetFraction) internal view returns (uint256 targetSupply) {
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
   * @param stabilityPoolPercentage The percentage of the target amount to calculate
   * @return desiredStabilityPoolBalance
   */
  function calculateTargetStabilityPoolBalance(
    uint256 stabilityPoolPercentage
  ) internal view returns (uint256 desiredStabilityPoolBalance) {
    uint256 targetStabilityPoolBalance;
    if (ctx.prices.poolPriceAbove) {
      uint256 numerator = ctx.prices.oracleDen *
        ctx.reserves.reserveNum -
        ctx.prices.oracleNum *
        ctx.reserves.reserveDen;
      uint256 denominator = (ctx.prices.oracleDen * (2 * LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps)) /
        LQ.BASIS_POINTS_DENOMINATOR;
      uint256 amountOut = LQ.convertWithRateScaling(1, 1e18, ctx.token1Dec, numerator, denominator);

      targetStabilityPoolBalance = LQ.convertWithRateScalingAndFee(
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

      targetStabilityPoolBalance = LQ.convertWithRateScalingAndFee(
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
    desiredStabilityPoolBalance = (targetStabilityPoolBalance * stabilityPoolPercentage) / 1e18;
    uint256 a = IStabilityPool(stabilityPool).MIN_BOLD_AFTER_REBALANCE() + desiredStabilityPoolBalance;
    uint256 b = (desiredStabilityPoolBalance *
      LQ.BASIS_POINTS_DENOMINATOR +
      policy.deptTokenStabilityPoolPercentage(debtToken) -
      1) / policy.deptTokenStabilityPoolPercentage(debtToken);

    // take the higher of the two
    desiredStabilityPoolBalance = a > b ? a : b;
  }
}
