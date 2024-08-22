// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.8;

import { Test } from "mento-std/Test.sol";
import { CELO_REGISTRY_ADDRESS } from "mento-std/Constants.sol";
import { console } from "forge-std/console.sol";

import { FixidityLib } from "celo/contracts/common/FixidityLib.sol";
import { IRegistry } from "celo/contracts/common/interfaces/IRegistry.sol";

import { Utils } from "./Utils.sol";
import { TestAsserts } from "./TestAsserts.sol";

import { IBiPoolManager } from "contracts/interfaces/IBiPoolManager.sol";
import { IBreakerBox } from "contracts/interfaces/IBreakerBox.sol";
import { IBroker } from "contracts/interfaces/IBroker.sol";
import { IExchangeProvider } from "contracts/interfaces/IExchangeProvider.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";
import { IStableTokenV2 } from "contracts/interfaces/IStableTokenV2.sol";
import { ITradingLimitsHarness } from "test/harnesses/ITradingLimitsHarness.sol";

interface IMint {
  function mint(address, uint256) external;
}

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
contract BaseForkTest is Test, TestAsserts {
  using FixidityLib for FixidityLib.Fraction;

  using Utils for Utils.Context;
  using Utils for uint256;

  struct ExchangeWithProvider {
    address exchangeProvider;
    IExchangeProvider.Exchange exchange;
  }

  IRegistry public registry = IRegistry(CELO_REGISTRY_ADDRESS);

  address governance;
  IBroker public broker;
  IBreakerBox public breakerBox;
  ISortedOracles public sortedOracles;
  IReserve public reserve;
  ITradingLimitsHarness public tradingLimits;

  address public trader;

  ExchangeWithProvider[] public exchanges;
  mapping(address => mapping(bytes32 => ExchangeWithProvider)) public exchangeMap;

  uint8 public constant L0 = 1; // 0b001 Limit0
  uint8 public constant L1 = 2; // 0b010 Limit1
  uint8 public constant LG = 4; // 0b100 LimitGlobal

  uint256 targetChainId;

  constructor(uint256 _targetChainId) Test() {
    targetChainId = _targetChainId;
  }

  function lookup(string memory key) public returns (address) {
    address addr = registry.getAddressForStringOrDie(key);
    if (addr != address(0)) {
      vm.label(addr, key);
    }
    return addr;
  }

  function setUp() public virtual {
    fork(targetChainId);
    // The precompile handler needs to be reinitialized after forking.
    __CeloPrecompiles_init();

    tradingLimits = ITradingLimitsHarness(deployCode("TradingLimitsHarness"));
    broker = IBroker(lookup("Broker"));
    sortedOracles = ISortedOracles(lookup("SortedOracles"));
    governance = lookup("Governance");
    breakerBox = IBreakerBox(address(sortedOracles.breakerBox()));
    vm.label(address(breakerBox), "BreakerBox");
    trader = makeAddr("trader");
    reserve = IReserve(broker.reserve());

    vm.startPrank(trader);

    address[] memory exchangeProviders = broker.getExchangeProviders();
    for (uint256 i = 0; i < exchangeProviders.length; i++) {
      vm.label(exchangeProviders[i], "ExchangeProvider");
      IExchangeProvider.Exchange[] memory _exchanges = IExchangeProvider(exchangeProviders[i]).getExchanges();
      for (uint256 j = 0; j < _exchanges.length; j++) {
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
      vm.label(collateralAsset, IERC20(collateralAsset).symbol());
      _deal(collateralAsset, address(reserve), Utils.toSubunits(25_000_000, collateralAsset), true);
      console.log("Minting 25mil %s to reserve", IERC20(collateralAsset).symbol());
    }

    console.log("Exchanges(%d): ", exchanges.length);
    for (uint256 i = 0; i < exchanges.length; i++) {
      Utils.Context memory ctx = Utils.newContext(address(this), i);
      console.log("%d | %s | %s", i, ctx.ticker(), ctx.exchangeProvider);
      console.logBytes32(ctx.exchange.exchangeId);
    }
  }

  function _deal(address asset, address to, uint256 amount, bool updateSupply) public {
    if (asset == lookup("GoldToken")) {
      vm.startPrank(address(0));
      IMint(asset).mint(to, amount);
      vm.startPrank(trader);
      return;
    }

    deal(asset, to, amount, updateSupply);
  }
}
