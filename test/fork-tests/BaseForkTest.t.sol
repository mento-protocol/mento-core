// SPDX-License-Identifier: UNLICENSED
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Test } from "celo-foundry/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { console } from "forge-std/console.sol";
import { PrecompileHandler } from "celo-foundry/PrecompileHandler.sol";

import { TokenHelpers } from "test/utils/TokenHelpers.t.sol";
import { Chain } from "test/utils/Chain.sol";

import { Utils } from "./Utils.t.sol";
import { SwapAssert } from "./SwapAssert.t.sol";

import { IExchangeProvider } from "contracts/interfaces/IExchangeProvider.sol";
import { IRegistry } from "contracts/common/interfaces/IRegistry.sol";
import { IERC20Metadata } from "contracts/common/interfaces/IERC20Metadata.sol";
import { FixidityLib } from "contracts/common/FixidityLib.sol";

import { Broker } from "contracts/Broker.sol";
import { SortedOracles } from "contracts/SortedOracles.sol";
import { BiPoolManager } from "contracts/BiPoolManager.sol";
import { TradingLimits } from "contracts/common/TradingLimits.sol";

/**
 * @title BaseForkTest
 * @notice Fork tests for Mento!
 * This test suite tests invariantes on a fork of a live Mento environemnts.
 * The philosophy is to test in accordance with how the target fork is configured,
 * therfore it doesn't make assumptions about the systems, nor tries to configure
 * the system to test specific scenarios.
 * However, it should be exausitve in testing invariants across all tradable pairs
 * in the system, therfore each test should.
 */
contract BaseForkTest is Test, TokenHelpers, SwapAssert {
  using FixidityLib for FixidityLib.Fraction;
  using TradingLimits for TradingLimits.State;
  using TradingLimits for TradingLimits.Config;

  using Utils for Utils.Context;
  using Utils for uint256;

  struct ExchangeWithProvider {
    address exchangeProvider;
    IExchangeProvider.Exchange exchange;
  }

  address public constant REGISTRY_ADDRESS = 0x000000000000000000000000000000000000ce10;
  IRegistry public registry = IRegistry(REGISTRY_ADDRESS);

  Broker public broker;

  SortedOracles public sortedOracles;
  address governance;

  address public trader0;

  ExchangeWithProvider[] public exchanges;
  mapping(address => mapping(bytes32 => ExchangeWithProvider)) public exchangeMap;

  uint8 private constant L0 = 1; // 0b001 Limit0
  uint8 private constant L1 = 2; // 0b010 Limit1
  uint8 private constant LG = 4; // 0b100 LimitGlobal

  uint256 targetChainId;

  constructor(uint256 _targetChainId) public Test() {
    targetChainId = _targetChainId;
  }

  function setUp() public {
    Chain.fork(targetChainId);
    // The precompile handler is usually initialized in the celo-foundry/Test constructor
    // but it needs to be reinitalized after forking
    ph = new PrecompileHandler();

    broker = Broker(registry.getAddressForStringOrDie("Broker"));
    sortedOracles = SortedOracles(registry.getAddressForStringOrDie("SortedOracles"));
    governance = registry.getAddressForStringOrDie("Governance");
    trader0 = actor("trader0");
    changePrank(trader0);

    vm.label(address(broker), "Broker");
    __swapAssertDebug = true;

    address[] memory exchangeProviders = broker.getExchangeProviders();
    for (uint256 i = 0; i < exchangeProviders.length; i++) {
      IExchangeProvider.Exchange[] memory _exchanges = IExchangeProvider(exchangeProviders[i]).getExchanges();
      for (uint256 j = 0; j < _exchanges.length; j++) {
        exchanges.push(ExchangeWithProvider(exchangeProviders[i], _exchanges[j]));
        exchangeMap[exchangeProviders[i]][_exchanges[j].exchangeId] = ExchangeWithProvider(
          exchangeProviders[i],
          _exchanges[j]
        );
      }
    }

    for (uint256 i = 0; i < exchanges.length; i++) {
      console.log(i, exchanges[i].exchangeProvider, exchanges[i].exchange.assets[0], exchanges[i].exchange.assets[1]);
    }

    // XXX: Temporarily add trading limits to broker
    // These are not the real trading limits, but they are good enough for testing.
    changePrank(governance);
    for (uint256 i = 0; i < exchanges.length; i++) {
      IExchangeProvider.Exchange memory exchange = exchanges[i].exchange;
      TradingLimits.Config memory config = TradingLimits.Config(
        60 * 5, // 5min
        60 * 60 * 24, // 1day
        1_000,
        10_000,
        100_000,
        L0 | L1 | LG
      );
      broker.configureTradingLimit(exchange.exchangeId, exchange.assets[0], config);
    }
    changePrank(trader0);
  }

  function test_swapsHappenInBothDirections() public {
    for (uint256 i = 0; i < exchanges.length; i++) {
      Utils.Context memory ctx = Utils.newContext(address(this), i);
      IExchangeProvider.Exchange memory exchange = ctx.exchange;

      // asset0 -> asset1
      assert_swapIn(ctx, exchange.assets[0], exchange.assets[1], Utils.toSubunits(1000, exchange.assets[0]));
      // asset1 -> asset0
      assert_swapIn(ctx, exchange.assets[1], exchange.assets[0], Utils.toSubunits(1000, exchange.assets[1]));
    }
  }

  function test_tradingLimitsAreConfigured() public {
    for (uint256 i = 0; i < exchanges.length; i++) {
      Utils.Context memory ctx = Utils.newContext(address(this), i);
      IExchangeProvider.Exchange memory exchange = ctx.exchange;

      bytes32 asset0Bytes32 = bytes32(uint256(uint160(exchange.assets[0])));
      bytes32 limitIdForAsset0 = exchange.exchangeId ^ asset0Bytes32;
      bytes32 asset1Bytes32 = bytes32(uint256(uint160(exchange.assets[1])));
      bytes32 limitIdForAsset1 = exchange.exchangeId ^ asset1Bytes32;

      require(
        ctx.isLimitConfigured(limitIdForAsset0) || ctx.isLimitConfigured(limitIdForAsset1),
        "Limit not configured"
      );
    }
  }

  function test_tradingLimitsAreEnforced_0to1_L0() public {
    for (uint256 i = 0; i < exchanges.length; i++) {
      Utils.Context memory ctx = Utils.newContext(address(this), i);
      IExchangeProvider.Exchange memory exchange = ctx.exchange;

      assert_swapOverLimitFails(ctx, exchange.assets[0], exchange.assets[1], L0);
    }
  }

  function test_tradingLimitsAreEnforced_0to1_L1() public {
    for (uint256 i = 0; i < exchanges.length; i++) {
      Utils.Context memory ctx = Utils.newContext(address(this), i);
      IExchangeProvider.Exchange memory exchange = ctx.exchange;

      assert_swapOverLimitFails(ctx, exchange.assets[0], exchange.assets[1], L1);
    }
  }

  function test_tradingLimitsAreEnforced_0to1_LG() public {
    for (uint256 i = 0; i < exchanges.length; i++) {
      Utils.Context memory ctx = Utils.newContext(address(this), i);
      IExchangeProvider.Exchange memory exchange = ctx.exchange;

      assert_swapOverLimitFails(ctx, exchange.assets[0], exchange.assets[1], LG);
    }
  }

  function test_tradingLimitsAreEnforced_1to0_L0() public {
    for (uint256 i = 0; i < exchanges.length; i++) {
      Utils.Context memory ctx = Utils.newContext(address(this), i);
      IExchangeProvider.Exchange memory exchange = ctx.exchange;

      assert_swapOverLimitFails(ctx, exchange.assets[1], exchange.assets[0], L0);
    }
  }

  function test_tradingLimitsAreEnforced_1to0_L1() public {
    for (uint256 i = 0; i < exchanges.length; i++) {
      Utils.Context memory ctx = Utils.newContext(address(this), i);
      IExchangeProvider.Exchange memory exchange = ctx.exchange;

      assert_swapOverLimitFails(ctx, exchange.assets[1], exchange.assets[0], L1);
    }
  }

  function test_tradingLimitsAreEnforced_1to0_LG() public {
    for (uint256 i = 0; i < exchanges.length; i++) {
      Utils.Context memory ctx = Utils.newContext(address(this), i);
      IExchangeProvider.Exchange memory exchange = ctx.exchange;

      assert_swapOverLimitFails(ctx, exchange.assets[1], exchange.assets[0], LG);
    }
  }
}
