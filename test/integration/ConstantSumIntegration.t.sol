// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Test, console2 as console } from "celo-foundry/Test.sol";
import { IERC20 } from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

import { IntegrationTest } from "../utils/IntegrationTest.t.sol";
import { TokenHelpers } from "../utils/TokenHelpers.t.sol";

import { Broker } from "contracts/swap/Broker.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";
import { IExchangeProvider } from "contracts/interfaces/IExchangeProvider.sol";
import { IBiPoolManager } from "contracts/interfaces/IBiPoolManager.sol";
import { IPricingModule } from "contracts/interfaces/IPricingModule.sol";

import { FixidityLib } from "contracts/common/FixidityLib.sol";

contract ConstantSumIntegrationTest is IntegrationTest, TokenHelpers {
  address trader;

  function setUp() public {
    IntegrationTest.setUp();

    trader = actor("trader");

    mint(cUSDToken, trader, 10**22); // Mint 10k to trader
    mint(cEURToken, trader, 10**22); // Mint 10k to trader
    //mint(usdcToken, trader, 10**22); // Mint 10k to trader

    deal(address(celoToken), address(reserve), 10**(6 + 18)); // Gift 1Mil Celo to reserve
    deal(address(usdcToken), address(reserve), 10**(6 + 6)); // Gift 1Mil USDC to reserve
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

    expectedOut = broker.getAmountOut(exchangeProviders[0], poolId, tokenIn, tokenOut, amountIn);

    changePrank(trader);
    IERC20(tokenIn).approve(address(broker), amountIn);

    // Execute swap
    actualOut = broker.swapIn(address(exchangeProviders[0]), poolId, tokenIn, tokenOut, amountIn, 0);
  }

  function test_swap_whenConstantSum_pricesShouldStayTheSameInBetweenBucketUpdates() public {
    uint256 amountIn = 5000 * 10**18; // 5k cUSD
    IERC20 tokenIn = IERC20(address(cUSDToken));
    IERC20 tokenOut = usdcToken;
    bytes32 poolId = pair_cUSD_bridgedUSDC_ID;

    // Execute swap cUSD -> USDC
    (uint256 expectedOut, uint256 actualOut) = doSwapIn(poolId, amountIn, address(tokenIn), address(tokenOut));
    assertEq(actualOut, 5000 * 0.995 * 10**6); //  4975(6 decimals)

    // Execute second swap cUSD -> USDC
    (uint256 expectedOut2, uint256 actualOut2) = doSwapIn(poolId, amountIn, address(tokenIn), address(tokenOut));
    assertEq(actualOut, actualOut2);

    amountIn = 5000 * 10**6; // 5k USDC

    // Execute swap USDC -> cUSD
    (uint256 expectedOut3, uint256 actualOut3) = doSwapIn(poolId, amountIn, address(tokenOut), address(tokenIn));
    assertEq(actualOut3, 5000 * 0.995 * 10**18); //  4975(18 decimals)
  }
}
