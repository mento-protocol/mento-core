// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { CDPLiquidityStrategy } from "contracts/v3/CDPLiquidityStrategy.sol";
import { CDPPolicy } from "contracts/v3/CDPPolicy.sol";
import { LiquidityTypes as LQ } from "contracts/v3/libraries/LiquidityTypes.sol";
import { FPMM } from "contracts/swap/FPMM.sol";
import { Test } from "forge-std/Test.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";

import { MockStabilityPool } from "test/utils/mocks/MockStabilityPool.sol";
import { LiquidityController } from "contracts/v3/LiquidityController.sol";
import { ILiquidityPolicy } from "contracts/v3/Interfaces/ILiquidityPolicy.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";
import { IBreakerBox } from "contracts/interfaces/IBreakerBox.sol";
import { ICollateralRegistry } from "contracts/v3/Interfaces/ICollateralRegistry.sol";
import { MockCollateralRegistry } from "test/utils/mocks/MockCollateralRegistry.sol";

import { console } from "forge-std/console.sol";

contract CDPLiquidityStrategyTest is Test {
  CDPLiquidityStrategy public cdpLiquidityStrategy;
  CDPPolicy public cdpPolicy;
  FPMM public fpmm;
  MockStabilityPool public mockStabilityPool;
  MockCollateralRegistry public mockCollateralRegistry;
  LiquidityController public liquidityController;
  address public liquiditySource;
  address public debtToken;
  address public collToken;
  address public sortedOracles = makeAddr("sortedOracles");
  address public referenceRateFeedID = makeAddr("referenceRateFeedID");
  address public breakerBox = makeAddr("breakerBox");
  uint256 public oracleNumerator;
  uint256 public oracleDenominator;

  function setUp() public {
    fpmm = new FPMM(false);
    cdpLiquidityStrategy = new CDPLiquidityStrategy(true);
    liquidityController = new LiquidityController();
    liquidityController.initialize(address(this));
  }

  modifier fpmmToken0Debt(uint8 debtDecimals, uint8 collateralDecimals) {
    // deploy debt and collateral with specified decimals and correct address order
    deployDebtAndCollateral(true, debtDecimals, collateralDecimals);

    // deploy collateral registry mock
    mockCollateralRegistry = new MockCollateralRegistry(debtToken, collToken);

    // deploy stability pool mock
    mockStabilityPool = new MockStabilityPool(debtToken);

    // initialize fpmm and set liquidity strategy
    fpmm.initialize(debtToken, collToken, sortedOracles, referenceRateFeedID, false, breakerBox, address(this));
    fpmm.setLiquidityStrategy(address(cdpLiquidityStrategy), true);

    // deploy cdp policy
    address[] memory debtTokens = new address[](1);
    address[] memory stabilityPools = new address[](1);
    address[] memory collateralRegistries = new address[](1);
    uint256[] memory redemptionBetas = new uint256[](1);
    debtTokens[0] = debtToken;
    stabilityPools[0] = address(mockStabilityPool);
    collateralRegistries[0] = address(mockCollateralRegistry);
    redemptionBetas[0] = 1;
    cdpPolicy = new CDPPolicy(debtTokens, stabilityPools, collateralRegistries, redemptionBetas);

    // set trusted pools on cdp liquidity strategy
    cdpLiquidityStrategy.setTrustedPools(address(fpmm), true);

    // configure liquidity controller
    ILiquidityPolicy[] memory policies = new ILiquidityPolicy[](1);
    policies[0] = ILiquidityPolicy(address(cdpPolicy));
    liquidityController.addPool(address(fpmm), debtToken, collToken, 0 seconds, 50);
    liquidityController.setPoolPipeline(address(fpmm), policies);
    liquidityController.setLiquiditySourceStrategy(LQ.LiquiditySource.CDP, cdpLiquidityStrategy);

    // mock breaker box trading mode to trading allowed
    mockBreakerBoxTradingMode(false);
    _;
  }

  modifier fpmmToken1Debt(uint8 debtDecimals, uint8 collateralDecimals) {
    // deploy debt and collateral with specified decimals and correct address order
    deployDebtAndCollateral(false, debtDecimals, collateralDecimals);

    // deploy collateral registry mock
    mockCollateralRegistry = new MockCollateralRegistry(debtToken, collToken);

    // deploy stability pool mock
    mockStabilityPool = new MockStabilityPool(debtToken);

    // initialize fpmm and set liquidity strategy
    fpmm.initialize(collToken, debtToken, sortedOracles, referenceRateFeedID, false, breakerBox, address(this));
    fpmm.setLiquidityStrategy(address(cdpLiquidityStrategy), true);

    // deploy cdp policy
    address[] memory debtTokens = new address[](1);
    address[] memory stabilityPools = new address[](1);
    address[] memory collateralRegistries = new address[](1);
    uint256[] memory redemptionBetas = new uint256[](1);
    debtTokens[0] = debtToken;
    stabilityPools[0] = address(mockStabilityPool);
    collateralRegistries[0] = address(mockCollateralRegistry);
    redemptionBetas[0] = 1;
    cdpPolicy = new CDPPolicy(debtTokens, stabilityPools, collateralRegistries, redemptionBetas);

    // set trusted pools on cdp liquidity strategy
    cdpLiquidityStrategy.setTrustedPools(address(fpmm), true);

    // configure liquidity controller
    ILiquidityPolicy[] memory policies = new ILiquidityPolicy[](1);
    policies[0] = ILiquidityPolicy(address(cdpPolicy));
    liquidityController.addPool(address(fpmm), debtToken, collToken, 0 seconds, 50);
    liquidityController.setPoolPipeline(address(fpmm), policies);
    liquidityController.setLiquiditySourceStrategy(LQ.LiquiditySource.CDP, cdpLiquidityStrategy);

    // mock breaker box trading mode to trading allowed
    mockBreakerBoxTradingMode(false);
    _;
  }

  /* ============================================================ */
  /* ================ Contraction Token 0 Debt ================== */
  /* ============================================================ */

  function test_rebalance_whenToken0DebtAndPoolPriceBelowOraclePriceAndRedemptionFeeSmallerIncentive_shouldContractAndBringPriceAboveOraclePrice()
    public
    fpmmToken0Debt(12, 18)
  {
    // COP USD rate
    oracleNumerator = 255050000000000000000;
    oracleDenominator = 1e24;
    // 4_704_949_844_000_000
    // 3_920_799_843

    // 3_920_799_843 COP.m in 12 decimals and 1_000_000 USD.m in 18 decimals
    provideFPMMReserves(3_920_799_843e12, 1_000_000e18, true);
    setOracleRate(oracleNumerator, oracleDenominator);
    // 50 or 0.5% is max redemption fee in bps
    // setting base rate to 0.25% in 18 decimals
    uint256 baseRate = 25e14;
    uint256 totalSupply = 1_000_000_000_000e12;
    mockCollateralRegistry.setRedemptionRateWithDecay(baseRate);
    // payed redemption fee is base rate + redeemedAmount/totalSupply
    // setting total supply to 1_000_000_000_000 in 12 decimals to ensure total redemption fee is less than 0.5%
    setDebtTokenTotalSupply(totalSupply);
    mockCollateralRegistry.setOracleRate(oracleNumerator / 1e6, oracleDenominator / 1e6);

    // debalance fpmm by swaping 200_000$ worth of COP into the pool
    swapIn(debtToken, 784_150_001e12);
    //   reserve1:  1000000000000000000000000
    //   reserve0:  3920799843000000000000
    //   reserve1:  800602534618215150000000
    //   reserve0:  4704949844000000000000
    //   reserve1:  1000142853558808882907263
    //   reserve0:  3920013727794990613173
    //   --------------------------------
    // reserve1Before 800602534618215150000000
    // reserve0Before 4704949844000000000000000000
    // reserve0After 1000142853558808882907263
    // reserve1After 3920013727794990613173000000
    // rateNumerator 255050000000000
    // rateDenominator 1000000000000000000

    //totalReserveValueBefore 20_013_849_800_657_068_800_000
    //totalReserveValueAfter  199_88821855265486193835
    // --------------------------------

    // Snapshot before the rebalance
    (
      ,
      ,
      uint256 reserve1Before,
      uint256 reserve0Before,
      uint256 priceDifferenceBefore,
      bool reservePriceAboveOraclePriceBefore
    ) = fpmm.getPrices();

    // pool price is below oracle price
    assertTrue(!reservePriceAboveOraclePriceBefore);
    // price difference is positive
    assertTrue(priceDifferenceBefore > 0);

    liquidityController.rebalance(address(fpmm));

    // Snapshot after the rebalance
    (
      ,
      ,
      uint256 reserve1After,
      uint256 reserve0After,
      uint256 priceDifferenceAfter,
      bool reservePriceAboveOraclePriceAfter
    ) = fpmm.getPrices();

    // we allow the price difference to be moved in the wrong direction but not by more than the rebalance incentive
    // this is due to the dynamic rebalance fee that is taken from the swap
    assertTrue(priceDifferenceAfter <= ((priceDifferenceBefore * 50) / 10_000));
    assertTrue(reservePriceAboveOraclePriceAfter);
    assertTrue(reserve0Before > reserve0After);
    assertTrue(reserve1Before < reserve1After);
    assertReserveValueIncentives(reserve0Before, reserve1Before);
    // assertRebalanceAmountIncentives(reserve1Before - reserve1After, reserve0After - reserve0Before, false, false);
  }

  function test_rebalance_whenToken0DebtAndPoolPriceBelowOraclePriceAndRedemptionFeeLargerIncentive_shouldContractAndBringPriceCloserToOraclePrice()
    public
    fpmmToken0Debt(12, 18)
  {
    // COP USD rate
    oracleNumerator = 255050000000000000000;
    oracleDenominator = 1e24;

    // 3_920_799_843 COP.m in 12 decimals and 1_000_000 USD.m in 18 decimals
    provideFPMMReserves(3_920_799_843e12, 1_000_000e18, true);
    setOracleRate(oracleNumerator, oracleDenominator);
    // 50 or 0.5% is max redemption fee in bps
    // setting base rate to 0.25% in 18 decimals
    uint256 baseRate = 25e14;
    uint256 totalSupply = 100_000_000_000e12;
    mockCollateralRegistry.setRedemptionRateWithDecay(baseRate);
    // payed redemption fee is base rate + redeemedAmount/totalSupply
    // setting total supply to 100_000_000_000 in 12 decimals.
    // This results in maximum amount that can be redeemed is 0.25% of the total supply.
    // or 250_000_000e12 which is less than the amount required to bring the pool price fully back to the oracle price.
    setDebtTokenTotalSupply(totalSupply);
    mockCollateralRegistry.setOracleRate(oracleNumerator / 1e6, oracleDenominator / 1e6);

    // debalance fpmm by swaping 200_000$ worth of COP into the pool
    swapIn(debtToken, 784_150_001e12);

    // Snapshot before the rebalance
    (
      ,
      ,
      uint256 reserve1Before,
      uint256 reserve0Before,
      uint256 priceDifferenceBefore,
      bool reservePriceAboveOraclePriceBefore
    ) = fpmm.getPrices();

    assertTrue(!reservePriceAboveOraclePriceBefore);
    assertTrue(priceDifferenceBefore > 0);

    liquidityController.rebalance(address(fpmm));

    // Snapshot after the rebalance
    (
      ,
      ,
      uint256 reserve1After,
      uint256 reserve0After,
      uint256 priceDifferenceAfter,
      bool reservePriceAboveOraclePriceAfter
    ) = fpmm.getPrices();

    // price difference is less than before
    assertTrue(priceDifferenceAfter < priceDifferenceBefore);
    // price is still below oracle price
    assertTrue(!reservePriceAboveOraclePriceAfter);
    assertTrue(reserve0Before > reserve0After);
    assertTrue(reserve1Before < reserve1After);
    // reserve0 should be 0.25% of the total supply less than before due to the redemption fee
    assertTrue(reserve0Before - reserve0After == ((totalSupply * 25) / 10_000) * 1e6);
  }

  function test_rebalance_whenToken0DebtAndPoolPriceBelowOraclePriceAndRedemptionFeeIsEqualToIncentive_shouldContractAndBringBackToOraclePrice()
    public
    fpmmToken0Debt(12, 18)
  {
    // COP USD rate
    oracleNumerator = 255050000000000000000;
    oracleDenominator = 1e24;

    // 3_920_799_843 COP.m in 12 decimals and 1_000_000 USD.m in 18 decimals
    provideFPMMReserves(3920799843e12, 1000000e18, true);
    setOracleRate(oracleNumerator, oracleDenominator);
    // 50 or 0.5% is max redemption fee in bps
    // setting base rate to 0.25% in 18 decimals
    uint256 baseRate = 25e14;
    mockCollateralRegistry.setRedemptionRateWithDecay(baseRate);

    // calculating the supply that results in the redemption fee being equal to the incentive
    // target amount to redeem comes from the formula in the CDPPolicy.sol
    uint256 targetAmountToRedeem = 784936116205009386827;
    // formula targetSupply = (targetAmountToRedeem * 1e18) / ( incentive - decayedBaseRate);
    uint256 targetSupply = (targetAmountToRedeem * 1e18) / (50 * 1e14 - baseRate);

    setDebtTokenTotalSupply(targetSupply);
    mockCollateralRegistry.setOracleRate(oracleNumerator / 1e6, oracleDenominator / 1e6);

    // debalance fpmm
    swapIn(debtToken, 784_150_001e12);

    // Snapshot before the rebalance
    (
      ,
      ,
      uint256 reserve1Before,
      uint256 reserve0Before,
      uint256 priceDifferenceBefore,
      bool reservePriceAboveOraclePriceBefore
    ) = fpmm.getPrices();

    // pool price is below oracle price
    assertTrue(!reservePriceAboveOraclePriceBefore);
    // price difference is positive
    assertTrue(priceDifferenceBefore > 0);

    liquidityController.rebalance(address(fpmm));

    // Snapshot after the rebalance
    (
      ,
      ,
      uint256 reserve1After,
      uint256 reserve0After,
      uint256 priceDifferenceAfter,
      bool reservePriceAboveOraclePriceAfter
    ) = fpmm.getPrices();

    // price difference is 0
    assertTrue(priceDifferenceAfter == 0);
    // price is still above oracle price
    assertTrue(!reservePriceAboveOraclePriceAfter);
    assertTrue(reserve0Before > reserve0After);
    assertTrue(reserve1Before < reserve1After);
  }

  /* ============================================================ */
  /* ================ Contraction Token 1 Debt ================== */
  /* ============================================================ */
  function test_rebalance_whenToken1DebtAndPoolPriceAboveOraclePriceAndRedemptionFeeSmallerIncentive_shouldContractAndBringPriceBelowOraclePrice()
    public
    fpmmToken1Debt(18, 6)
  {
    // USDC USD rate
    oracleNumerator = 999884980000000000000000;
    oracleDenominator = 1e24;

    provideFPMMReserves(10_000e6, 10_000e18, false);
    setOracleRate(oracleNumerator, oracleDenominator);
    // 50 or 0.5% is max redemption fee in bps
    // setting base rate to 0.25% in 18 decimals
    uint256 baseRate = 25e14;
    uint256 totalSupply = 1e25;
    mockCollateralRegistry.setRedemptionRateWithDecay(baseRate);

    // payed redemption fee is base rate + redeemedAmount/totalSupply
    // setting total supply to 10_000_000 in 18 decimals to ensure total redemption fee is less than 0.5%
    setDebtTokenTotalSupply(totalSupply);
    // since token1 is debt token oracle rate is inverted and scaled to 18 decimals
    mockCollateralRegistry.setOracleRate(oracleDenominator / 1e6, oracleNumerator / 1e6);

    // debalance fpmm by swaping 5_000$ worth of USD.m into the pool
    swapIn(debtToken, 5_000e18);

    // Snapshot before the rebalance
    (
      ,
      ,
      uint256 reserve1Before,
      uint256 reserve0Before,
      uint256 priceDifferenceBefore,
      bool reservePriceAboveOraclePriceBefore
    ) = fpmm.getPrices();

    // pool price is above oracle price
    assertTrue(reservePriceAboveOraclePriceBefore);
    // price difference is positive
    assertTrue(priceDifferenceBefore > 0);

    liquidityController.rebalance(address(fpmm));

    // Snapshot after the rebalance
    (
      ,
      ,
      uint256 reserve1After,
      uint256 reserve0After,
      uint256 priceDifferenceAfter,
      bool reservePriceAboveOraclePriceAfter
    ) = fpmm.getPrices();

    // we allow the price difference to be moved in the wrong direction but not by more than the rebalance incentive
    // this is due to the dynamic rebalance fee that is taken from the swap
    assertTrue(priceDifferenceAfter <= ((priceDifferenceBefore * 50) / 10_000));
    // price is now below oracle price due to the redemption fee
    assertTrue(!reservePriceAboveOraclePriceAfter);
    assertTrue(reserve0Before < reserve0After);
    assertTrue(reserve1Before > reserve1After);
  }

  function test_rebalance_whenToken1DebtAndPoolPriceAboveOraclePriceAndRedemptionFeeLargerIncentive_shouldContractAndBringPriceCloserToOraclePrice()
    public
    fpmmToken1Debt(18, 6)
  {
    // USDC USD rate
    oracleNumerator = 999884980000000000000000;
    oracleDenominator = 1e24;

    provideFPMMReserves(10000e6, 10000e18, false);
    setOracleRate(oracleNumerator, oracleDenominator);
    // 50 or 0.5% is max redemption fee in bps
    // setting base rate to 0.25% in 18 decimals
    uint256 baseRate = 25e14;
    uint256 totalSupply = 1e24;
    mockCollateralRegistry.setRedemptionRateWithDecay(baseRate);

    // payed redemption fee is base rate + redeemedAmount/totalSupply
    // setting total supply to 1_000_000 in 18 decimals.
    // This results in maximum amount that can be redeemed is 0.25% of the total supply.
    // or 2_500e18 which is less than the 5_000e18 to bring the pool price fully back to the oracle price.
    setDebtTokenTotalSupply(totalSupply);
    // since token1 is debt token oracle rate is inverted and scaled to 18 decimals
    mockCollateralRegistry.setOracleRate(oracleDenominator / 1e6, oracleNumerator / 1e6);

    // debalance fpmm
    swapIn(debtToken, 5000e18);

    // Snapshot before the rebalance
    (
      ,
      ,
      uint256 reserve1Before,
      uint256 reserve0Before,
      uint256 priceDifferenceBefore,
      bool reservePriceAboveOraclePriceBefore
    ) = fpmm.getPrices();

    // pool price is above oracle price
    assertTrue(reservePriceAboveOraclePriceBefore);
    // price difference is positive
    assertTrue(priceDifferenceBefore > 0);

    liquidityController.rebalance(address(fpmm));

    // Snapshot after the rebalance
    (
      ,
      ,
      uint256 reserve1After,
      uint256 reserve0After,
      uint256 priceDifferenceAfter,
      bool reservePriceAboveOraclePriceAfter
    ) = fpmm.getPrices();

    // price difference is less than before
    assertTrue(priceDifferenceAfter < priceDifferenceBefore);
    // price is still above oracle price
    assertTrue(reservePriceAboveOraclePriceAfter);
    assertTrue(reserve0Before < reserve0After);
    assertTrue(reserve1Before > reserve1After);
    // reserve1 should be 2_500e18 less than before due to the redemption fee 0.25% * 1_000_000 = 2_500
    assertTrue(reserve1Before - reserve1After == 2_500e18);
  }

  function test_rebalance_whenToken1DebtAndPoolPriceAboveOraclePriceAndRedemptionFeeIsEqualToIncentive_shouldContractAndBringBackToOraclePrice()
    public
    fpmmToken1Debt(18, 6)
  {
    // USDC USD rate
    oracleNumerator = 999884980000000000000000;
    oracleDenominator = 1e24;

    provideFPMMReserves(10_000e6, 10_000e18, false);
    setOracleRate(oracleNumerator, oracleDenominator);
    // 50 or 0.5% is max redemption fee in bps
    // setting base rate to 0.25% in 18 decimals
    uint256 baseRate = 25e14;
    mockCollateralRegistry.setRedemptionRateWithDecay(baseRate);

    // calculating the supply that results in the redemption fee being equal to the incentive
    // target amount to redeem comes from the formula in the CDPPolicy.sol
    uint256 targetAmountToRedeem = 5005589072352346466165;
    // formula targetSupply = (targetAmountToRedeem * 1e18) / ( incentive - decayedBaseRate);
    uint256 targetSupply = (targetAmountToRedeem * 1e18) / (50 * 1e14 - baseRate);

    setDebtTokenTotalSupply(targetSupply);
    // since token1 is debt token oracle rate is inverted and scaled to 18 decimals
    mockCollateralRegistry.setOracleRate(oracleDenominator / 1e6, oracleNumerator / 1e6);

    // debalance fpmm
    swapIn(debtToken, 5000e18);

    // Snapshot before the rebalance
    (
      ,
      ,
      uint256 reserve1Before,
      uint256 reserve0Before,
      uint256 priceDifferenceBefore,
      bool reservePriceAboveOraclePriceBefore
    ) = fpmm.getPrices();

    // pool price is above oracle price
    assertTrue(reservePriceAboveOraclePriceBefore);
    // price difference is positive
    assertTrue(priceDifferenceBefore > 0);

    liquidityController.rebalance(address(fpmm));

    // Snapshot after the rebalance
    (
      ,
      ,
      uint256 reserve1After,
      uint256 reserve0After,
      uint256 priceDifferenceAfter,
      bool reservePriceAboveOraclePriceAfter
    ) = fpmm.getPrices();

    // price difference is 0
    assertTrue(priceDifferenceAfter == 0);
    // price is still above oracle price
    assertTrue(reservePriceAboveOraclePriceAfter);
    assertTrue(reserve0Before < reserve0After);
    assertTrue(reserve1Before > reserve1After);

    assertReserveValueIncentives(reserve0Before, reserve1Before);
    assertRebalanceAmountIncentives(reserve1Before - reserve1After, reserve0After - reserve0Before, false, false);
  }

  /* ============================================================ */
  /* ================= Expansion Token 0 Debt =================== */
  /* ============================================================ */

  function test_whenToken0DebtEnoughFundsInStabilityPoolAndPoolPriceAboveOraclePrice_shouldExpandAndBringPriceBacktoOraclePrice()
    public
    fpmmToken0Debt(12, 6)
  {
    // JPY USD rate
    oracleNumerator = 6755340000000000000000;
    oracleDenominator = 1e24;

    // provide roughly 550_000$ to both reserves
    provideFPMMReserves(81_419_800e12, 550_000e6, true);
    setOracleRate(oracleNumerator, oracleDenominator);

    // debalance fpmm by swaping 75k$ worth of USD.m into the pool
    swapIn(collToken, 75_000e6);

    // set stability pool balance to 100_000_000 jpy.m enough to cover the expansion
    setStabilityPoolBalance(debtToken, 100_000_000e12);

    // Snapshot before the rebalance
    (
      ,
      ,
      uint256 reserve1Before,
      uint256 reserve0Before,
      uint256 priceDifferenceBefore,
      bool reservePriceAboveOraclePriceBefore
    ) = fpmm.getPrices();
    uint256 stabilityPoolDebtBalanceBefore = MockERC20(debtToken).balanceOf(address(mockStabilityPool));
    uint256 stabilityPoolCollBalanceBefore = MockERC20(collToken).balanceOf(address(mockStabilityPool));

    assertTrue(reservePriceAboveOraclePriceBefore);
    assertTrue(priceDifferenceBefore > 0);

    liquidityController.rebalance(address(fpmm));

    (
      ,
      ,
      uint256 reserve1After,
      uint256 reserve0After,
      uint256 priceDifferenceAfter,
      bool reservePriceAboveOraclePriceAfter
    ) = fpmm.getPrices();
    uint256 stabilityPoolDebtBalanceAfter = MockERC20(debtToken).balanceOf(address(mockStabilityPool));
    uint256 stabilityPoolCollBalanceAfter = MockERC20(collToken).balanceOf(address(mockStabilityPool));

    assertTrue(reservePriceAboveOraclePriceAfter);
    assertEq(priceDifferenceAfter, 0);
    assertEq(stabilityPoolDebtBalanceBefore - (reserve0After - reserve0Before) / 1e6, stabilityPoolDebtBalanceAfter);
    assertEq(stabilityPoolCollBalanceBefore + (reserve1Before - reserve1After) / 1e12, stabilityPoolCollBalanceAfter);
    assertTrue(reservePriceAboveOraclePriceAfter);
    assertTrue(reserve0Before < reserve0After);
    assertTrue(reserve1Before > reserve1After);
  }

  function test_whenToken0DebtNotEnoughFundsInStabilityPoolAndPoolPriceAboveOraclePrice_shouldExpandAndBringPriceClosertoOraclePrice()
    public
    fpmmToken0Debt(12, 6)
  {
    // JPY USD rate
    oracleNumerator = 6755340000000000000000;
    oracleDenominator = 1e24;

    // provide roughly 550_000$ to both reserves
    provideFPMMReserves(81_419_800e12, 550_000e6, true);
    setOracleRate(oracleNumerator, oracleDenominator);

    // debalance fpmm by swaping 75k$ worth of USD.m into the pool
    swapIn(collToken, 75_000e6);

    // set stability pool balance to 5_000_000 jpy.m not enough to cover the full expansion
    setStabilityPoolBalance(debtToken, 5_000_000e12);

    // Snapshot before the rebalance
    (
      ,
      ,
      uint256 reserve1Before,
      uint256 reserve0Before,
      uint256 priceDifferenceBefore,
      bool reservePriceAboveOraclePriceBefore
    ) = fpmm.getPrices();
    uint256 stabilityPoolDebtBalanceBefore = MockERC20(debtToken).balanceOf(address(mockStabilityPool));
    uint256 stabilityPoolCollBalanceBefore = MockERC20(collToken).balanceOf(address(mockStabilityPool));

    assertTrue(reservePriceAboveOraclePriceBefore);
    assertTrue(priceDifferenceBefore > 0);

    liquidityController.rebalance(address(fpmm));

    (
      ,
      ,
      uint256 reserve1After,
      uint256 reserve0After,
      uint256 priceDifferenceAfter,
      bool reservePriceAboveOraclePriceAfter
    ) = fpmm.getPrices();
    uint256 stabilityPoolDebtBalanceAfter = MockERC20(debtToken).balanceOf(address(mockStabilityPool));
    uint256 stabilityPoolCollBalanceAfter = MockERC20(collToken).balanceOf(address(mockStabilityPool));

    assertTrue(reservePriceAboveOraclePriceAfter);
    assertTrue(priceDifferenceBefore > priceDifferenceAfter);
    assertEq(stabilityPoolDebtBalanceBefore - (reserve0After - reserve0Before) / 1e6, stabilityPoolDebtBalanceAfter);
    assertEq(stabilityPoolCollBalanceBefore + (reserve1Before - reserve1After) / 1e12, stabilityPoolCollBalanceAfter);
    assertTrue(reservePriceAboveOraclePriceAfter);
    assertTrue(reserve0Before < reserve0After);
    assertTrue(reserve1Before > reserve1After);
    assertTrue(stabilityPoolDebtBalanceAfter == 1e18);
  }

  /* ============================================================ */
  /* ================= Expansion Token 1 Debt =================== */
  /* ============================================================ */

  function test_rebalance_whenToken1DebtEnoughFundsInStabilityPoolAndPoolPriceBelowOraclePrice_shouldExpand()
    public
    fpmmToken1Debt(18, 6)
  {
    oracleNumerator = 999884980000000000000000;
    oracleDenominator = 1e24;

    provideFPMMReserves(10000e6, 10000e18, false);
    setOracleRate(oracleNumerator, oracleDenominator);

    // debalance fpmm
    swapIn(collToken, 5000e6);
    setStabilityPoolBalance(debtToken, 100000e18);

    (
      ,
      ,
      uint256 reserve1Before,
      uint256 reserve0Before,
      uint256 priceDifferenceBefore,
      bool reservePriceAboveOraclePriceBefore
    ) = fpmm.getPrices();

    uint256 stabilityPoolDebtBalanceBefore = MockERC20(debtToken).balanceOf(address(mockStabilityPool));
    uint256 stabilityPoolCollBalanceBefore = MockERC20(collToken).balanceOf(address(mockStabilityPool));

    assertTrue(!reservePriceAboveOraclePriceBefore);
    assertTrue(priceDifferenceBefore > 0);

    liquidityController.rebalance(address(fpmm));

    (
      ,
      ,
      uint256 reserve1After,
      uint256 reserve0After,
      uint256 priceDifferenceAfter,
      bool reservePriceAboveOraclePriceAfter
    ) = fpmm.getPrices();

    uint256 stabilityPoolDebtBalanceAfter = MockERC20(debtToken).balanceOf(address(mockStabilityPool));
    uint256 stabilityPoolCollBalanceAfter = MockERC20(collToken).balanceOf(address(mockStabilityPool));

    assertTrue(!reservePriceAboveOraclePriceAfter);
    assertEq(priceDifferenceAfter, 0);
    assertEq(stabilityPoolDebtBalanceAfter, stabilityPoolDebtBalanceBefore - (reserve1After - reserve1Before));
    assertEq(stabilityPoolCollBalanceAfter, stabilityPoolCollBalanceBefore + (reserve0Before - reserve0After) / 1e12);
  }

  /**
   * @notice Deploy debt and collateral tokens with specified decimals and correct address order
   * @param isToken0Debt True if the debt token is token0, false otherwise
   * @param debtDecimals Decimals of the debt token
   * @param collateralDecimals Decimals of the collateral token
   */
  function deployDebtAndCollateral(bool isToken0Debt, uint8 debtDecimals, uint8 collateralDecimals) public {
    uint256 currentNonce = vm.getNonce(address(this));
    address a1 = vm.computeCreateAddress(address(this), currentNonce);
    address a2 = vm.computeCreateAddress(address(this), currentNonce + 1);

    if (a1 < a2 && isToken0Debt) {
      debtToken = address(new MockERC20("DebtToken", "DT", debtDecimals));
      collToken = address(new MockERC20("CollateralToken", "CT", collateralDecimals));
    } else if (a1 < a2 && !isToken0Debt) {
      collToken = address(new MockERC20("CollateralToken", "CT", collateralDecimals));
      debtToken = address(new MockERC20("DebtToken", "DT", debtDecimals));
    } else if (a1 > a2 && isToken0Debt) {
      collToken = address(new MockERC20("CollateralToken", "CT", collateralDecimals));
      debtToken = address(new MockERC20("DebtToken", "DT", debtDecimals));
    } else {
      debtToken = address(new MockERC20("DebtToken", "DT", debtDecimals));
      collToken = address(new MockERC20("CollateralToken", "CT", collateralDecimals));
    }
  }

  /**
   * @notice Provide liquidity to the FPMM
   * @param reserve0 Reserve of token0
   * @param reserve1 Reserve of token1
   */
  function provideFPMMReserves(uint256 reserve0, uint256 reserve1, bool isToken0Debt) public {
    if (isToken0Debt) {
      MockERC20(debtToken).mint(address(fpmm), reserve0);
      MockERC20(collToken).mint(address(fpmm), reserve1);
    } else {
      MockERC20(collToken).mint(address(fpmm), reserve0);
      MockERC20(debtToken).mint(address(fpmm), reserve1);
    }
    fpmm.mint(address(this));
  }

  /**
   * @notice Set the oracle rate
   * @param numerator Numerator of the oracle rate
   * @param denominator Denominator of the oracle rate
   */
  function setOracleRate(uint256 numerator, uint256 denominator) public {
    vm.mockCall(
      sortedOracles,
      abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID),
      abi.encode(numerator, denominator)
    );
  }

  /**
   * @notice Mock the breaker box trading mode
   * @param shouldBreak True if the breaker box should break, false otherwise
   */
  function mockBreakerBoxTradingMode(bool shouldBreak) public {
    if (shouldBreak) {
      vm.mockCall(
        breakerBox,
        abi.encodeWithSelector(IBreakerBox.getRateFeedTradingMode.selector, referenceRateFeedID),
        abi.encode(3)
      );
    } else {
      vm.mockCall(
        breakerBox,
        abi.encodeWithSelector(IBreakerBox.getRateFeedTradingMode.selector, referenceRateFeedID),
        abi.encode(0)
      );
    }
  }

  /**
   * @notice Set the total supply of the debt token
   * @param totalSupply Total supply of the debt token
   */
  function setDebtTokenTotalSupply(uint256 totalSupply) public {
    vm.mockCall(debtToken, abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(totalSupply));
  }
  /**
   * @notice Set the balance of the stability pool
   * @param token Address of the token
   * @param balance Balance of the stability pool
   */
  function setStabilityPoolBalance(address token, uint256 balance) public {
    MockERC20(token).mint(address(mockStabilityPool), balance);
  }

  /**
   * @notice Performs a swap in the FPMM
   * @param tokenIn Address of the token to swap in
   * @param amountIn Amount of the token to swap in
   */
  function swapIn(address tokenIn, uint256 amountIn) public {
    uint256 expectedOut = fpmm.getAmountOut(amountIn, tokenIn);
    address tokenOut = fpmm.token1() == tokenIn ? fpmm.token0() : fpmm.token1();
    MockERC20(tokenIn).mint(address(this), amountIn);
    MockERC20(tokenIn).transfer(address(fpmm), amountIn);
    if (fpmm.token0() == tokenIn) {
      fpmm.swap(0, expectedOut, address(this), "");
    } else {
      fpmm.swap(expectedOut, 0, address(this), "");
    }
  }

  function assertReserveValueIncentives(uint256 reserve0Before, uint256 reserve1Before) public {
    (uint256 rateNumerator, uint256 rateDenominator, uint256 reserve1After, uint256 reserve0After, , ) = fpmm
      .getPrices();

    MockERC20 token0 = MockERC20(fpmm.token0());
    MockERC20 token1 = MockERC20(fpmm.token1());

    uint256 token0Scaler = 10 ** token0.decimals();
    uint256 token1Scaler = 10 ** token1.decimals();

    uint256 totalReserveValueBefore;
    uint256 totalReserveValueAfter;
    if (token0.decimals() > token1.decimals()) {
      // calculate total reserve value in debt token decimals
      totalReserveValueBefore = reserve0Before + ((reserve1Before * rateDenominator) / (rateNumerator));
      totalReserveValueAfter = reserve0After + ((reserve1After * rateDenominator) / (rateNumerator));
    } else {
      // calculate total reserve value in collateral token decimals
      totalReserveValueBefore = reserve1Before + ((reserve0Before * rateNumerator) / (rateDenominator));
      totalReserveValueAfter = reserve1After + ((reserve0After * rateNumerator) / (rateDenominator));
    }
    console.log("--------------------------------");
    console.log("totalReserveValueBefore", totalReserveValueBefore);
    console.log("totalReserveValueAfter", totalReserveValueAfter);
    console.log("--------------------------------");
    uint256 reserveValueDifference = ((totalReserveValueBefore - totalReserveValueAfter) * 10_000) /
      totalReserveValueBefore;
    // Since we allow the incentive to be up to 50 bps of the amount takenOut off the fppm and the max amount that makes sense for a
    // rebalance is taking out 50% of the reserves, we allow the incentive to be up to 0.25% of the total reserve value
    assertTrue(reserveValueDifference <= 25); // 0.25%
  }

  function assertRebalanceAmountIncentives(
    uint256 amountTakenOut,
    uint256 amountAdded,
    bool isToken0Out,
    bool isCheapContraction
  ) public {
    (uint256 rateNumerator, uint256 rateDenominator, , , , ) = fpmm.getPrices();

    uint256 amountInInTokenOut;
    if (isToken0Out) {
      amountInInTokenOut = (amountAdded * rateDenominator) / rateNumerator;
    } else {
      amountInInTokenOut = (amountAdded * rateNumerator) / rateDenominator;
    }
    uint256 bpsDifference = ((amountTakenOut - amountInInTokenOut) * 10_000) / amountTakenOut;
    // 50 bps is the max but for contractions the amount can be less depending on the redemption rate
    if (isCheapContraction) {
      assertTrue(bpsDifference < 50); // 0.5%
    } else {
      assertTrue(bpsDifference == 50); // 0.5%
    }
  }

  function assertStabilityPoolIncentives() public {}
}
