// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.8;

import { Test } from "mento-std/Test.sol";
import { CELO_REGISTRY_ADDRESS } from "mento-std/Constants.sol";
import { console } from "forge-std/console.sol";

import { FixidityLib } from "celo/contracts/common/FixidityLib.sol";
import { IRegistry } from "celo/contracts/common/interfaces/IRegistry.sol";

// import { Utils } from "./Utils.sol";
// import { TestAsserts } from "./TestAsserts.sol";

import { IBreakerBox } from "contracts/interfaces/IBreakerBox.sol";
import { IBroker } from "contracts/interfaces/IBroker.sol";
import { IExchangeProvider } from "contracts/interfaces/IExchangeProvider.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";
import { ITradingLimitsHarness } from "test/utils/harnesses/ITradingLimitsHarness.sol";

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
contract BaseForkTest is Test {
  using FixidityLib for FixidityLib.Fraction;

  IRegistry public registry = IRegistry(CELO_REGISTRY_ADDRESS);

  address governance;
  IBroker public broker;
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

  function setUp() public virtual {
    fork(targetChainId);
    fork(targetChainId, (block.number / 100) * 100);
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
