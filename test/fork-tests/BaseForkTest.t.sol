// SPDX-License-Identifier: GPL-3.0-or-later
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

import { IMentoERC20 } from "contracts/interfaces/IMentoERC20.sol";
import { Broker } from "contracts/swap/Broker.sol";
import { BreakerBox } from "contracts/oracles/BreakerBox.sol";
import { SortedOracles } from "contracts/oracles/SortedOracles.sol";
import { Reserve } from "contracts/swap/Reserve.sol";
import { BiPoolManager } from "contracts/swap/BiPoolManager.sol";
import { TradingLimits } from "contracts/libraries/TradingLimits.sol";
import { IBreakerBox } from "contracts/interfaces/IBreakerBox.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";

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
  Reserve public reserve;

  address public trader;

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
    breakerBox = BreakerBox(address(sortedOracles.breakerBox()));
    trader = actor("trader");
    reserve = Reserve(uint160(address(broker.reserve())));

    vm.startPrank(trader);
    currentPrank = trader;

    vm.label(address(broker), "Broker");

    // Use this by running tests like:
    // env ONLY={exchangeId} yarn fork-tests:baklava
    (bool success, bytes memory data) = address(vm).call(abi.encodeWithSignature("envBytes32(string)", "ONLY"));
    bytes32 exchangeIdFilter;
    if (success) {
      exchangeIdFilter = abi.decode(data, (bytes32));
    }

    if (exchangeIdFilter != bytes32(0)) {
      console.log("🚨 Filtering exchanges by exchangeId:");
      console.logBytes32(exchangeIdFilter);
      console.log("------------------------------------------------------------------");
    }

    address[] memory exchangeProviders = broker.getExchangeProviders();
    for (uint256 i = 0; i < exchangeProviders.length; i++) {
      IExchangeProvider.Exchange[] memory _exchanges = IExchangeProvider(exchangeProviders[i]).getExchanges();
      for (uint256 j = 0; j < _exchanges.length; j++) {
        if (exchangeIdFilter != bytes32(0) && _exchanges[j].exchangeId != exchangeIdFilter) continue;
        exchanges.push(ExchangeWithProvider(exchangeProviders[i], _exchanges[j]));
        exchangeMap[exchangeProviders[i]][_exchanges[j].exchangeId] = ExchangeWithProvider(
          exchangeProviders[i],
          _exchanges[j]
        );
      }
    }
    require(exchanges.length > 0, "No exchanges found");

    // XXX: The number of collateral assets 2 is hardcoded here [CELO, USDC]
    for (uint256 i = 0; i < 2; i++) {
      address collateralAsset = reserve.collateralAssets(i);
      mint(collateralAsset, address(reserve), Utils.toSubunits(10_000_000, collateralAsset));
      console.log("Minting 10mil %s to reserve", IERC20Metadata(collateralAsset).symbol());
    }

    console.log("Exchanges(%d): ", exchanges.length);
    for (uint256 i = 0; i < exchanges.length; i++) {
      Utils.Context memory ctx = Utils.newContext(address(this), i);
      console.log("%d | %s | %s", i, ctx.ticker(), ctx.exchangeProvider);
      console.logBytes32(ctx.exchange.exchangeId);
    }
  }

  function test_biPoolManagerCanNotBeReinitialized() public {
    BiPoolManager biPoolManager = BiPoolManager(broker.getExchangeProviders()[0]);

    vm.expectRevert("contract already initialized");
    biPoolManager.initialize(address(broker), reserve, sortedOracles, breakerBox);
  }

  function test_brokerCanNotBeReinitialized() public {
    vm.expectRevert("contract already initialized");
    broker.initialize(new address[](0), address(reserve));
  }

  function test_sortedOraclesCanNotBeReinitialized() public {
    vm.expectRevert("contract already initialized");
    sortedOracles.initialize(1);
  }

  function test_reserveCanNotBeReinitialized() public {
    vm.expectRevert("contract already initialized");
    reserve.initialize(
      address(10),
      0,
      0,
      0,
      0,
      new bytes32[](0),
      new uint256[](0),
      0,
      0,
      new address[](0),
      new uint256[](0)
    );
  }

  function test_stableTokensCanNotBeReinitialized() public {
    IMentoERC20 stableToken = IMentoERC20(registry.getAddressForStringOrDie("StableToken"));
    IMentoERC20 stableTokenEUR = IMentoERC20(registry.getAddressForStringOrDie("StableTokenEUR"));
    IMentoERC20 stableTokenBRL = IMentoERC20(registry.getAddressForStringOrDie("StableTokenBRL"));

    vm.expectRevert("contract already initialized");
    stableToken.initialize("", "", 8, address(10), 0, 0, new address[](0), new uint256[](0), "");

    vm.expectRevert("contract already initialized");
    stableTokenEUR.initialize("", "", 8, address(10), 0, 0, new address[](0), new uint256[](0), "");

    vm.expectRevert("contract already initialized");
    stableTokenBRL.initialize("", "", 8, address(10), 0, 0, new address[](0), new uint256[](0), "");
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

  function test_tradingLimitsAreConfigured() public view {
    for (uint256 i = 0; i < exchanges.length; i++) {
      Utils.Context memory ctx = Utils.newContext(address(this), i);
      IExchangeProvider.Exchange memory exchange = ctx.exchange;

      bytes32 asset0Bytes32 = bytes32(uint256(uint160(exchange.assets[0])));
      bytes32 limitIdForAsset0 = exchange.exchangeId ^ asset0Bytes32;
      bytes32 asset1Bytes32 = bytes32(uint256(uint160(exchange.assets[1])));
      bytes32 limitIdForAsset1 = exchange.exchangeId ^ asset1Bytes32;

      bool asset0LimitConfigured = ctx.isLimitConfigured(limitIdForAsset0);
      bool asset1LimitConfigured = ctx.isLimitConfigured(limitIdForAsset1);

      require(asset0LimitConfigured || asset1LimitConfigured, "Limit not configured");
      require(!asset0LimitConfigured || !asset1LimitConfigured, "Limit configured for both assets");
    }
  }

  function test_tradingLimitsAreEnforced_0to1_L0() public {
    for (uint256 i = 0; i < exchanges.length; i++) {
      Utils.Context memory ctx = Utils.newContext(address(this), i);
      ctx.logHeader();
      IExchangeProvider.Exchange memory exchange = ctx.exchange;

      assert_swapOverLimitFails(ctx, exchange.assets[0], exchange.assets[1], L0);
    }
  }

  function test_tradingLimitsAreEnforced_0to1_L1() public {
    for (uint256 i = 0; i < exchanges.length; i++) {
      Utils.Context memory ctx = Utils.newContext(address(this), i);
      ctx.logHeader();
      IExchangeProvider.Exchange memory exchange = ctx.exchange;

      assert_swapOverLimitFails(ctx, exchange.assets[0], exchange.assets[1], L1);
    }
  }

  function test_tradingLimitsAreEnforced_0to1_LG() public {
    for (uint256 i = 0; i < exchanges.length; i++) {
      Utils.Context memory ctx = Utils.newContext(address(this), i);
      ctx.logHeader();
      IExchangeProvider.Exchange memory exchange = ctx.exchange;

      assert_swapOverLimitFails(ctx, exchange.assets[0], exchange.assets[1], LG);
    }
  }

  function test_tradingLimitsAreEnforced_1to0_L0() public {
    for (uint256 i = 0; i < exchanges.length; i++) {
      Utils.Context memory ctx = Utils.newContext(address(this), i);
      ctx.logHeader();
      IExchangeProvider.Exchange memory exchange = ctx.exchange;

      assert_swapOverLimitFails(ctx, exchange.assets[1], exchange.assets[0], L0);
    }
  }

  function test_tradingLimitsAreEnforced_1to0_L1() public {
    for (uint256 i = 0; i < exchanges.length; i++) {
      Utils.Context memory ctx = Utils.newContext(address(this), i);
      ctx.logHeader();
      IExchangeProvider.Exchange memory exchange = ctx.exchange;

      assert_swapOverLimitFails(ctx, exchange.assets[1], exchange.assets[0], L1);
    }
  }

  function test_tradingLimitsAreEnforced_1to0_LG() public {
    for (uint256 i = 0; i < exchanges.length; i++) {
      Utils.Context memory ctx = Utils.newContext(address(this), i);
      ctx.logHeader();
      IExchangeProvider.Exchange memory exchange = ctx.exchange;

      assert_swapOverLimitFails(ctx, exchange.assets[1], exchange.assets[0], LG);
    }
  }

  function test_circuitBreaker_rateFeedsAreProtected() public view {
    address[] memory breakers = breakerBox.getBreakers();
    for (uint256 i = 0; i < exchanges.length; i++) {
      Utils.Context memory ctx = Utils.newContext(address(this), i);
      ctx.logHeader();
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
      ctx.logHeader();
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
      ctx.logHeader();
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
      ctx.logHeader();
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
          assert_swapInFails(
            ctx,
            exchange.assets[1],
            exchange.assets[0],
            Utils.toSubunits(1000, exchange.assets[1]),
            "Trading is suspended for this reference rate"
          );

          assert_swapOutFails(
            ctx,
            exchange.assets[0],
            exchange.assets[1],
            Utils.toSubunits(1000, exchange.assets[1]),
            "Trading is suspended for this reference rate"
          );
          assert_swapOutFails(
            ctx,
            exchange.assets[1],
            exchange.assets[0],
            Utils.toSubunits(1000, exchange.assets[0]),
            "Trading is suspended for this reference rate"
          );
        }
      }
    }
  }
}
