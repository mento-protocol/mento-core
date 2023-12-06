// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase

import { GovernanceFactory } from "../../contracts/governance/GovernanceFactory.sol";

contract GovernanceFactoryHarness is GovernanceFactory {
  constructor(
    address owner_,
    address gnosisSafeSingleton_,
    address gnosisSafeProxyFactory_
  ) GovernanceFactory(owner_, gnosisSafeSingleton_, gnosisSafeProxyFactory_) {}

  function exposed_addressForNonce(uint256 nonce) external view returns (address) {
    return addressForNonce(nonce);
  }

  function exposed_bytesToAddress(bytes memory bys) external pure returns (address addr) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      addr := mload(add(bys, 20))
    }
  }

  function exposed_calculateSafeProxyAddress(bytes memory initializer, uint256 saltNonce)
    external
    returns (address proxy)
  {
    return calculateSafeProxyAddress(initializer, saltNonce);
  }
}
