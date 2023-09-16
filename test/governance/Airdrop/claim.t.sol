// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { Airdrop_Test } from "./Base.t.sol";

contract Claim_Airdrop_Test is Airdrop_Test {
  address public account;
  uint256 public amount;
  bytes32[] public merkleProof;
  uint8 public kycType;
  uint8 public countryOfIDIssuance;
  uint8 public countryOfResidence;
  bytes32 public rootHash;
  bytes public issuerSignature;
  uint32 public slope;
  uint32 public cliff;

  bytes32[] public invalidMerkleProof = new bytes32[](0);

  function setUp() override public {
    super.setUp();
    setAirdrop();
  }

  modifier whenAirdropEnded() {
    vm.warp(endTimestamp + 1);
    _;
  }

  modifier whenClaimer(address claimer) {
    account = claimer;
    _;
  }

  modifier whenAmount(uint256 _amount) {
    amount = amount;
    _;
  }

  modifier whenMerkleProof(bytes32[] memory _merkleProof) {
    merkleProof = _merkleProof;
    _;
  }

  function test_Claim_afterAirdrop() 
    whenAirdropEnded 
    external
  {
    vm.expectRevert("Airdrop: finished");
    subject();
  }

  function test_Claim_fails0() 
    whenClaimer(invalidClaimer)
    whenMerkleProof(invalidMerkleProof)
    external
  {
    vm.expectRevert("Airdrop: not in tree");
    subject();
  }

  function test_Claim_whenValidClaimerButWrongAmount() 
    whenClaimer(claimer0)
    whenAmount(1)
    external
  {
    vm.expectRevert("Airdrop: not in tree");
    subject();
  }

  function subject() internal {
    airdrop.claim(
      account,
      amount,
      merkleProof,
      kycType,
      countryOfIDIssuance,
      countryOfResidence,
      rootHash,
      issuerSignature,
      slope,
      cliff
    );
  }
}
