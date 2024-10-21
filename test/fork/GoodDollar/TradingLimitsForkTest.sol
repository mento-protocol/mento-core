// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

// Libraries
import { console } from "forge-std/console.sol";
import { L0, L1 } from "../helpers/misc.sol";
import { TokenHelpers } from "../helpers/TokenHelpers.sol";
import { TradingLimitHelpers } from "../helpers/TradingLimitHelpers.sol";

// Interfaces
import { ITradingLimits } from "contracts/interfaces/ITradingLimits.sol";

// Contracts
import { Broker } from "contracts/swap/Broker.sol";
import { GoodDollarBaseForkTest } from "./GoodDollarBaseForkTest.sol";

contract GoodDollarTradingLimitsForkTest is GoodDollarBaseForkTest {
  using TradingLimitHelpers for *;
  using TokenHelpers for *;

  constructor(uint256 _chainId) GoodDollarBaseForkTest(_chainId) {}

  function setUp() public override {
    super.setUp();
  }

  function test_tradingLimitsAreConfigured() public view {
    bytes32 reserveAssetBytes32 = bytes32(uint256(uint160(address(reserveToken))));
    bytes32 limitIdForReserveAsset = exchangeId ^ reserveAssetBytes32;
    (, , , , , uint8 flags) = Broker(address(broker)).tradingLimitsConfig(limitIdForReserveAsset);
    bool reserveAssetLimitConfigured = flags > uint8(0);
    require(reserveAssetLimitConfigured, "Limit not configured");
  }

  function test_tradingLimitsAreEnforced_reserveTokenL0() public {
    ITradingLimits.Config memory config = getTradingLimitsConfig(address(reserveToken));

    uint256 maxAmountOut = uint256(uint48(config.limit0)) * 1e18;
    uint256 amountInRequired = goodDollarExchangeProvider.getAmountIn({
      exchangeId: exchangeId,
      tokenIn: address(goodDollarToken),
      tokenOut: address(reserveToken),
      amountOut: maxAmountOut
    });

    mintGoodDollar(amountInRequired, trader);

    vm.startPrank(trader);
    goodDollarToken.approve(address(broker), amountInRequired);

    // First swap to take us exactly to the trading limit
    broker.swapOut({
      exchangeProvider: address(goodDollarExchangeProvider),
      exchangeId: exchangeId,
      tokenIn: address(goodDollarToken),
      tokenOut: address(reserveToken),
      amountOut: maxAmountOut,
      amountInMax: type(uint256).max
    });

    // Second swap to push us over the limit
    vm.expectRevert(bytes(L0.revertReason()));
    broker.swapOut({
      exchangeProvider: address(goodDollarExchangeProvider),
      exchangeId: exchangeId,
      tokenIn: address(goodDollarToken),
      tokenOut: address(reserveToken),
      amountOut: 1 * 1e18,
      amountInMax: type(uint256).max
    });

    vm.stopPrank();
  }

  function test_tradingLimitsAreEnforced_reserveTokenL1() public {
    // Get the trading limits config and state for the reserve token
    ITradingLimits.Config memory config = getTradingLimitsConfig(address(reserveToken));
    ITradingLimits.State memory state = getRefreshedTradingLimitsState(address(reserveToken));
    console.log(unicode"🏷️ [%d] Swap until L1=%d on outflow", block.timestamp, uint48(config.limit1));

    // The limit we want to test
    uint256 limit1InWei = uint256(uint48(config.limit1)) * 1e18;

    // Get the max amount we can swap in a single transaction before we hit L0
    int48 maxPerSwap = config.limit0;
    uint256 maxPerSwapInWei = uint256(uint48(config.limit0)) * 1e18;

    // Get the G$ amountIn required to hit the L1 cUSD outflow limit
    uint256 amountInRequired = goodDollarExchangeProvider.getAmountIn({
      exchangeId: exchangeId,
      tokenIn: address(goodDollarToken),
      tokenOut: address(reserveToken),
      amountOut: limit1InWei
    });

    // Mint the required amount of G$ to the trader and approve the broker to spend it
    mintGoodDollar(amountInRequired * 2, trader);

    vm.startPrank(trader);
    goodDollarToken.approve(address(broker), amountInRequired * 2);

    // Swap until right before we would hit the L1 limit.
    // We swap in `maxPerSwap` increments and timewarp
    // by `timestep0 + 1` seconds so we avoid hitting L0.
    uint256 i;
    while (state.netflow1 - maxPerSwap >= -1 * config.limit1) {
      skip(config.timestep0 + 1);
      // Check that there's still outflow to trade as sometimes we hit LG while
      // still having a bit of L1 left, which causes an infinite loop.
      if (maxOutflow(address(reserveToken)) == 0) {
        break;
      }

      broker.swapOut({
        exchangeProvider: address(goodDollarExchangeProvider),
        exchangeId: exchangeId,
        tokenIn: address(goodDollarToken),
        tokenOut: address(reserveToken),
        amountOut: maxPerSwapInWei,
        amountInMax: type(uint256).max
      });

      config = getTradingLimitsConfig(address(reserveToken));
      state = getTradingLimitsState(address(reserveToken));

      i++;
      require(i <= 10, "infinite loop");
    }
    skip(config.timestep0 + 1);

    // The next swap should push us over the L1 limit and fail
    vm.expectRevert(bytes(L1.revertReason()));
    broker.swapOut({
      exchangeProvider: address(goodDollarExchangeProvider),
      exchangeId: exchangeId,
      tokenIn: address(goodDollarToken),
      tokenOut: address(reserveToken),
      amountOut: maxPerSwapInWei,
      amountInMax: type(uint256).max
    });
    vm.stopPrank();
  }

  // TODO: Implement LG limit test
  // TODO: Implement L0/L1/LG tests for the other direction (swapIn)
}
