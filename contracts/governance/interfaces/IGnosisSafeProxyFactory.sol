// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

// Taken from Gnosis Safe Proxy Factory contract
// https://celoscan.io/address/0xC22834581EbC8527d974F8a1c97E1bEA4EF910BC#code
interface IGnosisSafeProxyFactory {
  /// @dev Allows to get the address for a new proxy contact created via `createProxyWithNonce`
  ///      This method is only meant for address calculation purpose when you use an initializer
  ///      that would revert, therefore the response is returned with a revert. When calling this
  ///      method set `from` to the address of the proxy factory.
  /// @param _singleton Address of singleton contract.
  /// @param initializer Payload for message call sent to new proxy contract.
  /// @param saltNonce Nonce that will be used to generate the salt to calculate the address of the new proxy contract.
  function calculateCreateProxyWithNonceAddress(
    address _singleton,
    bytes calldata initializer,
    uint256 saltNonce
  ) external returns (address proxy);

  /// @dev Allows to create new proxy contact and execute a message call to the new proxy within one transaction.
  /// @param _singleton Address of singleton contract.
  /// @param initializer Payload for message call sent to new proxy contract.
  /// @param saltNonce Nonce that will be used to generate the salt to calculate the address of the new proxy contract.
  function createProxyWithNonce(
    address _singleton,
    bytes memory initializer,
    uint256 saltNonce
  ) external returns (address proxy);
}
