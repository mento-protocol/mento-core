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
    notDeployer = actor("notDeployer");

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

  function test_setRegistry_shouldSetRegistryAddress() public {
    address newRegistry = actor("newRegistry");
    testee.setRegistry(newRegistry);
    assertEq(address(testee.registry()), newRegistry);
  }

  function test_setRegistry_whenNotCalledByOwner_shouldRevert() public {
    changePrank(notDeployer);
    address newRegistry = actor("newRegistry");
    vm.expectRevert("Ownable: caller is not the owner");
    testee.setRegistry(newRegistry);
  }
}

contract StableTokenTest_mint is StableTokenTest {
  address exchange;
  address validators;
  address grandaMento;

  uint256 mintAmount = 100 * 10**18;

  function setUp() public {
    super.setUp();

    exchange = actor("exchange");
    validators = actor("validators");
    grandaMento = actor("grandaMento");

    registry.setAddressFor("Exchange", exchange);
    registry.setAddressFor("Validators", validators);
    registry.setAddressFor("GrandaMento", grandaMento);
  }

  function mintAndAssert(address to, uint256 value) public {
    changePrank(to);
    testee.mint(to, value);
    assertEq(testee.balanceOf(to), value);
    assertEq(testee.totalSupply(), value);
  }

  function test_mint_whenCalledByExchange_shouldMintTokens() public {
    mintAndAssert(exchange, mintAmount);
  }

  function test_mint_whenCalledByValidators_shouldMintTokens() public {
    mintAndAssert(validators, mintAmount);
  }

  function test_mint_whenCalledByGrandaMento_shouldMintTokens() public {
    mintAndAssert(grandaMento, mintAmount);
  }

  function test_mint_whenValueIsZero_shouldAllowMint() public {
    mintAndAssert(validators, 0);
  }

  function test_mint_whenSenderIsNotAuthorized_shouldRevert() public {
    changePrank(notDeployer);
    vm.expectRevert("Sender not authorized to mint");
    testee.mint(notDeployer, 10000);
  }
}

contract StableTokenTest_transferWithComment is StableTokenTest {
  address sender;
  address receiver;
  string comment;

  function setUp() public {
    super.setUp();

    sender = actor("sender");
    receiver = actor("receiver");
    comment = "pineapples belong on pizza";

    registry.setAddressFor("Exchange", sender);
    registry.setAddressFor("Validators", sender);
    registry.setAddressFor("GrandaMento", sender);

    changePrank(sender);
    testee.mint(sender, 100 * 10**18);
  }
}
