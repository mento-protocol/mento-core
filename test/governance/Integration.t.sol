pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase

import { TestSetup } from "./TestSetup.sol";

import { Factory } from "contracts/governance/Factory.sol";
import { MentoToken } from "contracts/governance/MentoToken.sol";
import { Emission } from "contracts/governance/Emission.sol";
import { Airgrab } from "contracts/governance/Airgrab.sol";
import { Locking } from "contracts/governance/locking/Locking.sol";
import { TimelockController } from "contracts/governance/TimelockController.sol";
import { MentoGovernor } from "contracts/governance/MentoGovernor.sol";
import { Arrays } from "test/utils/Arrays.sol";

import { ECDSA } from "openzeppelin-contracts-next/contracts/utils/cryptography/ECDSA.sol";
import { Strings } from "openzeppelin-contracts-next/contracts/utils/Strings.sol";

contract GovernanceIntegrationTest is TestSetup {
  Factory public factory;

  MentoToken public mentoToken;
  Emission public emission;
  Airgrab public airgrab;
  TimelockController public timelockController;
  MentoGovernor public mentoGovernor;
  Locking public locking;

  address public celoGovernance = makeAddr("CeloGovernance");
  address public communityMultisig = makeAddr("CommunityMultisig");
  address public vestingContract = makeAddr("VestingContract");
  address public mentoMultisig = makeAddr("MentoMultisig");
  address public treasuryContract = makeAddr("TreasuryContract");

  address public fractalSigner;
  uint256 public fractalSignerPk;

  bytes32 public merkleRoot = 0x945d83ced94efc822fed712b4c4694b4e1129607ec5bbd2ab971bb08dca4d809;
  address public invalidClaimer = makeAddr("InvalidClaimer");
  address public claimer0 = 0x547a9687D36e51DA064eE7C6ac82590E344C4a0e;
  uint96 public claimer0Amount = 100e18;
  bytes32[] public claimer0Proof = Arrays.bytes32s(0xf213211627972cf2d02a11f800ed3f60110c1d11d04ec1ea8cb1366611efdaa3);
  address public claimer1 = 0x6B70014D9c0BF1F53695a743Fe17996f132e9482;
  uint96 public claimer1Amount = 20_000e18;
  bytes32[] public claimer1Proof = Arrays.bytes32s(0x0294d3fc355e136dd6fea7f5c2934dd7cb67c2b4607110780e5fbb23d65d7ac4);

  string public constant EXPECTED_CREDENTIAL = "level:plus;residency_not:ca,us";

  function setUp() public {
    vm.roll(21871402); // (Oct-11-2023 WED 12:00:01 PM +UTC)
    vm.warp(1697025601); // (Oct-11-2023 WED 12:00:01 PM +UTC)

    vm.label(claimer0, "Claimer0");
    vm.label(claimer1, "Claimer1");

    (fractalSigner, fractalSignerPk) = makeAddrAndKey("FractalSigner");

    vm.prank(owner);
    factory = new Factory(celoGovernance);

    vm.prank(celoGovernance);
    factory.createGovernance(
      vestingContract,
      mentoMultisig,
      treasuryContract,
      communityMultisig,
      merkleRoot,
      fractalSigner
    );
    mentoToken = factory.mentoToken();
    emission = factory.emission();
    airgrab = factory.airgrab();
    timelockController = factory.timelockController();
    mentoGovernor = factory.mentoGovernor();
    locking = factory.locking();

    vm.prank(alice);
    mentoToken.approve(address(locking), type(uint256).max);
    vm.prank(bob);
    mentoToken.approve(address(locking), type(uint256).max);
    vm.prank(charlie);
    mentoToken.approve(address(locking), type(uint256).max);
  }

  // Factory + All
  function test_factory_shouldCreateAndSetupContracts() public {
    assertEq(mentoToken.balanceOf(address(vestingContract)), 80_000_000 * 10**18);
    assertEq(mentoToken.balanceOf(address(mentoMultisig)), 120_000_000 * 10**18);
    assertEq(mentoToken.balanceOf(address(airgrab)), 50_000_000 * 10**18);
    assertEq(mentoToken.balanceOf(address(treasuryContract)), 100_000_000 * 10**18);
    assertEq(mentoToken.emissionSupply(), 650_000_000 * 10**18);
    assertEq(mentoToken.emissionContract(), address(emission));

    assertEq(emission.emissionStartTime(), block.timestamp);
    assertEq(address(emission.mentoToken()), address(mentoToken));
    assertEq(emission.emissionTarget(), address(treasuryContract));
    assertEq(emission.owner(), address(timelockController));

    assertEq(airgrab.root(), merkleRoot);
    assertEq(airgrab.fractalSigner(), fractalSigner);
    assertEq(airgrab.fractalMaxAge(), 180 days);
    assertEq(airgrab.endTimestamp(), block.timestamp + 365 days);
    assertEq(airgrab.slopePeriod(), 104);
    assertEq(airgrab.cliffPeriod(), 0);
    assertEq(address(airgrab.token()), address(mentoToken));
    assertEq(address(airgrab.lockingContract()), address(locking));
    assertEq(address(airgrab.treasury()), address(treasuryContract));

    bytes32 proposerRole = timelockController.PROPOSER_ROLE();
    bytes32 executorRole = timelockController.EXECUTOR_ROLE();
    bytes32 cancellerRole = timelockController.CANCELLER_ROLE();

    assertEq(timelockController.getMinDelay(), 2 days);
    assert(timelockController.hasRole(proposerRole, address(mentoGovernor)));
    assert(timelockController.hasRole(executorRole, (address(0))));
    assert(timelockController.hasRole(cancellerRole, address(mentoGovernor)));
    assert(timelockController.hasRole(cancellerRole, communityMultisig));

    assertEq(address(mentoGovernor.token()), address(locking));
    assertEq(mentoGovernor.votingDelay(), 1);
    assertEq(mentoGovernor.votingPeriod(), BLOCKS_WEEK);
    assertEq(mentoGovernor.proposalThreshold(), 1_000e18);
    assertEq(mentoGovernor.quorumNumerator(), 2);
    assertEq(mentoGovernor.timelock(), address(timelockController));

    assertEq(address(locking.token()), address(mentoToken));
    assertEq(locking.startingPointWeek(), 179);
    assertEq(locking.minCliffPeriod(), 0);
    assertEq(locking.minSlopePeriod(), 1);
    assertEq(locking.owner(), address(timelockController));
    assertEq(locking.getWeek(), 1);
  }

  // MentoToken + Locking
  function test_locking_whenLocked_shouldMintveMentoInExchangeForMentoAndReleaseBySchedule() public {
    // Since we use the min slope period of 1, calculations are slightly off as expected
    uint256 negligibleAmount = 3e18;
    vm.prank(treasuryContract);
    mentoToken.transfer(alice, 1000e18);

    vm.prank(treasuryContract);
    mentoToken.transfer(bob, 1000e18);
    // Alice locks for ~6 months
    vm.prank(alice);
    locking.lock(alice, alice, 1000e18, 26, 0);

    // Bob locks for ~1 year
    vm.prank(bob);
    uint256 lockId = locking.lock(bob, bob, 1000e18, 52, 0);

    // Difference between voting powers accounted correctly
    assertApproxEqAbs(locking.balanceOf(alice), 300e18, negligibleAmount);
    assertApproxEqAbs(locking.balanceOf(bob), 400e18, negligibleAmount);

    timeTravel(13 * BLOCKS_WEEK);

    // Alice withdraws after ~3 months
    vm.prank(alice);
    locking.withdraw();

    // Half of the tokens should be released, half of the voting power should be revoked
    assertApproxEqAbs(locking.balanceOf(alice), 150e18, negligibleAmount);
    assertApproxEqAbs(mentoToken.balanceOf(alice), 500e18, negligibleAmount);

    // Bob's voting power is 3/4 of the initial voting power
    assertApproxEqAbs(locking.balanceOf(bob), 300e18, negligibleAmount);
    assertEq(mentoToken.balanceOf(bob), 0);

    timeTravel(13 * BLOCKS_WEEK);

    // Bob relocks and delegates to alice
    vm.prank(bob);
    lockId = locking.relock(lockId, alice, 1000e18, 26, 0);

    // Alice has the voting power from Bob's lock
    assertApproxEqAbs(locking.balanceOf(alice), 300e18, negligibleAmount);
    assertEq(locking.balanceOf(bob), 0);

    timeTravel(13 * BLOCKS_WEEK);

    // Bob delegates the lock without relocking
    vm.prank(bob);
    locking.delegateTo(lockId, charlie);

    assertEq(locking.balanceOf(alice), 0);
    assertEq(locking.balanceOf(bob), 0);
    assertApproxEqAbs(locking.balanceOf(charlie), 150e18, negligibleAmount);

    // End of the locking period
    timeTravel(13 * BLOCKS_WEEK);

    vm.prank(bob);
    locking.withdraw();

    assertEq(locking.balanceOf(alice), 0);
    assertEq(locking.balanceOf(bob), 0);
    assertEq(locking.balanceOf(charlie), 0);
  }

  // MentoToken + Locking + Governor
  function test_governor_whenUsedByLockedAccounts_shouldUpdateSettings() public {
    vm.prank(treasuryContract);
    mentoToken.transfer(alice, 10_000e18);

    vm.prank(treasuryContract);
    mentoToken.transfer(bob, 10_000e18);
    // Alice locks for max cliff
    vm.prank(alice);
    locking.lock(alice, alice, 2000e18, 1, 103);

    // Bob locks a small amount for max cliff
    vm.prank(bob);
    locking.lock(bob, bob, 1500e18, 1, 103);

    timeTravel(BLOCKS_DAY);

    uint256 newVotingDelay = BLOCKS_DAY;
    uint256 newVotingPeriod = 2 * BLOCKS_WEEK;
    uint256 newThreshold = 5000e18;
    uint256 newQuorum = 10; //10%
    uint256 newMinDelay = 3 days;

    vm.prank(alice);
    (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    ) = proposeChangeGovernorSettings(newVotingDelay, newVotingPeriod, newThreshold, newQuorum, newMinDelay);

    // ~10 mins
    timeTravel(120);

    // both users cast vote, majority in favor
    vm.prank(alice);
    mentoGovernor.castVote(proposalId, 1);

    vm.prank(bob);
    mentoGovernor.castVote(proposalId, 0);

    // voting period ends
    timeTravel(BLOCKS_WEEK);

    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));

    // timelock ends
    timeTravel(2 * BLOCKS_DAY);

    // anyone can execute the proposal
    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));

    // settings are updated
    assertEq(mentoGovernor.votingDelay(), newVotingDelay);
    assertEq(mentoGovernor.votingPeriod(), newVotingPeriod);
    assertEq(mentoGovernor.proposalThreshold(), newThreshold);
    assertEq(mentoGovernor.quorumNumerator(), newQuorum);
    assertEq(timelockController.getMinDelay(), newMinDelay);

    // Proposal reverts because new threshold is higher
    vm.prank(alice);
    vm.expectRevert("Governor: proposer votes below proposal threshold");
    proposeChangeGovernorSettings(newVotingDelay, newVotingPeriod, newThreshold, newQuorum, newMinDelay);
  }

  // MentoToken + Airgrab + Locking + Governor + Timelock
  function test_airgrab_whenClaimedByUser_shouldBeLocked_canBeUsedInGovernance() public {
    uint256 validUntil = block.timestamp + 60 days;
    uint256 approvedAt = block.timestamp - 10 days;

    bytes memory fractalProof = validKycSignature(
      fractalSignerPk,
      claimer0,
      EXPECTED_CREDENTIAL,
      validUntil,
      approvedAt
    );

    bytes memory fractalProof1 = validKycSignature(
      fractalSignerPk,
      claimer1,
      EXPECTED_CREDENTIAL,
      validUntil,
      approvedAt
    );

    vm.prank(claimer0);
    airgrab.claim(claimer0Amount, claimer0, claimer0Proof, fractalProof, validUntil, approvedAt, "fractalId");

    vm.prank(claimer1);
    airgrab.claim(claimer1Amount, claimer1, claimer1Proof, fractalProof1, validUntil, approvedAt, "fractalId");

    // claimed amounts are locked automatically
    assertEq(locking.balanceOf(claimer0), 60e18);
    assertEq(locking.balanceOf(claimer1), 12_000e18);

    timeTravel(BLOCKS_DAY);

    address newEmissionTarget = makeAddr("NewEmissionTarget");

    // claimer0 is under threshold
    vm.expectRevert("Governor: proposer votes below proposal threshold");
    vm.prank(claimer0);
    (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    ) = proposeChangeEmissionTarget(newEmissionTarget);

    // claimer 1 can propose
    vm.prank(claimer1);
    (proposalId, targets, values, calldatas, description) = proposeChangeEmissionTarget(newEmissionTarget);

    // ~10 mins
    timeTravel(120);

    // both claimers cast vote
    vm.prank(claimer0);
    mentoGovernor.castVote(proposalId, 0);

    // majority of the votes are in favor
    vm.prank(claimer1);
    mentoGovernor.castVote(proposalId, 1);

    vm.expectRevert("Governor: proposal not successful");
    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));

    // voting period ends
    timeTravel(BLOCKS_WEEK);

    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));

    // timelock blocks for the lock delay
    vm.expectRevert("TimelockController: operation is not ready");
    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));

    timeTravel(2 * BLOCKS_DAY);

    assertEq(emission.emissionTarget(), address(treasuryContract));

    // anyone can execute the proposal
    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));

    // protected function is called by the owner after execution
    assertEq(emission.emissionTarget(), newEmissionTarget);
  }

  // MentoToken + Emission + Locking + Governance + Timelock
  function test_emission_whenEmitted_shouldBeSentToTreasury_canBeUsedInGovernanceAfterLocking() public {
    assertEq(mentoToken.balanceOf(treasuryContract), 100_000_000e18);

    // emit tokens after a year
    timeTravel(365 * BLOCKS_DAY);
    uint256 amount = emission.emitTokens();

    assertEq(mentoToken.balanceOf(treasuryContract), amount + 100_000_000e18);

    // treasury distrubutes tokens to users
    vm.prank(treasuryContract);
    mentoToken.transfer(alice, 5000e18);

    vm.prank(treasuryContract);
    mentoToken.transfer(bob, 5000e18);

    vm.prank(treasuryContract);
    mentoToken.transfer(charlie, 5000e18);

    // users locks= tokens
    vm.prank(alice);
    locking.lock(alice, alice, 5000e18, 20, 10);

    vm.prank(bob);
    locking.lock(bob, bob, 5000e18, 40, 10);

    vm.prank(charlie);
    locking.lock(charlie, charlie, 5000e18, 30, 10);

    timeTravel(1);

    address newEmissionTarget = makeAddr("NewEmissionTarget");

    // alice proposes to change the emission target
    vm.prank(alice);
    (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    ) = proposeChangeEmissionTarget(newEmissionTarget);

    // ~10 mins
    timeTravel(120);

    // majority votes in favor of the proposal
    vm.prank(alice);
    mentoGovernor.castVote(proposalId, 1);

    vm.prank(bob);
    mentoGovernor.castVote(proposalId, 1);

    vm.prank(charlie);
    mentoGovernor.castVote(proposalId, 0);

    timeTravel(BLOCKS_WEEK);

    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));

    // still time locked
    timeTravel(BLOCKS_DAY);

    bytes32 timelockId = timelockController.hashOperationBatch(
      targets,
      values,
      calldatas,
      0,
      keccak256(bytes(description))
    );

    // multi sig cancels the proposal in the time lock
    vm.prank(communityMultisig);
    timelockController.cancel(timelockId);

    // timelock delay is over
    timeTravel(BLOCKS_DAY);

    // proposal can not be executed
    vm.expectRevert("Governor: proposal not successful");
    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));
  }

  /// @notice build the KYC message hash and sign it with the provided pk
  /// @param signer The PK to sign the message with
  /// @param account The account to sign the message for
  function validKycSignature(
    uint256 signer,
    address account,
    string memory credential,
    uint256 validUntil,
    uint256 approvedAt
  ) internal view returns (bytes memory) {
    bytes32 signedMessageHash = ECDSA.toEthSignedMessageHash(
      abi.encodePacked(
        Strings.toHexString(uint256(uint160(account)), 20),
        ";",
        "fractalId",
        ";",
        Strings.toString(approvedAt),
        ";",
        Strings.toString(validUntil),
        ";",
        credential
      )
    );

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer, signedMessageHash);
    return abi.encodePacked(r, s, v);
  }

  function proposeChangeEmissionTarget(address newTarget)
    internal
    returns (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    )
  {
    targets = new address[](1);
    targets[0] = address(emission);

    values = new uint256[](1);
    values[0] = 0;

    calldatas = new bytes[](1);
    calldatas[0] = abi.encodeWithSelector(emission.setEmissionTarget.selector, newTarget);

    description = "Change emission target";

    proposalId = mentoGovernor.propose(targets, values, calldatas, description);
  }

  function proposeChangeGovernorSettings(
    uint256 votingDelay,
    uint256 votingPeriod,
    uint256 threshold,
    uint256 quorum,
    uint256 minDelay
  )
    internal
    returns (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    )
  {
    targets = new address[](5);
    targets[0] = address(mentoGovernor);
    targets[1] = address(mentoGovernor);
    targets[2] = address(mentoGovernor);
    targets[3] = address(mentoGovernor);
    targets[4] = address(timelockController);

    values = new uint256[](5);
    values[0] = 0;
    values[1] = 0;
    values[2] = 0;
    values[3] = 0;
    values[4] = 0;

    calldatas = new bytes[](5);
    calldatas[0] = abi.encodeWithSelector(mentoGovernor.setVotingDelay.selector, votingDelay);
    calldatas[1] = abi.encodeWithSelector(mentoGovernor.setVotingPeriod.selector, votingPeriod);
    calldatas[2] = abi.encodeWithSelector(mentoGovernor.setProposalThreshold.selector, threshold);
    calldatas[3] = abi.encodeWithSelector(mentoGovernor.updateQuorumNumerator.selector, quorum);
    calldatas[4] = abi.encodeWithSelector(timelockController.updateDelay.selector, minDelay);

    description = "Change governance config";

    proposalId = mentoGovernor.propose(targets, values, calldatas, description);
  }

  function timeTravel(uint256 blocks) internal {
    uint256 time = blocks * 5;
    vm.roll(block.number + blocks);
    skip(time);
  }
}
