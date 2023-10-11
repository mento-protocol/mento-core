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
  address public fractalSigner = makeAddr("FractalSigner");

  bytes32 public merkleRoot = 0x945d83ced94efc822fed712b4c4694b4e1129607ec5bbd2ab971bb08dca4d809; // Mock root

  function setUp() public {
    vm.roll(21871402); // (Oct-11-2023 WED 12:00:01 PM +UTC)
    vm.warp(1697025601); // (Oct-11-2023 WED 12:00:01 PM +UTC)

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

  function test_createGovernance_shouldCreateAndSetupContracts() public {
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
}
