// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase
// solhint-disable contract-name-camelcase
import { TestSetup } from "../TestSetup.sol";
import { Emission } from "contracts/governance/Emission.sol";
import { MockMentoToken } from "../../mocks/MockMentoToken.sol";

contract Emission_Test is TestSetup {
  Emission public emission;

  MockMentoToken public mentoToken;
  address public emissionTarget;

  event TokenContractSet(address newTokenAddress);
  event EmissionTargetSet(address newTargetAddress);
  event TokensEmitted(address indexed target, uint256 amount);

  function _newEmission() internal {
    vm.prank(owner);
    emission = new Emission();
  }

  function _setupEmissionContract() internal {
    emissionTarget = makeAddr("EmissionTarget");
    mentoToken = new MockMentoToken();

    vm.startPrank(owner);
    emission.setTokenContract(address(mentoToken));
    emission.setEmissionTarget(emissionTarget);
    vm.stopPrank();
  }
}
