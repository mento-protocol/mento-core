// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable max-line-length

import { MentoToken } from "../MentoToken.sol";

library MentoTokenDeployerLib {
  /**
   * @notice Deploys a new MentoToken contract
   * @param mentoLabsMultiSig The address of the Mento Labs multisig
   * @param mentoLabsTreasuryTimelock The address of the timelocked Mento Labs Treasury
   * @param airgrab The address of the airgrab contract
   * @param governanceTimelock The address of the governance timelock
   * @param emission The address of the emission contract
   * @return The address of the new MentoToken contract
   */
  function deploy(
    address mentoLabsMultiSig,
    address mentoLabsTreasuryTimelock,
    address airgrab,
    address governanceTimelock,
    address emission
  ) external returns (MentoToken) {
    return new MentoToken(mentoLabsMultiSig, mentoLabsTreasuryTimelock, airgrab, governanceTimelock, emission);
  }
}
