// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { Airdrop_Test, ERC20 } from "./Base.t.sol";

contract Drain_Airdrop_Test is Airdrop_Test {
  event TokensDrained(address indexed token, uint256 amount);

  /// @notice Test subject parameters
  address tokenToDrain;

  /// @notice Test subject `drain`
  function subject() internal {
    airdrop.drain(tokenToDrain);
  }

  function setUp() public override {
    super.setUp();
    initAirdrop();
    tokenToDrain = tokenAddress;
  }

  /// @notice Reverts if airdrop hasn't ended
  function test_Drain_beforeAirdropEnds() public {
    vm.expectRevert("Airdrop: not finished");
    subject();
  }

  /// @notice Reverts if the airdrop contract doesn't have balance
  function test_Drain_afterAirdropEndsWhenNoBalance() public {
    vm.warp(airdrop.endTimestamp() + 1);
    vm.expectRevert("Airdrop: nothing to drain");
    subject();
  }

  /// @notice Drains all tokens to the treasury if the airdrop has ended
  function test_Drain_afterAirdropEndsWithSomeBalance() public {
    vm.warp(airdrop.endTimestamp() + 1);
    deal(tokenAddress, address(airdrop), 100e18);
    vm.expectEmit(true, true, true, true);
    emit TokensDrained(tokenAddress, 100e18);
    subject();
    assertEq(token.balanceOf(treasury), 100e18);
    assertEq(token.balanceOf(address(airdrop)), 0);
  }

  /// @notice Drains all arbitrary tokens to the treasury if the airdrop has ended
  function test_Drain_afterAirdropEndsWithSomeOtherTokenBalance() public {
    ERC20 otherToken = new ERC20("Other Token", "OTT");
    tokenToDrain = address(otherToken);

    vm.warp(airdrop.endTimestamp() + 1);
    deal(address(otherToken), address(airdrop), 100e18);
    vm.expectEmit(true, true, true, true);
    emit TokensDrained(address(otherToken), 100e18);
    subject();
    assertEq(otherToken.balanceOf(treasury), 100e18);
    assertEq(otherToken.balanceOf(address(airdrop)), 0);
  }
}
