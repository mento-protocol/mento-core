// // solhint-disable func-name-mixedcase
// // solhint-disable max-line-length
// // SPDX-License-Identifier: GPL-3.0-or-later
// pragma solidity 0.8.18;

// import { Test } from "forge-std-next/Test.sol";
// import { IVotesUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/governance/extensions/GovernorVotesUpgradeable.sol";
// import { MentoToken } from "contracts/governance/MentoToken.sol";
// import { Emission } from "contracts/governance/Emission.sol";
// import { TimelockController } from "contracts/governance/TimelockController.sol";
// import { MentoGovernor } from "contracts/governance/MentoGovernor.sol";
// import { MockVeMento } from "../mocks/MockVeMento.sol";

// contract TestSetup is Test {
//   MentoToken public mentoToken;
//   Emission public emission;
//   TimelockController public timelockController;
//   MentoGovernor public mentoGovernor;

//   MockVeMento public mockVeMento; // TODO: change mock with locking contracts

//   address public immutable vestingContract = makeAddr("vestingContract");
//   address public immutable airgrabContract = makeAddr("airgrabContract");
//   address public immutable treasuryContract = makeAddr("treasuryContract");

//   address public immutable owner = makeAddr("owner");
//   address public immutable alice = makeAddr("alice");
//   address public immutable bob = makeAddr("bob");
//   address public immutable charlie = makeAddr("charlie");

//   uint256 public constant INITIAL_TOTAL_SUPPLY = 350_000_000 * 1e18;
//   uint256 public constant EMISSION_SUPPLY = 650_000_000 * 1e18;

//   uint256 public constant MONTH = 30 days;
//   uint256 public constant YEAR = 365 days;

//   uint256 public constant BLOCKS_DAY = 17_280; // in CELO
//   uint256 public constant BLOCKS_WEEK = 120_960; // in CELO

//   function setUp() public virtual {
//     address[] memory proposers;
//     address[] memory executors;

//     vm.startPrank(owner);

//     emission = new Emission();
//     mentoToken = new MentoToken(vestingContract, airgrabContract, treasuryContract, address(emission));
//     mockVeMento = new MockVeMento();

//     timelockController = new TimelockController();
//     timelockController.__MentoTimelockController_init(1 days, proposers, executors, owner);

//     mentoGovernor = new MentoGovernor();
//     mentoGovernor.__MentoGovernor_init(IVotesUpgradeable(address(mockVeMento)), timelockController);

//     vm.stopPrank();
//   }
// }
