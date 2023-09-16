// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { ECDSA } from "openzeppelin-contracts-next/contracts/utils/cryptography/ECDSA.sol";
import { Airdrop_Test } from "./Base.t.sol";

contract IsValidKycSignature_Airdrop_Test is Airdrop_Test {
  uint256 fractalIssuerPk;
  uint256 otherIssuerPk;

  /// @notice Test subject parameters
  address account = claimer0;
  uint8 kycType = 1;
  uint8 countryOfIDIssuance = 2;
  uint8 countryOfResidence = 2;
  bytes32 rootHash = keccak256("ROOTHASH");
  bytes issuerSignature;
  /// ----------------------------------

  /// @notice Test subject `isValidKycSignature`
  function subject() internal view returns (bool) {
    return airdrop.isValidKycSignature(
      account,
      kycType,
      countryOfIDIssuance,
      countryOfResidence,
      rootHash,
      issuerSignature
    );
  }

  function setUp() public override {
    super.setUp();

    (fractalIssuer, fractalIssuerPk) = makeAddrAndKey("FractalIssuer");
    (,otherIssuerPk) = makeAddrAndKey("OtherIssuer");

    initAirdrop();
  }

  /// @notice When the signature is malformed
  function test_IsValidKycSignature_whenMalformed() public {
    issuerSignature = abi.encodePacked(uint8(2), keccak256("random"), keccak256("random"));
    vm.expectRevert("ECDSA: invalid signature");
    subject();
  }

  /// @notice When the signature is correct and from the expected issuer
  function test_IsValidKycSignature_whenValidAndCorrectIssuer() public {
    issuerSignature = validKycSignature(fractalIssuerPk);
    assertEq(subject(), true);
  }

  /// @notice When the signature is correct but from an unexpected issuer
  function test_IsValidKycSignature_whenValidAndIncorrectIssuer() public {
    issuerSignature = validKycSignature(otherIssuerPk);
    assertEq(subject(), false);
  }

  /// @notice build the KYC message hash and sign it with the provided pk
  /// @param signer The PK to sign the message with
  function validKycSignature(uint256 signer) internal view returns (bytes memory) {
    bytes32 signedMessageHash = ECDSA.toEthSignedMessageHash(
      keccak256(abi.encodePacked(account, kycType, countryOfIDIssuance, countryOfResidence, rootHash))
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer, signedMessageHash);
    return abi.encodePacked(r,s,v);
  }
}
