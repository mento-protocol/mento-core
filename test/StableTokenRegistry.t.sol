pragma solidity ^0.5.13;

pragma experimental ABIEncoderV2;
import { Test, console2 as console } from "celo-foundry/Test.sol";

import { StableTokenRegistry } from "contracts/StableTokenRegistry.sol";

contract StableTokenRegistryTest is Test {
  StableTokenRegistry stableTokenRegistry;

  address deployer;
  address notDeployer;
  bytes fiatTickerUSD = bytes("USD");
  bytes stableTokenContractUSD = bytes("StableToken");

  //  console.log(stableTokenRegistry.fiatTickers(0));

  //   function assertSTContractNames(
  //     bytes concatenatedContracts,
  //     uint256[] lengths,
  //     bytes[] expectedContracts
  //   ) public {
  //     assertEq(lengths.length, expectedContracts.length);
  //     uint256 currentIndex = 0;
  //     for (uint256 i = 0; i < expectedContracts.length; i++) {
  //         uint256 nimver = currentIndex + lengths[i];
  //       bytes contractt = abi.decode(concatenatedContracts[currentIndex:nimver]);
  //       currentIndex += lengths[i];
  //       assertEq(contractt, expectedContracts[i]);
  //     }
  //     assertEq(concatenatedContracts.length, currentIndex);
  //   }

  function getSlice(
    uint256 begin,
    uint256 end,
    string memory text
  ) public pure returns (string memory) {
    bytes memory a = new bytes(end - begin + 1);
    for (uint256 i = 0; i <= end - begin; i++) {
      a[i] = bytes(text)[i + begin - 1];
    }
    return string(a);
  }

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
}
