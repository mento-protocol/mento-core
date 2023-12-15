pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase

import { TestSetup } from "./TestSetup.sol";

import { GovernanceFactory } from "contracts/governance/GovernanceFactory.sol";
import { MentoToken } from "contracts/governance/MentoToken.sol";
import { Emission } from "contracts/governance/Emission.sol";
import { Airgrab } from "contracts/governance/Airgrab.sol";
import { Locking } from "contracts/governance/locking/Locking.sol";
import { TimelockController } from "contracts/governance/TimelockController.sol";
import { MentoGovernor } from "contracts/governance/MentoGovernor.sol";
import { Arrays } from "test/utils/Arrays.sol";

import { TestLocking } from "../utils/TestLocking.sol";

import { ECDSA } from "openzeppelin-contracts-next/contracts/utils/cryptography/ECDSA.sol";
import { Strings } from "openzeppelin-contracts-next/contracts/utils/Strings.sol";
import { ProxyAdmin } from "openzeppelin-contracts-next/contracts/proxy/transparent/ProxyAdmin.sol";
import { ITransparentUpgradeableProxy } from "openzeppelin-contracts-next/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { GnosisSafe } from "safe-contracts/contracts/GnosisSafe.sol";
import { GnosisSafeProxyFactory } from "safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import { GnosisSafeProxy } from "safe-contracts/contracts/proxies/GnosisSafeProxy.sol";

import { Enum } from "safe-contracts/contracts/common/Enum.sol";
import "forge-std/console2.sol";
import "forge-std/console.sol";

contract GovernanceIntegrationTest is TestSetup {
  GovernanceFactory public factory;

  ProxyAdmin public proxyAdmin;
  MentoToken public mentoToken;
  Emission public emission;
  Airgrab public airgrab;
  TimelockController public timelockController;
  MentoGovernor public mentoGovernor;
  Locking public locking;
  GnosisSafe public safeSingleton;
  GnosisSafe public mentoLabsMultisig;
  GnosisSafeProxyFactory public safeFactory;

  address public mentoSigner0;
  uint256 public mentoPK0;
  address public mentoSigner1;
  uint256 public mentoPK1;
  address public mentoSigner2;
  uint256 public mentoPK2;

  address public celoGovernance = makeAddr("CeloGovernance");
  address public communityFund = makeAddr("CommunityFund");
  address public watchdogMultisig = makeAddr("WatchdogMultisig");

  address public governanceTimelock;
  TimelockController public mentoLabsTreasury;

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
    (mentoSigner0, mentoPK0) = makeAddrAndKey("MentoSigner0");
    (mentoSigner1, mentoPK1) = makeAddrAndKey("MentoSigner1");
    (mentoSigner2, mentoPK2) = makeAddrAndKey("MentoSigner2");

    safeSingleton = new GnosisSafe();
    safeFactory = new GnosisSafeProxyFactory();

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
    factory.createGovernance(address(mentoLabsMultisig), watchdogMultisig, communityFund, merkleRoot, fractalSigner);
    proxyAdmin = factory.proxyAdmin();
    mentoToken = factory.mentoToken();
    emission = factory.emission();
    airgrab = factory.airgrab();
    timelockController = factory.governanceTimelock();
    mentoGovernor = factory.mentoGovernor();
    locking = factory.locking();
    mentoLabsTreasury = factory.mentoLabsTreasuryTimelock();
    governanceTimelock = address(factory.governanceTimelock());

    vm.prank(alice);
    mentoToken.approve(address(locking), type(uint256).max);
    vm.prank(bob);
    mentoToken.approve(address(locking), type(uint256).max);
    vm.prank(charlie);
    mentoToken.approve(address(locking), type(uint256).max);
  }

  // Factory + All
  function test_factory_shouldCreateAndSetupContracts() public {
    assertEq(mentoToken.balanceOf(address(mentoLabsMultisig)), 80_000_000 * 10**18);
    assertEq(mentoToken.balanceOf(address(mentoLabsTreasury)), 120_000_000 * 10**18);
    assertEq(mentoToken.balanceOf(address(airgrab)), 50_000_000 * 10**18);
    assertEq(mentoToken.balanceOf(governanceTimelock), 100_000_000 * 10**18);
    assertEq(mentoToken.emissionSupply(), 650_000_000 * 10**18);
    assertEq(mentoToken.emission(), address(emission));

    assertEq(emission.emissionStartTime(), block.timestamp);
    assertEq(address(emission.mentoToken()), address(mentoToken));
    assertEq(emission.emissionTarget(), address(governanceTimelock));
    assertEq(emission.owner(), address(timelockController));

    assertEq(airgrab.root(), merkleRoot);
    assertEq(airgrab.fractalSigner(), fractalSigner);
    assertEq(airgrab.fractalMaxAge(), 180 days);
    assertEq(airgrab.endTimestamp(), block.timestamp + 365 days);
    assertEq(airgrab.slopePeriod(), 104);
    assertEq(airgrab.cliffPeriod(), 0);
    assertEq(address(airgrab.token()), address(mentoToken));
    assertEq(address(airgrab.locking()), address(locking));
    assertEq(address(airgrab.communityFund()), address(communityFund));

    bytes32 proposerRole = timelockController.PROPOSER_ROLE();
    bytes32 executorRole = timelockController.EXECUTOR_ROLE();
    bytes32 cancellerRole = timelockController.CANCELLER_ROLE();

    assertEq(timelockController.getMinDelay(), 2 days);
    assert(timelockController.hasRole(proposerRole, address(mentoGovernor)));
    assert(timelockController.hasRole(executorRole, (address(0))));
    assert(timelockController.hasRole(cancellerRole, address(mentoGovernor)));
    assert(timelockController.hasRole(cancellerRole, watchdogMultisig));

    assert(mentoLabsTreasury.hasRole(proposerRole, address(mentoLabsMultisig)));
    assert(mentoLabsTreasury.hasRole(executorRole, address(0)));
    assert(mentoLabsTreasury.hasRole(cancellerRole, address(timelockController)));

    assertEq(address(mentoGovernor.token()), address(locking));
    assertEq(mentoGovernor.votingDelay(), 0);
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
    vm.prank(governanceTimelock);
    mentoToken.transfer(alice, 1000e18);

    vm.prank(governanceTimelock);
    mentoToken.transfer(bob, 1000e18);
    // Alice locks for ~6 months
    vm.prank(alice);
    locking.lock(alice, alice, 1000e18, 26, 0);

    // Bob locks for ~1 year
    vm.prank(bob);
    uint256 lockId = locking.lock(bob, bob, 1000e18, 52, 0);

    // Difference between voting powers accounted correctly
    assertApproxEqAbs(locking.getVotes(alice), 300e18, negligibleAmount);
    assertApproxEqAbs(locking.getVotes(bob), 400e18, negligibleAmount);

    timeTravel(13 * BLOCKS_WEEK);

    // Alice withdraws after ~3 months
    vm.prank(alice);
    locking.withdraw();

    // Half of the tokens should be released, half of the voting power should be revoked
    assertApproxEqAbs(locking.getVotes(alice), 150e18, negligibleAmount);
    assertApproxEqAbs(mentoToken.balanceOf(alice), 500e18, negligibleAmount);

    // Bob's voting power is 3/4 of the initial voting power
    assertApproxEqAbs(locking.getVotes(bob), 300e18, negligibleAmount);
    assertEq(mentoToken.balanceOf(bob), 0);

    timeTravel(13 * BLOCKS_WEEK);

    // Bob relocks and delegates to alice
    vm.prank(bob);
    lockId = locking.relock(lockId, alice, 1000e18, 26, 0);

    // Alice has the voting power from Bob's lock
    assertApproxEqAbs(locking.getVotes(alice), 300e18, negligibleAmount);
    assertEq(locking.getVotes(bob), 0);

    timeTravel(13 * BLOCKS_WEEK);

    // Bob delegates the lock without relocking
    vm.prank(bob);
    locking.delegateTo(lockId, charlie);

    assertEq(locking.getVotes(alice), 0);
    assertEq(locking.getVotes(bob), 0);
    assertApproxEqAbs(locking.getVotes(charlie), 150e18, negligibleAmount);

    // End of the locking period
    timeTravel(13 * BLOCKS_WEEK);

    vm.prank(bob);
    locking.withdraw();

    assertEq(locking.getVotes(alice), 0);
    assertEq(locking.getVotes(bob), 0);
    assertEq(locking.getVotes(charlie), 0);
  }

  // MentoToken + Locking + Governor
  function test_governor_whenUsedByLockedAccounts_shouldUpdateSettings() public {
    vm.prank(governanceTimelock);
    mentoToken.transfer(alice, 10_000e18);

    vm.prank(governanceTimelock);
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
    uint32 newMinCliff = 6;
    uint32 newMinSlope = 12;

    vm.prank(alice);
    (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    ) = proposeChangeSettings(
        newVotingDelay,
        newVotingPeriod,
        newThreshold,
        newQuorum,
        newMinDelay,
        newMinCliff,
        newMinSlope
      );

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
    assertEq(locking.minCliffPeriod(), newMinCliff);
    assertEq(locking.minSlopePeriod(), newMinSlope);

    // Proposal reverts because new threshold is higher
    vm.prank(alice);
    vm.expectRevert("Governor: proposer votes below proposal threshold");
    proposeChangeSettings(
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
    assertEq(locking.getVotes(claimer0), 60e18);
    assertEq(locking.getVotes(claimer1), 12_000e18);

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

    assertEq(emission.emissionTarget(), governanceTimelock);

    // anyone can execute the proposal
    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));

    // protected function is called by the owner after execution
    assertEq(emission.emissionTarget(), newEmissionTarget);
  }

  // MentoToken + Emission + Locking + Governance + Timelock
  function test_emission_whenEmitted_shouldBeSentToTreasury_canBeUsedInGovernanceAfterLocking() public {
    assertEq(mentoToken.balanceOf(governanceTimelock), 100_000_000e18);

    // emit tokens after a year
    timeTravel(365 * BLOCKS_DAY);
    uint256 amount = emission.emitTokens();

    assertEq(mentoToken.balanceOf(governanceTimelock), amount + 100_000_000e18);

    // governanceTimelock distrubutes tokens to users
    vm.prank(governanceTimelock);
    mentoToken.transfer(alice, 5000e18);

    vm.prank(governanceTimelock);
    mentoToken.transfer(bob, 5000e18);

    vm.prank(governanceTimelock);
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
    mentoGovernor.castVote(proposalId, 0);

    vm.prank(charlie);
    mentoGovernor.castVote(proposalId, 1);

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
    vm.prank(watchdogMultisig);
    timelockController.cancel(timelockId);

    // timelock delay is over
    timeTravel(BLOCKS_DAY);

    // proposal can not be executed
    vm.expectRevert("Governor: proposal not successful");
    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));
  }

  function test_governor_propose_whenExecutedForImplementationUpgrade_shouldUpgradeTheContracts() public {
    vm.prank(governanceTimelock);
    mentoToken.transfer(alice, 10_000e18);

    vm.prank(governanceTimelock);
    mentoToken.transfer(bob, 10_000e18);
    // Alice locks for max cliff
    vm.prank(alice);
    locking.lock(alice, alice, 2000e18, 1, 103);

    // Bob locks a small amount for max cliff
    vm.prank(bob);
    locking.lock(bob, bob, 1500e18, 1, 103);

    timeTravel(BLOCKS_DAY);

    TestLocking newLockingContract = new TestLocking();
    TimelockController newGovernonceTimelockContract = new TimelockController();
    MentoGovernor newGovernorContract = new MentoGovernor();
    TimelockController newMLTreasuryTimelockContract = new TimelockController();

    vm.prank(alice);
    (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    ) = proposeUpgradeContracts(
        address(newLockingContract),
        address(newGovernonceTimelockContract),
        address(newGovernorContract),
        address(newMLTreasuryTimelockContract)
      );

    // ~10 mins
    timeTravel(120);

    // both claimers cast vote
    vm.prank(alice);
    mentoGovernor.castVote(proposalId, 1);

    // majority of the votes are in favor
    vm.prank(bob);
    mentoGovernor.castVote(proposalId, 1);

    timeTravel(7 * BLOCKS_DAY);

    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));

    timeTravel(2 * BLOCKS_DAY);

    vm.expectRevert();
    TestLocking(address(locking)).setEpochShift(1337);

    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));

    TestLocking(address(locking)).setEpochShift(1337);
  }

  function proposeUpgradeContracts(
    address newLockingContract,
    address newGovernonceTimelockContract,
    address newGovernorContract,
    address newMLTreasuryTimelockContract
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
    ITransparentUpgradeableProxy proxy0 = ITransparentUpgradeableProxy(address(locking));
    ITransparentUpgradeableProxy proxy1 = ITransparentUpgradeableProxy(address(timelockController));
    ITransparentUpgradeableProxy proxy2 = ITransparentUpgradeableProxy(address(mentoGovernor));
    ITransparentUpgradeableProxy proxy3 = ITransparentUpgradeableProxy(address(mentoLabsTreasury));

    targets = new address[](4);
    targets[0] = address(proxyAdmin);
    targets[1] = address(proxyAdmin);
    targets[2] = address(proxyAdmin);
    targets[3] = address(proxyAdmin);

    values = new uint256[](4);
    values[0] = 0;
    values[1] = 0;
    values[2] = 0;
    values[3] = 0;

    calldatas = new bytes[](4);
    calldatas[0] = abi.encodeWithSelector(proxyAdmin.upgrade.selector, proxy0, newLockingContract);
    calldatas[1] = abi.encodeWithSelector(proxyAdmin.upgrade.selector, proxy1, newGovernonceTimelockContract);
    calldatas[2] = abi.encodeWithSelector(proxyAdmin.upgrade.selector, proxy2, newGovernorContract);
    calldatas[3] = abi.encodeWithSelector(proxyAdmin.upgrade.selector, proxy3, newMLTreasuryTimelockContract);

    description = "Upgrade all upgradeable contracts";

    proposalId = mentoGovernor.propose(targets, values, calldatas, description);
  }

  function test_vestingContract_execute_whenEnoughSignatures_shouldTransferFunds() public {
    assertEq(mentoToken.balanceOf(address(mentoLabsMultisig)), 80_000_000 * 10**18);

    // sign a gnosis safe transaction to transfer tokens from the multisig to the governanceTimelock
    bytes memory transferCallData = abi.encodeWithSelector(
      mentoToken.transfer.selector,
      governanceTimelock,
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

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(mentoPK0, txHash);
    bytes memory signature0 = constructSignature(v, r, s);

    (v, r, s) = vm.sign(mentoPK1, txHash);
    bytes memory signature1 = constructSignature(v, r, s);

    (v, r, s) = vm.sign(mentoPK2, txHash);
    bytes memory signature2 = constructSignature(v, r, s);

    bytes memory signatures = abi.encodePacked(signature2);

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

    assertEq(mentoToken.balanceOf(address(mentoLabsMultisig)), 70_000_000 * 10**18);
    assertEq(mentoToken.balanceOf(address(governanceTimelock)), 110_000_000 * 10**18);
  }

  function test_mlTreasury_schedule_whenNotCancelled_shouldTransferFunds() public {
    bytes memory transferCallData = abi.encodeWithSelector(
      mentoToken.transfer.selector,
      governanceTimelock,
      10_000_000e18
    );
    // sign a gnosis safe transaction to transfer tokens from the multisig to the governanceTimelock
    bytes memory scheduleCallData = abi.encodeWithSelector(
      mentoLabsTreasury.schedule.selector,
      address(mentoToken),
      0,
      transferCallData,
      0,
      keccak256(bytes("Transfer tokens to governanceTimelock")),
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

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(mentoPK0, txHash);
    bytes memory signature0 = constructSignature(v, r, s);

    (v, r, s) = vm.sign(mentoPK1, txHash);
    bytes memory signature1 = constructSignature(v, r, s);

    (v, r, s) = vm.sign(mentoPK2, txHash);
    bytes memory signature2 = constructSignature(v, r, s);

    bytes memory signatures = abi.encodePacked(signature2, signature1, signature0);

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

    timeTravel(12 * BLOCKS_DAY);

    vm.expectRevert("TimelockController: operation is not ready");
    mentoLabsTreasury.execute(
      address(mentoToken),
      0,
      transferCallData,
      0,
      keccak256(bytes("Transfer tokens to governanceTimelock"))
    );

    timeTravel(2 * BLOCKS_DAY);

    mentoLabsTreasury.execute(
      address(mentoToken),
      0,
      transferCallData,
      0,
      keccak256(bytes("Transfer tokens to governanceTimelock"))
    );

    assertEq(mentoToken.balanceOf(address(mentoLabsTreasury)), 110_000_000 * 10**18);
    assertEq(mentoToken.balanceOf(address(governanceTimelock)), 110_000_000 * 10**18);
  }

  function constructSignature(
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public pure returns (bytes memory signature) {
    // Signature is 65 bytes long
    signature = new bytes(65);

    // Copy `r` into the first 32 bytes
    assembly {
      mstore(add(signature, 32), r)
    }

    // Copy `s` into the next 32 bytes
    assembly {
      mstore(add(signature, 64), s)
    }

    // Append `v` as the last byte
    signature[64] = bytes1(v);

    return signature;
  }

  /// @dev build the KYC message hash and sign it with the provided pk
  /// @param signer The PK to sign the message with
  /// @param account The account to sign the message for
  /// @param credential KYC credentials
  /// @param validUntil KYC valid until this ts
  /// @param approvedAt KYC approved at this ts
  function validKycSignature(
    uint256 signer,
    address account,
    string memory credential,
    uint256 validUntil,
    uint256 approvedAt
  ) internal pure returns (bytes memory) {
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

  /// @dev propose to change the emission target
  /// @param newTarget The new emission target address
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

  /// @dev propose to change the governance settings
  /// @param votingDelay The new voting delay
  /// @param votingPeriod The new voting period
  /// @param threshold The new threshold
  /// @param quorum The new quorum
  /// @param minDelay The new min delay
  /// @param minCliff The new min cliff period
  /// @param minSlope The new min slope period
  function proposeChangeSettings(
    uint256 votingDelay,
    uint256 votingPeriod,
    uint256 threshold,
    uint256 quorum,
    uint256 minDelay,
    uint32 minCliff,
    uint32 minSlope
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
    targets = new address[](7);
    targets[0] = address(mentoGovernor);
    targets[1] = address(mentoGovernor);
    targets[2] = address(mentoGovernor);
    targets[3] = address(mentoGovernor);
    targets[4] = address(timelockController);
    targets[5] = address(locking);
    targets[6] = address(locking);

    values = new uint256[](7);
    values[0] = 0;
    values[1] = 0;
    values[2] = 0;
    values[3] = 0;
    values[4] = 0;
    values[5] = 0;
    values[6] = 0;

    calldatas = new bytes[](7);
    calldatas[0] = abi.encodeWithSelector(mentoGovernor.setVotingDelay.selector, votingDelay);
    calldatas[1] = abi.encodeWithSelector(mentoGovernor.setVotingPeriod.selector, votingPeriod);
    calldatas[2] = abi.encodeWithSelector(mentoGovernor.setProposalThreshold.selector, threshold);
    calldatas[3] = abi.encodeWithSelector(mentoGovernor.updateQuorumNumerator.selector, quorum);
    calldatas[4] = abi.encodeWithSelector(timelockController.updateDelay.selector, minDelay);
    calldatas[5] = abi.encodeWithSelector(locking.setMinCliffPeriod.selector, minCliff);
    calldatas[6] = abi.encodeWithSelector(locking.setMinSlopePeriod.selector, minSlope);

    description = "Change governance config";

    proposalId = mentoGovernor.propose(targets, values, calldatas, description);
  }

  /// @dev moves block.number and block.timestamp in sync
  /// @param blocks The number of blocks that will be moved
  function timeTravel(uint256 blocks) internal {
    uint256 time = blocks * 5;
    vm.roll(block.number + blocks);
    skip(time);
  }
}
