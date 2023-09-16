// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { ECDSA } from "openzeppelin-contracts-next/contracts/utils/cryptography/ECDSA.sol";
import { ILocking } from "locking-contracts/ILocking.sol";

import { Airdrop_Test } from "./Base.t.sol";
import { console } from "forge-std-next/console.sol";

contract Claim_Airdrop_Test is Airdrop_Test {
  event TokensClaimed(address indexed claimer, uint256 indexed amount, uint32 slope, uint32 cliff);

  bytes32[] public invalidMerkleProof = new bytes32[](0);
  uint256 fractalIssuerPk;
  uint256 otherIssuerPk;

  /// @notice Test subject parameters
  address public account = claimer0;
  uint256 public amount = claimer0Amount;
  bytes32[] public merkleProof = claimer0Proof;
  uint8 public kycType = 1;
  uint8 public countryOfIDIssuance = 2;
  uint8 public countryOfResidence = 2;
  bytes32 rootHash = keccak256("ROOTHASH");
  bytes public issuerSignature;
  uint32 public slope;
  uint32 public cliff;
  /// ----------------------------------

  /// @notice Test subject `claim`
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

  function setUp() public override {
    super.setUp();

    (fractalIssuer, fractalIssuerPk) = makeAddrAndKey("FractalIssuer");
    (,otherIssuerPk) = makeAddrAndKey("OtherIssuer");

    initAirdrop();

    vm.mockCall(
      lockingContract, 
      abi.encodeWithSelector(
        ILocking(lockingContract).lock.selector
      ),
      abi.encode(0)
    );
  }

  /// @notice Warp to after endTimestamp
  modifier whenAirdropEnded() {
    vm.warp(endTimestamp + 1);
    _;
  }

  /// @notice Sets the claimer
  modifier whenClaimer(address claimer) {
    account = claimer;
    _;
  }

  /// @notice Sets the claim amount
  modifier whenAmount(uint256 _amount) {
    amount = _amount;
    _;
  }

  /// @notice Sets the merkle proof for the claim
  modifier whenMerkleProof(bytes32[] memory _merkleProof) {
    merkleProof = _merkleProof;
    _;
  }

  /// @notice Sets an invalid KYC type
  modifier whenKycTypeInvalid() {
    kycType = 2;
    _;
  }

  /// @notice Sets an invalid country tier
  modifier whenKycCountryInvalid() {
    countryOfResidence = 7;
    _;
  }

  /// @notice Sets the issuerSignature correctly
  modifier whenKycSignatureValid() {
    issuerSignature = validKycSignature(fractalIssuerPk);
    _;
  }

  /// @notice Sets an invalid KYC issuer signature
  modifier whenKycSignatureInvalid() {
    issuerSignature = abi.encodePacked(uint8(2), keccak256("random"), keccak256("random"));
    _;
  }

  /// @notice Sets a valid issuer signature but by the wrong signer
  modifier whenKycSignerInvalid() {
    issuerSignature = validKycSignature(otherIssuerPk);
    _;
  }

  /// @notice Sets cliff and slope for the claim
  modifier whenLockingFor(uint32 cliff_, uint32 slope_) {
    cliff = cliff_;
    slope = slope_;
    _;
  }

  /// @notice Sets the airdrop contract's token balance.
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
    

  /// @notice When the claimer locks for full cliff and full slope 
  /// they get 100% of their allocation locked.
  function test_Claim_withLockingFullCliffAndFullSlope() 
    whenKycSignatureValid()
    whenTokenBalance(1e30)
    whenLockingFor(14, 14)
    external
  {
    expectClaimAndLock(claimer0Amount); // 100%
  }

  /// @notice When the claimer locks for full cliff and partial slope
  /// they get 75% of their allocation locked.
  function test_Claim_withLockingFullCliffAndHalfSlope() 
    whenKycSignatureValid()
    whenTokenBalance(1e30)
    whenLockingFor(14, 7)
    external
  {
    expectClaimAndLock(claimer0Amount * 75 / 100); // 75%
  }

  /// @notice When the claimer locks for full cliff and no slope
  /// they get 50% of their allocation locked.
  function test_Claim_withLockingFullCliffAndNoSlope()
    whenKycSignatureValid()
    whenTokenBalance(1e30)
    whenLockingFor(14, 0)
    external
  {
    expectClaimAndLock(claimer0Amount * 50 / 100); // 50%
  }
  
  /// @notice When the claimer locks for half cliff and full slope
  /// they get 85% of their allocation locked.
  function test_Claim_withLockingHalfCliffAndFullSlope() 
    whenKycSignatureValid()
    whenTokenBalance(1e30)
    whenLockingFor(7, 14)
    external
  {
    expectClaimAndLock(claimer0Amount * 85 / 100); // 85%
  }


  /// @notice When the claimer locks for half the cliff and half the slope, 
  /// they get 60% of their allocation locked.
  function test_Claim_withLockingHalfCliffAndHalfSlope() 
    whenKycSignatureValid()
    whenTokenBalance(1e30)
    whenLockingFor(7, 7)
    external
  {
    expectClaimAndLock(claimer0Amount * 6 / 10); // 60%
  }


  /// @notice When the claimer locks for full cliff and no slope
  /// they get 35% of their allocation locked.
  function test_Claim_withLockingHalfCliffAndNoSlope() 
    whenKycSignatureValid()
    whenTokenBalance(1e30)
    whenLockingFor(7, 0)
    external
  {
    expectClaimAndLock(claimer0Amount * 35 / 100); // 35%
  }

  /// @notice When the claimer locks for full cliff and full slope 
  /// they get 70% of their allocation locked.
  function test_Claim_withLockingNoCliffAndFullSlope() 
    whenKycSignatureValid()
    whenTokenBalance(1e30)
    whenLockingFor(0, 14)
    external
  {
    expectClaimAndLock(claimer0Amount * 70 / 100); // 70%
  }

  /// @notice When the claimer locks for full cliff and partial slope
  /// they get 45% of their allocation locked.
  function test_Claim_withLockingNoCliffAndHalfSlope() 
    whenKycSignatureValid()
    whenTokenBalance(1e30)
    whenLockingFor(0, 7)
    external
  {
    expectClaimAndLock(claimer0Amount * 45 / 100); // 45%
  }

  /// @notice When the claimer doesn't lock, they instantly get
  /// 20% of their allocation transfered.
  function test_Claim_withoutLocking() 
    whenKycSignatureValid()
    whenTokenBalance(1e30)
    whenLockingFor(0, 0)
    external
  {
    uint256 expectedUnlockedAmount = claimer0Amount * 20 / 100;
    vm.expectEmit(true, true, true, true);
    emit TokensClaimed(claimer0, expectedUnlockedAmount, 0, 0);
    uint256 unlockedAmount = subject();
    assertEq(unlockedAmount, expectedUnlockedAmount);
    assertEq(token.balanceOf(claimer0), expectedUnlockedAmount);
  }

  /// @notice Fuzz test for arbitrary locks, ensures that the
  /// unlocked amount is always between 20%-100% of what's allocated
  function test_Claim_fuzzLockDuration(uint32 slope_, uint32 cliff_)
    whenKycSignatureValid()
    whenTokenBalance(1e30)
    whenLockingFor(slope_, cliff_)
    external
  {
    vm.assume(slope_ <= MAX_SLOPE_PERIOD);
    vm.assume(cliff_ <= MAX_CLIFF_PERIOD);
    uint256 unlockedAmount = subject();
    require(unlockedAmount <= amount);
    require(unlockedAmount >= amount * 20/100);
  }

  /// @notice Helper expectations for claiming and locking
  /// @param expectedUnlockedAmount The expected amount to be alocated based on cliff and slope
  function expectClaimAndLock(uint256 expectedUnlockedAmount) internal {
    vm.expectEmit(true, true, true, true);
    emit TokensClaimed(account, expectedUnlockedAmount, slope, cliff);
    vm.expectCall(
      lockingContract, 
      abi.encodeWithSelector(
        ILocking(lockingContract).lock.selector,
        account,
        address(0), // delegate
        uint96(expectedUnlockedAmount),
        slope,
        cliff
      )
    );
    uint256 actualUnlockedAmount = subject();
    assertEq(actualUnlockedAmount, expectedUnlockedAmount);
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
