// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { ECDSA } from "openzeppelin-contracts-next/contracts/utils/cryptography/ECDSA.sol";
import { ILocking } from "locking-contracts/ILocking.sol";

import { Airgrab_Base_Test, ERC20 } from "./Base.t.sol";

contract Airgrab_Test is Airgrab_Base_Test {
  // ========================================
  // Airgrab.constructor
  // ========================================
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  /// @notice Subject of the section: Airgrab constructor
  function c_subject() internal {
    newAirgrab();
  }

  /// @notice Check that all parameters are set correctly during initialization
  /// and that ownership is transferred to the caller.
  function test_Constructor() external {
    vm.expectEmit(true, true, true, true);
    emit OwnershipTransferred(address(0), address(this));
    c_subject();

    assertEq(airgrab.root(), merkleRoot);
    assertEq(airgrab.fractalIssuer(), fractalIssuer);
    assertEq(address(airgrab.token()), address(0));
    assertEq(address(airgrab.owner()), address(this));
    assertEq(address(airgrab.lockingContract()), address(lockingContract));
    assertEq(airgrab.treasury(), treasury);
    assertEq(airgrab.endTimestamp(), endTimestamp);
    assertEq(airgrab.basePercentage(), basePercentage);
    assertEq(airgrab.cliffPercentage(), cliffPercentage);
    assertEq(airgrab.requiredCliffPeriod(), requiredCliffPeriod);
    assertEq(airgrab.slopePercentage(), slopePercentage);
    assertEq(airgrab.requiredSlopePeriod(), requiredSlopePeriod);
  }

  /// @notice Checks the merke root
  function test_Constructor_InvalidMerkleRoot() external {
    merkleRoot = bytes32(0);
    vm.expectRevert("Airgrab: invalid root");
    c_subject();
  }

  /// @notice Checks the fractal issuer address
  function test_Constructor_InvalidFractalIssuer() external {
    fractalIssuer = address(0);
    vm.expectRevert("Airgrab: invalid fractal issuer");
    c_subject();
  }

  /// @notice Checks th treasury address
  function test_Constructor_InvalidTreasury() external {
    treasury = payable(address(0));
    vm.expectRevert("Airgrab: invalid treasury");
    c_subject();
  }

  /// @notice Checks the airgrab end time
  function test_Constructor_InvalidEndTimestamp() external {
    endTimestamp = block.timestamp;
    vm.expectRevert("Airgrab: invalid end timestamp");
    c_subject();
  }

  /// @notice Ensures base + cliff + slope percentages add up to 1
  function test_Constructor_InvalidTotalPercentage() external {
    basePercentage = 0;
    vm.expectRevert("Airgrab: unlock percentages must add up to 1");
    c_subject();
  }

  /// @notice Checks the cliff period based on MAX_CLIF_PERIOD
  function test_Constructor_InvalidCliffPeriod() external {
    requiredCliffPeriod = MAX_CLIFF_PERIOD + 1;
    vm.expectRevert("Airgrab: required cliff period too large");
    c_subject();
  }

  /// @notice Checks the slope period based on MAX_SLOPE_PERIOD
  function test_Constructor_InvalidSlopePeriod() external {
    requiredSlopePeriod = MAX_SLOPE_PERIOD + 1;
    vm.expectRevert("Airgrab: required slope period too large");
    c_subject();
  }

  // ========================================
  // Airgrab.initialize
  // ========================================
  event Approval(address indexed owner, address indexed spender, uint256 value);

  /// @notice Test subject `initialize`
  function i_subject() internal {
    airgrab.initialize(tokenAddress);
  }

  modifier i_setUp() {
    newAirgrab();
    _;
  }

  /// @notice Checks the token address
  function test_Initialize_InvalidToken() i_setUp external {
    tokenAddress = address(0);
    vm.expectRevert("Airgrab: invalid token");
    i_subject();
  }

  /// @notice Renounces ownership and sets token
  function test_Initialize_TransfersOwnershipAndSetsToken() i_setUp external {
    vm.expectEmit(true, true, true, true);
    emit Approval(address(airgrab), lockingContract, type(uint256).max);
    vm.expectEmit(true, true, true, true);
    emit OwnershipTransferred(address(this), address(0));
    i_subject();
    assertEq(address(airgrab.token()), tokenAddress);
    assertEq(airgrab.owner(), address(0));
  }

  /// @notice Reverts if called two times, because ownership is renounced
  function test_Initialize_OnlyCallableOnce() i_setUp external {
    i_subject();
    vm.expectRevert("Ownable: caller is not the owner");
    i_subject();
  }

  /// @notice Reverts if not the owner
  function test_Initialize_OnlyCallableByOwner() i_setUp external {
    vm.prank(address(1));
    vm.expectRevert("Ownable: caller is not the owner");
    i_subject();
  }

  // ========================================
  // Airgrab.hasClaim
  // ========================================
  /// @notice Test subject parameters
  struct HasClaimParams {
    address account;
    uint256 amount;
    bytes32[] merkleProof;
  }
  HasClaimParams params;

  /// @notice Test subject `hasClaim`
  function hc_subject() internal view returns (bool) {
    return airgrab.hasClaim(
      params.account, 
      params.amount, 
      params.merkleProof
    );
  }

  /// @notice setup for hasClaim tests
  modifier hc_setUp() {
    initAirgrab();

    params.account = claimer0;
    params.amount = claimer0Amount;
    params.merkleProof = claimer0Proof;
    _;
  }

  /// @notice With default params, returns true
  function test_HasClaim_Valid() hc_setUp external {
    assertEq(hc_subject(), true);
  }

  /// @notice With an invalidClaimer, returns false
  function test_HasClaim_InvalidAccount() hc_setUp external {
    params.account = invalidClaimer;
    assertEq(hc_subject(), false);
  }

  /// @notice With an invalide amount, returns false
  function test_HasClaim_InvalidAmount() hc_setUp external {
    params.amount = 2 * claimer0Amount;
    assertEq(hc_subject(), false);
  }

  /// @notice With an invalid proof, returns false
  function test_HasClaim_InvalidProof() hc_setUp external {
    params.merkleProof = new bytes32[](0);
    assertEq(hc_subject(), false);
  }

  // ========================================
  // Airgrab.drain
  // ========================================
  event TokensDrained(address indexed token, uint256 amount);

  /// @notice Test subject parameters
  struct DrainParams{
    address token;
    function() subject;

  }
  DrainParams d_params;

  /// @notice Test subject `drain`
  function d_subject() internal {
    airgrab.drain(d_params.token);
  }

  /// @notice setup for drain tests
  modifier d_setUp() {
    initAirgrab();
    d_params.token = tokenAddress;
    _;
  }

  /// @notice Reverts if airgrab hasn't ended
  function test_Drain_beforeAirgrabEnds() d_setUp public {
    vm.expectRevert("Airgrab: not finished");
    d_subject();
  }

  /// @notice Reverts if the airgrab contract doesn't have balance
  function test_Drain_afterAirgrabEndsWhenNoBalance() d_setUp public {
    vm.warp(airgrab.endTimestamp() + 1);
    vm.expectRevert("Airgrab: nothing to drain");
    d_subject();
  }

  /// @notice Drains all tokens to the treasury if the airgrab has ended
  function test_Drain_afterAirgrabEndsWithSomeBalance() d_setUp public {
    vm.warp(airgrab.endTimestamp() + 1);
    deal(tokenAddress, address(airgrab), 100e18);
    vm.expectEmit(true, true, true, true);
    emit TokensDrained(tokenAddress, 100e18);
    d_subject();
    assertEq(token.balanceOf(treasury), 100e18);
    assertEq(token.balanceOf(address(airgrab)), 0);
  }

  /// @notice Drains all arbitrary tokens to the treasury if the airgrab has ended
  function test_Drain_afterAirgrabEndsWithSomeOtherTokenBalance() d_setUp public {
    ERC20 otherToken = new ERC20("Other Token", "OTT");
    d_params.token = address(otherToken);

    vm.warp(airgrab.endTimestamp() + 1);
    deal(address(otherToken), address(airgrab), 100e18);
    vm.expectEmit(true, true, true, true);
    emit TokensDrained(address(otherToken), 100e18);
    d_subject();
    assertEq(otherToken.balanceOf(treasury), 100e18);
    assertEq(otherToken.balanceOf(address(airgrab)), 0);
  }

  // ========================================
  // Airgrab.isValidKyc
  // ========================================

  /// @notice When kycType = 1 and countryOfResidence != 7, returns true
  function test_IsValidKyc_whenValid() public {
    initAirgrab();
    assertEq(airgrab.isValidKyc(1, 2), true);
  }

  /// @notice When kycType != 1, returns false
  function test_IsValidKyc_whenKycTypeInvalid() public {
    initAirgrab();
    assertEq(airgrab.isValidKyc(2, 2), false);
  }

  /// @notice When country of residence is invalid, returns false
  function test_IsValidKyc_whenCountryOfResidenceIsInvalid() public {
    initAirgrab();
    assertEq(airgrab.isValidKyc(1, 7), false);
    assertEq(airgrab.isValidKyc(1, 9), false);
    assertEq(airgrab.isValidKyc(1, 0), false);
  }

  // ========================================
  // Airgrab.isValidKycSignature
  // ========================================

  /// @notice Test helper parameters
  uint256 fractalIssuerPk;
  uint256 otherIssuerPk;

  /// @notice Test subject parameters
  struct IsValidKycSignatureParams {
    address account;
    uint8 kycType;
    uint8 countryOfIDIssuance;
    uint8 countryOfResidence;
    bytes32 rootHash;
    bytes issuerSignature;
  }
  IsValidKycSignatureParams ivks_params;

  /// @notice Test subject `isValidKycSignature`
  function ivks_subject() internal view returns (bool) {
    return airgrab.isValidKycSignature(
      ivks_params.account, 
      ivks_params.kycType, 
      ivks_params.countryOfIDIssuance, 
      ivks_params.countryOfResidence, 
      ivks_params.rootHash, 
      ivks_params.issuerSignature
    );
  }

  /// @notice setup for isValidKycSignature tests
  modifier ivks_setUp() {
    initAirgrab();

    (fractalIssuer, fractalIssuerPk) = makeAddrAndKey("FractalIssuer");
    (, otherIssuerPk) = makeAddrAndKey("OtherIssuer");

    ivks_params.account = claimer0;
    ivks_params.kycType = 1;
    ivks_params.countryOfIDIssuance = 2;
    ivks_params.countryOfResidence = 2;
    ivks_params.rootHash = keccak256("ROOTHASH");

    _;
  }

  /// @notice When the signature is malformed
  function test_IsValidKycSignature_whenMalformed() ivks_setUp public {
    ivks_params.issuerSignature = abi.encodePacked(uint8(2), keccak256("random"), keccak256("random"));
    vm.expectRevert("ECDSA: invalid signature");
    ivks_subject();
  }

  /// @notice When the signature is correct and from the expected issuer
  function test_IsValidKycSignature_whenValidAndCorrectIssuer() ivks_setUp public {
    ivks_params.issuerSignature = ivks_validKycSignature(fractalIssuerPk);
    assertEq(ivks_subject(), true);
  }

  /// @notice When the signature is correct but from an unexpected issuer
  function test_IsValidKycSignature_whenValidAndIncorrectIssuer() ivks_setUp public {
    ivks_params.issuerSignature = ivks_validKycSignature(otherIssuerPk);
    assertEq(ivks_subject(), false);
  }

  /// @notice build the KYC message hash and sign it with the provided pk
  /// @param signer The PK to sign the message with
  function ivks_validKycSignature(uint256 signer) internal view returns (bytes memory) {
    bytes32 signedMessageHash = ECDSA.toEthSignedMessageHash(
      keccak256(abi.encodePacked(
        ivks_params.account, 
        ivks_params.kycType, 
        ivks_params.countryOfIDIssuance, 
        ivks_params.countryOfResidence, 
        ivks_params.rootHash
      ))
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer, signedMessageHash);
    return abi.encodePacked(r, s, v);
  }

  // ========================================
  // Airgrab.claim
  // ========================================
  event TokensClaimed(address indexed claimer, uint256 indexed amount, uint32 slope, uint32 cliff);

  /// @notice Test subject parameters
  struct ClaimParams {
    address account;
    uint256 amount;
    bytes32[] merkleProof;
    uint8 kycType;
    uint8 countryOfIDIssuance;
    uint8 countryOfResidence;
    bytes32 rootHash;
    bytes issuerSignature;
    uint32 slope;
    uint32 cliff;
  }
  ClaimParams cl_params;

  /// @notice Test subject `claim`
  function cl_subject() internal returns (uint256) {
    return
      airgrab.claim(
        cl_params.account,
        cl_params.amount,
        cl_params.merkleProof,
        cl_params.kycType,
        cl_params.countryOfIDIssuance,
        cl_params.countryOfResidence,
        cl_params.rootHash,
        cl_params.issuerSignature,
        cl_params.slope,
        cl_params.cliff
      );
  }

  /// @notice setup for claim tests
  modifier cl_setUp()  {
    (fractalIssuer, fractalIssuerPk) = makeAddrAndKey("FractalIssuer");
    (, otherIssuerPk) = makeAddrAndKey("OtherIssuer");

    initAirgrab();

    vm.mockCall(lockingContract, abi.encodeWithSelector(ILocking(lockingContract).lock.selector), abi.encode(0));

    cl_params.account = claimer0;
    cl_params.amount = claimer0Amount;
    cl_params.merkleProof = claimer0Proof;
    cl_params.kycType = 1;
    cl_params.countryOfIDIssuance = 2;
    cl_params.countryOfResidence = 2;
    cl_params.rootHash = keccak256("ROOTHASH");
    cl_params.slope = 0;
    cl_params.cliff = 0;

    _;
  }

  /// @notice build the KYC message hash and sign it with the provided pk
  /// @param signer The PK to sign the message with
  function cl_validKycSignature(uint256 signer) internal view returns (bytes memory) {
    bytes32 signedMessageHash = ECDSA.toEthSignedMessageHash(
      keccak256(abi.encodePacked(
        cl_params.account, 
        cl_params.kycType, 
        cl_params.countryOfIDIssuance, 
        cl_params.countryOfResidence, 
        cl_params.rootHash
      ))
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer, signedMessageHash);
    return abi.encodePacked(r, s, v);
  }

  /// @notice Sets the issuer signature and gives enough balance to the airgrab
  modifier cl_whenValidClaim() {
    cl_params.issuerSignature = cl_validKycSignature(fractalIssuerPk);
    deal(tokenAddress, address(airgrab), 1000e18);
    _;
  }

  /// @notice After the airgrab ends, it reverts
  function test_Claim_afterAirgrab() cl_setUp external {
    vm.warp(endTimestamp + 1);
    vm.expectRevert("Airgrab: finished");
    cl_subject();
  }

  /// @notice When the claimer is not in the tree, it reverts
  function test_Claim_invalidClaimer() cl_setUp external {
    cl_params.account = invalidClaimer;
    vm.expectRevert("Airgrab: not in tree");
    cl_subject();
  }

  /// @notice When the amount is not the right one for the claimer, it reverts
  function test_Claim_invalidClaimAmount() cl_setUp external {
    cl_params.amount = 123124124;
    vm.expectRevert("Airgrab: not in tree");
    cl_subject();
  }

  /// @notice When the submitted proof is invalid, it reverts
  function test_Claim_invalidProof() cl_setUp external {
    cl_params.merkleProof = new bytes32[](0);
    vm.expectRevert("Airgrab: not in tree");
    cl_subject();
  }

  /// @notice When the KYC signature is invalid
  function test_Claim_whenInvalidKYCSignature() cl_setUp external {
    cl_params.issuerSignature = abi.encodePacked(uint8(2), keccak256("random"), keccak256("random"));
    vm.expectRevert("ECDSA: invalid signature");
    cl_subject();
  }

  /// @notice When the KYC signature belongs to the wrong signer
  function test_Claim_whenInvalidKYCSigner() cl_setUp external {
    cl_params.issuerSignature = cl_validKycSignature(otherIssuerPk);
    vm.expectRevert("Airgrab: invalid kyc signer");
    cl_subject();
  }

  /// @notice When the KYC is the wrong type
  function test_Claim_whenInvalidKycType() cl_setUp external {
    cl_params.kycType = 2;
    cl_params.issuerSignature = cl_validKycSignature(fractalIssuerPk);
    vm.expectRevert("Airgrab: invalid kyc params");
    cl_subject();
  }

  /// @notice When the KYC Country Tier is not supported
  function test_Claim_whenInvalidKycCountry() cl_setUp external {
    cl_params.countryOfResidence = 7;
    cl_params.issuerSignature = cl_validKycSignature(fractalIssuerPk);
    vm.expectRevert("Airgrab: invalid kyc params");
    cl_subject();
  }

  /// @notice When the airgrab contract has insufficient token balance
  function test_Claim_whenInsufficientBalance() cl_setUp external {
    cl_params.issuerSignature = cl_validKycSignature(fractalIssuerPk);
    deal(tokenAddress, address(airgrab), 1e18);
    vm.expectRevert("Airgrab: insufficient balance");
    cl_subject();
  }

  /// @notice When the claimer has already claimed
  function test_Claim_whenAlreadyClaimed() external cl_setUp cl_whenValidClaim {
    cl_subject();
    vm.expectRevert("Airgrab: already claimed");
    cl_subject();
  }

  /// @notice When the claimer locks for full cliff and full slope
  /// they get 100% of their allocation locked.
  function test_Claim_withLockingFullCliffAndFullSlope() external cl_setUp cl_whenValidClaim {
    cl_params.cliff = 14;
    cl_params.slope = 14;
    expectClaimAndLock(cl_params.amount); // 100%
  }

  /// @notice When the claimer locks for full cliff and partial slope
  /// they get 75% of their allocation locked.
  function test_Claim_withLockingFullCliffAndHalfSlope() external cl_setUp cl_whenValidClaim {
    cl_params.cliff = 14;
    cl_params.slope = 7;
    uint256 expected = (claimer0Amount * 80) / 100;
    expectClaimAndLock(expected);
  }

  /// @notice When the claimer locks for full cliff and no slope
  /// they get 50% of their allocation locked.
  function test_Claim_withLockingFullCliffAndNoSlope() external cl_setUp cl_whenValidClaim {
    cl_params.cliff = 14;
    cl_params.slope = 0;
    uint256 expected = (cl_params.amount * 60) / 100;
    expectClaimAndLock(expected);
  }

  /// @notice When the claimer locks for half cliff and full slope
  /// they get 85% of their allocation locked.
  function test_Claim_withLockingHalfCliffAndFullSlope() external cl_setUp cl_whenValidClaim {
    cl_params.cliff = 7;
    cl_params.slope = 14;
    uint256 expected = (cl_params.amount * 85) / 100;
    expectClaimAndLock(expected);
  }

  /// @notice When the claimer locks for half the cliff and half the slope,
  /// they get 60% of their allocation locked.
  function test_Claim_withLockingHalfCliffAndHalfSlope() external cl_setUp cl_whenValidClaim {
    cl_params.cliff = 7;
    cl_params.slope = 7;
    uint256 expected = (cl_params.amount * 65) / 100;
    expectClaimAndLock(expected);
  }

  /// @notice When the claimer locks for full cliff and no slope
  /// they get 35% of their allocation locked.
  function test_Claim_withLockingHalfCliffAndNoSlope() external cl_setUp cl_whenValidClaim {
    cl_params.cliff = 7;
    cl_params.slope = 0;
    uint256 expected = (cl_params.amount * 45) / 100;
    expectClaimAndLock(expected);
  }

  /// @notice When the claimer locks for full cliff and full slope
  /// they get 70% of their allocation locked.
  function test_Claim_withLockingNoCliffAndFullSlope() external cl_setUp cl_whenValidClaim {
    cl_params.cliff = 0;
    cl_params.slope = 14;
    uint256 expected = (cl_params.amount * 70) / 100;
    expectClaimAndLock(expected);
  }

  /// @notice When the claimer locks for full cliff and partial slope
  /// they get 45% of their allocation locked.
  function test_Claim_withLockingNoCliffAndHalfSlope() external cl_setUp cl_whenValidClaim {
    cl_params.cliff = 0;
    cl_params.slope = 7;
    uint256 expected = (cl_params.amount * 50) / 100;
    expectClaimAndLock(expected);
  }

  /// @notice When the claimer doesn't lock, they instantly get
  /// 20% of their allocation transfered.
  function test_Claim_withoutLocking() external cl_setUp cl_whenValidClaim {
    uint256 expectedUnlockedAmount = (cl_params.amount * 20) / 100;
    vm.expectEmit(true, true, true, true);
    emit TokensClaimed(cl_params.account, expectedUnlockedAmount, 0, 0);
    uint256 unlockedAmount = cl_subject();
    assertEq(unlockedAmount, expectedUnlockedAmount);
    assertEq(token.balanceOf(claimer0), expectedUnlockedAmount);
  }

  /// @notice Fuzz test for arbitrary locks, ensures that the
  /// unlocked amount is always between 20%-100% of what's allocated
  function test_Claim_fuzzLockDuration(uint32 slope_, uint32 cliff_) external cl_setUp cl_whenValidClaim {
    vm.assume(slope_ <= MAX_SLOPE_PERIOD);
    vm.assume(cliff_ <= MAX_CLIFF_PERIOD);
    cl_params.slope = slope_;
    cl_params.cliff = cliff_;
    uint256 unlockedAmount = cl_subject();
    require(unlockedAmount <= cl_params.amount);
    require(unlockedAmount >= (cl_params.amount * 20) / 100);
  }

  /// @notice Helper expectations for claiming and locking
  /// @param expectedUnlockedAmount The expected amount to be alocated based on cliff and slope
  function expectClaimAndLock(uint256 expectedUnlockedAmount) internal {
    vm.expectEmit(true, true, true, true);
    emit TokensClaimed(cl_params.account, expectedUnlockedAmount, cl_params.slope, cl_params.cliff);
    vm.expectCall(
      lockingContract,
      abi.encodeWithSelector(
        ILocking(lockingContract).lock.selector,
        cl_params.account,
        address(0), // delegate
        uint96(expectedUnlockedAmount),
        cl_params.slope,
        cl_params.cliff
      )
    );
    uint256 actualUnlockedAmount = cl_subject();
    assertEq(actualUnlockedAmount, expectedUnlockedAmount);
  }

  // ========================================
  // Airgrab.getUnlockedAmount
  // ========================================
  // @dev The main logic to calculate the unlocked amount
  // is tested in the getUnlockedPercentage tests.

  /// @notice When there's no required cliff and slope, returns the full amount
  function test_GetUnlockedAmount_whenNoLockRequired_Fuzz(
    uint256 amount,
    uint32 cliff,
    uint32 slope
  ) public {
    vm.assume(cliff <= MAX_CLIFF_PERIOD);
    vm.assume(slope <= MAX_SLOPE_PERIOD);

    requiredCliffPeriod = 0;
    requiredSlopePeriod = 0;
    initAirgrab();

    uint256 unlocked = airgrab.getUnlockedAmount(amount, slope, cliff);
    assertEq(unlocked, amount);
  }

  /// @notice When there's a required cliff and slope, uses the percentage to scale the amount
  function test_GetUnlockedAmount_whenLockRequired_Fuzz(
    uint256 amount,
    uint32 cliff,
    uint32 slope
  ) public {
    vm.assume(amount <= type(uint96).max);
    vm.assume(cliff <= MAX_CLIFF_PERIOD);
    vm.assume(slope <= MAX_SLOPE_PERIOD);

    requiredCliffPeriod = 14;
    requiredSlopePeriod = 14;
    initAirgrab();

    uint256 unlockedPercentage = airgrab.getUnlockedPercentage(slope, cliff);
    uint256 unlocked = airgrab.getUnlockedAmount(amount, slope, cliff);
    assertEq(unlocked, (amount * unlockedPercentage) / 1e18);
  }
}
