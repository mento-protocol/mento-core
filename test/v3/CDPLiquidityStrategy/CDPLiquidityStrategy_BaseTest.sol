// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { Test } from "mento-std/Test.sol";
import { LiquidityStrategy_BaseTest } from "../LiquidityStrategy/LiquidityStrategy_BaseTest.sol";
import { CDPLiquidityStrategy } from "contracts/v3/CDPLiquidityStrategy.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/v3/libraries/LiquidityStrategyTypes.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { MockStabilityPool } from "test/utils/mocks/MockStabilityPool.sol";
import { MockCollateralRegistry } from "test/utils/mocks/MockCollateralRegistry.sol";
import { IStabilityPool } from "bold/Interfaces/IStabilityPool.sol";
import { ICollateralRegistry } from "bold/Interfaces/ICollateralRegistry.sol";

contract CDPLiquidityStrategy_BaseTest is LiquidityStrategy_BaseTest {
  CDPLiquidityStrategy public strategy;

  // Mock contracts specific to CDP
  MockStabilityPool public mockStabilityPool;
  MockCollateralRegistry public mockCollateralRegistry;

  function setUp() public virtual override {
    LiquidityStrategy_BaseTest.setUp();
    strategy = new CDPLiquidityStrategy(owner);
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
      stabilityPoolPercentage
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
    return
      LQ.Context({
        pool: address(fpmm),
        reserves: LQ.Reserves({ reserveNum: reserveNum, reserveDen: reserveDen }),
        prices: LQ.Prices({ oracleNum: oracleNum, oracleDen: oracleDen, poolPriceAbove: poolPriceAbove, diffBps: 0 }),
        incentiveBps: uint128(incentiveBps),
        token0Dec: 1e18,
        token1Dec: 1e18,
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
    return calculatePriceDifference(ctx.prices.oracleNum, ctx.prices.oracleDen, ctx.reserves.reserveNum, ctx.reserves.reserveDen);
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
    uint256 reserve0After = ctx.reserves.reserveDen + action.inputAmount - action.amount0Out;
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
}
