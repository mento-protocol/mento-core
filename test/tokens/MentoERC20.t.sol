// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8.19;

import { console } from "forge-std-next/console.sol";
import { Arrays } from "../utils/Arrays.sol";
import { BaseTest } from "../utils/BaseTest.next.sol";

import { MentoERC20 } from "contracts/tokens/MentoERC20.sol";

contract MentoERC20Test is BaseTest {
  event TransferComment(string comment);

  address validators = address(0x1001);
  address broker = address(0x1002);
  address exchange = address(0x1003);

  address holder0 = address(0x2001);
  address holder1 = address(0x2002);
  address holder2;
  uint256 holder2Pk = uint256(0x31337);

  MentoERC20 private token;

  function setUp() public {
    holder2 = vm.addr(holder2Pk);

    token = new MentoERC20(false);
    token.initialize(
      "cUSD",
      "cUSD",
      0, // deprecated
      address(0), // deprecated
      0, // deprecated
      0, // deprecated
      Arrays.addresses(holder0, holder1, holder2, broker, exchange),
      Arrays.uints(1000, 1000, 1000, 1000, 1000),
      "" // deprecated
    );
    token.initializeV2(
      broker,
      validators,
      exchange
    );
  }

  function test_initializers_disabled() public {
    MentoERC20 disabledToken = new MentoERC20(true);

    address[] memory initialAddresses = new address[](0);
    uint256[] memory initialBalances = new uint256[](0);

    vm.expectRevert(bytes("Initializable: contract is already initialized"));
    disabledToken.initialize(
      "cUSD",
      "cUSD",
      0, // deprecated
      address(0), // deprecated
      0, // deprecated
      0, // deprecated
      initialAddresses,
      initialBalances,
      "" // deprecated
    );

    vm.expectRevert(bytes("Initializable: contract is already initialized"));
    token.initializeV2(
      broker,
      validators,
      exchange
    );
  }

  function test_transferWithComment() public {
    vm.expectEmit(true, true, true, true);
    emit TransferComment("Hello World");
    vm.prank(holder0);
    token.transferWithComment(holder1, 100, "Hello World");
  }

  function test_mint_allowed() public {
    uint256 before = token.balanceOf(holder0);
    vm.prank(broker);
    token.mint(holder0, 100);
    vm.prank(validators);
    token.mint(holder0, 100);
    vm.prank(exchange);
    token.mint(holder0, 100);
    assertEq(before + 300, token.balanceOf(holder0));
  }

  function test_mint_forbidden() public {
    vm.prank(holder0);
    vm.expectRevert(bytes("MentoERC20: not allowed to mint"));
    token.mint(holder0, 100);
  }

  function test_burn_allowed() public {
    vm.prank(broker);
    token.burn(100);
    assertEq(900, token.balanceOf(broker));

    vm.prank(exchange);
    token.burn(100);
    assertEq(900, token.balanceOf(exchange));
  }

  function test_burn_forbidden() public {
    vm.prank(holder0);
    vm.expectRevert(bytes("MentoERC20: not allowed to burn"));
    token.burn(100);
  }

  function test_erc20_permit() public {
    console.log("holder2", holder2);
    console.logBytes32(token.DOMAIN_SEPARATOR());
  }
}
