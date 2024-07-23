// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Test } from "celo-foundry/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { console } from "forge-std/console.sol";
import { PrecompileHandler } from "celo-foundry/PrecompileHandler.sol";

import { Arrays } from "test/utils/Arrays.sol";
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

import { IStableTokenV2 } from "contracts/interfaces/IStableTokenV2.sol";
import { Broker } from "contracts/swap/Broker.sol";
import { BreakerBox } from "contracts/oracles/BreakerBox.sol";
import { SortedOracles } from "contracts/common/SortedOracles.sol";
import { Reserve } from "contracts/swap/Reserve.sol";
import { BiPoolManager } from "contracts/swap/BiPoolManager.sol";
import { TradingLimits } from "contracts/libraries/TradingLimits.sol";
import { IBreakerBox } from "contracts/interfaces/IBreakerBox.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";

/**
 * @title MentoFork
 * @notice General fork test set up
 * This test suite tests invariantes on a fork of a live Mento environemnts.
 */
contract MentoFork is Test, TokenHelpers, TestAsserts {
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

  uint8 internal constant L0 = 1; // 0b001 Limit0
  uint8 internal constant L1 = 2; // 0b010 Limit1
  uint8 internal constant LG = 4; // 0b100 LimitGlobal

  uint256 public targetChainId;

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
    // solhint-disable-next-line avoid-low-level-calls
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

    // The number of collateral assets 5 is hardcoded here [CELO, AxelarUSDC, EUROC, NativeUSDC, NativeUSDT]
    for (uint256 i = 0; i < 5; i++) {
      address collateralAsset = reserve.collateralAssets(i);
      mint(collateralAsset, address(reserve), Utils.toSubunits(25_000_000, collateralAsset));
      console.log("Minting 25mil %s to reserve", IERC20Metadata(collateralAsset).symbol());
    }

    console.log("Exchanges(%d): ", exchanges.length);
    for (uint256 i = 0; i < exchanges.length; i++) {
      Utils.Context memory ctx = Utils.newContext(address(this), i);
      console.log("%d | %s | %s", i, ctx.ticker(), ctx.exchangeProvider);
      console.logBytes32(ctx.exchange.exchangeId);
    }
  }
}
