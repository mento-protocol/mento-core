// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import { IGnosisSafeProxyFactory } from "contracts/governance/interfaces/IGnosisSafeProxyFactory.sol";

contract MockGnosisSafeProxyFactory is IGnosisSafeProxyFactory {
  // forge cheatcode makeAddr("TreasuryContract") = 0x7513eC655cA916B5712cA762f2989ca495ef976C
  // https://book.getfoundry.sh/reference/forge-std/make-addr
  address public constant GNOSIS_SAFE_SINGLETON_ADDRESS = address(0x7513eC655cA916B5712cA762f2989ca495ef976C);

  function calculateCreateProxyWithNonceAddress(
    address /* _singleton */,
    bytes calldata /* initializer */,
    uint256 /* saltNonce */
  ) external pure returns (address) {
    revert(string(abi.encodePacked(GNOSIS_SAFE_SINGLETON_ADDRESS)));
  }

  function createProxyWithNonce(
    address /* _singleton */,
    bytes memory /* memory initializer */,
    uint256 /* saltNonce */
  ) external pure returns (address proxy) {
    return GNOSIS_SAFE_SINGLETON_ADDRESS;
  }
}
