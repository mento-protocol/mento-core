// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.5.13;

pragma experimental ABIEncoderV2;
import { Test } from "celo-foundry/Test.sol";

import { StableTokenRegistry } from "contracts/StableTokenRegistry.sol";

contract StableTokenRegistryTest is Test {
  StableTokenRegistry stableTokenRegistry;

  address deployer;
  address notDeployer;
  bytes fiatTickerUSD = bytes("USD");
  bytes stableTokenContractUSD = bytes("StableToken");

  function setUp() public {
    notDeployer = actor("notDeployer");
    deployer = actor("deployer");
    changePrank(deployer);
    stableTokenRegistry = new StableTokenRegistry(true);
    stableTokenRegistry.initialize(bytes("GEL"), bytes("StableTokenGEL"));
  }
}

contract StableTokenRegistryTest_initializerAndSetters is StableTokenRegistryTest {
  /* ---------- Initilizer ---------- */

  function test_initilize_shouldSetOwner() public {
    assertEq(stableTokenRegistry.owner(), deployer);
  }

  function test_initialize_whenAlreadyInitialized_shouldRevert() public {
    changePrank(notDeployer);
    vm.expectRevert("contract already initialized");
    stableTokenRegistry.initialize(bytes("GEL"), bytes("StableTokenGEL"));
  }

  function test_initilize_shouldSetFiatTickersAndContractAddresses() public {
    assertEq(stableTokenRegistry.fiatTickers(0), fiatTickerUSD);
    assertEq(stableTokenRegistry.fiatTickers(1), bytes("EUR"));
    assertEq(stableTokenRegistry.fiatTickers(2), bytes("BRL"));
    assertEq(stableTokenRegistry.fiatTickers(3), bytes("GEL"));
    assertEq(stableTokenRegistry.queryStableTokenContractNames(fiatTickerUSD), stableTokenContractUSD);
    assertEq(stableTokenRegistry.queryStableTokenContractNames(bytes("EUR")), bytes("StableTokenEUR"));
    assertEq(stableTokenRegistry.queryStableTokenContractNames(bytes("BRL")), bytes("StableTokenBRL"));
    assertEq(stableTokenRegistry.queryStableTokenContractNames(bytes("GEL")), bytes("StableTokenGEL"));
  }

  /* ---------- Setters ---------- */

  function test_removeStableToken_whenSenderIsNotOwner_shouldRevert() public {
    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    stableTokenRegistry.removeStableToken(fiatTickerUSD, 0);
  }

  function test_removeStableToken_whenIndexIsOutOfRange_shouldRevert() public {
    vm.expectRevert("Index is invalid");
    stableTokenRegistry.removeStableToken(fiatTickerUSD, 6);
  }

  function test_removeStableToken_whenIndexDoesNotMatchSource_shouldRevert() public {
    vm.expectRevert("source doesn't match the existing fiatTicker");
    stableTokenRegistry.removeStableToken(fiatTickerUSD, 1);
  }

  function test_removeStableToken_whenSenderIsOwner_shouldUpdate() public {
    stableTokenRegistry.removeStableToken(fiatTickerUSD, 0);
    assertEq(stableTokenRegistry.fiatTickers(0), bytes("GEL"));
    assertEq(stableTokenRegistry.fiatTickers(1), bytes("EUR"));
    assertEq(stableTokenRegistry.fiatTickers(2), bytes("BRL"));
    (bytes memory updatedContracts, ) = stableTokenRegistry.getContractInstances();
    assertEq(
      updatedContracts,
      abi.encodePacked(bytes("StableTokenGEL"), bytes("StableTokenEUR"), bytes("StableTokenBRL"))
    );
    assertEq(stableTokenRegistry.queryStableTokenContractNames((fiatTickerUSD)), "");
  }

  function test_addStableToken_whenSenderIsNotOwner_shouldRevert() public {
    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    stableTokenRegistry.addNewStableToken(fiatTickerUSD, stableTokenContractUSD);
  }

  function test_addStableToken_whenFiatTickerIsEmptyString_shouldRevert() public {
    vm.expectRevert("fiatTicker cant be an empty string");
    stableTokenRegistry.addNewStableToken("", stableTokenContractUSD);
  }

  function test_addStableToken_whenContractNameIsEmptyString_shouldRevert() public {
    vm.expectRevert("stableTokenContractName cant be an empty string");
    stableTokenRegistry.addNewStableToken(fiatTickerUSD, "");
  }

  function test_addStableToken_whenAlreadyAdded_shouldRevert() public {
    vm.expectRevert("This registry already exists");
    stableTokenRegistry.addNewStableToken(fiatTickerUSD, stableTokenContractUSD);
  }

  function test_addStableToken_whenSenderIsOwner_shouldUpdate() public {
    stableTokenRegistry.addNewStableToken(bytes("GBP"), bytes("StableTokenGBP"));
    assertEq(stableTokenRegistry.fiatTickers(0), fiatTickerUSD);
    assertEq(stableTokenRegistry.fiatTickers(1), bytes("EUR"));
    assertEq(stableTokenRegistry.fiatTickers(2), bytes("BRL"));
    assertEq(stableTokenRegistry.fiatTickers(3), bytes("GEL"));
    assertEq(stableTokenRegistry.fiatTickers(4), bytes("GBP"));
    (bytes memory updatedContracts, ) = stableTokenRegistry.getContractInstances();
    assertEq(
      updatedContracts,
      abi.encodePacked(
        bytes("StableToken"),
        bytes("StableTokenEUR"),
        bytes("StableTokenBRL"),
        bytes("StableTokenGEL"),
        bytes("StableTokenGBP")
      )
    );
    assertEq(stableTokenRegistry.queryStableTokenContractNames((bytes("GBP"))), bytes("StableTokenGBP"));
  }
}
