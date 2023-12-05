// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

// Taken from Gnosis Safe Singleton https://celoscan.io/address/0xfb1bffC9d739B8D520DaF37dF666da4C687191EA#code
interface IGnosisSafe {
  /// @dev Setup function sets initial storage of contract.
  /// @param _owners List of Safe owners.
  /// @param _threshold Number of required confirmations for a Safe transaction.
  /// @param to Contract address for optional delegate call.
  /// @param data Data payload for optional delegate call.
  /// @param fallbackHandler Handler for fallback calls to this contract
  /// @param paymentToken Token that should be used for the payment (0 is ETH)
  /// @param payment Value that should be paid
  /// @param paymentReceiver Adddress that should receive the payment (or 0 if tx.origin)
  function setup(
    address[] calldata _owners,
    uint256 _threshold,
    address to,
    bytes calldata data,
    address fallbackHandler,
    address paymentToken,
    uint256 payment,
    address payable paymentReceiver
  ) external;
}
