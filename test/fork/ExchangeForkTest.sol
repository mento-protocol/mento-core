// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.8;

import "./BaseForkTest.sol";

contract ExchangeForkTest is BaseForkTest {
  using FixidityLib for FixidityLib.Fraction;

  using Utils for Utils.Context;
  using Utils for uint256;

  uint256 exchangeIndex;

  constructor(uint256 _chainId, uint256 _exchangeIndex) BaseForkTest(_chainId) {
    exchangeIndex = _exchangeIndex;
  }

  Utils.Context ctx;

  function setUp() public override {
    super.setUp();
    ctx = Utils.newContext(address(this), exchangeIndex);
  }

  function test_swapsHappenInBothDirections() public {
    IExchangeProvider.Exchange memory exchange = ctx.exchange;

    // asset0 -> asset1
    assert_swapIn(ctx, exchange.assets[0], exchange.assets[1], Utils.toSubunits(1000, exchange.assets[0]));
    // asset1 -> asset0
    assert_swapIn(ctx, exchange.assets[1], exchange.assets[0], Utils.toSubunits(1000, exchange.assets[1]));
  }

  function test_tradingLimitsAreConfigured() public view {
    IExchangeProvider.Exchange memory exchange = ctx.exchange;

    bytes32 asset0Bytes32 = bytes32(uint256(uint160(exchange.assets[0])));
    bytes32 limitIdForAsset0 = exchange.exchangeId ^ asset0Bytes32;
    bytes32 asset1Bytes32 = bytes32(uint256(uint160(exchange.assets[1])));
    bytes32 limitIdForAsset1 = exchange.exchangeId ^ asset1Bytes32;

    bool asset0LimitConfigured = ctx.isLimitConfigured(limitIdForAsset0);
    bool asset1LimitConfigured = ctx.isLimitConfigured(limitIdForAsset1);

    require(asset0LimitConfigured || asset1LimitConfigured, "Limit not configured");
  }

  function test_tradingLimitsAreEnforced_0to1_L0() public {
    ctx.logHeader();
    IExchangeProvider.Exchange memory exchange = ctx.exchange;

    assert_swapOverLimitFails(ctx, exchange.assets[0], exchange.assets[1], L0);
  }

  function test_tradingLimitsAreEnforced_0to1_L1() public {
    ctx.logHeader();
    IExchangeProvider.Exchange memory exchange = ctx.exchange;

    assert_swapOverLimitFails(ctx, exchange.assets[0], exchange.assets[1], L1);
  }

  function test_tradingLimitsAreEnforced_0to1_LG() public {
    ctx.logHeader();
    IExchangeProvider.Exchange memory exchange = ctx.exchange;

    assert_swapOverLimitFails(ctx, exchange.assets[0], exchange.assets[1], LG);
  }

  function test_tradingLimitsAreEnforced_1to0_L0() public {
    ctx.logHeader();
    IExchangeProvider.Exchange memory exchange = ctx.exchange;

    assert_swapOverLimitFails(ctx, exchange.assets[1], exchange.assets[0], L0);
  }

  function test_tradingLimitsAreEnforced_1to0_L1() public {
    ctx.logHeader();
    IExchangeProvider.Exchange memory exchange = ctx.exchange;

    assert_swapOverLimitFails(ctx, exchange.assets[1], exchange.assets[0], L1);
  }

  function test_tradingLimitsAreEnforced_1to0_LG() public {
    ctx.logHeader();
    IExchangeProvider.Exchange memory exchange = ctx.exchange;

    assert_swapOverLimitFails(ctx, exchange.assets[1], exchange.assets[0], LG);
  }

  function test_circuitBreaker_rateFeedsAreProtected() public view {
    address[] memory breakers = breakerBox.getBreakers();
    ctx.logHeader();
    address rateFeedID = ctx.getReferenceRateFeedID();
    bool found = false;
    for (uint256 j = 0; j < breakers.length && !found; j++) {
      found = breakerBox.isBreakerEnabled(breakers[j], rateFeedID);
    }
    require(found, "No breaker found for rateFeedID");
  }

  function test_circuitBreaker_breaks() public {
    address[] memory breakers = breakerBox.getBreakers();
    ctx.logHeader();
    address rateFeedID = ctx.getReferenceRateFeedID();
    for (uint256 j = 0; j < breakers.length; j++) {
      if (breakerBox.isBreakerEnabled(breakers[j], rateFeedID)) {
        assert_breakerBreaks(ctx, breakers[j], j);
        // we recover this breaker so that it doesn't affect other exchanges in this test,
        // since the rateFeed for this exchange could be a dependency for other rateFeeds
        assert_breakerRecovers(ctx, breakers[j], j);
      }
    }
  }

  function test_circuitBreaker_recovers() public {
    address[] memory breakers = breakerBox.getBreakers();
    ctx.logHeader();
    address rateFeedID = ctx.getReferenceRateFeedID();
    for (uint256 j = 0; j < breakers.length; j++) {
      if (breakerBox.isBreakerEnabled(breakers[j], rateFeedID)) {
        assert_breakerRecovers(ctx, breakers[j], j);
      }
    }
  }

  function test_circuitBreaker_haltsTrading() public {
    address[] memory breakers = breakerBox.getBreakers();
    ctx.logHeader();
    address rateFeedID = ctx.getReferenceRateFeedID();
    IExchangeProvider.Exchange memory exchange = ctx.exchange;

    for (uint256 j = 0; j < breakers.length; j++) {
      if (breakerBox.isBreakerEnabled(breakers[j], rateFeedID)) {
        assert_breakerBreaks(ctx, breakers[j], j);

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

        // we recover this breaker so that it doesn't affect other exchanges in this test,
        // since the rateFeed for this exchange could be a dependency for other rateFeeds
        assert_breakerRecovers(ctx, breakers[j], j);
      }
    }
  }

  mapping(address => uint256) depsCount;

  function test_rateFeedDependencies_haltsDependantTrading() public {
    // Hardcoded number of dependencies for each ratefeed
    depsCount[registry.getAddressForStringOrDie("StableToken")] = 0;
    depsCount[registry.getAddressForStringOrDie("StableTokenEUR")] = 0;
    depsCount[registry.getAddressForStringOrDie("StableTokenBRL")] = 0;
    depsCount[registry.getAddressForStringOrDie("StableTokenXOF")] = 2;
    depsCount[0xA1A8003936862E7a15092A91898D69fa8bCE290c] = 0; // USDC/USD
    depsCount[0x206B25Ea01E188Ee243131aFdE526bA6E131a016] = 1; // USDC/EUR
    depsCount[0x25F21A1f97607Edf6852339fad709728cffb9a9d] = 1; // USDC/BRL
    depsCount[0x26076B9702885d475ac8c3dB3Bd9F250Dc5A318B] = 0; // EUROC/EUR

    address[] memory breakers = breakerBox.getBreakers();

    address[] memory dependencies = new address[](depsCount[ctx.getReferenceRateFeedID()]);
    for (uint256 d = 0; d < dependencies.length; d++) {
      dependencies[d] = ctx.breakerBox.rateFeedDependencies(ctx.getReferenceRateFeedID(), d);
    }
    if (dependencies.length == 0) {
      return;
    }

    Utils.logPool(ctx);
    address rateFeedID = ctx.getReferenceRateFeedID();
    console.log(
      "\t exchangeIndex: %d | rateFeedId: %s | %s dependencies",
      exchangeIndex,
      rateFeedID,
      dependencies.length
    );

    for (uint256 k = 0; k < dependencies.length; k++) {
      Utils.Context memory dependencyContext = Utils.getContextForRateFeedID(address(this), dependencies[k]);

      for (uint256 j = 0; j < breakers.length; j++) {
        if (breakerBox.isBreakerEnabled(breakers[j], dependencies[k])) {
          assert_breakerBreaks(dependencyContext, breakers[j], j);

          assert_swapInFails(
            ctx,
            ctx.exchange.assets[0],
            ctx.exchange.assets[1],
            Utils.toSubunits(1000, ctx.exchange.assets[0]),
            "Trading is suspended for this reference rate"
          );

          assert_breakerRecovers(dependencyContext, breakers[j], j);
        }
      }
    }
  }
}
