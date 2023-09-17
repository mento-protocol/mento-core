// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { Airgrab_Test } from "./Base.t.sol";

contract HasAirgrab_Airgrab_Test is Airgrab_Test {
  bytes32[] public invalidMerkleProof = new bytes32[](0);

  /// @notice Test subject parameters
  address public account;
  uint256 amount;
  bytes32[] merkleProof;

  /// @notice Test subject `hasAirgrab`
  function subject() internal view returns (bool) {
    return airgrab.hasAirgrab(account, amount, merkleProof);
  }

  function setUp() public override {
    super.setUp();
    initAirgrab();

    account = claimer0;
    amount = claimer0Amount;
    merkleProof = claimer0Proof;
  }

  /// @notice With default params, returns true
  function test_HasAirgrab_Valid() external {
    assertEq(subject(), true);
  }

  /// @notice With an invalidClaimer, returns false
  function test_HasAirgrab_InvalidAccount() external {
    account = invalidClaimer;
    assertEq(subject(), false);
  }

  /// @notice With an invalide amount, returns false
  function test_HasAirgrab_InvalidAmount() external {
    amount = 2 * claimer0Amount;
    assertEq(subject(), false);
  }

  /// @notice With an invalid proof, returns false
  function test_HasAirgrab_InvalidProof() external {
    merkleProof = invalidMerkleProof;
    assertEq(subject(), false);
  }
}
