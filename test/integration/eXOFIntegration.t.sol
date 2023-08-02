// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Test, console2 as console } from "celo-foundry/Test.sol";
import { IERC20 } from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import { ValueDeltaBreaker } from "contracts/oracles/breakers/ValueDeltaBreaker.sol";

import { IntegrationTest } from "../utils/IntegrationTest.t.sol";
import { TokenHelpers } from "../utils/TokenHelpers.t.sol";
import { Arrays } from "../utils/Arrays.sol";

import { IExchangeProvider } from "contracts/interfaces/IExchangeProvider.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";

import { FixidityLib } from "contracts/common/FixidityLib.sol";
import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";

contract EXOFIntegrationTest is IntegrationTest, TokenHelpers {
  using SafeMath for uint256;
  address trader;
  ValueDeltaBreaker valueDeltaBreaker2;

  bytes32 pair_eXOF_EUROC_ID;

  function setUp() public {
    IntegrationTest.setUp();

    trader = actor("trader");

    mint(eXOFToken, trader, 10**22); // Mint 10k to trader
    deal(address(eurocToken), trader, 10**(6 + 4)); // Gift 10K EUROC to Trader
    deal(address(eurocToken), address(reserve), 10**(6 + 6)); // Gift 1Mil EUROC to reserve

    // set up second ValueDeltaBreaker used for eXOF
    uint256 valueDeltaBreakerDefaultThreshold = 0.1 * 10**24;
    uint256 valueDeltaBreakerDefaultCooldown = 0 seconds;

    address[] memory rateFeed = Arrays.addresses(eXOF_bridgedEUROC_referenceRateFeedID);

    uint256[] memory rateChangeThreshold = Arrays.uints(0.2 * 10**24); // 20% -> potential rebase

    uint256[] memory cooldownTime = Arrays.uints(0 seconds); // 0 seconds cooldown -> non-recoverable

    valueDeltaBreaker2 = new ValueDeltaBreaker(
      valueDeltaBreakerDefaultCooldown,
      valueDeltaBreakerDefaultThreshold,
      ISortedOracles(address(sortedOracles)),
      rateFeed,
      rateChangeThreshold,
      cooldownTime
    );

    uint256[] memory referenceValues = Arrays.uints(656 * 1e24); // 1 eXOF ≈  0.001524 EUROC
    valueDeltaBreaker2.setReferenceValues(rateFeed, referenceValues);

    vm.startPrank(deployer);
    breakerBox.addBreaker(address(valueDeltaBreaker2), 3);
    breakerBox.toggleBreaker(address(valueDeltaBreaker2), eXOF_bridgedEUROC_referenceRateFeedID, true);
  }

  /**
   * @notice Test helper function to do swap with revert option on quote and swap
   */
  function assert_swapIn(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    bool getAmountOutReverts,
    string memory getAmountOutRevertMessage,
    bool swapInReverts,
    string memory swapInRevertMessage
  ) internal {
    bytes32 poolId = pair_eXOF_bridgedEUROC_ID;

    // Get exchange provider from broker
    address[] memory exchangeProviders = broker.getExchangeProviders();
    assertEq(exchangeProviders.length, 1);

    if (getAmountOutReverts) {
      vm.expectRevert(bytes(getAmountOutRevertMessage));
    }
    broker.getAmountOut(exchangeProviders[0], poolId, tokenIn, tokenOut, amountIn);

    changePrank(trader);
    IERC20(tokenIn).approve(address(broker), amountIn);

    if (swapInReverts) {
      vm.expectRevert(bytes(swapInRevertMessage));
    }
    broker.swapIn(address(exchangeProviders[0]), poolId, tokenIn, tokenOut, amountIn, 0);
  }

  /**
   * @notice Test helper function to do a succesful swap
   */
  function assert_swapIn_successful(
    uint256 amountIn,
    address tokenIn,
    address tokenOut
  ) public {
    assert_swapIn(tokenIn, tokenOut, amountIn, false, "", false, "");
  }

  /**
   * @notice Test helper function to do a swap that reverts on circuit breaker
   */
  function assert_swapIn_tradingSuspended(
    uint256 amountIn,
    address tokenIn,
    address tokenOut
  ) public {
    assert_swapIn(tokenIn, tokenOut, amountIn, false, "", true, "Trading is suspended for this reference rate");
  }

  /**
   * @notice Test helper function to do a swap that reverts on invalid median
   */
  function assert_swapIn_noValidMedian(
    uint256 amountIn,
    address tokenIn,
    address tokenOut
  ) public {
    assert_swapIn(tokenIn, tokenOut, amountIn, true, "no valid median", true, "no valid median");
  }

  function test_setUp_isCorrect() public {
    assertTrue(breakerBox.isBreakerEnabled(address(valueDeltaBreaker), eXOF_bridgedEUROC_referenceRateFeedID));
    assertTrue(breakerBox.isBreakerEnabled(address(valueDeltaBreaker2), eXOF_bridgedEUROC_referenceRateFeedID));
    assertEq(
      valueDeltaBreaker.rateChangeThreshold(eXOF_bridgedEUROC_referenceRateFeedID),
      0.15 * 1e24 // 15% recoverable breaker
    );
    assertEq(
      valueDeltaBreaker2.rateChangeThreshold(eXOF_bridgedEUROC_referenceRateFeedID),
      0.2 * 1e24 // 20% non-recoverable breaker
    );
    assertEq(valueDeltaBreaker.getCooldown(eXOF_bridgedEUROC_referenceRateFeedID), 1 seconds);
    assertEq(valueDeltaBreaker2.getCooldown(eXOF_bridgedEUROC_referenceRateFeedID), 0 seconds);
  }

  function test_eXOFPool_SwapInSwapOutWorkAsExpected() public {
    uint256 eXOFBalance = eXOFToken.balanceOf(trader);
    uint256 eurocBalance = eurocToken.balanceOf(trader);

    assert_swapIn_successful(1e6, address(eurocToken), address(eXOFToken));
    // 1 EUROC ≈  656 eXOF
    assertTrue(eXOFBalance < eXOFToken.balanceOf(trader) && eXOFToken.balanceOf(trader) < eXOFBalance + (1e18 * 656));
    assertEq(eurocToken.balanceOf(trader), eurocBalance - 1e6);

    eXOFBalance = eXOFToken.balanceOf(trader);
    eurocBalance = eurocToken.balanceOf(trader);

    assert_swapIn_successful(1e18, address(eXOFToken), address(eurocToken));
    assertEq(eXOFToken.balanceOf(trader), eXOFBalance - 1e18);
    // 1/656 ≈  0.001524 -> 1 eXOF ≈  0.001524 EUROC
    assertTrue(
      eurocBalance < eurocToken.balanceOf(trader) && eurocToken.balanceOf(trader) < eurocBalance + (1e6 * 0.001524)
    );
  }

  function test_eXOFPool_whenMedianExceedsRecoverableBreaker_shouldBreakAndRecover() public {
    // New median that exceeds recoverable breaker threshold: 15%
    setMedianRate(eXOF_bridgedEUROC_referenceRateFeedID, 1e24 * 656 + (1e24 * 656 * 0.16));

    // Try swap that should revert
    assert_swapIn_tradingSuspended(1e6, address(eurocToken), address(eXOFToken));

    // Check breakers: verify that only recoverable breaker has triggered
    uint8 rateFeedTradingMode = breakerBox.getRateFeedTradingMode(eXOF_bridgedEUROC_referenceRateFeedID);
    (uint8 valueDelta1TradingMode, , ) = breakerBox.rateFeedBreakerStatus(
      eXOF_bridgedEUROC_referenceRateFeedID,
      address(valueDeltaBreaker)
    );
    (uint8 valueDelta2TradingMode, , ) = breakerBox.rateFeedBreakerStatus(
      eXOF_bridgedEUROC_referenceRateFeedID,
      address(valueDeltaBreaker2)
    );
    assertEq(uint256(rateFeedTradingMode), 3); // 3 = trading halted
    assertEq(uint256(valueDelta1TradingMode), 3); // 3 = trading halted
    assertEq(uint256(valueDelta2TradingMode), 0); // 0 = bidirectional trading

    // New median that is below recoverable breaker threshold: 15%
    vm.warp(now + 1 seconds);
    setMedianRate(eXOF_bridgedEUROC_referenceRateFeedID, 1e24 * 656 - (1e24 * 656 * 0.14));

    // Try succesful swap -> trading should be possible again
    assert_swapIn_successful(1e6, address(eurocToken), address(eXOFToken));

    // Check breakers: verify that recoverable breaker has recovered
    rateFeedTradingMode = breakerBox.getRateFeedTradingMode(eXOF_bridgedEUROC_referenceRateFeedID);
    (valueDelta1TradingMode, , ) = breakerBox.rateFeedBreakerStatus(
      eXOF_bridgedEUROC_referenceRateFeedID,
      address(valueDeltaBreaker)
    );
    (valueDelta2TradingMode, , ) = breakerBox.rateFeedBreakerStatus(
      eXOF_bridgedEUROC_referenceRateFeedID,
      address(valueDeltaBreaker2)
    );
    assertEq(uint256(rateFeedTradingMode), 0); // 0 = bidirectional trading
    assertEq(uint256(valueDelta1TradingMode), 0); // 0 = bidirectional trading
    assertEq(uint256(valueDelta2TradingMode), 0); // 0 = bidirectional trading
  }

  function test_eXOFPool_whenMedianExceedsNonRecoverableBreaker_shouldBreakAndNeverRecover() public {
    // New median that exceeds non recoverable breaker threshold: 20%
    setMedianRate(eXOF_bridgedEUROC_referenceRateFeedID, 1e24 * 656 + (1e24 * 656 * 0.21));

    // Try swap that should revert
    assert_swapIn_tradingSuspended(1e6, address(eurocToken), address(eXOFToken));

    // Check breakers: verify that non recoverable breaker has triggered
    uint8 rateFeedTradingMode = breakerBox.getRateFeedTradingMode(eXOF_bridgedEUROC_referenceRateFeedID);
    (uint8 valueDelta1TradingMode, , ) = breakerBox.rateFeedBreakerStatus(
      eXOF_bridgedEUROC_referenceRateFeedID,
      address(valueDeltaBreaker)
    );
    (uint8 valueDelta2TradingMode, , ) = breakerBox.rateFeedBreakerStatus(
      eXOF_bridgedEUROC_referenceRateFeedID,
      address(valueDeltaBreaker2)
    );
    assertEq(uint256(rateFeedTradingMode), 3); // 3 = trading halted
    assertEq(uint256(valueDelta1TradingMode), 3); // 3 = trading halted
    assertEq(uint256(valueDelta2TradingMode), 3); // 3 = trading halted

    // New median that is below non recoverable breaker threshold: 20%
    vm.warp(now + 5 minutes);
    setMedianRate(eXOF_bridgedEUROC_referenceRateFeedID, 1e24 * 656);

    // Try swap that should still revert
    assert_swapIn_tradingSuspended(1e6, address(eurocToken), address(eXOFToken));

    // Check breakers: verify that recoverable breaker has recovered and non recoverable breaker hasn't
    rateFeedTradingMode = breakerBox.getRateFeedTradingMode(eXOF_bridgedEUROC_referenceRateFeedID);
    (valueDelta1TradingMode, , ) = breakerBox.rateFeedBreakerStatus(
      eXOF_bridgedEUROC_referenceRateFeedID,
      address(valueDeltaBreaker)
    );
    (valueDelta2TradingMode, , ) = breakerBox.rateFeedBreakerStatus(
      eXOF_bridgedEUROC_referenceRateFeedID,
      address(valueDeltaBreaker2)
    );
    assertEq(uint256(rateFeedTradingMode), 3); //  3 = trading halted
    assertEq(uint256(valueDelta1TradingMode), 0); // 0 = bidirectional trading
    assertEq(uint256(valueDelta2TradingMode), 3); // 3 = trading halted
  }

  function test_eXOFPool_whenEUROCDepegs_shouldHaltTrading() public {
    // New median that exceeds EUROC/EUR breaker threshold: 5%
    setMedianRate(bridgedEUROC_EUR_referenceRateFeedID, 1.051 * 1e24);

    // Try swap that should revert
    assert_swapIn_tradingSuspended(1e6, address(eurocToken), address(eXOFToken));

    // Check Breakers: verify that only the EUROC/EURO breaker has triggered
    uint8 rateFeedTradingMode = breakerBox.getRateFeedTradingMode(eXOF_bridgedEUROC_referenceRateFeedID);
    uint8 independentRateFeedTradingMode = breakerBox.rateFeedTradingMode(eXOF_bridgedEUROC_referenceRateFeedID);
    uint8 dependencyTradingMode = breakerBox.getRateFeedTradingMode(bridgedEUROC_EUR_referenceRateFeedID);
    assertEq(uint256(rateFeedTradingMode), 3); // 3 = trading halted
    assertEq(uint256(independentRateFeedTradingMode), 0); // 0 = bidirectional trading
    assertEq(uint256(dependencyTradingMode), 3); // 3 = trading halted

    // New median that is below EUROC/EUR breaker threshold: 5%
    vm.warp(now + 5 seconds);
    setMedianRate(bridgedEUROC_EUR_referenceRateFeedID, 1e24 * 1.04);

    // Try succesful swap -> trading should be possible again
    assert_swapIn_successful(1e6, address(eurocToken), address(eXOFToken));

    // Check breakers: verify that EUROC/EURO breaker has recovered
    rateFeedTradingMode = breakerBox.getRateFeedTradingMode(eXOF_bridgedEUROC_referenceRateFeedID);
    independentRateFeedTradingMode = breakerBox.rateFeedTradingMode(eXOF_bridgedEUROC_referenceRateFeedID);
    dependencyTradingMode = breakerBox.getRateFeedTradingMode(bridgedEUROC_EUR_referenceRateFeedID);
    assertEq(uint256(rateFeedTradingMode), 0); // 0 = bidirectional trading
    assertEq(uint256(independentRateFeedTradingMode), 0); // 0 = bidirectional trading
    assertEq(uint256(dependencyTradingMode), 0); // 0 = bidirectional trading
  }

  function test_eXOFPool_whenNoValidMedian_shouldHaltTradingAndRecoverOnNewValidMedian() public {
    // New median that doesnt exceed breaker thresholds
    setMedianRate(eXOF_bridgedEUROC_referenceRateFeedID, 1e24 * 656 + (1e24 * 656 * 0.05));

    // Try succesful swap -> trading should be possible
    assert_swapIn_successful(1e6, address(eurocToken), address(eXOFToken));

    // time jump that expires reports
    vm.warp(now + 5 minutes);

    // Try swap that should revert
    assert_swapIn_noValidMedian(1e6, address(eurocToken), address(eXOFToken));

    // New reports
    setMedianRate(eXOF_bridgedEUROC_referenceRateFeedID, 1e24 * 656 - (1e24 * 656 * 0.05));

    // Try succesful swap -> trading should be possible again
    assert_swapIn_successful(1e18, address(eXOFToken), address(eurocToken));
  }
}
