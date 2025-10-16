// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { LiquidityStrategy_BaseTest } from "../LiquidityStrategy/LiquidityStrategy_BaseTest.sol";
import { CDPLiquidityStrategyHarness } from "test/utils/harnesses/CDPLiquidityStrategyHarness.sol";

import { ICDPLiquidityStrategy } from "contracts/interfaces/ICDPLiquidityStrategy.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/libraries/LiquidityStrategyTypes.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

import { MockStabilityPool } from "test/utils/mocks/MockStabilityPool.sol";
import { MockCollateralRegistry } from "test/utils/mocks/MockCollateralRegistry.sol";
import { IStabilityPool } from "bold/Interfaces/IStabilityPool.sol";
import { ICollateralRegistry } from "bold/Interfaces/ICollateralRegistry.sol";

import { MockERC20 } from "test/utils/mocks/MockERC20.sol";

contract CDPLiquidityStrategy_BaseTest is LiquidityStrategy_BaseTest {
  CDPLiquidityStrategyHarness public strategy;

  // Mock contracts specific to CDP
  MockStabilityPool public mockStabilityPool;
  MockCollateralRegistry public mockCollateralRegistry;

  function setUp() public virtual override {
    LiquidityStrategy_BaseTest.setUp();
    strategy = new CDPLiquidityStrategyHarness(owner);
    strategyAddr = address(strategy);
  }

  modifier addFpmm(uint64 cooldown, uint32 incentiveBps, uint256 stabilityPoolPercentage) {
    // Deploy collateral registry mock
    mockCollateralRegistry = new MockCollateralRegistry(debtToken, collToken);

    // Deploy stability pool mock
    mockStabilityPool = new MockStabilityPool(debtToken, collToken);

    // Add pool to strategy with CDP-specific configuration
    vm.prank(owner);
    strategy.addPool(
      address(fpmm),
      debtToken,
      cooldown,
      incentiveBps,
      address(mockStabilityPool),
      address(mockCollateralRegistry),
      1, // redemption beta
      stabilityPoolPercentage,
      100 // maxIterations
    );
    _;
  }

  /* ============================================================ */
  /* ================= Helper Functions ========================= */
  /* ============================================================ */

  /**
   * @notice Mock the collateral registry redemption rate with decay
   * @param redemptionRate The redemption rate (base rate) in 18 decimals
   */
  function mockRedemptionRateWithDecay(uint256 redemptionRate) internal {
    vm.mockCall(
      address(mockCollateralRegistry),
      abi.encodeWithSelector(ICollateralRegistry.getRedemptionRateWithDecay.selector),
      abi.encode(redemptionRate)
    );
  }

  /**
   * @notice Mock the collateral registry oracle rate
   * @param numerator Oracle rate numerator
   * @param denominator Oracle rate denominator
   */
  function mockCollateralRegistryOracleRate(uint256 numerator, uint256 denominator) internal {
    mockCollateralRegistry.setOracleRate(numerator, denominator);
  }

  /**
   * @notice Set the stability pool minimum BOLD balance after rebalance
   * @param minBalance Minimum balance in BOLD token decimals
   */
  function setStabilityPoolMinBalance(uint256 minBalance) internal {
    vm.mockCall(
      address(mockStabilityPool),
      abi.encodeWithSelector(IStabilityPool.MIN_BOLD_AFTER_REBALANCE.selector),
      abi.encode(minBalance)
    );
  }

  /**
   * @notice Set the stability pool balance for a token
   * @param token The token address
   * @param balance The balance to set
   */
  function setStabilityPoolBalance(address token, uint256 balance) internal {
    deal(token, address(mockStabilityPool), balance);
  }

  /**
   * @notice Create a liquidity context for testing
   * @param reserveDen token0 reserves (denominator in pool price)
   * @param reserveNum token1 reserves (numerator in pool price)
   * @param oracleNum Oracle price numerator
   * @param oracleDen Oracle price denominator
   * @param poolPriceAbove Whether pool price is above oracle price
   * @param incentiveBps Incentive in basis points
   */
  function _createContext(
    uint256 reserveDen,
    uint256 reserveNum,
    uint256 oracleNum,
    uint256 oracleDen,
    bool poolPriceAbove,
    uint256 incentiveBps
  ) internal view returns (LQ.Context memory) {
    return
      _createContextWithDecimals(
        reserveDen,
        reserveNum,
        oracleNum,
        oracleDen,
        poolPriceAbove,
        incentiveBps,
        1e18, // 18 decimals for token0
        1e18 // 18 decimals for token1
      );
  }

  /**
   * @notice Create a liquidity context with custom decimals
   */
  function _createContextWithDecimals(
    uint256 reserveDen,
    uint256 reserveNum,
    uint256 oracleNum,
    uint256 oracleDen,
    bool poolPriceAbove,
    uint256 incentiveBps,
    uint256 token0Dec,
    uint256 token1Dec
  ) internal view returns (LQ.Context memory) {
    return
      LQ.Context({
        pool: address(fpmm),
        reserves: LQ.Reserves({ reserveNum: reserveNum, reserveDen: reserveDen }),
        prices: LQ.Prices({ oracleNum: oracleNum, oracleDen: oracleDen, poolPriceAbove: poolPriceAbove, diffBps: 0 }),
        incentiveBps: uint128(incentiveBps),
        token0Dec: uint64(token0Dec),
        token1Dec: uint64(token1Dec),
        token0: debtToken,
        token1: collToken,
        isToken0Debt: true
      });
  }

  /**
   * @notice Create a liquidity context with custom token order
   */
  function _createContextWithTokenOrder(
    uint256 reserveDen,
    uint256 reserveNum,
    uint256 oracleNum,
    uint256 oracleDen,
    bool poolPriceAbove,
    uint256 incentiveBps,
    bool isToken0Debt
  ) internal view returns (LQ.Context memory) {
    uint256 token0Dec = 10 ** (isToken0Debt ? IERC20(debtToken).decimals() : IERC20(collToken).decimals());
    uint256 token1Dec = 10 ** (isToken0Debt ? IERC20(collToken).decimals() : IERC20(debtToken).decimals());
    return
      LQ.Context({
        pool: address(fpmm),
        reserves: LQ.Reserves({ reserveNum: reserveNum, reserveDen: reserveDen }),
        prices: LQ.Prices({ oracleNum: oracleNum, oracleDen: oracleDen, poolPriceAbove: poolPriceAbove, diffBps: 0 }),
        incentiveBps: uint128(incentiveBps),
        token0Dec: uint64(token0Dec),
        token1Dec: uint64(token1Dec),
        token0: isToken0Debt ? debtToken : collToken,
        token1: isToken0Debt ? collToken : debtToken,
        isToken0Debt: isToken0Debt
      });
  }

  /**
   * @notice Calculate price difference between pool and oracle
   * @param oracleNum Oracle price numerator
   * @param oracleDen Oracle price denominator
   * @param reserveNum Pool reserve numerator (token1)
   * @param reserveDen Pool reserve denominator (token0)
   * @return priceDifference Price difference in basis points
   * @return reservePriceAboveOracle Whether reserve price is above oracle price
   */
  function calculatePriceDifference(
    uint256 oracleNum,
    uint256 oracleDen,
    uint256 reserveNum,
    uint256 reserveDen
  ) internal pure returns (uint256 priceDifference, bool reservePriceAboveOracle) {
    uint256 oracleCrossProduct = oracleNum * reserveDen;
    uint256 reserveCrossProduct = reserveNum * oracleDen;

    reservePriceAboveOracle = reserveCrossProduct > oracleCrossProduct;
    uint256 absolutePriceDiff = reservePriceAboveOracle
      ? reserveCrossProduct - oracleCrossProduct
      : oracleCrossProduct - reserveCrossProduct;
    priceDifference = (absolutePriceDiff * 10_000) / oracleCrossProduct;
  }

  /**
   * @notice Calculate price difference for a context
   * @param ctx The liquidity context
   * @return priceDifference Price difference in basis points
   * @return reservePriceAboveOracle Whether reserve price is above oracle price
   */
  function calculatePriceDifference(
    LQ.Context memory ctx
  ) internal pure returns (uint256 priceDifference, bool reservePriceAboveOracle) {
    return
      calculatePriceDifference(
        ctx.prices.oracleNum,
        ctx.prices.oracleDen,
        ctx.reserves.reserveNum,
        ctx.reserves.reserveDen
      );
  }

  /**
   * @notice Calculate price difference after an action
   * @param ctx The liquidity context
   * @param action The action to simulate
   * @return priceDifference Price difference in basis points
   * @return reservePriceAboveOracle Whether reserve price is above oracle price
   */
  function calculatePriceDifference(
    LQ.Context memory ctx,
    LQ.Action memory action
  ) internal pure returns (uint256 priceDifference, bool reservePriceAboveOracle) {
    uint256 reserve0After = ctx.reserves.reserveDen + action.amountOwedToPool - action.amount0Out;
    uint256 reserve1After = ctx.reserves.reserveNum - action.amount1Out;
    return calculatePriceDifference(ctx.prices.oracleNum, ctx.prices.oracleDen, reserve1After, reserve0After);
  }

  /**
   * @notice Assert that the incentive is within expected bounds
   * @param expectedIncentiveBps Expected incentive in basis points
   * @param isToken0Out Whether token0 is flowing out (true) or token1 (false)
   * @param amountOut Amount of token flowing out
   * @param amountIn Amount of token flowing in
   * @param oracleNum Oracle price numerator
   * @param oracleDen Oracle price denominator
   */
  function assertIncentive(
    uint256 expectedIncentiveBps,
    bool isToken0Out,
    uint256 amountOut,
    uint256 amountIn,
    uint256 oracleNum,
    uint256 oracleDen
  ) internal {
    uint256 amountOutInOtherToken;
    if (isToken0Out) {
      amountOutInOtherToken = (amountOut * oracleNum) / oracleDen;
    } else {
      amountOutInOtherToken = (amountOut * oracleDen) / oracleNum;
    }
    uint256 actualIncentive = ((amountOutInOtherToken - amountIn) * 10_000) / amountOutInOtherToken;

    // Allow 1bp difference due to rounding
    assertApproxEqAbs(actualIncentive, expectedIncentiveBps, 1, "Incentive should match expected value");
  }

  /**
   * @notice Assert the reserve value change is within the incentive
   * @param reserve0Before Reserve of token0 before the rebalance
   * @param reserve1Before Reserve of token1 before the rebalance
   * @param reserve0After Reserve of token0 after the rebalance
   * @param reserve1After Reserve of token1 after the rebalance
   */
  function assertReserveValueIncentives(
    uint256 reserve0Before,
    uint256 reserve1Before,
    uint256 reserve0After,
    uint256 reserve1After
  ) public {
    (uint256 rateNumerator, uint256 rateDenominator, , , , ) = fpmm.getPrices();

    uint256 token0Scaler = 10 ** MockERC20(fpmm.token0()).decimals();
    uint256 token1Scaler = 10 ** MockERC20(fpmm.token1()).decimals();

    uint256 totalReserveValueBefore;
    uint256 totalReserveValueAfter;
    if (token0Scaler > token1Scaler) {
      // calculate total reserve value token0
      totalReserveValueBefore =
        reserve0Before +
        convertWithRateAndScale(reserve1Before, rateDenominator, rateNumerator, token1Scaler, token0Scaler);

      totalReserveValueAfter =
        reserve0After +
        convertWithRateAndScale(reserve1After, rateDenominator, rateNumerator, token1Scaler, token0Scaler);
    } else {
      // calculate total reserve value token1
      totalReserveValueBefore =
        reserve1Before +
        convertWithRateAndScale(reserve0Before, rateNumerator, rateDenominator, token0Scaler, token1Scaler);
      totalReserveValueAfter =
        reserve1After +
        convertWithRateAndScale(reserve0After, rateNumerator, rateDenominator, token0Scaler, token1Scaler);
    }
    uint256 reserveValueDifference = ((totalReserveValueBefore - totalReserveValueAfter) * 10_000) /
      totalReserveValueBefore;
    // Since we allow the incentive to be up to 50 bps of the amount taken out off the fppm
    // and the max amount that makes sense for a rebalance is taking out 50% of the reserves,
    // we allow the reserve value difference to be up to 0.25% of the total reserve value
    assertTrue(reserveValueDifference <= 25); // 0.25%
  }

  /**
   * @notice Assert the rebalance amounts are within the incentive
   * @param amountTakenOut Amount of the token taken out
   * @param amountAdded Amount of the token added
   * @param isToken0Out True if the token taken out is token0, false otherwise
   * @param isCheapContraction True if the rebalance is a cheap contraction (contraction with less than 50bps)
   */
  function assertRebalanceAmountIncentives(
    uint256 amountTakenOut,
    uint256 amountAdded,
    bool isToken0Out,
    bool isCheapContraction
  ) public {
    (uint256 rateNumerator, uint256 rateDenominator, , , , ) = fpmm.getPrices();

    uint256 token0Scaler = 10 ** MockERC20(fpmm.token0()).decimals();
    uint256 token1Scaler = 10 ** MockERC20(fpmm.token1()).decimals();

    uint256 amountInInTokenOut;
    if (isToken0Out) {
      amountInInTokenOut = ((amountAdded * rateDenominator * token0Scaler) / (rateNumerator * token1Scaler));
    } else {
      amountInInTokenOut = ((amountAdded * rateNumerator * token1Scaler) / (rateDenominator * token0Scaler));
    }
    uint256 bpsDifference = ((amountTakenOut - amountInInTokenOut) * 10_000) / amountTakenOut;

    // 50 bps is the max but for contractions the amount can be less depending on the redemption rate
    if (isCheapContraction) {
      assertTrue(bpsDifference < 50); // 0.5%
    } else {
      // we allow for a difference of 1 due to rounding when token decimals differ
      assertApproxEqAbs(bpsDifference, 50, 1); // 0.5%
    }
  }

  function convertWithRateAndScale(
    uint256 amount,
    uint256 rateNumerator,
    uint256 rateDenominator,
    uint256 fromDec,
    uint256 toDec
  ) public pure returns (uint256) {
    return (amount * rateNumerator * toDec) / (rateDenominator * fromDec);
  }
  /**
   * @notice Calculate the stability pool balance in order to cover a percentage of the target amount needed to rebalance
   * @param stabilityPoolPercentage The percentage of the target amount to calculate
   * @return desiredStabilityPoolBalance
   */
  function calculateTargetStabilityPoolBalance(
    uint256 stabilityPoolPercentage,
    LQ.Context memory ctx
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
    desiredStabilityPoolBalance = (targetStabilityPoolBalance * stabilityPoolPercentage) / 1e18;
    ICDPLiquidityStrategy.CDPConfig memory config = strategy.getCDPConfig(ctx.pool);
    uint256 a = mockStabilityPool.MIN_BOLD_AFTER_REBALANCE() + desiredStabilityPoolBalance;
    uint256 b = (desiredStabilityPoolBalance * LQ.BASIS_POINTS_DENOMINATOR + config.stabilityPoolPercentage - 1) /
      config.stabilityPoolPercentage;

    // take the higher of the two
    desiredStabilityPoolBalance = a > b ? a : b;
  }

  /**
   * @notice Calculate the target supply such that the redemption fraction is equal to the target fraction
   * @param targetFraction the redemption fraction to target
   * @return targetSupply
   */
  function calculateTargetSupply(
    uint256 targetFraction,
    LQ.Context memory ctx
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
}
