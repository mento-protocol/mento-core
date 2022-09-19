// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;

import { Test } from "celo-foundry/Test.sol";

import { WithRegistry } from "./utils/WithRegistry.sol";

import { StableToken } from "contracts/StableToken.sol";
import { Freezer } from "contracts/common/Freezer.sol";
import { FixidityLib } from "contracts/common/FixidityLib.sol";

contract StableTokenTest is Test, WithRegistry {
  using FixidityLib for FixidityLib.Fraction;

  event InflationFactorUpdated(uint256 factor, uint256 lastUpdated);
  event InflationParametersUpdated(uint256 rate, uint256 updatePeriod, uint256 lastUpdated);
  event Transfer(address indexed from, address indexed to, uint256 value);
  event TransferComment(string comment);

  // Dependencies
  Freezer freezer;
  StableToken testee;

  // Actors
  address deployer;
  address notDeployer;

  // Global variables
  uint256 initTime;

  function setUp() public {
    deployer = actor("deployer");
    notDeployer = actor("deployer");

    changePrank(deployer);

    // Init dependencies
    freezer = new Freezer(true);
    testee = new StableToken(true);

    address[] memory initialAddresses = new address[](0);
    uint256[] memory initialBalances = new uint256[](0);
    testee.initialize(
      "Celo Dollar",
      "cUSD",
      18,
      address(registry),
      FixidityLib.unwrap(FixidityLib.fixed1()),
      1 weeks,
      initialAddresses,
      initialBalances,
      "Exchange"
    );

    initTime = block.timestamp;
  }
}

contract StableTokenTest_initilizerAndSetters is StableTokenTest {
  function test_initialize_shouldSetName() public {
    assertEq(testee.name(), "Celo Dollar");
  }

  function test_initialize_shouldSetSymbol() public {
    assertEq(testee.symbol(), "cUSD");
  }

  function test_initialize_shouldSetOwner() public {
    assert(testee.owner() == deployer);
  }

  function test_initialize_shouldSetDecimals() public {
    assert(testee.decimals() == 18);
  }

  function test_initialize_shouldSetRegistry() public {
    assert(address(testee.registry()) == address(registry));
  }

  function test_initialize_shouldSetInflationRateParams() public {
    (uint256 rate, uint256 factor, uint256 updatePeriod, uint256 lastUpdated) = testee.getInflationParameters();

    assertEq(rate, FixidityLib.unwrap(FixidityLib.fixed1()));
    assertEq(factor, FixidityLib.unwrap(FixidityLib.fixed1()));
    assertEq(updatePeriod, 1 weeks);
    assertEq(lastUpdated, initTime);
  }

  function test_initialize_whenCalledAgain_shouldRevert() public {
    address[] memory addresses = new address[](0);
    uint256[] memory balances = new uint256[](0);
    vm.expectRevert("contract already initialized");
    testee.initialize(
      "Celo Dollar",
      "cUSD",
      18,
      address(registry),
      FixidityLib.unwrap(FixidityLib.fixed1()),
      1 weeks,
      addresses,
      balances,
      "Exchange"
    );
  }
}
