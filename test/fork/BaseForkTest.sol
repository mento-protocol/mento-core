// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.8;

// Libraries
import { Test } from "mento-std/Test.sol";
import { CELO_REGISTRY_ADDRESS } from "mento-std/Constants.sol";
import { FixidityLib } from "celo/contracts/common/FixidityLib.sol";

// Interfaces
import { IBiPoolManager } from "contracts/interfaces/IBiPoolManager.sol";
import { IBreakerBox } from "contracts/interfaces/IBreakerBox.sol";
import { IOwnable } from "contracts/interfaces/IOwnable.sol";
import { IPricingModule } from "contracts/interfaces/IPricingModule.sol";
import { IRegistry } from "celo/contracts/common/interfaces/IRegistry.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";
import { IStableTokenV2 } from "contracts/interfaces/IStableTokenV2.sol";
import { ITradingLimits } from "contracts/interfaces/ITradingLimits.sol";
import { ITradingLimitsHarness } from "test/utils/harnesses/ITradingLimitsHarness.sol";

// Contracts & Utils
import { Broker } from "contracts/swap/Broker.sol";
import { TradingLimitsHarness } from "test/utils/harnesses/TradingLimitsHarness.sol";
import { TestERC20 } from "test/utils/mocks/TestERC20.sol";
import { USDC } from "test/utils/mocks/USDC.sol";
import { toRateFeed } from "./helpers/misc.sol";

interface IMint {
  function mint(address, uint256) external;
}

/**
 * @title BaseForkTest
 * @notice Fork tests for Mento!
 * This test suite tests invariants on a fork of a live Mento environemnts.
 * The philosophy is to test in accordance with how the target fork is configured,
 * therfore it doesn't make assumptions about the systems, nor tries to configure
 * the system to test specific scenarios.
 * However, it should be exhaustive in testing invariants across all tradable pairs
 * in the system, therefore each test should.
 */
abstract contract BaseForkTest is Test {
  using FixidityLib for FixidityLib.Fraction;

  IRegistry public registry = IRegistry(CELO_REGISTRY_ADDRESS);

  address governance;
  Broker public broker;
  IBiPoolManager biPoolManager;
  IBreakerBox public breakerBox;
  ISortedOracles public sortedOracles;
  IReserve public reserve;
  ITradingLimitsHarness public tradingLimits;

  address public trader;

  // @dev The number of collateral assets 5 is hardcoded here:
  // [CELO, AxelarUSDC, EUROC, NativeUSDC, NativeUSDT]
  uint8 public constant COLLATERAL_ASSETS_COUNT = 5;

  uint256 targetChainId;

  // TODO: Should use real USDC here
  TestERC20 usdcToken;

  // TODO: Should use real EUROC here
  TestERC20 eurocToken;
  IStableTokenV2 cUSDToken;
  IStableTokenV2 cEURToken;
  IStableTokenV2 eXOFToken;
  IStableTokenV2 cCOPToken;

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

  mapping(address rateFeed => uint8 count) rateFeedDependenciesCount;

  function setUp() public virtual {
    fork(targetChainId);
    // @dev Updaing the target fork block every 200 blocks, about ~8 min.
    // This means that when running locally RPC calls will be cached.
    fork(targetChainId, (block.number / 100) * 100);
    // The precompile handler needs to be reinitialized after forking.
    __CeloPrecompiles_init();

    tradingLimits = new TradingLimitsHarness();

    // TODO: Replace with `lookup("Broker")` after we've updated the broker on mainnet
    broker = new Broker(true);

    // TODO: Probably can't do it like this to be compatible between both Alfajores & Mainnet, but couldn't find BiPoolManager in registry?
    biPoolManager = IBiPoolManager(0x22d9db95E6Ae61c104A7B6F6C78D7993B94ec901);
    sortedOracles = ISortedOracles(lookup("SortedOracles"));
    governance = lookup("Governance");
    breakerBox = IBreakerBox(address(sortedOracles.breakerBox()));
    vm.label(address(breakerBox), "BreakerBox");
    trader = makeAddr("trader");
    reserve = IReserve(lookup("Reserve"));

    setUpAssets();
    setUpBroker();

    /// @dev Hardcoded number of dependencies for each ratefeed.
    /// Should be updated when they change, there is a test that will
    /// validate that.
    rateFeedDependenciesCount[lookup("StableTokenXOF")] = 2;
    rateFeedDependenciesCount[toRateFeed("EUROCXOF")] = 2;
    rateFeedDependenciesCount[toRateFeed("USDCEUR")] = 1;
    rateFeedDependenciesCount[toRateFeed("USDCBRL")] = 1;
  }

  function setUpAssets() internal {
    usdcToken = new USDC("bridgedUSDC", "bridgedUSDC");
    eurocToken = new USDC("bridgedEUROC", "bridgedEUROC");

    // TODO: Probably can't do it like this to be compatible between both Alfajores & Mainnet, but couldn't find it in the registry?
    cUSDToken = IStableTokenV2(0x765DE816845861e75A25fCA122bb6898B8B1282a);
    vm.startPrank(IOwnable(address(cUSDToken)).owner());
    cUSDToken.setBroker(address(broker));

    // TODO: Probably can't do it like this to be compatible between both Alfajores & Mainnet, but couldn't find it in the registry?
    cEURToken = IStableTokenV2(0xD8763CBa276a3738E6DE85b4b3bF5FDed6D6cA73);
    cEURToken.setBroker(address(broker));

    // TODO: Probably can't do it like this to be compatible between both Alfajores & Mainnet, but couldn't find it in the registry?
    eXOFToken = IStableTokenV2(0x73F93dcc49cB8A239e2032663e9475dd5ef29A08);
    eXOFToken.setBroker(address(broker));

    // TODO: Probably can't do it like this to be compatible between both Alfajores & Mainnet, but couldn't find it in the registry?
    // TODO: Do we use cCOP or PUSO?
    cCOPToken = IStableTokenV2(0x8A567e2aE79CA692Bd748aB832081C45de4041eA);
    vm.stopPrank();

    vm.label(address(cUSDToken), "cUSD");
    vm.label(address(cEURToken), "cEUR");
    vm.label(address(eXOFToken), "eXOF");
  }

  function setUpBroker() internal {
    vm.prank(biPoolManager.owner());
    biPoolManager.setBroker(address(broker));

    address[] memory exchangeProviders = new address[](1);
    exchangeProviders[0] = address(biPoolManager);

    address[] memory reserves = new address[](1);
    reserves[0] = address(reserve);

    broker.initialize(exchangeProviders, reserves);

    vm.prank(IOwnable(address(registry)).owner());
    registry.setAddressFor("Broker", address(broker));

    vm.prank(reserve.owner());
    reserve.addExchangeSpender(address(broker));
  }

  function setUp_tradingLimits() internal {
    ITradingLimits.Config memory config = configL0L1LG(100, 10000, 1000, 100000, 1000000);

    bytes32 pair_cUSD_CELO_ID = keccak256(abi.encodePacked("cUSD", "CELO", "ConstantProduct"));
    broker.configureTradingLimit(pair_cUSD_CELO_ID, address(cUSDToken), config);

    bytes32 pair_cEUR_CELO_ID = keccak256(abi.encodePacked("cEUR", "CELO", "ConstantProduct"));
    broker.configureTradingLimit(pair_cEUR_CELO_ID, address(cEURToken), config);

    bytes32 pair_cUSD_bridgedUSDC_ID = keccak256(abi.encodePacked("cUSD", "USDC", "ConstantSum"));
    broker.configureTradingLimit(pair_cUSD_bridgedUSDC_ID, address(usdcToken), config);

    bytes32 pair_cEUR_bridgedUSDC_ID = keccak256(abi.encodePacked("cEUR", "USDC", "ConstantProduct"));
    broker.configureTradingLimit(pair_cEUR_bridgedUSDC_ID, address(usdcToken), config);

    bytes32 pair_cUSD_cEUR_ID = keccak256(abi.encodePacked("cUSD", "cEUR", "ConstantProduct"));
    broker.configureTradingLimit(pair_cUSD_cEUR_ID, address(cUSDToken), config);

    bytes32 pair_eXOF_bridgedEUROC_ID = keccak256(abi.encodePacked("eXOF", "cEUR", "ConstantSum"));
    broker.configureTradingLimit(pair_eXOF_bridgedEUROC_ID, address(eXOFToken), config);

    // FIXME: This might be breaking the tests atm
    bytes32 pair_cUSD_PUSO_ID = keccak256(abi.encodePacked("cUSD", "PUSO", "ConstantSum"));
    broker.configureTradingLimit(pair_cUSD_PUSO_ID, address(cCOPToken), config);
  }

  function mint(address asset, address to, uint256 amount, bool updateSupply) public {
    if (asset == lookup("GoldToken")) {
      if (!updateSupply) {
        revert("BaseForkTest: can't mint GoldToken without updating supply");
      }
      vm.prank(address(0));
      IMint(asset).mint(to, amount);
      return;
    }

    deal(asset, to, amount, updateSupply);
  }

  function configL0L1LG(
    uint32 timestep0,
    int48 limit0,
    uint32 timestep1,
    int48 limit1,
    int48 limitGlobal
  ) internal pure returns (ITradingLimits.Config memory config) {
    config.timestep0 = timestep0;
    config.limit0 = limit0;
    config.timestep1 = timestep1;
    config.limit1 = limit1;
    config.limitGlobal = limitGlobal;
    config.flags = 1 | 2 | 4; //L0, L1, and LG
  }
}
