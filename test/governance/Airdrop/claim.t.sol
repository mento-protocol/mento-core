// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { ECDSA } from "openzeppelin-contracts-next/contracts/utils/cryptography/ECDSA.sol";
import { ILocking } from "locking-contracts/ILocking.sol";

import { Airdrop_Test } from "./Base.t.sol";

contract Claim_Airdrop_Test is Airdrop_Test {
  event TokensClaimed(address indexed claimer, uint256 indexed amount, uint32 cliff, uint32 slope);

  bytes32[] public invalidMerkleProof = new bytes32[](0);
  uint256 fractalIssuerPk;
  uint256 otherIssuerPk;

  /// @notice Subject params:
  address public account = claimer0;
  uint256 public amount = claimer0Amount;
  bytes32[] public merkleProof;
  uint8 public kycType = 1;
  uint8 public countryOfIDIssuance = 2;
  uint8 public countryOfResidence = 2;
  bytes32 rootHash = keccak256("ROOTHASH");
  bytes public issuerSignature;
  uint32 public slope;
  uint32 public cliff;

  function setUp() public override {
    super.setUp();
    merkleProof = claimer0Proof; // gets set during setup

    (fractalIssuer, fractalIssuerPk) = makeAddrAndKey("FractalIssuer");
    (,otherIssuerPk) = makeAddrAndKey("OtherIssuer");

    initAirdrop();
  }

  function subject() internal returns (uint256) {
    return airdrop.claim(
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

  modifier whenAirdropEnded() {
    vm.warp(endTimestamp + 1);
    _;
  }

  modifier whenClaimer(address claimer) {
    account = claimer;
    _;
  }

  modifier whenAmount(uint256 _amount) {
    amount = _amount;
    _;
  }

  modifier whenMerkleProof(bytes32[] memory _merkleProof) {
    merkleProof = _merkleProof;
    _;
  }

  modifier whenKycTypeInvalid() {
    kycType = 2;
    _;
  }

  modifier whenKycCountryInvalid() {
    countryOfResidence = 7;
    _;
  }

  modifier whenKycSignatureValid() {
    issuerSignature = validKycSignature(fractalIssuerPk);
    _;
  }

  modifier whenKycSignatureInvalid() {
    issuerSignature = abi.encodePacked(uint8(2), keccak256("random"), keccak256("random"));
    _;
  }

  modifier whenKycSignerInvalid() {
    issuerSignature = validKycSignature(otherIssuerPk);
    _;
  }

  modifier whenLockingFor(uint32 cliff_, uint32 slope_) {
    cliff = cliff_;
    slope = slope_;
    _;
  }

  modifier whenTokenBalance(uint256 amount_) {
    deal(tokenAddress, address(airdrop), amount_);
    _;
  }

  /// @notice After the airdrop ends, it reverts
  function test_Claim_afterAirdrop() 
    whenAirdropEnded 
    external
  {
    vm.expectRevert("Airdrop: finished");
    subject();
  }

  /// @notice When the claimer is not in the tree, it reverts
  function test_Claim_invalidClaimer() 
    whenClaimer(invalidClaimer)
    external
  {
    vm.expectRevert("Airdrop: not in tree");
    subject();
  }

  /// @notice When the amount is not the right one for the claimer, it reverts
  function test_Claim_invalidClaimAmount() 
    whenAmount(123124124)
    external
  {
    vm.expectRevert("Airdrop: not in tree");
    subject();
  }

  /// @notice When the submitted proof is invalid, it reverts
  function test_Claim_invalidProof() 
    whenMerkleProof(invalidMerkleProof)
    external
  {
    vm.expectRevert("Airdrop: not in tree");
    subject();
  }

  /// @notice When the KYC signature is invalid
  function test_Claim_whenInvalidKYCSignature() 
    whenKycSignatureInvalid
    external
  {
    vm.expectRevert("ECDSA: invalid signature");
    subject();
  }

  /// @notice When the KYC signature belongs to the wrong signer
  function test_Claim_whenInvalidKYCSigner() 
    whenKycSignerInvalid
    external
  {
    vm.expectRevert("Airdrop: invalid kyc signer");
    subject();
  }

  /// @notice When the KYC is the wrong type
  function test_Claim_whenInvalidKycType() 
    whenKycTypeInvalid()
    whenKycSignatureValid()
    external
  {
    vm.expectRevert("Airdrop: invalid kyc params");
    subject();
  }

  /// @notice When the KYC Country Tier is not supported
  function test_Claim_whenInvalidKycCountry() 
    whenKycCountryInvalid()
    whenKycSignatureValid()
    external
  {
    vm.expectRevert("Airdrop: invalid kyc params");
    subject();
  }

  /// @notice When the airdrop contract has insufficient token balance
  function test_Claim_whenInsufficientBalance() 
    whenKycSignatureValid()
    whenTokenBalance(1e18)
    external
  {
    vm.expectRevert("Airdrop: insufficient balance");
    subject();
  }

  /// @notice When the claimer has already claimed
  function test_Claim_whenAlreadyClaimed()
    whenKycSignatureValid()
    whenTokenBalance(1e30)
    whenLockingFor(0, 0)
    external
  {
    subject();
    vm.expectRevert("Airdrop: already claimed");
    subject();
  }
    

  /// @notice When the claimer doesn't lock at all, they instantly get
  /// 20% of their allocation transfered.
  function test_Claim_withoutLocking() 
    whenKycSignatureValid()
    whenTokenBalance(1e30)
    whenLockingFor(0, 0)
    external
  {
    uint256 expectedUnlockedAmount = claimer0Amount * 20 / 100;
    vm.expectEmit(true, true, true, true);
    emit TokensClaimed(claimer0, expectedUnlockedAmount, 0 ,0);
    uint256 unlockedAmount = subject();
    assertEq(unlockedAmount, expectedUnlockedAmount);
    assertEq(token.balanceOf(claimer0), unlockedAmount);
  }

  /// @notice When the claimer locks for the full period, they get 100%
  /// of their allocation locked.
  function test_Claim_withFullLocking() 
    whenKycSignatureValid()
    whenTokenBalance(1e30)
    whenLockingFor(14, 14)
    external
  {
    vm.mockCall(
      lockingContract, 
      abi.encodeWithSelector(
        ILocking(lockingContract).lock.selector,
        claimer0, // account
        address(0), // delegate
        uint96(claimer0Amount), // amount to lock
        slope,  
        cliff
      ),
      abi.encode(0)
    );

    vm.expectEmit(true, true, true, true);
    emit TokensClaimed(claimer0, claimer0Amount, 14, 14);
    uint256 unlockedAmount = subject();
    assertEq(unlockedAmount, claimer0Amount);
  }

  /// @notice When the claimer locks for partial period, they get 60%
  /// of their allocation locked.
  function test_Claim_withPartialLocking() 
    whenKycSignatureValid()
    whenTokenBalance(1e30)
    whenLockingFor(7, 7)
    external
  {
    uint256 expectedUnlockedAmount = claimer0Amount * 60 / 100;
    vm.mockCall(
      lockingContract, 
      abi.encodeWithSelector(
        ILocking(lockingContract).lock.selector,
        claimer0, // account
        address(0), // delegate
        uint96(expectedUnlockedAmount), // amount to lock
        slope,
        cliff
      ),
      abi.encode(0)
    );

    vm.expectEmit(true, true, true, true);
    emit TokensClaimed(claimer0, expectedUnlockedAmount, 7, 7);
    uint256 unlockedAmount = subject();
    assertEq(unlockedAmount, expectedUnlockedAmount);
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
