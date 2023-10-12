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
  }

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

    assertEq(locking.balanceOf(claimer0), 60e18);
    assertEq(locking.balanceOf(claimer1), 12_000e18);

    timeTravel(BLOCKS_DAY);

    address newEmissionTarget = makeAddr("NewEmissionTarget");

    vm.expectRevert("Governor: proposer votes below proposal threshold");
    vm.prank(claimer0);
    (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    ) = proposeChangeEmissionTarget(newEmissionTarget);

    vm.prank(claimer1);
    (proposalId, targets, values, calldatas, description) = proposeChangeEmissionTarget(newEmissionTarget);

    timeTravel(1);

    vm.prank(claimer0);
    mentoGovernor.castVote(proposalId, 0);

    vm.prank(claimer1);
    mentoGovernor.castVote(proposalId, 1);

    vm.expectRevert("Governor: proposal not successful");
    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));

    timeTravel(BLOCKS_WEEK);

    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));

    vm.expectRevert("TimelockController: operation is not ready");
    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));

    timeTravel(2 * BLOCKS_DAY);

    assertEq(emission.emissionTarget(), address(treasuryContract));

    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));

    assertEq(emission.emissionTarget(), newEmissionTarget);
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

  function timeTravel(uint256 blocks) internal {
    uint256 time = blocks * 5;
    vm.roll(block.number + blocks);
    skip(time);
  }
}
