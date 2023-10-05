// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { console } from "forge-std-next/console.sol";
import { Test } from "forge-std-next/Test.sol";
import { Arrays } from "test/utils/Arrays.sol";

import { ECDSA } from "openzeppelin-contracts-next/contracts/utils/cryptography/ECDSA.sol";
import { ERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/ERC20.sol";
import { Strings } from "openzeppelin-contracts-next/contracts/utils/Strings.sol";
import { ILocking } from "locking-contracts/ILocking.sol";

import { Airgrab } from "contracts/governance/Airgrab.sol";

contract Airgrab_Test is Test {
  // ========================================
  // Test Setup
  // ========================================
  /**
   * A merkle tree was generated based on the following CSV file:
   * -----
   * 0x547a9687D36e51DA064eE7C6ac82590E344C4a0e,100000000000000000000
   * 0x6B70014D9c0BF1F53695a743Fe17996f132e9482,20000000000000000000000
   * ----
   * Merkle Root: 0x945d83ced94efc822fed712b4c4694b4e1129607ec5bbd2ab971bb08dca4d809
   * Proof[0x5..] = [ 0xf213211627972cf2d02a11f800ed3f60110c1d11d04ec1ea8cb1366611efdaa3 ]
   * Proof[0x6..] = [ 0x0294d3fc355e136dd6fea7f5c2934dd7cb67c2b4607110780e5fbb23d65d7ac4 ]
   */

  uint32 public constant MAX_CLIFF_PERIOD = 103;
  uint32 public constant MAX_SLOPE_PERIOD = 104;

  /// @notice see https://github.com/trustfractal/credentials-api-verifiers#setup
  string constant EXPECTED_CREDENTIAL = "level:plus;residency_not:ca,us";
  string constant OTHER_CREDENTIAL = "level:plus;residency_not:de";

  Airgrab public airgrab;
  ERC20 public token;

  address payable public treasury = payable(makeAddr("Treasury"));
  address public fractalSigner;
  uint256 public fractalSignerPk;
  uint256 public otherSignerPk;
  uint256 public fractalMaxAge = 15724800; // ~6 months
  address public lockingContract = makeAddr("LockingContract");
  address public tokenAddress;

  bytes32 public merkleRoot = 0x945d83ced94efc822fed712b4c4694b4e1129607ec5bbd2ab971bb08dca4d809;
  address public invalidClaimer = makeAddr("InvalidClaimer");
  address public claimer0 = 0x547a9687D36e51DA064eE7C6ac82590E344C4a0e;
  uint96 public claimer0Amount = 100000000000000000000;
  bytes32[] public claimer0Proof = Arrays.bytes32s(0xf213211627972cf2d02a11f800ed3f60110c1d11d04ec1ea8cb1366611efdaa3);
  address public claimer1 = 0x6B70014D9c0BF1F53695a743Fe17996f132e9482;
  uint96 public claimer1Amount = 20000000000000000000000;
  bytes32[] public claimer1Proof = Arrays.bytes32s(0x0294d3fc355e136dd6fea7f5c2934dd7cb67c2b4607110780e5fbb23d65d7ac4);

  uint256 public endTimestamp;

  uint32 cliffPeriod = 14; // 14 weeks ~= 3months
  uint32 slopePeriod = 14; // 14 weeks ~= 3months

  function setUp() public virtual {
    vm.warp(1695991948);
    endTimestamp = block.timestamp + 1 days;

    vm.label(claimer0, "Claimer0");
    vm.label(claimer1, "Claimer1");

    token = new ERC20("Mento Token", "MENTO");
    tokenAddress = address(token);

    vm.label(tokenAddress, "MENTO");

    (fractalSigner, fractalSignerPk) = makeAddrAndKey("FractalSigner");
    (, otherSignerPk) = makeAddrAndKey("OtherSigner");
  }

  /// @notice Create a new Airgrab, but don't initialize it.
  function newAirgrab() internal {
    airgrab = new Airgrab(
      merkleRoot,
      fractalSigner,
      fractalMaxAge,
      lockingContract,
      treasury,
      endTimestamp,
      cliffPeriod,
      slopePeriod
    );
  }

  /// @notice Create and initialize an Airgrab.
  function initAirgrab() internal {
    newAirgrab();
    airgrab.initialize(tokenAddress);
  }

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
    assertEq(airgrab.fractalSigner(), fractalSigner);
    assertEq(address(airgrab.token()), address(0));
    assertEq(address(airgrab.owner()), address(this));
    assertEq(address(airgrab.lockingContract()), address(lockingContract));
    assertEq(airgrab.treasury(), treasury);
    assertEq(airgrab.cliffPeriod(), cliffPeriod);
    assertEq(airgrab.slopePeriod(), slopePeriod);
  }

  /// @notice Checks the merke root
  function test_Constructor_InvalidMerkleRoot() external {
    merkleRoot = bytes32(0);
    vm.expectRevert("Airgrab: invalid root");
    c_subject();
  }

  /// @notice Checks the fractal issuer address
  function test_Constructor_InvalidFractalSigner() external {
    fractalSigner = address(0);
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

  /// @notice Checks the cliff period based on MAX_CLIF_PERIOD
  function test_Constructor_InvalidCliffPeriod() external {
    cliffPeriod = MAX_CLIFF_PERIOD + 1;
    vm.expectRevert("Airgrab: cliff period too large");
    c_subject();
  }

  /// @notice Checks the slope period based on MAX_SLOPE_PERIOD
  function test_Constructor_InvalidSlopePeriod() external {
    slopePeriod = MAX_SLOPE_PERIOD + 1;
    vm.expectRevert("Airgrab: slope period too large");
    c_subject();
  }

  // ========================================
  // Airgrab.initialize
  // ========================================
  event Approval(address indexed owner, address indexed spender, uint256 value);

  /// @notice setup for initialize tests
  modifier i_setUp() {
    newAirgrab();
    _;
  }

  /// @notice Test subject `initialize`
  function i_subject() internal {
    airgrab.initialize(tokenAddress);
  }

  /// @notice Checks the token address
  function test_Initialize_InvalidToken() external i_setUp {
    tokenAddress = address(0);
    vm.expectRevert("Airgrab: invalid token");
    i_subject();
  }

  /// @notice Renounces ownership and sets token
  function test_Initialize_TransfersOwnershipAndSetsToken() external i_setUp {
    vm.expectEmit(true, true, true, true);
    emit Approval(address(airgrab), lockingContract, type(uint256).max);
    vm.expectEmit(true, true, true, true);
    emit OwnershipTransferred(address(this), address(0));
    i_subject();
    assertEq(address(airgrab.token()), tokenAddress);
    assertEq(airgrab.owner(), address(0));
  }

  /// @notice Reverts if called two times, because ownership is renounced
  function test_Initialize_OnlyCallableOnce() external i_setUp {
    i_subject();
    vm.expectRevert("Ownable: caller is not the owner");
    i_subject();
  }

  /// @notice Reverts if not the owner
  function test_Initialize_OnlyCallableByOwner() external i_setUp {
    vm.prank(address(1));
    vm.expectRevert("Ownable: caller is not the owner");
    i_subject();
  }

  // ========================================
  // Airgrab.drain
  // ========================================
  event TokensDrained(address indexed token, uint256 amount);

  /// @notice setup for drain tests
  modifier d_setUp() {
    initAirgrab();
    _;
  }

  /// @notice Reverts if airgrab hasn't ended
  function test_Drain_beforeAirgrabEnds() public d_setUp {
    vm.expectRevert("Airgrab: not finished");
    airgrab.drain(tokenAddress);
  }

  /// @notice Reverts if the airgrab contract doesn't have balance
  function test_Drain_afterAirgrabEndsWhenNoBalance() public d_setUp {
    vm.warp(airgrab.endTimestamp() + 1);
    vm.expectRevert("Airgrab: nothing to drain");
    airgrab.drain(tokenAddress);
  }

  /// @notice Drains all tokens to the treasury if the airgrab has ended
  function test_Drain_afterAirgrabEndsWithSomeBalance() public d_setUp {
    vm.warp(airgrab.endTimestamp() + 1);
    deal(tokenAddress, address(airgrab), 100e18);
    vm.expectEmit(true, true, true, true);
    emit TokensDrained(tokenAddress, 100e18);
    airgrab.drain(tokenAddress);
    assertEq(token.balanceOf(treasury), 100e18);
    assertEq(token.balanceOf(address(airgrab)), 0);
  }

  /// @notice Drains all arbitrary tokens to the treasury if the airgrab has ended
  function test_Drain_afterAirgrabEndsWithSomeOtherTokenBalance() public d_setUp {
    ERC20 otherToken = new ERC20("Other Token", "OTT");

    vm.warp(airgrab.endTimestamp() + 1);
    deal(address(otherToken), address(airgrab), 100e18);
    vm.expectEmit(true, true, true, true);

    emit TokensDrained(address(otherToken), 100e18);
    airgrab.drain(address(otherToken));

    assertEq(otherToken.balanceOf(treasury), 100e18);
    assertEq(otherToken.balanceOf(address(airgrab)), 0);
  }

  // ========================================
  // Airgrab.claim
  // ========================================
  event TokensClaimed(address indexed claimer, uint256 amount, uint256 votingPower);

  /// @notice Test subject parameters
  struct ClaimParams {
    address account;
    uint96 amount;
    bytes32[] merkleProof;
    bytes fractalProof;
    uint256 fractalProofValidUntil;
    uint256 fractalProofApprovedAt;
    string fractalId;
  }
  ClaimParams cl_params;

  /// @notice Test subject `claim`
  function cl_subject() internal {
    airgrab.claim(
      cl_params.account,
      cl_params.amount,
      cl_params.merkleProof,
      cl_params.fractalProof,
      cl_params.fractalProofValidUntil,
      cl_params.fractalProofApprovedAt,
      cl_params.fractalId
    );
  }

  /// @notice setup for claim tests
  modifier cl_setUp() {
    initAirgrab();

    cl_params.account = claimer0;
    cl_params.amount = claimer0Amount;
    cl_params.merkleProof = claimer0Proof;
    cl_params.fractalProof = abi.encodePacked("");
    cl_params.fractalProofValidUntil = block.timestamp + 2 days;
    cl_params.fractalProofApprovedAt = block.timestamp - 1 minutes;
    cl_params.fractalId = "fractalId";

    _;
  }

  /// @notice sets a valid fractal proof in the claim params
  modifier validKyc() {
    cl_params.fractalProof = validKycSignature(fractalSignerPk, cl_params.account, EXPECTED_CREDENTIAL);
    _;
  }

  /// @notice gives token to the Airgrab contract
  modifier hasBalance() {
    deal(tokenAddress, address(airgrab), 1000e18);
    _;
  }

  /// @notice build the KYC message hash and sign it with the provided pk
  /// @param signer The PK to sign the message with
  /// @param account The account to sign the message for
  function validKycSignature(
    uint256 signer,
    address account,
    string memory credential
  ) internal view returns (bytes memory) {
    bytes32 signedMessageHash = ECDSA.toEthSignedMessageHash(
      abi.encodePacked(
        Strings.toHexString(uint256(uint160(account)), 20),
        ";",
        cl_params.fractalId,
        ";",
        Strings.toString(cl_params.fractalProofApprovedAt),
        ";",
        Strings.toString(cl_params.fractalProofValidUntil),
        ";",
        credential
      )
    );

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer, signedMessageHash);
    return abi.encodePacked(r, s, v);
  }

  // ========================================
  // Airgrab.claim {hasValidKyc}
  // ========================================

  /// @notice When the KYC has expired, it reverts
  function test_Claim_hasValidKyc_whenNotLongerValid() public cl_setUp {
    cl_params.fractalProofValidUntil = block.timestamp - 100;
    vm.expectRevert("Airgrab: KYC no longer valid");
    cl_subject();
  }

  /// @notice when the KYC is not recent enough, it reverts
  function test_Claim_hasValidKyc_whenNotRecentEnough() public cl_setUp {
    cl_params.fractalProofApprovedAt = block.timestamp - fractalMaxAge - 1;
    vm.expectRevert("Airgrab: KYC not recent enough");
    cl_subject();
  }

  /// @notice when the KYC signature is not valid, it reverts
  function test_Claim_hasValidKyc_whenInvalidSignature() public cl_setUp {
    cl_params.fractalProof = abi.encodePacked(uint8(2), keccak256("random"), keccak256("random"));
    vm.expectRevert("Airgrab: Invalid KYC");
    cl_subject();
  }

  /// @notice when the KYC signed by the wrong signer, it reverts
  function test_Claim_hasValidKyc_whenWrongSigner() public cl_setUp {
    cl_params.fractalProof = validKycSignature(otherSignerPk, cl_params.account, EXPECTED_CREDENTIAL);
    vm.expectRevert("Airgrab: Invalid KYC");
    cl_subject();
  }

  /// @notice when the KYC credential is not the right one
  function test_Claim_hasValidKyc_whenWrongCredential() public cl_setUp {
    cl_params.fractalProof = validKycSignature(otherSignerPk, cl_params.account, OTHER_CREDENTIAL);
    vm.expectRevert("Airgrab: Invalid KYC");
    cl_subject();
  }

  // ========================================
  // Airgrab.claim {canClaim}
  // ========================================

  /// @notice when airgrab finished, it reverts
  function test_Claim_canClaim_whenAirgrabFinished() public cl_setUp validKyc {
    vm.warp(endTimestamp + 1);
    vm.expectRevert("Airgrab: finished");
    cl_subject();
  }

  /// @notice when not in tree, it reverts
  function test_Claim_canClaim_whenNotInTree() public cl_setUp {
    cl_params.fractalProof = validKycSignature(fractalSignerPk, invalidClaimer, EXPECTED_CREDENTIAL);
    cl_params.account = invalidClaimer;
    vm.expectRevert("Airgrab: not in tree");
    cl_subject();
  }

  /// @notice When the amount is not the right one for the claimer, it reverts
  function test_Claim_canClaim_invalidClaimAmount() external cl_setUp validKyc {
    cl_params.amount = 123124124;
    vm.expectRevert("Airgrab: not in tree");
    cl_subject();
  }

  /// @notice When the submitted proof is invalid, it reverts
  function test_Claim_canClaim_invalidProof() external cl_setUp validKyc {
    cl_params.merkleProof = new bytes32[](0);
    vm.expectRevert("Airgrab: not in tree");
    cl_subject();
  }

  /// @notice when already claimed
  function test_Claim_canClaim_whenAlreadyClaimed() public cl_setUp validKyc hasBalance {
    cl_subject();
    vm.expectRevert("Airgrab: already claimed");
    cl_subject();
  }

  // ========================================
  // Airgrab.claim {claim}
  // ========================================

  /// @notice when the claimer has not enough balance
  function test_Claim_whenNotEnoughBalance() public cl_setUp validKyc {
    vm.expectRevert("Airgrab: insufficient balance");
    cl_subject();
  }

  /// @notice happy path
  function test_Claim_locksTokens() public cl_setUp validKyc hasBalance {
    vm.mockCall(
      lockingContract,
      abi.encodeWithSelector(ILocking(lockingContract).lock.selector),
      abi.encode(cl_params.amount * 2)
    );

    vm.expectEmit(true, true, true, true);
    emit TokensClaimed(cl_params.account, cl_params.amount, cl_params.amount * 2);

    vm.expectCall(
      lockingContract,
      abi.encodeWithSelector(
        ILocking(lockingContract).lock.selector,
        cl_params.account,
        address(0), // delegate
        cl_params.amount,
        slopePeriod,
        cliffPeriod
      )
    );

    cl_subject();
  }
}
