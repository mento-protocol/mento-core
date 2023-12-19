// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, max-line-length, max-states-count

import { TestSetup } from "../TestSetup.sol";
import { Vm } from "forge-std-next/Vm.sol";
import { VmExtension } from "test/utils/VmExtension.sol";

import { MentoGovernor } from "contracts/governance/MentoGovernor.sol";
import { GovernanceFactory } from "contracts/governance/GovernanceFactory.sol";
import { MentoToken } from "contracts/governance/MentoToken.sol";
import { Airgrab } from "contracts/governance/Airgrab.sol";
import { Emission } from "contracts/governance/Emission.sol";
import { Locking } from "contracts/governance/locking/Locking.sol";
import { TimelockController } from "contracts/governance/TimelockController.sol";

import { Proposals } from "./Proposals.sol";
import { Arrays } from "test/utils/Arrays.sol";
import { TestLocking } from "test/utils/TestLocking.sol";

import { ProxyAdmin } from "openzeppelin-contracts-next/contracts/proxy/transparent/ProxyAdmin.sol";
import { GnosisSafe } from "safe-contracts/contracts/GnosisSafe.sol";
import { GnosisSafeProxyFactory } from "safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import { Enum } from "safe-contracts/contracts/common/Enum.sol";

import { ITransparentUpgradeableProxy } from "openzeppelin-contracts-next/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract GovernanceIntegrationTest is TestSetup {
  using VmExtension for Vm;

  GovernanceFactory public factory;

  ProxyAdmin public proxyAdmin;
  MentoToken public mentoToken;
  Emission public emission;
  Airgrab public airgrab;
  TimelockController public governanceTimelock;
  address public governanceTimelockAddress;
  TimelockController public mentoLabsTreasury;
  MentoGovernor public mentoGovernor;
  Locking public locking;

  address public celoGovernance = makeAddr("CeloGovernance");
  address public celoCommunityFund = makeAddr("CeloCommunityFund");
  address public watchdogMultisig = makeAddr("WatchdogMultisig");

  GnosisSafe public safeSingleton;
  GnosisSafe public mentoLabsMultisig;
  GnosisSafeProxyFactory public safeFactory;
  address public mentoSigner0;
  uint256 public mentoPK0;
  address public mentoSigner1;
  uint256 public mentoPK1;
  address public mentoSigner2;
  uint256 public mentoPK2;

  address public fractalSigner;
  uint256 public fractalSignerPk;

  bytes32 public merkleRoot = 0x945d83ced94efc822fed712b4c4694b4e1129607ec5bbd2ab971bb08dca4d809;
  address public claimer0 = 0x547a9687D36e51DA064eE7C6ac82590E344C4a0e;
  uint96 public claimer0Amount = 100e18;
  bytes32[] public claimer0Proof = Arrays.bytes32s(0xf213211627972cf2d02a11f800ed3f60110c1d11d04ec1ea8cb1366611efdaa3);
  address public claimer1 = 0x6B70014D9c0BF1F53695a743Fe17996f132e9482;
  uint96 public claimer1Amount = 20_000e18;
  bytes32[] public claimer1Proof = Arrays.bytes32s(0x0294d3fc355e136dd6fea7f5c2934dd7cb67c2b4607110780e5fbb23d65d7ac4);

  string public constant EXPECTED_CREDENTIAL = "level:plus;residency_not:ca,us";

  modifier s_governance() {
    vm.prank(governanceTimelockAddress);
    mentoToken.transfer(alice, 10_000e18);

    vm.prank(governanceTimelockAddress);
    mentoToken.transfer(bob, 10_000e18);

    vm.prank(alice);
    locking.lock(alice, alice, 2000e18, 1, 103);

    vm.prank(bob);
    locking.lock(bob, bob, 1500e18, 1, 103);

    vm.timeTravel(BLOCKS_DAY);
    _;
  }

  function setUp() public {
    vm.roll(21871402); // (Oct-11-2023 WED 12:00:01 PM +UTC)
    vm.warp(1697025601); // (Oct-11-2023 WED 12:00:01 PM +UTC)

    vm.label(claimer0, "Claimer0");
    vm.label(claimer1, "Claimer1");

    (fractalSigner, fractalSignerPk) = makeAddrAndKey("FractalSigner");

    safeSingleton = new GnosisSafe();
    safeFactory = new GnosisSafeProxyFactory();
    // Signers for the mento labs gnosis safe
    (mentoSigner0, mentoPK0) = makeAddrAndKey("MentoSigner0");
    (mentoSigner1, mentoPK1) = makeAddrAndKey("MentoSigner1");
    (mentoSigner2, mentoPK2) = makeAddrAndKey("MentoSigner2");
    address[] memory owners = new address[](3);
    owners[0] = mentoSigner0;
    owners[1] = mentoSigner1;
    owners[2] = mentoSigner2;

    bytes memory mentoLabsMultisigInit = abi.encodeWithSelector(
      GnosisSafe.setup.selector,
      owners, ///     @param _owners List of Safe owners.
      2, ///          @param _threshold Number of required confirmations for a Safe transaction.
      address(0), /// @param to Contract address for optional delegate call.
      "", ///         @param data Data payload for optional delegate call.
      address(0), /// @param fallbackHandler Handler for fallback calls to this contract
      address(0), /// @param paymentToken Token that should be used for the payment (0 is ETH)
      0, ///          @param payment Value that should be paid
      address(0) ///  @param paymentReceiver Adddress that should receive the payment (or 0 if tx.origin)
    );

    uint256 mentoLabsMultisigSalt = uint256(keccak256(abi.encodePacked("mentoLabsMultisig")));

    mentoLabsMultisig = GnosisSafe(
      payable(
        address(safeFactory.createProxyWithNonce(address(safeSingleton), mentoLabsMultisigInit, mentoLabsMultisigSalt))
      )
    );

    vm.prank(owner);
    factory = new GovernanceFactory(celoGovernance);

    vm.prank(celoGovernance);
    factory.createGovernance(
      address(mentoLabsMultisig),
      watchdogMultisig,
      celoCommunityFund,
      merkleRoot,
      fractalSigner
    );
    proxyAdmin = factory.proxyAdmin();
    mentoToken = factory.mentoToken();
    emission = factory.emission();
    airgrab = factory.airgrab();
    governanceTimelock = factory.governanceTimelock();
    mentoGovernor = factory.mentoGovernor();
    locking = factory.locking();
    mentoLabsTreasury = factory.mentoLabsTreasuryTimelock();

    // Without this cast, tests do not work as expected
    // It causes a yul exception about memory safety
    governanceTimelockAddress = address(governanceTimelock);

    vm.prank(alice);
    mentoToken.approve(address(locking), type(uint256).max);
    vm.prank(bob);
    mentoToken.approve(address(locking), type(uint256).max);
    vm.prank(charlie);
    mentoToken.approve(address(locking), type(uint256).max);
  }

  function test_factory_shouldCreateAndSetupContracts() public {
    assertEq(mentoToken.balanceOf(address(mentoLabsMultisig)), 80_000_000 * 10**18);
    assertEq(mentoToken.balanceOf(address(mentoLabsTreasury)), 120_000_000 * 10**18);
    assertEq(mentoToken.balanceOf(address(airgrab)), 50_000_000 * 10**18);
    assertEq(mentoToken.balanceOf(governanceTimelockAddress), 100_000_000 * 10**18);
    assertEq(mentoToken.emissionSupply(), 650_000_000 * 10**18);
    assertEq(mentoToken.emission(), address(emission));
    assertEq(mentoToken.symbol(), "MENTO");
    assertEq(mentoToken.name(), "Mento Token");

    assertEq(emission.emissionStartTime(), block.timestamp);
    assertEq(address(emission.mentoToken()), address(mentoToken));
    assertEq(emission.emissionTarget(), address(governanceTimelockAddress));
    assertEq(emission.owner(), governanceTimelockAddress);

    assertEq(airgrab.root(), merkleRoot);
    assertEq(airgrab.fractalSigner(), fractalSigner);
    assertEq(airgrab.fractalMaxAge(), 180 days);
    assertEq(airgrab.endTimestamp(), block.timestamp + 365 days);
    assertEq(airgrab.slopePeriod(), 104);
    assertEq(airgrab.cliffPeriod(), 0);
    assertEq(address(airgrab.token()), address(mentoToken));
    assertEq(address(airgrab.locking()), address(locking));
    assertEq(address(airgrab.celoCommunityFund()), address(celoCommunityFund));

    bytes32 proposerRole = governanceTimelock.PROPOSER_ROLE();
    bytes32 executorRole = governanceTimelock.EXECUTOR_ROLE();
    bytes32 cancellerRole = governanceTimelock.CANCELLER_ROLE();

    assertEq(governanceTimelock.getMinDelay(), 2 days);
    assert(governanceTimelock.hasRole(proposerRole, address(mentoGovernor)));
    assert(governanceTimelock.hasRole(executorRole, (address(0))));
    assert(governanceTimelock.hasRole(cancellerRole, address(mentoGovernor)));
    assert(governanceTimelock.hasRole(cancellerRole, watchdogMultisig));

    assertEq(mentoLabsTreasury.getMinDelay(), 13 days);
    assert(mentoLabsTreasury.hasRole(proposerRole, address(mentoLabsMultisig)));
    assert(mentoLabsTreasury.hasRole(executorRole, address(0)));
    assert(mentoLabsTreasury.hasRole(cancellerRole, governanceTimelockAddress));

    assertEq(address(mentoGovernor.token()), address(locking));
    assertEq(mentoGovernor.votingDelay(), 0);
    assertEq(mentoGovernor.votingPeriod(), BLOCKS_WEEK);
    assertEq(mentoGovernor.proposalThreshold(), 1_000e18);
    assertEq(mentoGovernor.quorumNumerator(), 2);
    assertEq(mentoGovernor.timelock(), governanceTimelockAddress);

    assertEq(address(locking.token()), address(mentoToken));
    assertEq(locking.startingPointWeek(), 179);
    assertEq(locking.minCliffPeriod(), 0);
    assertEq(locking.minSlopePeriod(), 1);
    assertEq(locking.owner(), governanceTimelockAddress);
    assertEq(locking.getWeek(), 1);
    assertEq(locking.symbol(), "veMENTO");
    assertEq(locking.name(), "Mento Vote-Escrow");
  }

  function test_locking_whenLocked_shouldMintveMentoInExchangeForMentoAndReleaseBySchedule() public {
    // Since we use the min slope period of 1, calculations are slightly off as expected
    uint256 negligibleAmount = 3e18;

    vm.prank(governanceTimelockAddress);
    mentoToken.transfer(alice, 1000e18);

    vm.prank(governanceTimelockAddress);
    mentoToken.transfer(bob, 1000e18);
    // Alice locks for ~6 months
    vm.prank(alice);
    locking.lock(alice, alice, 1000e18, 26, 0);

    // Bob locks for ~1 year
    vm.prank(bob);
    uint256 bobsLockId = locking.lock(bob, bob, 1000e18, 52, 0);

    // Difference between voting powers accounted correctly
    assertApproxEqAbs(locking.getVotes(alice), 300e18, negligibleAmount);
    assertApproxEqAbs(locking.getVotes(bob), 400e18, negligibleAmount);

    vm.timeTravel(13 * BLOCKS_WEEK);

    // Alice withdraws after ~3 months
    vm.prank(alice);
    locking.withdraw();

    // Half of the tokens should be released, half of the voting power should be revoked
    assertApproxEqAbs(locking.getVotes(alice), 150e18, negligibleAmount);
    assertApproxEqAbs(mentoToken.balanceOf(alice), 500e18, negligibleAmount);

    // Bob's voting power is 3/4 of the initial voting power
    assertApproxEqAbs(locking.getVotes(bob), 300e18, negligibleAmount);
    assertEq(mentoToken.balanceOf(bob), 0);

    vm.timeTravel(13 * BLOCKS_WEEK);

    // Bob relocks and delegates to alice
    vm.prank(bob);
    bobsLockId = locking.relock(bobsLockId, alice, 1000e18, 26, 0);

    // Alice has the voting power from Bob's lock
    assertApproxEqAbs(locking.getVotes(alice), 300e18, negligibleAmount);
    assertEq(locking.getVotes(bob), 0);

    vm.timeTravel(13 * BLOCKS_WEEK);

    // Bob delegates the lock without relocking
    vm.prank(bob);
    locking.delegateTo(bobsLockId, charlie);

    assertEq(locking.getVotes(alice), 0);
    assertEq(locking.getVotes(bob), 0);
    assertApproxEqAbs(locking.getVotes(charlie), 150e18, negligibleAmount);

    // End of the locking period
    vm.timeTravel(13 * BLOCKS_WEEK);

    vm.prank(bob);
    locking.withdraw();

    assertEq(locking.getVotes(alice), 0);
    assertEq(locking.getVotes(bob), 0);
    assertEq(locking.getVotes(charlie), 0);
  }

  function test_governor_whenUsedByLockedAccounts_shouldUpdateSettings() public s_governance {
    uint256 newVotingDelay = BLOCKS_DAY;
    uint256 newVotingPeriod = 2 * BLOCKS_WEEK;
    uint256 newThreshold = 5000e18;
    uint256 newQuorum = 10; //10%
    uint256 newMinDelay = 3 days;
    uint32 newMinCliff = 6;
    uint32 newMinSlope = 12;

    vm.prank(alice);
    (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    ) = Proposals._proposeChangeSettings(
        mentoGovernor,
        governanceTimelock,
        locking,
        newVotingDelay,
        newVotingPeriod,
        newThreshold,
        newQuorum,
        newMinDelay,
        newMinCliff,
        newMinSlope
      );

    // ~10 mins
    vm.timeTravel(120);

    // both users cast vote, majority in favor (because alice has more votes than bob)
    vm.prank(alice);
    mentoGovernor.castVote(proposalId, 1);

    vm.prank(bob);
    mentoGovernor.castVote(proposalId, 0);

    // voting period ends
    vm.timeTravel(BLOCKS_WEEK);

    // proposal can now be queued
    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));

    // timelock ends
    vm.timeTravel(2 * BLOCKS_DAY);

    // anyone can execute the proposal
    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));

    // settings are updated
    assertEq(mentoGovernor.votingDelay(), newVotingDelay);
    assertEq(mentoGovernor.votingPeriod(), newVotingPeriod);
    assertEq(mentoGovernor.proposalThreshold(), newThreshold);
    assertEq(mentoGovernor.quorumNumerator(), newQuorum);
    assertEq(governanceTimelock.getMinDelay(), newMinDelay);
    assertEq(locking.minCliffPeriod(), newMinCliff);
    assertEq(locking.minSlopePeriod(), newMinSlope);

    // Proposal reverts because new threshold is higher
    vm.prank(alice);
    vm.expectRevert("Governor: proposer votes below proposal threshold");
    Proposals._proposeChangeSettings(
      mentoGovernor,
      governanceTimelock,
      locking,
      newVotingDelay,
      newVotingPeriod,
      newThreshold,
      newQuorum,
      newMinDelay,
      newMinCliff,
      newMinSlope
    );
    // Lock reverts because new min period is higher
    vm.prank(alice);
    vm.expectRevert("cliff period < minimal lock period");
    locking.lock(alice, alice, 2000e18, 5, 5);
  }

  function test_airgrab_whenClaimedByUser_shouldBeLocked_canBeUsedInGovernance() public {
    // kyc signature is valid
    uint256 validUntil = block.timestamp + 60 days;
    uint256 approvedAt = block.timestamp - 10 days;

    bytes memory fractalProof0 = vm.validKycSignature(
      fractalSignerPk,
      claimer0,
      EXPECTED_CREDENTIAL,
      validUntil,
      approvedAt
    );

    bytes memory fractalProof1 = vm.validKycSignature(
      fractalSignerPk,
      claimer1,
      EXPECTED_CREDENTIAL,
      validUntil,
      approvedAt
    );

    vm.prank(claimer0);
    airgrab.claim(claimer0Amount, claimer0, claimer0Proof, fractalProof0, validUntil, approvedAt, "fractalId");

    // claim with a delegate
    vm.prank(claimer1);
    airgrab.claim(claimer1Amount, alice, claimer1Proof, fractalProof1, validUntil, approvedAt, "fractalId");

    // claimed amounts are locked automatically
    assertEq(locking.getVotes(claimer0), 60e18);
    assertEq(locking.getVotes(claimer1), 0);
    assertEq(locking.getVotes(alice), 12_000e18);

    vm.timeTravel(BLOCKS_DAY);

    address newEmissionTarget = makeAddr("NewEmissionTarget");

    // claimer0 is under threshold
    vm.expectRevert("Governor: proposer votes below proposal threshold");
    vm.prank(claimer0);
    Proposals._proposeChangeEmissionTarget(mentoGovernor, emission, newEmissionTarget);

    // delegate of  claimer1 can propose
    vm.prank(alice);
    (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    ) = Proposals._proposeChangeEmissionTarget(mentoGovernor, emission, newEmissionTarget);

    // ~10 mins
    vm.timeTravel(120);

    // both claimers and delegate cast vote
    vm.prank(claimer0);
    mentoGovernor.castVote(proposalId, 0);

    // majority of the votes are in favor
    vm.prank(alice);
    mentoGovernor.castVote(proposalId, 1);

    // voting is still active, can not pre-queue
    vm.expectRevert("Governor: proposal not successful");
    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));

    // voting period ends
    vm.timeTravel(BLOCKS_WEEK);

    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));

    // timelock blocks for the lock delay
    vm.expectRevert("TimelockController: operation is not ready");
    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));

    vm.timeTravel(2 * BLOCKS_DAY);

    assertEq(emission.emissionTarget(), governanceTimelockAddress);

    // anyone can execute the proposal after the timelock
    vm.prank(makeAddr("Random"));
    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));

    // protected function is called by the owner after execution
    assertEq(emission.emissionTarget(), newEmissionTarget);
  }

  function test_watchdog_cancel_shouldCancelQueuedProposal() public {
    assertEq(mentoToken.balanceOf(governanceTimelockAddress), 100_000_000e18);

    // emit tokens after a year
    vm.timeTravel(365 * BLOCKS_DAY);
    uint256 amount = emission.emitTokens();

    assertEq(emission.totalEmittedAmount(), amount);
    assertEq(mentoToken.emittedAmount(), emission.totalEmittedAmount());

    assertEq(mentoToken.balanceOf(governanceTimelockAddress), amount + 100_000_000e18);

    // governanceTimelockAddress distrubutes tokens to users
    vm.prank(governanceTimelockAddress);
    mentoToken.transfer(alice, 5000e18);

    vm.prank(governanceTimelockAddress);
    mentoToken.transfer(bob, 5000e18);

    vm.prank(governanceTimelockAddress);
    mentoToken.transfer(charlie, 5000e18);

    // users lock tokens
    vm.prank(alice);
    locking.lock(alice, alice, 5000e18, 20, 10);

    vm.prank(bob);
    locking.lock(bob, bob, 5000e18, 40, 10);

    vm.prank(charlie);
    locking.lock(charlie, charlie, 5000e18, 30, 10);

    vm.timeTravel(1);

    address newEmissionTarget = makeAddr("NewEmissionTarget");

    // alice proposes to change the emission target
    vm.prank(alice);
    (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    ) = Proposals._proposeChangeEmissionTarget(mentoGovernor, emission, newEmissionTarget);

    // ~10 mins
    vm.timeTravel(120);

    // majority votes in favor of the proposal
    vm.prank(alice);
    mentoGovernor.castVote(proposalId, 1);

    vm.prank(bob);
    mentoGovernor.castVote(proposalId, 0);

    vm.prank(charlie);
    mentoGovernor.castVote(proposalId, 1);

    vm.timeTravel(BLOCKS_WEEK);

    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));

    // still time locked
    vm.timeTravel(BLOCKS_DAY);

    bytes32 timelockId = governanceTimelock.hashOperationBatch(
      targets,
      values,
      calldatas,
      0,
      keccak256(bytes(description))
    );

    // watchdog multisig cancels the proposal in the time lock
    vm.prank(watchdogMultisig);
    governanceTimelock.cancel(timelockId);

    // timelock delay is over
    vm.timeTravel(BLOCKS_DAY);

    // proposal can not be executed since it was cancelled
    vm.expectRevert("Governor: proposal not successful");
    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));
  }

  function test_governor_propose_whenExecutedForImplementationUpgrade_shouldUpgradeTheContracts() public s_governance {
    // create new implementations
    TestLocking newLockingContract = new TestLocking();
    TimelockController newGovernonceTimelockContract = new TimelockController();
    MentoGovernor newGovernorContract = new MentoGovernor();
    TimelockController newMLTreasuryTimelockContract = new TimelockController();

    // proxies of current implementations
    ITransparentUpgradeableProxy lockingProxy = ITransparentUpgradeableProxy(address(locking));
    ITransparentUpgradeableProxy governanceTimelockProxy = ITransparentUpgradeableProxy(governanceTimelockAddress);
    ITransparentUpgradeableProxy mentoGovernorProxy = ITransparentUpgradeableProxy(address(mentoGovernor));
    ITransparentUpgradeableProxy mentoLabsProxy = ITransparentUpgradeableProxy(address(mentoLabsTreasury));

    vm.prank(alice);
    (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    ) = Proposals._proposeUpgradeContracts(
        mentoGovernor,
        proxyAdmin,
        lockingProxy,
        governanceTimelockProxy,
        mentoGovernorProxy,
        mentoLabsProxy,
        address(newLockingContract),
        address(newGovernonceTimelockContract),
        address(newGovernorContract),
        address(newMLTreasuryTimelockContract)
      );

    // ~10 mins
    vm.timeTravel(120);

    // both claimers cast vote
    vm.prank(alice);
    mentoGovernor.castVote(proposalId, 1);

    // majority of the votes are in favor
    vm.prank(bob);
    mentoGovernor.castVote(proposalId, 1);

    vm.timeTravel(7 * BLOCKS_DAY);

    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));

    vm.timeTravel(2 * BLOCKS_DAY);

    // the old implementation has no such method
    vm.expectRevert();
    TestLocking(address(locking)).setEpochShift(1);

    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));

    // new implementation has the method and governance upgraded the contract
    TestLocking(address(locking)).setEpochShift(1);
  }

  function test_mentoLabsMultiSig_execute_whenEnoughSignatures_shouldTransferFunds() public {
    assertEq(mentoToken.balanceOf(address(mentoLabsMultisig)), 80_000_000 * 10**18);

    // create a gnosis safe transaction to transfer tokens from the multisig to the governanceTimelockAddress
    bytes memory transferCallData = abi.encodeWithSelector(
      mentoToken.transfer.selector,
      governanceTimelockAddress,
      10_000_000e18
    );
    bytes memory txHashData = mentoLabsMultisig.encodeTransactionData(
      address(mentoToken),
      0,
      transferCallData,
      Enum.Operation.Call,
      0, // safeTxGas
      0, // baseGas
      0, // gasPrice
      address(0), // gasToken
      payable(address(0)), // refundReceiver
      0
    );

    bytes32 txHash = keccak256(txHashData);

    // sign the transfer tx
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(mentoPK0, txHash);
    bytes memory signature0 = vm.constructSignature(v, r, s);
    (v, r, s) = vm.sign(mentoPK1, txHash);
    bytes memory signature1 = vm.constructSignature(v, r, s);
    (v, r, s) = vm.sign(mentoPK2, txHash);
    bytes memory signature2 = vm.constructSignature(v, r, s);

    bytes memory signatures = abi.encodePacked(signature2);

    // not enough signatures
    vm.expectRevert("GS020");
    mentoLabsMultisig.execTransaction(
      address(mentoToken),
      0,
      transferCallData,
      Enum.Operation.Call,
      0, // safeTxGas
      0, // baseGas
      0, // gasPrice
      address(0), // gasToken
      payable(address(0)), // refundReceiver
      signatures
    );

    signatures = abi.encodePacked(signature2, signature1, signature0);

    // enough signatures should transfer the funds
    mentoLabsMultisig.execTransaction(
      address(mentoToken),
      0,
      transferCallData,
      Enum.Operation.Call,
      0, // safeTxGas
      0, // baseGas
      0, // gasPrice
      address(0), // gasToken
      payable(address(0)), // refundReceiver
      signatures
    );

    // balances are updated
    assertEq(mentoToken.balanceOf(address(mentoLabsMultisig)), 70_000_000 * 10**18);
    assertEq(mentoToken.balanceOf(address(governanceTimelockAddress)), 110_000_000 * 10**18);
  }

  function test_mentoLabsTreasury_schedule_whenNotCancelled_shouldTransferFunds() public {
    //  create a transaction to transfer tokens from the MentoLabs Treasury to the MentoLabs Multisig
    bytes memory transferCallData = abi.encodeWithSelector(
      mentoToken.transfer.selector,
      mentoLabsMultisig,
      10_000_000e18
    );
    // call data to schedule the transfer
    bytes memory scheduleCallData = abi.encodeWithSelector(
      mentoLabsTreasury.schedule.selector,
      address(mentoToken),
      0,
      transferCallData,
      0,
      keccak256(bytes("Transfer tokens to MentoLabs Multisig")),
      14 days
    );

    bytes memory txHashData = mentoLabsMultisig.encodeTransactionData(
      address(mentoLabsTreasury),
      0,
      scheduleCallData,
      Enum.Operation.Call,
      0, // safeTxGas
      0, // baseGas
      0, // gasPrice
      address(0), // gasToken
      payable(address(0)), // refundReceiver
      0
    );

    bytes32 txHash = keccak256(txHashData);

    // sign the schedule tx
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(mentoPK0, txHash);
    bytes memory signature0 = vm.constructSignature(v, r, s);
    (v, r, s) = vm.sign(mentoPK1, txHash);
    bytes memory signature1 = vm.constructSignature(v, r, s);
    (v, r, s) = vm.sign(mentoPK2, txHash);
    bytes memory signature2 = vm.constructSignature(v, r, s);

    bytes memory signatures = abi.encodePacked(signature2, signature1, signature0);

    // schedule the transfer by calling schedule from the multisig on the timelock
    mentoLabsMultisig.execTransaction(
      address(mentoLabsTreasury),
      0,
      scheduleCallData,
      Enum.Operation.Call,
      0, // safeTxGas
      0, // baseGas
      0, // gasPrice
      address(0), // gasToken
      payable(address(0)), // refundReceiver
      signatures
    );

    vm.timeTravel(12 * BLOCKS_DAY);

    // the tx is not ready to be executed
    vm.expectRevert("TimelockController: operation is not ready");
    mentoLabsTreasury.execute(
      address(mentoToken),
      0,
      transferCallData,
      0,
      keccak256(bytes("Transfer tokens to MentoLabs Multisig"))
    );

    vm.timeTravel(2 * BLOCKS_DAY);

    // after 14 days, timelock expires
    mentoLabsTreasury.execute(
      address(mentoToken),
      0,
      transferCallData,
      0,
      keccak256(bytes("Transfer tokens to MentoLabs Multisig"))
    );

    // balances are updated
    assertEq(mentoToken.balanceOf(address(mentoLabsTreasury)), 110_000_000 * 10**18);
    assertEq(mentoToken.balanceOf(address(mentoLabsMultisig)), 90_000_000 * 10**18);
  }

  function test_mentoLabsTreasury_cancel_whenCalledByGovernance_shouldCancelOperation() public s_governance {
    // create a transaction to transfer tokens from the mento labs treasury to the governanceTimelockAddress
    bytes memory transferCallData = abi.encodeWithSelector(
      mentoToken.transfer.selector,
      governanceTimelockAddress,
      10_000_000e18
    );
    // call data to schedule the transfer
    bytes memory scheduleCallData = abi.encodeWithSelector(
      mentoLabsTreasury.schedule.selector,
      address(mentoToken),
      0,
      transferCallData,
      0,
      keccak256(bytes("Transfer tokens to governanceTimelockAddress")),
      14 days
    );

    bytes memory txHashData = mentoLabsMultisig.encodeTransactionData(
      address(mentoLabsTreasury),
      0,
      scheduleCallData,
      Enum.Operation.Call,
      0, // safeTxGas
      0, // baseGas
      0, // gasPrice
      address(0), // gasToken
      payable(address(0)), // refundReceiver
      0
    );

    bytes32 txHash = keccak256(txHashData);

    // sign the schedule tx
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(mentoPK0, txHash);
    bytes memory signature0 = vm.constructSignature(v, r, s);
    (v, r, s) = vm.sign(mentoPK1, txHash);
    bytes memory signature1 = vm.constructSignature(v, r, s);
    (v, r, s) = vm.sign(mentoPK2, txHash);
    bytes memory signature2 = vm.constructSignature(v, r, s);
    bytes memory signatures = abi.encodePacked(signature2, signature1, signature0);

    // schedule the transfer by calling schedule from the multisig on the timelock
    mentoLabsMultisig.execTransaction(
      address(mentoLabsTreasury),
      0,
      scheduleCallData,
      Enum.Operation.Call,
      0, // safeTxGas
      0, // baseGas
      0, // gasPrice
      address(0), // gasToken
      payable(address(0)), // refundReceiver
      signatures
    );

    // get the id of the queued operation
    bytes32 id = mentoLabsTreasury.hashOperation(
      address(mentoToken),
      0,
      transferCallData,
      0,
      keccak256(bytes("Transfer tokens to governanceTimelockAddress"))
    );

    // create a proposal to cancel the queued operation on the mento labs treasury
    vm.prank(alice);
    (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    ) = Proposals._proposeCancelQueuedTx(mentoGovernor, mentoLabsTreasury, id);

    // ~10 mins
    vm.timeTravel(120);

    // both claimers cast vote
    vm.prank(alice);
    mentoGovernor.castVote(proposalId, 1);

    // majority of the votes are in favor
    vm.prank(bob);
    mentoGovernor.castVote(proposalId, 1);

    vm.timeTravel(7 * BLOCKS_DAY);

    // queue the cancelling proposal
    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));

    vm.timeTravel(2 * BLOCKS_DAY);

    // governance cancels the queued transfer
    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));

    vm.timeTravel(5 * BLOCKS_DAY);

    // the transfer can not be executed
    vm.expectRevert("TimelockController: operation is not ready");
    mentoLabsTreasury.execute(
      address(mentoToken),
      0,
      transferCallData,
      0,
      keccak256(bytes("Transfer tokens to governanceTimelockAddress"))
    );

    // the balance is not updated
    assertEq(mentoToken.balanceOf(address(mentoLabsTreasury)), 120_000_000 * 10**18);
  }

  function test_mentoLabsTreasury_schedule_whenNotCancelled_shouldUpdateRoles() public {
    bytes32 proposerRole = mentoLabsTreasury.PROPOSER_ROLE();

    // call data to change the proposer role
    bytes memory proposerRoleCallData = abi.encodeWithSelector(
      mentoLabsTreasury.grantRole.selector,
      proposerRole,
      alice
    );

    // call data to schedule the tx
    bytes memory scheduleCallData = abi.encodeWithSelector(
      mentoLabsTreasury.schedule.selector,
      address(mentoLabsTreasury),
      0,
      proposerRoleCallData,
      0,
      keccak256(bytes("Grant proposer role to alice")),
      13 days
    );

    bytes memory txHashData = mentoLabsMultisig.encodeTransactionData(
      address(mentoLabsTreasury),
      0,
      scheduleCallData,
      Enum.Operation.Call,
      0, // safeTxGas
      0, // baseGas
      0, // gasPrice
      address(0), // gasToken
      payable(address(0)), // refundReceiver
      0
    );

    bytes32 txHash = keccak256(txHashData);

    // sign the grantRole tx
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(mentoPK0, txHash);
    bytes memory signature0 = vm.constructSignature(v, r, s);
    (v, r, s) = vm.sign(mentoPK1, txHash);
    bytes memory signature1 = vm.constructSignature(v, r, s);
    (v, r, s) = vm.sign(mentoPK2, txHash);
    bytes memory signature2 = vm.constructSignature(v, r, s);

    bytes memory signatures = abi.encodePacked(signature2, signature1, signature0);

    // schedule the tx by calling schedule from the multisig on the timelock
    mentoLabsMultisig.execTransaction(
      address(mentoLabsTreasury),
      0,
      scheduleCallData,
      Enum.Operation.Call,
      0, // safeTxGas
      0, // baseGas
      0, // gasPrice
      address(0), // gasToken
      payable(address(0)), // refundReceiver
      signatures
    );

    vm.timeTravel(13 * BLOCKS_DAY);

    assertFalse(mentoLabsTreasury.hasRole(proposerRole, alice));

    // after 13 days, timelock expires
    mentoLabsTreasury.execute(
      address(mentoLabsTreasury),
      0,
      proposerRoleCallData,
      0,
      keccak256(bytes("Grant proposer role to alice"))
    );

    assert(mentoLabsTreasury.hasRole(proposerRole, alice));
  }
}
