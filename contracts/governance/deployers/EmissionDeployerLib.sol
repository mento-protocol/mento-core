// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable max-line-length

import { Emission } from "../Emission.sol";

library EmissionDeployerLib {
  /**
   * @notice Deploys a new Emission contract
   * @param mentoToken The address of the MentoToken contract
   * @param emissionTarget The address of the emission target
   * @return The address of the new Emission contract
   */
  function deploy(
    address mentoToken,
    address emissionTarget
  ) external returns (Emission) {
    return new Emission(
      mentoToken,
      emissionTarget
    );
  }
}
