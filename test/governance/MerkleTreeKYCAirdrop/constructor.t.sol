// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { MerkleTreeKYCAirdrop_Test } from "./Base.t.sol";
import { MerkleTreeKYCAirdrop } from "contracts/governance/MerkleTreeKYCAirdrop.sol";

contract Constructor_MerkleTreeKYCAirdrop_Test is MerkleTreeKYCAirdrop_Test {
  function test_Constructor() external {
    // Asserts on the Airdrop created in the setUp() function.
    assertEq(airdrop.root(), merkleRoot); 
    assertEq(airdrop.fractalIssuer(), fractalIssuer);
    assertEq(airdrop.token(), address(token));
    assertEq(airdrop.treasury(), treasury);
    assertEq(airdrop.endTimestamp(), endTimestamp);
  }

  function test_Constructor_InvalidRoot() external {
    vm.expectRevert("Airdrop: invalid root");
    new MerkleTreeKYCAirdrop(
      bytes32(0),
      fractalIssuer,
      address(token),
      treasury,
      endTimestamp
    );
  }

  function test_Constructor_InvalidFractalIssuer() external {
    vm.expectRevert("Airdrop: invalid fractal issuer");
    new MerkleTreeKYCAirdrop(
      merkleRoot,
      address(0),
      address(token),
      treasury,
      endTimestamp
    );
  }

  function test_Constructor_InvalidToken() external {
    vm.expectRevert("Airdrop: invalid token");
    new MerkleTreeKYCAirdrop(
      merkleRoot,
      fractalIssuer,
      address(0),
      treasury,
      endTimestamp
    );
  }

  function test_Constructor_InvalidTreasury() external {
    vm.expectRevert("Airdrop: invalid treasury");
    new MerkleTreeKYCAirdrop(
      merkleRoot,
      fractalIssuer,
      address(token),
      payable(address(0)),
      endTimestamp
    );
  }

  function test_Constructor_InvalidEndTimestamp() external {
    vm.expectRevert("Airdrop: invalid end timestamp");
    new MerkleTreeKYCAirdrop(
      merkleRoot,
      fractalIssuer,
      address(token),
      treasury,
      block.timestamp
    );
  }
}
