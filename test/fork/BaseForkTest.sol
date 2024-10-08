// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.8;

import { Test } from "mento-std/Test.sol";
import { CELO_REGISTRY_ADDRESS } from "mento-std/Constants.sol";

import { FixidityLib } from "celo/contracts/common/FixidityLib.sol";
import { IRegistry } from "celo/contracts/common/interfaces/IRegistry.sol";

import { IBreakerBox } from "contracts/interfaces/IBreakerBox.sol";
import { IBroker } from "contracts/interfaces/IBroker.sol";
import { Broker } from "contracts/swap/Broker.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";
import { ITradingLimitsHarness } from "test/utils/harnesses/ITradingLimitsHarness.sol";
import { toRateFeed } from "./helpers/misc.sol";

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
 * in the system, therefore each test should.
 */
abstract contract BaseForkTest is Test {
  using FixidityLib for FixidityLib.Fraction;

  IRegistry public registry = IRegistry(CELO_REGISTRY_ADDRESS);

  address governance;
  Broker public broker;
  IBreakerBox public breakerBox;
  ISortedOracles public sortedOracles;
  IReserve public reserve;
  ITradingLimitsHarness public tradingLimits;

  address public trader;

  // @dev The number of collateral assets 5 is hardcoded here:
  // [CELO, AxelarUSDC, EUROC, NativeUSDC, NativeUSDT]
  uint8 public constant COLLATERAL_ASSETS_COUNT = 5;

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

  mapping(address rateFeed => uint8 count) rateFeedDependenciesCount;

  function setUp() public virtual {
    fork(targetChainId);
    // @dev Updaing the target fork block every 200 blocks, about ~8 min.
    // This means that when running locally RPC calls will be cached.
    fork(targetChainId, (block.number / 100) * 100);
    // The precompile handler needs to be reinitialized after forking.
    __CeloPrecompiles_init();

    tradingLimits = ITradingLimitsHarness(deployCode("TradingLimitsHarness"));
    broker = Broker(lookup("Broker"));
    sortedOracles = ISortedOracles(lookup("SortedOracles"));
    governance = lookup("Governance");
    breakerBox = IBreakerBox(address(sortedOracles.breakerBox()));
    vm.label(address(breakerBox), "BreakerBox");
    trader = makeAddr("trader");
    reserve = IReserve(lookup("Reserve"));

    /// @dev Hardcoded number of dependencies for each ratefeed.
    /// Should be updated when they change, there is a test that will
    /// validate that.
    rateFeedDependenciesCount[lookup("StableTokenXOF")] = 2;
    rateFeedDependenciesCount[toRateFeed("EUROCXOF")] = 2;
    rateFeedDependenciesCount[toRateFeed("USDCEUR")] = 1;
    rateFeedDependenciesCount[toRateFeed("USDCBRL")] = 1;
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
}
