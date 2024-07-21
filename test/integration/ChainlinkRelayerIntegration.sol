// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility,
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import "openzeppelin-contracts/ownership/Ownable.sol";

import { IntegrationTest } from "../utils/IntegrationTest.t.sol";

import { IChainlinkRelayerFactory } from "contracts/interfaces/IChainlinkRelayerFactory.sol";
import { IProxyAdmin } from "contracts/interfaces/IProxyAdmin.sol";
import { ITransparentProxy } from "contracts/interfaces/ITransparentProxy.sol";

contract ChainlinkRelayerIntegration is IntegrationTest {
  address owner = actor("owner");

  IChainlinkRelayerFactory relayerFactoryImplementation;
  IChainlinkRelayerFactory relayerFactory;
  IProxyAdmin proxyAdmin;
  ITransparentProxy proxy;

  function setUp() public {
    IntegrationTest.setUp();

    proxyAdmin = IProxyAdmin(factory.createContract("ChainlinkRelayerFactoryProxyAdmin", ""));
    relayerFactoryImplementation = IChainlinkRelayerFactory(
      factory.createContract("ChainlinkRelayerFactory", abi.encode(true))
    );
    proxy = ITransparentProxy(
      factory.createContract(
        "TransparentUpgradeableProxy",
        abi.encode(
          address(relayerFactoryImplementation),
          address(proxyAdmin),
          abi.encodeWithSignature("initialize(address)", address(sortedOracles))
        )
      )
    );
    relayerFactory = IChainlinkRelayerFactory(address(proxy));
    vm.startPrank(address(factory));
    Ownable(address(proxyAdmin)).transferOwnership(owner);
    Ownable(address(relayerFactory)).transferOwnership(owner);
    vm.stopPrank();
  }
}

contract ChainlinkRelayerIntegration_ProxySetup is ChainlinkRelayerIntegration {
  function test_proxyOwnedByAdmin() public {
    vm.prank(owner);
    address admin = proxyAdmin.getProxyAdmin(address(proxy));
    assertEq(admin, address(proxyAdmin));
  }

  function test_adminOwnedByOwner() public {
    address realOwner = Ownable(address(proxyAdmin)).owner();
    assertEq(realOwner, owner);
  }

  function test_adminCantCallImplementation() public {
    vm.prank(address(proxyAdmin));
    vm.expectRevert("TransparentUpgradeableProxy: admin cannot fallback to proxy target");
    relayerFactory.sortedOracles();
  }

  function test_nonAdminCantCallProxy() public {
    vm.prank(owner);
    vm.expectRevert();
    proxy.implementation();
  }

  function test_implementationOwnedByOwner() public {
    address realOwner = Ownable(address(relayerFactory)).owner();
    assertEq(realOwner, owner);
  }

  function test_implementationSetCorrectly() public {
    address implementation = proxyAdmin.getProxyImplementation(address(proxy));
    assertEq(implementation, address(relayerFactoryImplementation));
  }

  function test_implementationNotInitializable() public {
    vm.expectRevert("Initializable: contract is already initialized");
    relayerFactoryImplementation.initialize(address(sortedOracles));
  }
}
