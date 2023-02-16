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
import { TestAsserts } from "./TestAsserts.t.sol";

import { IExchangeProvider } from "contracts/interfaces/IExchangeProvider.sol";
import { IBreaker } from "contracts/interfaces/IBreaker.sol";
import { IRegistry } from "contracts/common/interfaces/IRegistry.sol";
import { IERC20Metadata } from "contracts/common/interfaces/IERC20Metadata.sol";
import { FixidityLib } from "contracts/common/FixidityLib.sol";
import { Proxy } from "contracts/common/Proxy.sol";

import { Broker } from "contracts/Broker.sol";
import { BreakerBox } from "contracts/BreakerBox.sol";
import { SortedOracles } from "contracts/SortedOracles.sol";
import { BiPoolManager } from "contracts/BiPoolManager.sol";
import { TradingLimits } from "contracts/common/TradingLimits.sol";
import { IBreakerBox } from "contracts/interfaces/IBreakerBox.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";
import { MedianDeltaBreaker } from "contracts/MedianDeltaBreaker.sol";
import { ValueDeltaBreaker } from "contracts/ValueDeltaBreaker.sol";

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
contract BaseForkTest is Test, TokenHelpers, TestAsserts {
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

  address governance;
  Broker public broker;
  BreakerBox public breakerBox;
  SortedOracles public sortedOracles;
  MedianDeltaBreaker public medianDeltaBreaker;
  ValueDeltaBreaker public valueDeltaBreaker;

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

  function __xxx_temp_setup() internal {}

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

    console.log("Exchanges:");
    for (uint256 i = 0; i < exchanges.length; i++) {
      console.log(i, exchanges[i].exchangeProvider, exchanges[i].exchange.assets[0], exchanges[i].exchange.assets[1]);
    }

    // ================================ TEMPORARY ====================================== //
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
    // XXX: Temporarily upgrade SortedOracles and set BreakerBox
    // These contracts are specific to baklava and are here just to make the tests work.
    address breakerBoxProxy = 0x5028D351F71b6797A49A2Ae429924B6a3f9cb280;
    address newSortedOraclesImpl = 0xeBD235883f9040f12AD583b0820a7A62C96f9b6f;
    Proxy(uint160(address(sortedOracles)))._setImplementation(newSortedOraclesImpl);
    sortedOracles.setBreakerBox(IBreakerBox(breakerBoxProxy));
    breakerBox = BreakerBox(breakerBoxProxy);
    address[] memory rateFeedIDs = new address[](0);
    uint256[] memory rateChangeThresholds = new uint256[](0);
    uint256[] memory cooldownTimes = new uint256[](0);

    medianDeltaBreaker = new MedianDeltaBreaker(
      60 * 10,
      FixidityLib.newFixedFraction(10, 100).unwrap(),
      ISortedOracles(address(sortedOracles)),
      rateFeedIDs,
      rateChangeThresholds,
      cooldownTimes
    );
    breakerBox.addBreaker(address(medianDeltaBreaker), 1);

    valueDeltaBreaker = new ValueDeltaBreaker(
      60 * 10,
      FixidityLib.newFixedFraction(3, 100).unwrap(),
      ISortedOracles(address(sortedOracles)),
      rateFeedIDs,
      rateChangeThresholds,
      cooldownTimes
    );
    breakerBox.addBreaker(address(valueDeltaBreaker), 2);

    require(exchanges.length == 2, "this temporary setup expects only 2 exchanges");
    Utils.Context memory ctx0 = Utils.newContext(address(this), 0);
    address rateFeedID0 = ctx0.getReferenceRateFeedID();
    breakerBox.toggleBreaker(address(medianDeltaBreaker), rateFeedID0, true);

    Utils.Context memory ctx1 = Utils.newContext(address(this), 1);
    address rateFeedID1 = ctx1.getReferenceRateFeedID();
    breakerBox.toggleBreaker(address(valueDeltaBreaker), rateFeedID1, true);
    rateFeedIDs = new address[](1);
    rateFeedIDs[0] = rateFeedID1;
    uint256[] memory referenceValues = new uint256[](1);
    (referenceValues[0], ) = ctx1.getReferenceRate();
    valueDeltaBreaker.setReferenceValues(rateFeedIDs, referenceValues);

    changePrank(trader0);
    // ================================================================================== //
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

  function test_circuitBreaker_rateFeedsAreProtected() public {
    address[] memory breakers = breakerBox.getBreakers();
    for (uint256 i = 0; i < exchanges.length; i++) {
      Utils.Context memory ctx = Utils.newContext(address(this), i);
      address rateFeedID = ctx.getReferenceRateFeedID();
      bool found = false;
      for (uint256 j = 0; j < breakers.length && !found; j++) {
        found = breakerBox.isBreakerEnabled(breakers[j], rateFeedID);
      }
      require(found, "No breaker found for rateFeedID");
    }
  }

  function test_circuitBreaker_breaks() public {
    address[] memory breakers = breakerBox.getBreakers();
    for (uint256 i = 0; i < exchanges.length; i++) {
      Utils.Context memory ctx = Utils.newContext(address(this), i);
      address rateFeedID = ctx.getReferenceRateFeedID();
      for (uint256 j = 0; j < breakers.length; j++) {
        if (breakerBox.isBreakerEnabled(breakers[j], rateFeedID)) {
          assert_breakerBreaks(ctx, breakers[j], breakerBox.breakerTradingMode(breakers[j]));
        }
      }
    }
  }

  function test_circuitBreaker_recovers() public {
    address[] memory breakers = breakerBox.getBreakers();
    for (uint256 i = 0; i < exchanges.length; i++) {
      Utils.Context memory ctx = Utils.newContext(address(this), i);
      address rateFeedID = ctx.getReferenceRateFeedID();
      for (uint256 j = 0; j < breakers.length; j++) {
        if (breakerBox.isBreakerEnabled(breakers[j], rateFeedID)) {
          assert_breakerRecovers(ctx, breakers[j], breakerBox.breakerTradingMode(breakers[j]));
        }
      }
    }
  }

  function test_circuitBreaker_haltsTrading() public {
    address[] memory breakers = breakerBox.getBreakers();
    for (uint256 i = 0; i < exchanges.length; i++) {
      Utils.Context memory ctx = Utils.newContext(address(this), i);
      address rateFeedID = ctx.getReferenceRateFeedID();
      IExchangeProvider.Exchange memory exchange = ctx.exchange;

      for (uint256 j = 0; j < breakers.length; j++) {
        if (breakerBox.isBreakerEnabled(breakers[j], rateFeedID)) {
          assert_breakerBreaks(ctx, breakers[j], breakerBox.breakerTradingMode(breakers[j]));
          assert_swapInFails(
            ctx,
            exchange.assets[0],
            exchange.assets[1],
            Utils.toSubunits(1000, exchange.assets[0]),
            "Trading is suspended for this reference rate"
          );
        }
      }
    }
  }
}
