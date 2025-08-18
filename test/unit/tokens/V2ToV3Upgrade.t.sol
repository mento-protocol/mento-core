// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { Test } from "mento-std/Test.sol";

import { StableTokenV3 } from "contracts/tokens/StableTokenV3.sol";

interface IProxy {
  function _getImplementation() external view returns (address);
  function _getOwner() external view returns (address);
  function _setImplementation(address newImplementation) external;
}

interface IStableTokenV2 {
  function setBroker(address newBroker) external;
  function setValidators(address newValidators) external;
  function broker() external view returns (address);
  function validators() external view returns (address);
  function exchange() external view returns (address);
}

contract V2ToV3UpgradeTest is Test {
  address cUSDProxy = 0x765DE816845861e75A25fCA122bb6898B8B1282a;
  address cUSDImplementation;
  address owner;
  address StableTokenV3Implementation;

  IStableTokenV2 tokenV2 = IStableTokenV2(cUSDProxy);

  address[] minters = new address[](3);
  address[] burners = new address[](4);
  address[] operators = new address[](1);

  function setUp() public {
    vm.createSelectFork("https://forno.celo.org");
    cUSDImplementation = IProxy(cUSDProxy)._getImplementation();
    owner = IProxy(cUSDProxy)._getOwner();
    StableTokenV3Implementation = address(new StableTokenV3(true));

    minters[0] = tokenV2.validators();
    minters[1] = makeAddr("borrowerOperations");
    minters[2] = makeAddr("activePool");

    burners[0] = makeAddr("collateralRegistry");
    burners[1] = makeAddr("borrowerOperations");
    burners[2] = makeAddr("troveManager");
    burners[3] = makeAddr("stabilityPool1");

    operators[0] = makeAddr("stabilityPool1");
  }

  function test_migrateToV3_shouldUpgradeStableToken() public {
    vm.startPrank(owner);

    // erase deprecated storage slots before upgrading
    // not necessary for the upgrade, but good practice
    tokenV2.setBroker(address(0));
    tokenV2.setValidators(address(0));

    assertEq(tokenV2.broker(), address(0));
    assertEq(tokenV2.validators(), address(0));
    assertEq(tokenV2.exchange(), address(0));

    bytes32 slot0 = vm.load(address(tokenV2), bytes32(0));
    uint8 initialized = uint8(uint256(slot0) >> 160);
    assertEq(initialized, 2);

    // upgrade to StableTokenV3
    IProxy(cUSDProxy)._setImplementation(StableTokenV3Implementation);

    StableTokenV3 tokenV3 = StableTokenV3(cUSDProxy);

    assertEq(tokenV3.deprecated_validators_storage_slot__(), address(0));
    assertEq(tokenV3.deprecated_broker_storage_slot__(), address(0));
    assertEq(tokenV3.deprecated_exchange_storage_slot__(), address(0));

    assertEq(IProxy(cUSDProxy)._getImplementation(), StableTokenV3Implementation);
    assertEq(IProxy(cUSDProxy)._getOwner(), owner);

    tokenV3.migrateToV3(minters, burners, operators);

    assertEq(tokenV3.isMinter(minters[0]), true);
    assertEq(tokenV3.isMinter(minters[1]), true);
    assertEq(tokenV3.isMinter(minters[2]), true);

    assertEq(tokenV3.isBurner(burners[0]), true);
    assertEq(tokenV3.isBurner(burners[1]), true);
    assertEq(tokenV3.isBurner(burners[2]), true);
    assertEq(tokenV3.isBurner(burners[3]), true);

    assertEq(tokenV3.isOperator(operators[0]), true);

    // check that the contract is initialized as V3
    slot0 = vm.load(address(tokenV3), bytes32(0));
    initialized = uint8(uint256(slot0) >> 160);
    assertEq(initialized, 3);

    // check that the contract cant be initialized again
    address[] memory emptyAddresses = new address[](0);
    uint256[] memory emptyBalances = new uint256[](0);
    vm.expectRevert(bytes("Initializable: contract is already initialized"));
    tokenV3.initialize("cUSD", "cUSD", emptyAddresses, emptyBalances, minters, burners, operators);
    vm.expectRevert(bytes("Initializable: contract is already initialized"));
    tokenV3.migrateToV3(minters, burners, operators);
  }
}
