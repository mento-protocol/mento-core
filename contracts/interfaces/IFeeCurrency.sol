pragma solidity ^0.8.13;

/**
 * @notice This interface should be implemented for tokens which are supposed to
 * act as fee currencies on the Celo blockchain, meaning that they can be
 * used to pay gas fees for CIP-64 transactions (and some older tx types).
 * See https://github.com/celo-org/celo-proposals/blob/master/CIPs/cip-0064.md
 *
 * @notice Before executing a tx with non-empty `feeCurrency` field, the fee
 * currency's `debitGasFees` function is called to reserve the maximum
 * amount of gas token that tx can spend. After the tx has been executed, the
 * `creditGasFees` function is called to refund any unused gas and credit
 * the spent fees to the appropriate recipients. Events which are emitted in
 * these functions will show up for every tx using the token as a
 * fee currency.
 *
 * @dev Requirements:
 * - The functions will be called by the blockchain client with `msg.sender
 * == address(0)`. If this condition is not met, the functions must
 * revert to prevent malicious users from crediting their accounts directly.
 * - `creditGasFees` must credit all specified amounts. If this is not
 * possible the functions must revert to prevent inconsistencies between
 * the debited and credited amounts.
 *
 * @dev Notes on compatibility:
 * - There are two versions of `creditGasFees`: one for the current
 * (2024-01-16) blockchain implementation and a more future-proof version
 * that omits deprecated fields and accommodates potential new recipients
 * that might become necessary on later blockchain implementations. Both
 * versions should be implemented to increase compatibility.
 */
interface IFeeCurrency {
  /// @notice Called before transaction execution to reserve the maximum amount of gas
  /// that can be used by the transaction.
  /// - The implementation must deduct `value` from `from`'s balance.
  /// - Must revert if `msg.sender` is not the zero address.
  function debitGasFees(address from, uint256 value) external;

  /// @notice New function signature, will be used when all fee currencies have migrated.
  /// Credited amounts include gas refund, base fee and tip. Future additions
  /// may include L1 gas fee when Celo becomes and L2.
  /// - The implementation must increase each `recipient`'s balance by corresponding `amount`.
  /// - Must revert if `msg.sender` is not the zero address.
  /// - Must revert if `recipients` and `amounts` have different lengths.
  /// - The blockchain client will never call this function with zero-address recipients or zero amounts.
  function creditGasFees(address[] calldata recipients, uint256[] calldata amounts) external;

  /// @notice Old function signature for backwards compatibility
  /// - Must revert if `msg.sender` is not the zero address.
  /// - `refundAmount` must be credited to `refundRecipient`
  /// - `tipAmount` must be credited to `tipRecipient`
  /// - `baseFeeAmount` must be credited to `baseFeeRecipient`
  /// - `_gatewayFeeRecipient` and `_gatewayFeeAmount` only exist for backwards
  ///   compatibility reasons and will always be zero.
  /// - The blockchain client will never call this function with zero-address
  ///   recipients, except for the legacy `_gatewayFeeRecipient`. The contract
  ///   should revert when any other recipient is zero.
  /// - The contract must accept zero amounts without reverting.
  function creditGasFees(
    address refundRecipient,
    address tipRecipient,
    address _gatewayFeeRecipient,
    address baseFeeRecipient,
    uint256 refundAmount,
    uint256 tipAmount,
    uint256 _gatewayFeeAmount,
    uint256 baseFeeAmount
  ) external;
}
