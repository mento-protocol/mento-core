// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { Airgrab_Test, ERC20 } from "./Base.t.sol";

contract Drain_Airgrab_Test is Airgrab_Test {
  event TokensDrained(address indexed token, uint256 amount);

  /// @notice Test subject parameters
  address tokenToDrain;

  /// @notice Test subject `drain`
  function subject() internal {
    airgrab.drain(tokenToDrain);
  }

  function setUp() public override {
    super.setUp();
    initAirgrab();
    tokenToDrain = tokenAddress;
  }

  /// @notice Reverts if airgrab hasn't ended
  function test_Drain_beforeAirgrabEnds() public {
    vm.expectRevert("Airgrab: not finished");
    subject();
  }

  /// @notice Reverts if the airgrab contract doesn't have balance
  function test_Drain_afterAirgrabEndsWhenNoBalance() public {
    vm.warp(airgrab.endTimestamp() + 1);
    vm.expectRevert("Airgrab: nothing to drain");
    subject();
  }

  /// @notice Drains all tokens to the treasury if the airgrab has ended
  function test_Drain_afterAirgrabEndsWithSomeBalance() public {
    vm.warp(airgrab.endTimestamp() + 1);
    deal(tokenAddress, address(airgrab), 100e18);
    vm.expectEmit(true, true, true, true);
    emit TokensDrained(tokenAddress, 100e18);
    subject();
    assertEq(token.balanceOf(treasury), 100e18);
    assertEq(token.balanceOf(address(airgrab)), 0);
  }

  /// @notice Drains all arbitrary tokens to the treasury if the airgrab has ended
  function test_Drain_afterAirgrabEndsWithSomeOtherTokenBalance() public {
    ERC20 otherToken = new ERC20("Other Token", "OTT");
    tokenToDrain = address(otherToken);

    vm.warp(airgrab.endTimestamp() + 1);
    deal(address(otherToken), address(airgrab), 100e18);
    vm.expectEmit(true, true, true, true);
    emit TokensDrained(address(otherToken), 100e18);
    subject();
    assertEq(otherToken.balanceOf(treasury), 100e18);
    assertEq(otherToken.balanceOf(address(airgrab)), 0);
  }
}
