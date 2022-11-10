// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;

import { Test, console2 as console } from "celo-foundry/Test.sol";

import { WithRegistry } from "./utils/WithRegistry.sol";

import { IERC20 } from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import { UsingPrecompiles } from "contracts/common/UsingPrecompiles.sol";
import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";

import { StableToken } from "contracts/StableToken.sol";
import { Freezer } from "contracts/common/Freezer.sol";
import { FixidityLib } from "contracts/common/FixidityLib.sol";

contract StableTokenTest is Test, WithRegistry, UsingPrecompiles {
  using SafeMath for uint256;
  using FixidityLib for FixidityLib.Fraction;

  event InflationFactorUpdated(uint256 factor, uint256 lastUpdated);
  event InflationParametersUpdated(uint256 rate, uint256 updatePeriod, uint256 lastUpdated);
  event Transfer(address indexed from, address indexed to, uint256 value);
  event TransferComment(string comment);
  event Approval(address indexed owner, address indexed spender, uint256 value);

  // Dependencies
  Freezer freezer;
  StableToken testee;

  // Actors
  address deployer;
  address notDeployer;

  // Global variables
  uint256 initTime;
  uint256 inflationRate = 0.995 * 10**24; // 0.5% weekly deflation
  uint256 inflationRate2 = 1.005 * 10**24; // 0.5% weekly inflation

  function setUp() public {
    deployer = actor("deployer");
    notDeployer = actor("notDeployer");

    changePrank(deployer);

    freezer = new Freezer(true);
    testee = new StableToken(true);

    registry.setAddressFor("Freezer", address(freezer));

    address[] memory initialAddresses = new address[](0);
    uint256[] memory initialBalances = new uint256[](0);
    testee.initialize("Celo Dollar", "cUSD", 18, address(registry), 1e24, 1 weeks, initialAddresses, initialBalances, "Exchange");

    initTime = block.timestamp;
  }

  function setUpInflation(uint256 inflationRate) public {
    testee.setInflationParameters(inflationRate, 1 weeks);
    skip(1 weeks);
    vm.roll(block.number + 1);
  }

  function mockFractionMul0995() public {
    ph.mockReturn(
      FRACTION_MUL,
      keccak256(abi.encodePacked(uint256(1e24), uint256(1e24), uint256(995e21), uint256(1e24), uint256(1), uint256(18))),
      abi.encode(uint256(0.995 * 10**18), uint256(1e18))
    );
  }

  function mockFractionMul0995Twice() public {
    ph.mockReturn(
      FRACTION_MUL,
      keccak256(abi.encodePacked(uint256(1e24), uint256(1e24), uint256(995e21), uint256(1e24), uint256(2), uint256(18))),
      abi.encode(uint256(0.990025 * 10**18), uint256(1e18))
    );
  }

  function mockFractionMul1005() public {
    ph.mockReturn(
      FRACTION_MUL,
      keccak256(abi.encodePacked(uint256(1e24), uint256(1e24), uint256(1.005 * 10**24), uint256(1e24), uint256(1), uint256(18))),
      abi.encode(uint256(1.005 * 10**18), uint256(1e18))
    );
  }

  function mockFractionMul1005Twice() public {
    ph.mockReturn(
      FRACTION_MUL,
      keccak256(abi.encodePacked(uint256(1e24), uint256(1e24), uint256(1.005 * 10**24), uint256(1e24), uint256(2), uint256(18))),
      abi.encode(uint256(1.010025 * 10**18), uint256(1e18))
    );
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

  function test_mint_whenInflationFactorIsOutdated_shouldUpdateAndEmit() public {
    mockFractionMul0995();

    changePrank(deployer);
    setUpInflation(inflationRate);

    changePrank(exchange);

    vm.expectEmit(true, true, true, true);
    emit InflationFactorUpdated(inflationRate, 1 weeks + initTime);
    testee.mint(exchange, mintAmount);
  }
}

contract StableTokenTest_transferWithComment is StableTokenTest {
  address sender;
  address receiver;
  string comment;
  uint256 mintAmount = 100 * 10**18;

  function setUp() public {
    super.setUp();

    sender = actor("sender");
    receiver = actor("receiver");
    comment = "pineapples absolutely do not belong on pizza";

    registry.setAddressFor("Exchange", sender);
    registry.setAddressFor("Validators", sender);
    registry.setAddressFor("GrandaMento", sender);

    changePrank(sender);
    testee.mint(sender, mintAmount);
  }

  function test_transferWithComment_whenToAddressIsNull_shouldRevert() public {
    vm.expectRevert("transfer attempted to reserved address 0x0");
    testee.transferWithComment(address(0), 1, comment);
  }

  function test_transferWithComment_whenValueGreaterThanBalance_shouldRevert() public {
    uint256 value = IERC20(testee).balanceOf(sender) + 1;
    vm.expectRevert("transfer value exceeded balance of sender");
    testee.transferWithComment(receiver, value, comment);
  }

  function test_transferWithComment_shouldTransferBalance() public {
    uint256 senderBalanceBefore = IERC20(testee).balanceOf(sender);
    uint256 receiverBalanceBefore = IERC20(testee).balanceOf(receiver);

    vm.expectEmit(true, true, true, true);
    emit Transfer(sender, receiver, 5);

    vm.expectEmit(true, true, true, true);
    emit TransferComment(comment);

    testee.transferWithComment(receiver, 5, comment);

    uint256 senderBalanceAfter = IERC20(testee).balanceOf(sender);
    uint256 receiverBalanceAfter = IERC20(testee).balanceOf(receiver);

    assertEq(senderBalanceAfter, senderBalanceBefore - 5);
    assertEq(receiverBalanceAfter, receiverBalanceBefore + 5);
  }

  function test_transferWithComment_whenInflationFactorIsOutdated_shouldUpdateAndEmit() public {
    mockFractionMul0995();
    changePrank(deployer);
    setUpInflation(inflationRate);

    changePrank(sender);

    vm.expectEmit(true, true, true, true);
    emit InflationFactorUpdated(inflationRate, 1 weeks + initTime);
    testee.transferWithComment(receiver, 5, comment);
  }

  function test_transferWithComment_whenContractIsFrozen_shouldRevert() public {
    changePrank(deployer);
    freezer.freeze(address(testee));
    vm.expectRevert("can't call when contract is frozen");
    testee.transferWithComment(receiver, 5, comment);
  }
}

contract StableTokenTest_setInflationParameters is StableTokenTest {
  uint256 newUpdatePeriod = 1 weeks + 5;

  function test_setInflationParameters_shouldUpdateParameters() public {
    uint256 newInflationRate = 2.1428571429 * 10**24;

    changePrank(deployer);
    testee.setInflationParameters(newInflationRate, newUpdatePeriod);
    (uint256 rate, , uint256 updatePeriod, uint256 lastUpdated) = testee.getInflationParameters();

    assertEq(rate, newInflationRate);
    assertEq(updatePeriod, newUpdatePeriod);
    assertEq(lastUpdated, initTime);
  }

  function test_setInflationParameters_shouldEmitEvent() public {
    uint256 newUpdatePeriod = 1 weeks + 5;

    changePrank(deployer);
    vm.expectEmit(true, true, true, true);
    emit InflationParametersUpdated(inflationRate, newUpdatePeriod, now);
    testee.setInflationParameters(inflationRate, newUpdatePeriod);
  }

  function test_setInflationParameters_whenInflationFactorIsOutdated_shouldUpdateFactor() public {
    mockFractionMul0995();

    changePrank(deployer);

    setUpInflation(inflationRate);

    vm.expectEmit(true, true, true, true);
    emit InflationFactorUpdated(inflationRate, 1 weeks + initTime);
    testee.setInflationParameters(2, newUpdatePeriod);
  }

  function test_setInflationParameters_whenRateIsZero_shouldRevert() public {
    changePrank(deployer);
    vm.expectRevert("Must provide a non-zero inflation rate.");
    testee.setInflationParameters(0, 1 weeks);
  }
}

contract StableTokenTest_balanceOf is StableTokenTest {
  uint256 mintAmount = 1000;
  address sender;

  function setUp() public {
    super.setUp();

    sender = actor("sender");

    registry.setAddressFor("Exchange", sender);

    changePrank(sender);
    testee.mint(sender, mintAmount);
  }

  function test_balanceOf_whenNoInflation_shouldFetchCorrectBalance() public {
    uint256 balance = testee.balanceOf(sender);
    assertEq(balance, mintAmount);
    vm.roll(block.number + 1);
    uint256 newBalance = testee.balanceOf(sender);
    assertEq(newBalance, balance);
  }

  function test_balanceOf_withInflation_shouldFetchCorrectBalance() public {
    changePrank(deployer);
    setUpInflation(inflationRate);
    mockFractionMul0995();
    uint256 adjustedBalance = testee.balanceOf(sender);
    assertEq(adjustedBalance, 1005);
  }

  function test_balanceOf_withInflation2_shouldFetchCorrectBalance() public {
    changePrank(deployer);
    setUpInflation(inflationRate2);
    mockFractionMul1005();
    uint256 adjustedBalance = testee.balanceOf(sender);
    assertEq(adjustedBalance, 995);
  }
}

contract StableTokenTest_valueToUnits is StableTokenTest {
  function test_valueToUnits_value1000AfterInflation_shouldCorrespondToRoughly995() public {
    changePrank(deployer);
    setUpInflation(inflationRate);
    mockFractionMul0995();
    uint256 value = testee.valueToUnits(1000);
    assertEq(value, 995);
  }

  function test_valueToUnits_value1000AfterInflationTwice_shouldCorrespondToRoughly990() public {
    changePrank(deployer);
    setUpInflation(inflationRate);
    mockFractionMul0995Twice();
    skip(1 weeks);
    uint256 value = testee.valueToUnits(1000);
    assertEq(value, 990);
  }

  function test_valueToUnits_value1000AfterInflation2_shouldCorrespondToRoughly1005() public {
    changePrank(deployer);
    setUpInflation(inflationRate2);
    mockFractionMul1005();
    uint256 value = testee.valueToUnits(1000);
    assertEq(value, 1005);
  }

  function test_valueToUnits_value1000AfterInflation2Twice_shouldCorrespondToRoughly1010() public {
    changePrank(deployer);
    setUpInflation(inflationRate2);
    mockFractionMul1005Twice();
    skip(1 weeks);
    uint256 value = testee.valueToUnits(1000);
    assertEq(value, 1010);
  }
}

contract StableTokenTest_unitsToValue is StableTokenTest {
  function test_unitsToValue_1000UnitsAfterInflation_shouldCorrespondToRoughly1005() public {
    changePrank(deployer);
    setUpInflation(inflationRate);
    mockFractionMul0995();
    uint256 value = testee.unitsToValue(1000);
    assertEq(value, 1005);
  }

  function test_unitsToValue_1000UnitsAfterInflationTwice_shouldCorrespondToRoughly1010() public {
    changePrank(deployer);
    setUpInflation(inflationRate);
    mockFractionMul0995Twice();
    skip(1 weeks);
    uint256 value = testee.unitsToValue(1000);
    assertEq(value, 1010);
  }

  function test_unitsToValue_1000UnitsAfterInflation2_shouldCorrespondToRoughly995() public {
    changePrank(deployer);
    setUpInflation(inflationRate2);
    mockFractionMul1005();
    uint256 value = testee.unitsToValue(1000);
    assertEq(value, 995);
  }

  function test_unitsToValue_1000UnitsAfterInflation2Twice_shouldCorrespondToRoughly990() public {
    changePrank(deployer);
    setUpInflation(inflationRate2);
    mockFractionMul1005Twice();
    skip(1 weeks);
    uint256 value = testee.unitsToValue(1000);
    assertEq(value, 990);
  }
}

contract StableTokenTest_burn is StableTokenTest {
  address exchange;
  address grandaMento;

  uint256 mintAmount = 10;
  uint256 burnAmount = 5;

  function setUp() public {
    super.setUp();

    exchange = actor("exchange");
    grandaMento = actor("grandaMento");

    registry.setAddressFor("Exchange", exchange);
    registry.setAddressFor("GrandaMento", grandaMento);
  }

  function burnAndAssert(address to, uint256 value) public {
    changePrank(to);
    vm.expectEmit(true, true, true, true);
    emit Transfer(to, address(0), testee.valueToUnits(value));
    testee.burn(value);
    assertEq(testee.balanceOf(to), value);
    assertEq(testee.totalSupply(), value);
  }

  function test_burn_whenCalledByExchange_shouldBurnTokens() public {
    changePrank(exchange);
    testee.mint(exchange, mintAmount);
    burnAndAssert(exchange, burnAmount);
  }

  function test_burn_whenCalledByGrandaMento_shouldBurnTokens() public {
    changePrank(grandaMento);
    testee.mint(grandaMento, mintAmount);
    burnAndAssert(grandaMento, burnAmount);
  }

  function test_burn_whenValueExceedsBalance_shouldRevert() public {
    changePrank(grandaMento);
    testee.mint(grandaMento, mintAmount);
    vm.expectRevert("value exceeded balance of sender");
    testee.burn(11);
  }

  function test_burn_whenCalledByUnothorizedSender_shouldRevert() public {
    changePrank(notDeployer);
    vm.expectRevert("Sender not authorized to burn");
    testee.burn(burnAmount);
  }

  function test_burn_whenInflationFactorIsOutdated_shouldUpdateAndEmit() public {
    mockFractionMul0995();
    changePrank(deployer);
    setUpInflation(inflationRate);

    vm.expectEmit(true, true, true, true);
    emit InflationFactorUpdated(inflationRate, 1 weeks + initTime);
    changePrank(exchange);
    testee.mint(exchange, mintAmount);
    testee.burn(burnAmount);
  }
}

contract StableTokenTest_getExchangeRegistryId is StableTokenTest {
  function test_getExchangeRegistryId_shouldMatchInitializedValue() public {
    StableToken stableToken2 = new StableToken(true);
    stableToken2.initialize(
      "Celo Dollar",
      "cUSD",
      18,
      address(registry),
      1e24,
      1 weeks,
      new address[](0),
      new uint256[](0),
      "ExchangeEUR"
    );
    bytes32 fetchedId = stableToken2.getExchangeRegistryId();
    assertEq(fetchedId, keccak256("ExchangeEUR"));
  }

  function test_whenUnitialized_shouldFallbackToDefault() public {
    StableToken stableToken2 = new StableToken(true);
    bytes32 fetchedId = stableToken2.getExchangeRegistryId();
    assertEq(fetchedId, keccak256("Exchange"));
  }
}

contract StableTokenTest_erc20Functions is StableTokenTest {
  address sender = actor("sender");
  address receiver = actor("receiver");
  uint256 transferAmount = 1;
  uint256 amountToMint = 10;

  function setUp() public {
    super.setUp();

    registry.setAddressFor("Exchange", sender);
    changePrank(sender);
    testee.mint(sender, amountToMint);
  }

  function assertBalance(address spenderAddress, uint256 balance) public {
    assertEq(testee.balanceOf(spenderAddress), balance);
  }

  function test_allowance_shouldReturnAllowance() public {
    testee.approve(receiver, transferAmount);
    assertEq(testee.allowance(sender, receiver), transferAmount);
  }

  function test_approve_whenSpenderIsNotZeroAddress_shouldUpdateAndEmit() public {
    vm.expectEmit(true, true, true, true);
    emit Approval(sender, receiver, transferAmount);
    bool res = testee.approve(receiver, transferAmount);
    assertEq(res, true);
    assertEq(testee.allowance(sender, receiver), transferAmount);
  }

  function test_approve_whenSpenderIsZeroAddress_shouldRevert() public {
    vm.expectRevert("reserved address 0x0 cannot have allowance");
    testee.approve(address(0), transferAmount);
  }

  function test_approve_whenInflationFactorIsOutdated_shouldUpdateAndEmit() public {
    mockFractionMul0995();

    changePrank(deployer);
    setUpInflation(inflationRate);

    changePrank(sender);

    vm.expectEmit(true, true, true, true);
    emit InflationFactorUpdated(inflationRate, 1 weeks + initTime);
    testee.approve(receiver, transferAmount);
  }

  function test_increaseAllowance_whenSpenderIsNotZeroAddress_shouldUpdateAndEmit() public {
    vm.expectEmit(true, true, true, true);
    emit Approval(sender, receiver, 2);
    bool res = testee.increaseAllowance(receiver, 2);
    assertEq(testee.allowance(sender, receiver), 2);
    assertEq(testee.allowance(sender, sender), 0);
  }

  function test_increaseAllowance_whenSpenderIsZeroAddress_shouldRevert() public {
    vm.expectRevert("reserved address 0x0 cannot have allowance");
    testee.increaseAllowance(address(0), transferAmount);
  }

  function test_increaseAllowance_whenInflationFactorIsOutdated_shouldUpdateAndEmit() public {
    mockFractionMul0995();

    changePrank(deployer);
    setUpInflation(inflationRate);
    changePrank(sender);

    vm.expectEmit(true, true, true, true);
    emit InflationFactorUpdated(inflationRate, 1 weeks + initTime);
    testee.increaseAllowance(receiver, 2);
  }

  function test_decreaseAllowance_whenSpenderIsNotZeroAddress_shouldUpdateAndEmit() public {
    testee.approve(receiver, 2);
    vm.expectEmit(true, true, true, true);
    emit Approval(sender, receiver, transferAmount);
    bool res = testee.decreaseAllowance(receiver, transferAmount);
    assertEq(res, true);
    assertEq(testee.allowance(sender, receiver), transferAmount);
  }

  function test_decreaseAllowance_whenInflationFactorIsOutdated_shouldUpdateAndEmit() public {
    testee.approve(receiver, 2);

    mockFractionMul0995();

    changePrank(deployer);
    testee.approve(receiver, 2);
    setUpInflation(inflationRate);
    changePrank(sender);

    vm.expectEmit(true, true, true, true);
    emit InflationFactorUpdated(inflationRate, 1 weeks + initTime);
    testee.decreaseAllowance(receiver, transferAmount);
  }

  function test_transfer_whenReceiverIsNotZeroAddress_shouldTransferAndEmit() public {
    uint256 senderStartBalance = testee.balanceOf(sender);
    uint256 receiverStartBalance = testee.balanceOf(receiver);

    vm.expectEmit(true, true, true, true);
    emit Transfer(sender, receiver, transferAmount);
    bool res = testee.transfer(receiver, transferAmount);
    assertEq(res, true);
    assertBalance(sender, senderStartBalance.sub(transferAmount));
    assertBalance(receiver, receiverStartBalance.add(transferAmount));
  }

  function test_transfer_whenReceiverIsZeroAddress_shouldRevert() public {
    vm.expectRevert("transfer attempted to reserved address 0x0");
    testee.transfer(address(0), transferAmount);
  }

  function test_transfer_whenItExceedsSenderBalance_shouldRevert() public {
    vm.expectRevert("transfer value exceeded balance of sender");
    testee.transfer(receiver, amountToMint + 1);
  }

  function test_transfer_whenContractIsFrozen_shouldRevert() public {
    changePrank(deployer);
    freezer.freeze(address(testee));
    vm.expectRevert("can't call when contract is frozen");
    testee.transfer(receiver, amountToMint + 1);
  }

  function test_transfer_whenInflationFactorIsOutdated_shouldUpdateAndEmit() public {
    mockFractionMul0995();

    changePrank(deployer);
    setUpInflation(inflationRate);

    changePrank(sender);

    vm.expectEmit(true, true, true, true);
    emit InflationFactorUpdated(inflationRate, 1 weeks + initTime);
    testee.transfer(receiver, transferAmount);
  }

  function test_transferFrom_whenSenderIsExchange_shouldTransferAndEmit() public {
    testee.approve(sender, transferAmount);

    uint256 exchangeStartBalance = testee.balanceOf(sender);
    uint256 receiverStartBalance = testee.balanceOf(receiver);

    vm.expectEmit(true, true, true, true);
    emit Transfer(sender, receiver, transferAmount);
    bool res = testee.transferFrom(sender, receiver, transferAmount);
    assertEq(res, true);
    assertBalance(sender, exchangeStartBalance.sub(transferAmount));
    assertBalance(receiver, receiverStartBalance.add(transferAmount));
  }

  function test_transferFrom_whenReceiverIsZeroAddress_shouldRevert() public {
    vm.expectRevert("transfer attempted to reserved address 0x0");
    testee.transferFrom(sender, address(0), transferAmount);
  }

  function test_transferFrom_whenItExceedsSenderBalance_shouldRevert() public {
    vm.expectRevert("transfer value exceeded balance of sender");
    testee.transferFrom(sender, receiver, amountToMint + 1);
  }

  function test_transferFrom_whenItExceedsSpenderAllowence_shoulrRevert() public {
    vm.expectRevert("transfer value exceeded sender's allowance for recipient");
    testee.transferFrom(sender, receiver, transferAmount);
  }

  function test_transferFrom_whenContractIsFrozen_shouldRevert() public {
    changePrank(deployer);
    freezer.freeze(address(testee));
    vm.expectRevert("can't call when contract is frozen");
    testee.transferFrom(sender, receiver, transferAmount);
  }

  function test_transferFrom_whenInflationFactorIsOutdated_shouldUpdateAndEmit() public {
    testee.approve(sender, transferAmount);

    mockFractionMul0995();

    changePrank(deployer);
    setUpInflation(inflationRate);

    changePrank(sender);

    vm.expectEmit(true, true, true, true);
    emit InflationFactorUpdated(inflationRate, 1 weeks + initTime);
    testee.transferFrom(sender, receiver, transferAmount);
  }
}
