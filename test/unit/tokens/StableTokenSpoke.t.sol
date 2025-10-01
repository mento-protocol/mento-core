// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { addresses, uints } from "mento-std/Array.sol";
import { Test } from "mento-std/Test.sol";

import { StableTokenSpoke } from "contracts/tokens/StableTokenSpoke.sol";

contract StableTokenSpokeTest is Test {
  event MinterUpdated(address indexed minter, bool isMinter);
  event BurnerUpdated(address indexed burner, bool isBurner);

  address _holder0 = makeAddr("holder0");
  address _holder1 = makeAddr("holder1");
  address _minter1 = makeAddr("minter1");
  address _minter2 = makeAddr("minter2");
  address _burner1 = makeAddr("burner1");
  address _burner2 = makeAddr("burner2");

  StableTokenSpoke private _token;

  function setUp() public {
    address[] memory minters = new address[](2);
    minters[0] = _minter1;
    minters[1] = _minter2;

    address[] memory burners = new address[](2);
    burners[0] = _burner1;
    burners[1] = _burner2;

    _token = new StableTokenSpoke(false);
    _token.initialize(
      "cUSD",
      "cUSD",
      addresses(_holder0, _holder1, _burner1, _minter1),
      uints(1000, 1000, 1000, 0),
      minters,
      burners
    );

    assertEq(_token.isMinter(_minter1), true);
    assertEq(_token.isMinter(_minter2), true);
    assertEq(_token.isBurner(_burner1), true);
    assertEq(_token.isBurner(_burner2), true);
  }

  function test_initializers_disabled() public {
    StableTokenSpoke disabledToken = new StableTokenSpoke(true);

    address[] memory emptyAddresses = new address[](0);
    uint256[] memory emptyBalances = new uint256[](0);
    address[] memory emptyRoles = new address[](0);

    vm.expectRevert(bytes("Initializable: contract is already initialized"));
    disabledToken.initialize("cUSD", "cUSD", emptyAddresses, emptyBalances, emptyRoles, emptyRoles);
  }

  function test_initialize_shouldMintInitialBalances_setRolesAndTransferOwnership() public {
    assertEq(_token.balanceOf(_holder0), 1000);
    assertEq(_token.balanceOf(_holder1), 1000);
    assertEq(_token.balanceOf(_burner1), 1000);

    assertEq(_token.owner(), address(this));
  }

  function test_setMinter_whenCalledByOwner_shouldSetMinterAndEmitEvent() public {
    address newMinter = makeAddr("newMinter");
    vm.expectEmit(true, true, true, true);
    emit MinterUpdated(newMinter, true);
    _token.setMinter(newMinter, true);
    assertEq(_token.isMinter(newMinter), true);

    vm.expectEmit(true, true, true, true);
    emit MinterUpdated(newMinter, false);
    _token.setMinter(newMinter, false);
    assertEq(_token.isMinter(newMinter), false);
  }

  function test_setMinter_whenCalledByNotOwner_shouldRevert() public {
    address newMinter = makeAddr("newMinter");
    vm.prank(_holder0);
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    _token.setMinter(newMinter, true);
  }

  function test_setBurner_whenCalledByOwner_shouldSetBurnerAndEmitEvent() public {
    address newBurner = makeAddr("newBurner");
    vm.expectEmit(true, true, true, true);
    emit BurnerUpdated(newBurner, true);
    _token.setBurner(newBurner, true);
    assertEq(_token.isBurner(newBurner), true);

    vm.expectEmit(true, true, true, true);
    emit BurnerUpdated(newBurner, false);
    _token.setBurner(newBurner, false);
    assertEq(_token.isBurner(newBurner), false);
  }

  function test_setBurner_whenCalledByNotOwner_shouldRevert() public {
    address newBurner = makeAddr("newBurner");
    vm.prank(_holder0);
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    _token.setBurner(newBurner, true);
  }

  function test_mint_whenCalledByMinter_shouldMintTokens() public {
    uint256 balanceBefore = _token.balanceOf(_holder0);
    vm.prank(_minter1);
    bool ok = _token.mint(_holder0, 100);
    assertTrue(ok);
    assertEq(_token.balanceOf(_holder0), balanceBefore + 100);
  }

  function test_mint_whenSenderIsNotAuthorized_shouldRevert() public {
    vm.prank(_holder0);
    vm.expectRevert(bytes("StableToken: not allowed to mint"));
    _token.mint(_holder0, 100);
  }

  function test_burn_whenCalledByBurner_shouldBurnTokens() public {
    uint256 balanceBefore = _token.balanceOf(_burner1);
    vm.prank(_burner1);
    bool ok = _token.burn(100);
    assertTrue(ok);
    assertEq(_token.balanceOf(_burner1), balanceBefore - 100);
  }

  function test_burn_whenSenderIsNotAuthorized_shouldRevert() public {
    vm.prank(_holder0);
    vm.expectRevert(bytes("StableToken: not allowed to burn"));
    _token.burn(100);
  }
}
