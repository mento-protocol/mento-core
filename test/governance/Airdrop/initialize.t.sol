// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";

import { Airdrop_Test } from "./Base.t.sol";
import { Airdrop } from "contracts/governance/Airdrop.sol";

contract Initialize_Airdrop_Test is Airdrop_Test {
  event Approval(address indexed owner, address indexed spender, uint256 value);
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  /// @notice Test subject `initialize`
  function subject() internal {
    airdrop.initialize(tokenAddress);
  }

  function setUp() public override {
    super.setUp();
    newAirdrop();
  }

  /// @notice Checks the token address
  function test_Initialize_InvalidToken() external {
    tokenAddress = address(0);
    vm.expectRevert("Airdrop: invalid token");
    subject();
  }

  /// @notice Renounces ownership and sets token
  function test_Initialize_TransfersOwnershipAndSetsToken() external {
    vm.expectEmit(true, true, true, true);
    emit Approval(address(airdrop), lockingContract, type(uint256).max);
    vm.expectEmit(true, true, true, true);
    emit OwnershipTransferred(address(this), address(0));
    subject();
    assertEq(address(airdrop.token()), tokenAddress);
    assertEq(airdrop.owner(), address(0));
  }

  /// @notice Reverts if called two times, because ownership is renounced
  function test_Initialize_OnlyCallableOnce() external {
    subject();
    vm.expectRevert("Ownable: caller is not the owner");
    subject();
  }

  /// @notice Reverts if not the owner
  function test_Initialize_OnlyCallableByOwner() external {
    vm.prank(address(1));
    vm.expectRevert("Ownable: caller is not the owner");
    subject();
  }
}
