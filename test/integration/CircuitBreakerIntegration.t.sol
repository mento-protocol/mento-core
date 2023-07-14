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
    deal(address(celoToken), address(reserve), 1e24); // Gift 1Mil Celo to reserve
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

  function test_circuitBreaker_breaks() public {
    console.log("start");
    // new Median thats larger than threshold: 0.15
    IntegrationTest.setMedianRate(cUSD_CELO_referenceRateFeedID, 5e23 * 1.151);
    console.log("end");
    /*
    //try swap with shouldBreak true
    doSwapIn(pair_cUSD_CELO_ID, address(cUSDToken), address(celoToken), true);
    uint8 tradingMode = breakerBox.rateFeedTradingMode(cUSD_CELO_referenceRateFeedID);
    assertEq(uint256(tradingMode), 3); // 3 = Break

    // cool down breaker and set new median that doesnt exceed threshold
    vm.warp(now + 5 minutes + 1 seconds);
    IntegrationTest.setMedianRate(cUSD_CELO_referenceRateFeedID, 5e23);

    //try swap with shouldBreak false since breaker coolDownTime hasnt passed
    doSwapIn(pair_cUSD_CELO_ID, address(cUSDToken), address(celoToken), false);
    tradingMode = breakerBox.rateFeedTradingMode(cUSD_CELO_referenceRateFeedID);
    assertEq(uint256(tradingMode), 0); // 0 = trading enabled*/
  }
}
