// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { Airdrop_Test } from "./Base.t.sol";

contract HasAirdrop_Airdrop_Test is Airdrop_Test {
  bytes32[] public invalidMerkleProof = new bytes32[](0);

  /// @notice Test subject parameters
  address public account;
  uint256 amount;
  bytes32[] merkleProof;
  /// @notice Test subject `hasAirdrop`
  function subject() internal view returns (bool) {
    return airdrop.hasAirdrop(account, amount, merkleProof);
  }

  function setUp() public override {
    super.setUp();
    initAirdrop();

    account = claimer0;
    amount = claimer0Amount;
    merkleProof = claimer0Proof;
  }

  /// @notice With default params, returns true
  function test_HasAirdrop_Valid() external {
    assertEq(subject(), true);
  }

  /// @notice With an invalidClaimer, returns false
  function test_HasAirdrop_InvalidAccount() external {
    account = invalidClaimer;
    assertEq(subject(), false);
  }

  /// @notice With an invalide amount, returns false
  function test_HasAirdrop_InvalidAmount() external {
    amount = 2 * claimer0Amount;
    assertEq(subject(), false);
  }

  /// @notice With an invalid proof, returns false
  function test_HasAirdrop_InvalidProof() external {
    merkleProof = invalidMerkleProof;
    assertEq(subject(), false);
  }
}
