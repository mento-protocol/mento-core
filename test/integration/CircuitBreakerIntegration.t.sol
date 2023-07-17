// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Test, console2 as console } from "celo-foundry/Test.sol";
import { IERC20 } from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

import { IntegrationTest } from "../utils/IntegrationTest.t.sol";
import { TokenHelpers } from "../utils/TokenHelpers.t.sol";

import { BreakerBox } from "contracts/oracles/BreakerBox.sol";

import { FixidityLib } from "contracts/common/FixidityLib.sol";
import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";

contract CircuitBreakerIntegration is IntegrationTest, TokenHelpers {
  using SafeMath for uint256;
  using FixidityLib for FixidityLib.Fraction;

  uint256 fixed1 = FixidityLib.fixed1().unwrap();

  address trader;

  function setUp() public {
    IntegrationTest.setUp();

    trader = actor("trader");

    mint(cUSDToken, trader, 10 ** 22); // Mint 10k to trader
    mint(cEURToken, trader, 10 ** 22); // Mint 10k to trader
    deal(address(celoToken), address(reserve), 1e24); // Gift 1Mil Celo to reserve
    deal(address(usdcToken), address(reserve), 1e24); // Gift 1Mil USDC to reserve
  }

  /**
   * @notice Test helper function to do swap in
   */
  function doSwapIn(bytes32 poolId, address tokenIn, address tokenOut, bool shouldBreak) public {
    uint256 amountIn = 10 ** 18;
    address[] memory exchangeProviders = broker.getExchangeProviders();
    assertEq(exchangeProviders.length, 1);

    changePrank(trader);
    IERC20(tokenIn).approve(address(broker), amountIn);

    // Execute swap
    if (shouldBreak) {
      vm.expectRevert("Trading is suspended for this reference rate");
    }
    broker.swapIn(exchangeProviders[0], poolId, tokenIn, tokenOut, amountIn, 0);
  }

  function test_medianDeltaBreaker_whenMedianExceedsThreshold_schoulHalt() public {
    // new Median thats larger than threshold: 0.15
    setMedianRate(cUSD_CELO_referenceRateFeedID, 5e23 * 1.151);
    //try swap with shouldBreak true
    doSwapIn(pair_cUSD_CELO_ID, address(cUSDToken), address(celoToken), true);
    uint8 tradingMode = breakerBox.getRateFeedTradingMode(cUSD_CELO_referenceRateFeedID);
    assertEq(uint256(tradingMode), 3); // 3 = trading halted

    // cool down breaker and set new median that doesnt exceed threshold
    vm.warp(now + 5 minutes);
    setMedianRate(cUSD_CELO_referenceRateFeedID, 5e23);

    //try swap with shouldBreak false since trading is bidirectional again
    doSwapIn(pair_cUSD_CELO_ID, address(cUSDToken), address(celoToken), false);
    tradingMode = breakerBox.getRateFeedTradingMode(cUSD_CELO_referenceRateFeedID);
    assertEq(uint256(tradingMode), 0); // 0 = bidirectional trading
  }

  function test_valueDeltaBreaker_whenMedianExceedsThreshold_shouldHalt() public {
    uint256 blockNumber = block.number;
    // new Median thats larger than threshold: 0.1
    setMedianRate(cUSD_bridgedUSDC_referenceRateFeedID, 1e24 + 1e24 * 0.11);

    //try swap with shouldBreak true
    doSwapIn(pair_cUSD_bridgedUSDC_ID, address(cUSDToken), address(usdcToken), true);

    //check tradingModes
    uint8 rateFeedTradingMode = breakerBox.getRateFeedTradingMode(cUSD_bridgedUSDC_referenceRateFeedID);
    (uint8 valueDeltaTradingMode, , ) = breakerBox.rateFeedBreakerStatus(
      cUSD_bridgedUSDC_referenceRateFeedID,
      address(valueDeltaBreaker)
    );
    (uint8 medianDeltaTradingMode, , ) = breakerBox.rateFeedBreakerStatus(
      cUSD_bridgedUSDC_referenceRateFeedID,
      address(medianDeltaBreaker)
    );
    assertEq(uint256(rateFeedTradingMode), 3); // 3 = trading halted
    assertEq(uint256(valueDeltaTradingMode), 3); // 3 = trading halted
    assertEq(uint256(medianDeltaTradingMode), 0); // 0 = bidirectional trading

    // cool down breaker and set new median that doesnt exceed threshold
    vm.warp(now + 1 seconds);
    setMedianRate(cUSD_bridgedUSDC_referenceRateFeedID, 1e24);

    //check tradingModes
    rateFeedTradingMode = breakerBox.getRateFeedTradingMode(cUSD_bridgedUSDC_referenceRateFeedID);
    (valueDeltaTradingMode, , ) = breakerBox.rateFeedBreakerStatus(
      cUSD_bridgedUSDC_referenceRateFeedID,
      address(valueDeltaBreaker)
    );
    (medianDeltaTradingMode, , ) = breakerBox.rateFeedBreakerStatus(
      cUSD_bridgedUSDC_referenceRateFeedID,
      address(medianDeltaBreaker)
    );
    assertEq(uint256(rateFeedTradingMode), 0); // 0 = bidirectional trading
    assertEq(uint256(valueDeltaTradingMode), 0); // 0 = bidirectional trading
    assertEq(uint256(medianDeltaTradingMode), 0); // 0 = bidirectional trading

    //try swap with shouldBreak false since trading is bidirectional again
    doSwapIn(pair_cUSD_bridgedUSDC_ID, address(cUSDToken), address(usdcToken), false);
    assertEq(blockNumber, block.number); // block number should not change
  }

  function test_dependantRateFeeds_whenDependenciesHalt_shouldHalt() public {
    // trip value delta Breaker for cUSD/USDC
    setMedianRate(cUSD_bridgedUSDC_referenceRateFeedID, 1e24 + 1e24 * 0.11);

    // check that trading modes are set correctly
    uint8 tradingModecUSDbridgedUSDC = breakerBox.getRateFeedTradingMode(cUSD_bridgedUSDC_referenceRateFeedID);
    uint8 tradingModecEURBridgedUSDC = breakerBox.getRateFeedTradingMode(cEUR_bridgedUSDC_referenceRateFeedID);
    uint8 independentTradingMode = breakerBox.rateFeedTradingMode(cEUR_bridgedUSDC_referenceRateFeedID);
    assertEq(uint256(tradingModecUSDbridgedUSDC), 3); // 3 = trading halted
    assertEq(uint256(independentTradingMode), 0); // 0 = bidirectional trading
    assertEq(uint256(tradingModecEURBridgedUSDC), 3); // 3 = trading halted

    // ensure that swaps fail for both pairs
    doSwapIn(pair_cUSD_bridgedUSDC_ID, address(cUSDToken), address(usdcToken), true);
    doSwapIn(pair_cEUR_bridgedUSDC_ID, address(cEURToken), address(usdcToken), true);

    // cool down breaker and set new median that doesnt exceed threshold
    vm.warp(now + 1 seconds);
    setMedianRate(cUSD_bridgedUSDC_referenceRateFeedID, 1e24);

    // check that trading modes are set correctly
    tradingModecUSDbridgedUSDC = breakerBox.getRateFeedTradingMode(cUSD_bridgedUSDC_referenceRateFeedID);
    tradingModecEURBridgedUSDC = breakerBox.getRateFeedTradingMode(cEUR_bridgedUSDC_referenceRateFeedID);
    independentTradingMode = breakerBox.rateFeedTradingMode(cEUR_bridgedUSDC_referenceRateFeedID);
    assertEq(uint256(tradingModecUSDbridgedUSDC), 0); // 0 = bidirectional trading
    assertEq(uint256(independentTradingMode), 0); // 0 = bidirectional trading
    assertEq(uint256(tradingModecEURBridgedUSDC), 0); // 0 = bidirectional trading

    // ensure that swaps fail for both pairs
    doSwapIn(pair_cUSD_bridgedUSDC_ID, address(cUSDToken), address(usdcToken), false);
    doSwapIn(pair_cEUR_bridgedUSDC_ID, address(cEURToken), address(usdcToken), false);
  }
}
