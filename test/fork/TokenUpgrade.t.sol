// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { console } from "forge-std/console.sol";
import { Test } from "mento-std/Test.sol";
import { CELO_ID } from "mento-std/Constants.sol";

import { WithRegistry } from "../utils/WithRegistry.sol";

import { ICeloProxy } from "contracts/interfaces/ICeloProxy.sol";
import { IStableTokenV2 } from "contracts/interfaces/IStableTokenV2.sol";

contract TokenUpgradeForkTest is Test, WithRegistry {
  // solhint-disable-next-line func-name-mixedcase
  function test_upgrade() public {
    fork(CELO_ID, 22856317);

    address stableToken = registry.getAddressForString("StableToken");
    ICeloProxy stableTokenProxy = ICeloProxy(stableToken);
    console.log(ICeloProxy(stableToken)._getImplementation());
    console.log(ICeloProxy(stableToken)._getOwner());
    vm.startPrank(ICeloProxy(stableToken)._getOwner());
    address mentoERC20Impl = deployCode("StableTokenV2", abi.encode(false));
    stableTokenProxy._setImplementation(mentoERC20Impl);

    IStableTokenV2 cusd = IStableTokenV2(stableToken);
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
