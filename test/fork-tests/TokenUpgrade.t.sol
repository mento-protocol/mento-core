// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { IRegistry } from "contracts/common/interfaces/IRegistry.sol";
import { IProxy as ILegacyProxy } from "contracts/common/interfaces/IProxy.sol";
import { MentoERC20 } from "contracts/tokens/MentoERC20.sol";

contract TokenUpgradeForkTest is Test {
  address public constant REGISTRY_ADDRESS = 0x000000000000000000000000000000000000ce10;
  IRegistry public registry = IRegistry(REGISTRY_ADDRESS);

  function test_upgrade() public {
    uint256 forkId = vm.createFork("celo_mainnet");
    vm.selectFork(forkId);

    address stableToken = registry.getAddressForString("StableToken");
    ILegacyProxy stableTokenProxy = ILegacyProxy(stableToken);
    console.log(ILegacyProxy(stableToken)._getImplementation());
    console.log(ILegacyProxy(stableToken)._getOwner());
    vm.startPrank(ILegacyProxy(stableToken)._getOwner());
    address mentoERC20Impl = address(new MentoERC20(false));
    stableTokenProxy._setImplementation(mentoERC20Impl);

    MentoERC20 cusd = MentoERC20(stableToken);
    cusd.initializeV2(
      registry.getAddressForString("Broker"),
      registry.getAddressForString("Validators"),
      registry.getAddressForString("Exchange")
    );

    address governance = registry.getAddressForString("Governance");
    cusd.balanceOf(governance);

    changePrank(governance);
    cusd.transfer(address(this), 1 ether);
    cusd.balanceOf(address(this));
  }
}
