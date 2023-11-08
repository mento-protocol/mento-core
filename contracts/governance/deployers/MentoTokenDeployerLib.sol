// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable max-line-length

import { MentoToken } from "../MentoToken.sol";

library MentoTokenDeployerLib {
  /**
   * @notice Deploys a new MentoToken contract
   * @param vesting The address of the vesting contract
   * @param mentoMultisig The address of the mento multisig
   * @param airgrab The address of the airgrab contract
   * @param treasury The address of the treasury
   * @param emission The address of the emission contract
   * @return The address of the new MentoToken contract
   */
  function deploy(
    address vesting,
    address mentoMultisig,
    address airgrab,
    address treasury,
    address emission
  ) external returns (MentoToken) {
    return new MentoToken(
      vesting,
      mentoMultisig,
      airgrab,
      treasury,
      emission
    );
  }
}
