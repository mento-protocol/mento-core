// SPDX-License-Identifier: UNLICENSED
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Test, console2 as console } from "celo-foundry/Test.sol";
import { IERC20 } from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

import { McMintIntegration } from "../utils/McMintIntegration.sol";
import { TokenHelpers } from "../utils/TokenHelpers.sol";

import { Broker } from "contracts/Broker.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";
import { IExchangeProvider } from "contracts/interfaces/IExchangeProvider.sol";
import { IBiPoolManager } from "contracts/interfaces/IBiPoolManager.sol";
import { IStableToken } from "contracts/interfaces/IStableToken.sol";
import { IPricingModule } from "contracts/interfaces/IPricingModule.sol";

import { FixidityLib } from "contracts/common/FixidityLib.sol";

// forge test --match-contract BrokerIntegration -vvv
contract BrokerIntegrationTest is Test, McMintIntegration, TokenHelpers {
  address trader;

  function setUp() public {
    setUp_mcMint();

    trader = actor("trader");

    mint(cUSDToken, trader, 10**22); // Mint 10k to trader
    mint(cEURToken, trader, 10**22); // Mint 10k to trader

    deal(address(celoToken), trader, 1000 * 10**18); // Gift 10k to trader

    deal(address(celoToken), address(reserve), 10**24); // Gift 1Mil to reserve
    deal(address(usdcToken), address(reserve), 10**24); // Gift 1Mil to reserve
  }

  /**
   * @notice Test helper function to do swap in
   */
  function doSwapIn(
    bytes32 poolId,
    uint256 amountIn,
    address tokenIn,
    address tokenOut
  ) public returns (uint256 expectedOut, uint256 actualOut) {
    // Get exchange provider from broker
    address[] memory exchangeProviders = broker.getExchangeProviders();
    assertEq(exchangeProviders.length, 1);

    // Get exchange from provider
    IBiPoolManager.PoolExchange memory exchange = IBiPoolManager(exchangeProviders[0]).getPoolExchange(poolId);

    uint256 bucketIn;
    uint256 bucketOut;

    if (tokenIn == exchange.asset0) {
      bucketIn = exchange.bucket0;
      bucketOut = exchange.bucket1;
    } else {
      bucketIn = exchange.bucket1;
      bucketOut = exchange.bucket0;
    }

    expectedOut = broker.getAmountOut(exchangeProviders[0], poolId, tokenIn, tokenOut, amountIn);

    changePrank(trader);
    IERC20(tokenIn).approve(address(broker), amountIn);

    // Execute swap
    actualOut = broker.swapIn(address(exchangeProviders[0]), poolId, tokenIn, tokenOut, 1000 * 10**18, 0);
  }

  function test_swap_whenBucketTriggerConditionsAreMet_shouldTriggerBucketUpdate() public {
    IBiPoolManager.PoolExchange memory pool = biPoolManager.getPoolExchange(pair_cUSD_USDCet_ID);

    // FF by bucket update frequency time
    vm.warp(pool.config.referenceRateResetFrequency + pool.lastBucketUpdate);

    // Median report recent == true
    sortedOracles.setMedianTimestampToNow(pool.config.referenceRateFeedID);

    changePrank(trader);
    IERC20(address(cUSDToken)).approve(address(broker), cUSDToken.totalSupply());

    vm.expectEmit(false, false, false, false);
    emit BucketsUpdated(pair_cUSD_USDCet_ID, 0, 0);

    broker.swapIn(address(biPoolManager), pair_cUSD_USDCet_ID, address(cUSDToken), address(usdcToken), 1, 0);
  }

  function test_getExchangeProviders_shouldReturnProviderWithCorrectExchanges() public {
    address[] memory exchangeProviders = broker.getExchangeProviders();
    assertEq(exchangeProviders.length, 1);

    IExchangeProvider.Exchange[] memory exchanges = IExchangeProvider(exchangeProviders[0]).getExchanges();
    assertEq(exchanges.length, 5);

    IExchangeProvider.Exchange memory exchange;
    for (uint256 i = 0; i < exchanges.length; i++) {
      exchange = exchanges[i];
      assert(exchange.assets[0] == address(cUSDToken) || exchange.assets[0] == address(cEURToken));
      assert(
        exchange.assets[1] == address(cEURToken) ||
          exchange.assets[1] == address(celoToken) ||
          exchange.assets[1] == address(usdcToken)
      );
    }
  }

  function test_swapIn_cUSDToUSDCet() public {
    uint256 amountIn = 1000 * 10**18; // 1k
    IERC20 tokenIn = cUSDToken;
    IERC20 tokenOut = usdcToken;
    bytes32 poolId = pair_cUSD_USDCet_ID;

    // Get amounts before swap
    uint256 traderTokenInBefore = tokenIn.balanceOf(trader);
    uint256 traderTokenOutBefore = tokenOut.balanceOf(trader);
    uint256 reserveCollateralBalanceBefore = tokenOut.balanceOf(address(reserve));
    uint256 StableAssetSupplyBefore = tokenIn.totalSupply();

    // Execute swap
    (uint256 expectedOut, uint256 actualOut) = doSwapIn(poolId, amountIn, address(tokenIn), address(tokenOut));

    // Get amounts after swap
    uint256 traderTokenInAfter = tokenIn.balanceOf(trader);
    uint256 traderTokenOutAfter = tokenOut.balanceOf(trader);
    uint256 reserveCollateralBalanceAfter = tokenOut.balanceOf(address(reserve));
    uint256 StableAssetSupplyAfter = tokenIn.totalSupply();

    // getAmountOut == swapOut
    assertEq(expectedOut, actualOut);
    // Trader token in balance decreased
    assertEq(traderTokenInBefore - traderTokenInAfter, amountIn);
    // Trader token out balance increased
    assertEq(traderTokenOutBefore + expectedOut, traderTokenOutAfter);
    // Reserve collateral asset balance decreased
    assertEq(reserveCollateralBalanceBefore - expectedOut, reserveCollateralBalanceAfter);
    // Stable asset supply decrease from burn
    assertEq(StableAssetSupplyBefore - amountIn, StableAssetSupplyAfter);
  }

  function test_swapIn_cEURToUSDCet() public {
    uint256 amountIn = 1000 * 10**18; // 1k
    IERC20 tokenIn = cEURToken;
    IERC20 tokenOut = usdcToken;
    bytes32 poolId = pair_cEUR_USDCet_ID;

    // Get amounts before swap
    uint256 traderTokenInBefore = tokenIn.balanceOf(trader);
    uint256 traderTokenOutBefore = tokenOut.balanceOf(trader);
    uint256 reserveCollateralBalanceBefore = tokenOut.balanceOf(address(reserve));
    uint256 StableAssetSupplyBefore = tokenIn.totalSupply();

    // Execute swap
    (uint256 expectedOut, uint256 actualOut) = doSwapIn(poolId, amountIn, address(tokenIn), address(tokenOut));

    // Get amounts after swap
    uint256 traderTokenInAfter = tokenIn.balanceOf(trader);
    uint256 traderTokenOutAfter = tokenOut.balanceOf(trader);
    uint256 reserveCollateralBalanceAfter = tokenOut.balanceOf(address(reserve));
    uint256 StableAssetSupplyAfter = tokenIn.totalSupply();

    // getAmountOut == swapOut
    assertEq(expectedOut, actualOut);
    // Trader token in balance decreased
    assertEq(traderTokenInBefore - traderTokenInAfter, amountIn);
    // Trader token out balance increased
    assertEq(traderTokenOutBefore + expectedOut, traderTokenOutAfter);
    // Reserve collateral asset balance decreased
    assertEq(reserveCollateralBalanceBefore - expectedOut, reserveCollateralBalanceAfter);
    // Stable asset supply decrease from burn
    assertEq(StableAssetSupplyBefore - amountIn, StableAssetSupplyAfter);
  }

  function test_swapIn_cEURTocUSD() public {
    uint256 amountIn = 1000 * 10**18; // 1k
    IERC20 tokenIn = cEURToken;
    IERC20 tokenOut = cUSDToken;
    bytes32 poolId = pair_cUSD_cEUR_ID;

    // Get amounts before swap
    uint256 traderTokenInBefore = tokenIn.balanceOf(trader);
    uint256 traderTokenOutBefore = tokenOut.balanceOf(trader);

    uint256 tokenInSupplyBefore = tokenIn.totalSupply();
    uint256 tokenOutSupplyBefore = tokenOut.totalSupply();

    // Execute swap
    (uint256 expectedOut, uint256 actualOut) = doSwapIn(poolId, amountIn, address(tokenIn), address(tokenOut));

    // Get amounts after swap
    uint256 traderTokenInAfter = tokenIn.balanceOf(trader);
    uint256 traderTokenOutAfter = tokenOut.balanceOf(trader);

    uint256 tokenInSupplyAfter = tokenIn.totalSupply();
    uint256 tokenOutSupplyAfter = tokenOut.totalSupply();

    // getAmountOut == swapOut
    assertEq(expectedOut, actualOut);
    // Trader token in balance decreased
    assertEq(traderTokenInBefore - traderTokenInAfter, amountIn);
    // Trader token out balance increased
    assertEq(traderTokenOutBefore + expectedOut, traderTokenOutAfter);
    // Token out stable asset supply increase from mint
    assertEq(tokenOutSupplyBefore + expectedOut, tokenOutSupplyAfter);
    // Token in stable asset supply decrease from burn
    assertEq(tokenInSupplyBefore - amountIn, tokenInSupplyAfter);
  }

  function test_swapIn_cUSDTocEUR() public {
    uint256 amountIn = 1000 * 10**18; // 1k
    IERC20 tokenIn = cUSDToken;
    IERC20 tokenOut = cEURToken;
    bytes32 poolId = pair_cUSD_cEUR_ID;

    // Get amounts before swap
    uint256 traderTokenInBefore = tokenIn.balanceOf(trader);
    uint256 traderTokenOutBefore = tokenOut.balanceOf(trader);

    uint256 tokenInSupplyBefore = tokenIn.totalSupply();
    uint256 tokenOutSupplyBefore = tokenOut.totalSupply();

    // Execute swap
    (uint256 expectedOut, uint256 actualOut) = doSwapIn(poolId, amountIn, address(tokenIn), address(tokenOut));

    // Get amounts after swap
    uint256 traderTokenInAfter = tokenIn.balanceOf(trader);
    uint256 traderTokenOutAfter = tokenOut.balanceOf(trader);

    uint256 tokenInSupplyAfter = tokenIn.totalSupply();
    uint256 tokenOutSupplyAfter = tokenOut.totalSupply();

    // getAmountOut == swapOut
    assertEq(expectedOut, actualOut);
    // Trader token in balance decreased
    assertEq(traderTokenInBefore - traderTokenInAfter, amountIn);
    // Trader token out balance increased
    assertEq(traderTokenOutBefore + expectedOut, traderTokenOutAfter);
    // Token out stable asset supply increase from mint
    assertEq(tokenOutSupplyBefore + expectedOut, tokenOutSupplyAfter);
    // Token in stable asset supply decrease from burn
    assertEq(tokenInSupplyBefore - amountIn, tokenInSupplyAfter);
  }

  function test_swapIn_CELOTocEUR() public {
    uint256 amountIn = 1000 * 10**18; // 1k
    IERC20 tokenIn = celoToken;
    IERC20 tokenOut = cEURToken;
    bytes32 poolId = pair_cEUR_CELO_ID;

    // Get amounts before swap
    uint256 traderTokenInBefore = tokenIn.balanceOf(trader);
    uint256 traderTokenOutBefore = tokenOut.balanceOf(trader);

    uint256 reserveCollateralBalanceBefore = tokenIn.balanceOf(address(reserve));
    uint256 StableAssetSupplyBefore = tokenOut.totalSupply();

    // Execute swap
    (uint256 expectedOut, uint256 actualOut) = doSwapIn(poolId, amountIn, address(tokenIn), address(tokenOut));

    // Get amounts after swap
    uint256 traderTokenInAfter = tokenIn.balanceOf(trader);
    uint256 traderTokenOutAfter = tokenOut.balanceOf(trader);

    uint256 reserveCollateralBalanceAfter = tokenIn.balanceOf(address(reserve));
    uint256 StableAssetSupplyAfter = tokenOut.totalSupply();

    // getAmountOut == swapOut
    assertEq(expectedOut, actualOut);
    // Trader token in balance decreased
    assertEq(traderTokenInBefore - traderTokenInAfter, amountIn);
    // Trader token out balance increased
    assertEq(traderTokenOutBefore + expectedOut, traderTokenOutAfter);
    // Reserve collateral asset balance increase
    assertEq(reserveCollateralBalanceBefore + amountIn, reserveCollateralBalanceAfter);
    // Stable asset supply increase from mint
    assertEq(StableAssetSupplyBefore + expectedOut, StableAssetSupplyAfter);
  }

  function test_swapIn_CELOTocUSD() public {
    uint256 amountIn = 1000 * 10**18; // 1k
    IERC20 tokenIn = celoToken;
    IERC20 tokenOut = cUSDToken;
    bytes32 poolId = pair_cUSD_CELO_ID;

    // Get amounts before swap
    uint256 traderTokenInBefore = tokenIn.balanceOf(trader);
    uint256 traderTokenOutBefore = tokenOut.balanceOf(trader);

    uint256 reserveCollateralBalanceBefore = tokenIn.balanceOf(address(reserve));
    uint256 StableAssetSupplyBefore = tokenOut.totalSupply();

    // Execute swap
    (uint256 expectedOut, uint256 actualOut) = doSwapIn(poolId, amountIn, address(tokenIn), address(tokenOut));

    // Get amounts after swap
    uint256 traderTokenInAfter = tokenIn.balanceOf(trader);
    uint256 traderTokenOutAfter = tokenOut.balanceOf(trader);

    uint256 reserveCollateralBalanceAfter = tokenIn.balanceOf(address(reserve));
    uint256 StableAssetSupplyAfter = tokenOut.totalSupply();

    // getAmountOut == swapOut
    assertEq(expectedOut, actualOut);
    // Trader token in balance decreased
    assertEq(traderTokenInBefore - traderTokenInAfter, amountIn);
    // Trader token out balance increased
    assertEq(traderTokenOutBefore + expectedOut, traderTokenOutAfter);
    // Reserve collateral asset balance increase
    assertEq(reserveCollateralBalanceBefore + amountIn, reserveCollateralBalanceAfter);
    // Stable asset supply increase from mint
    assertEq(StableAssetSupplyBefore + expectedOut, StableAssetSupplyAfter);
  }
}
