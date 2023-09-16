// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { Airdrop_Test } from "./Base.t.sol";

contract HasAirdrop_Airdrop_Test is Airdrop_Test {
  address public account;
  uint256 amount;
  bytes32[] merkleProof;

  bytes32[] public invalidMerkleProof = new bytes32[](0);

  function setUp() override public {
    super.setUp();
    setAirdrop();

    account = claimer0;
    amount = claimer0Amount;
    merkleProof = claimer0Proof;
  }

  function subject() internal returns (bool) {
    return airdrop.hasAirdrop(account, amount, merkleProof);
  }

  function test_HasAirdrop_Valid() external {
    assertEq(subject(), true);
  }

  function test_HasAirdrop_InvalidAccount() external {
    account = invalidClaimer;
    assertEq(subject(), false);
  }

  function test_HasAirdrop_InvalidAmount() external {
    amount = 2*claimer0Amount;
    assertEq(subject(), false);
  }

  function test_HasAirdrop_InvalidProof() external {
    merkleProof = invalidMerkleProof;
    assertEq(subject(), false);
  }
}
