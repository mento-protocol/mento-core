// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { ECDSA } from "openzeppelin-contracts-next/contracts/utils/cryptography/ECDSA.sol";
import { ILocking } from "locking-contracts/ILocking.sol";

import { Airgrab_Test } from "./Base.t.sol";
import { console } from "forge-std-next/console.sol";

contract Claim_Airgrab_Test is Airgrab_Test {
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

  /// @notice Test subject `claim`
  function subject() internal returns (uint256) {
    return
      airgrab.claim(
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
    (, otherIssuerPk) = makeAddrAndKey("OtherIssuer");

    initAirgrab();

    vm.mockCall(lockingContract, abi.encodeWithSelector(ILocking(lockingContract).lock.selector), abi.encode(0));
  }

  /// @notice Sets the issuer signature and gives enough balance to the airgrab
  modifier whenValidClaim() {
    issuerSignature = validKycSignature(fractalIssuerPk);
    deal(tokenAddress, address(airgrab), 1000e18);
    _;
  }

  /// @notice After the airgrab ends, it reverts
  function test_Claim_afterAirgrab() external {
    vm.warp(endTimestamp + 1);
    vm.expectRevert("Airgrab: finished");
    subject();
  }

  /// @notice When the claimer is not in the tree, it reverts
  function test_Claim_invalidClaimer() external {
    account = invalidClaimer;
    vm.expectRevert("Airgrab: not in tree");
    subject();
  }

  /// @notice When the amount is not the right one for the claimer, it reverts
  function test_Claim_invalidClaimAmount() external {
    amount = 123124124;
    vm.expectRevert("Airgrab: not in tree");
    subject();
  }

  /// @notice When the submitted proof is invalid, it reverts
  function test_Claim_invalidProof() external {
    merkleProof = invalidMerkleProof;
    vm.expectRevert("Airgrab: not in tree");
    subject();
  }

  /// @notice When the KYC signature is invalid
  function test_Claim_whenInvalidKYCSignature() external {
    issuerSignature = abi.encodePacked(uint8(2), keccak256("random"), keccak256("random"));
    vm.expectRevert("ECDSA: invalid signature");
    subject();
  }

  /// @notice When the KYC signature belongs to the wrong signer
  function test_Claim_whenInvalidKYCSigner() external {
    issuerSignature = validKycSignature(otherIssuerPk);
    vm.expectRevert("Airgrab: invalid kyc signer");
    subject();
  }

  /// @notice When the KYC is the wrong type
  function test_Claim_whenInvalidKycType() external {
    kycType = 2;
    issuerSignature = validKycSignature(fractalIssuerPk);
    vm.expectRevert("Airgrab: invalid kyc params");
    subject();
  }

  /// @notice When the KYC Country Tier is not supported
  function test_Claim_whenInvalidKycCountry() external {
    countryOfResidence = 7;
    issuerSignature = validKycSignature(fractalIssuerPk);
    vm.expectRevert("Airgrab: invalid kyc params");
    subject();
  }

  /// @notice When the airgrab contract has insufficient token balance
  function test_Claim_whenInsufficientBalance() external {
    issuerSignature = validKycSignature(fractalIssuerPk);
    deal(tokenAddress, address(airgrab), 1e18);
    vm.expectRevert("Airgrab: insufficient balance");
    subject();
  }

  /// @notice When the claimer has already claimed
  function test_Claim_whenAlreadyClaimed() external whenValidClaim {
    subject();
    vm.expectRevert("Airgrab: already claimed");
    subject();
  }

  /// @notice When the claimer locks for full cliff and full slope
  /// they get 100% of their allocation locked.
  function test_Claim_withLockingFullCliffAndFullSlope() external whenValidClaim {
    cliff = 14;
    slope = 14;
    expectClaimAndLock(claimer0Amount); // 100%
  }

  /// @notice When the claimer locks for full cliff and partial slope
  /// they get 75% of their allocation locked.
  function test_Claim_withLockingFullCliffAndHalfSlope() external whenValidClaim {
    cliff = 14;
    slope = 7;
    expectClaimAndLock((claimer0Amount * 80) / 100);
  }

  /// @notice When the claimer locks for full cliff and no slope
  /// they get 50% of their allocation locked.
  function test_Claim_withLockingFullCliffAndNoSlope() external whenValidClaim {
    cliff = 14;
    slope = 0;
    expectClaimAndLock((claimer0Amount * 60) / 100);
  }

  /// @notice When the claimer locks for half cliff and full slope
  /// they get 85% of their allocation locked.
  function test_Claim_withLockingHalfCliffAndFullSlope() external whenValidClaim {
    cliff = 7;
    slope = 14;
    expectClaimAndLock((claimer0Amount * 85) / 100);
  }

  /// @notice When the claimer locks for half the cliff and half the slope,
  /// they get 60% of their allocation locked.
  function test_Claim_withLockingHalfCliffAndHalfSlope() external whenValidClaim {
    cliff = 7;
    slope = 7;
    expectClaimAndLock((claimer0Amount * 65) / 100);
  }

  /// @notice When the claimer locks for full cliff and no slope
  /// they get 35% of their allocation locked.
  function test_Claim_withLockingHalfCliffAndNoSlope() external whenValidClaim {
    cliff = 7;
    slope = 0;
    expectClaimAndLock((claimer0Amount * 45) / 100);
  }

  /// @notice When the claimer locks for full cliff and full slope
  /// they get 70% of their allocation locked.
  function test_Claim_withLockingNoCliffAndFullSlope() external whenValidClaim {
    cliff = 0;
    slope = 14;
    expectClaimAndLock((claimer0Amount * 70) / 100);
  }

  /// @notice When the claimer locks for full cliff and partial slope
  /// they get 45% of their allocation locked.
  function test_Claim_withLockingNoCliffAndHalfSlope() external whenValidClaim {
    cliff = 0;
    slope = 7;
    expectClaimAndLock((claimer0Amount * 50) / 100); 
  }

  /// @notice When the claimer doesn't lock, they instantly get
  /// 20% of their allocation transfered.
  function test_Claim_withoutLocking() external whenValidClaim {
    uint256 expectedUnlockedAmount = (claimer0Amount * 20) / 100;
    vm.expectEmit(true, true, true, true);
    emit TokensClaimed(claimer0, expectedUnlockedAmount, 0, 0);
    uint256 unlockedAmount = subject();
    assertEq(unlockedAmount, expectedUnlockedAmount);
    assertEq(token.balanceOf(claimer0), expectedUnlockedAmount);
  }

  /// @notice Fuzz test for arbitrary locks, ensures that the
  /// unlocked amount is always between 20%-100% of what's allocated
  function test_Claim_fuzzLockDuration(uint32 slope_, uint32 cliff_) external whenValidClaim {
    vm.assume(slope_ <= MAX_SLOPE_PERIOD);
    vm.assume(cliff_ <= MAX_CLIFF_PERIOD);
    slope = slope_;
    cliff = cliff_;
    uint256 unlockedAmount = subject();
    require(unlockedAmount <= amount);
    require(unlockedAmount >= (amount * 20) / 100);
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
    return abi.encodePacked(r, s, v);
  }
}
