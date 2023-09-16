// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { MerkleProof } from "openzeppelin-contracts-next/contracts/utils/cryptography/MerkleProof.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/utils/SafeERC20.sol";
import { ECDSA } from "openzeppelin-contracts-next/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title Merke Tree KYC Airdrop
 * @author Mento Labs
 * @notice This contract implements a merkle tree airdrop gatted by KYC/KYB using Fractal.
 */
contract MerkleTreeKYCAirdrop {
  using SafeERC20 for IERC20;

  /// @notice The root of the merkle tree.
  bytes32 public immutable root;
  /// @notice The Fractal.id message signer for KYC/KYB.
  address public immutable fractalIssuer;
  /// @notice The token in the airdrop.
  address public token;
  /// @notice The treasury address where the tokens will be refunded.
  address payable public immutable treasury;
  /// @notice The timestamp when the airdrop ends.
  uint256 public endTimestamp;
  /// @notice The map of addresses that have claimed
  mapping(address => bool) public claimed;

  /**
   * @dev Constructor for the Airdrop contract.
   * @notice It sets the merkle root, the Fractal.id message signer, the treasury address,
   * the token address and the end timestamp.
   * @param root_ The root of the merkle tree.
   * @param fractalIssuer_ The Fractal.id message signer for KYC/KYB.
   * @param token_ The token in the airdrop.
   * @param treasury_ The treasury address where the tokens will be refunded.
   * @param endTimestamp_ The timestamp when the airdrop ends.
   */
  constructor(
    bytes32 root_,
    address fractalIssuer_,
    address token_,
    address payable treasury_,
    uint256 endTimestamp_
  ) {
    require(root_ != bytes32(0), "Airdrop: invalid root");
    require(fractalIssuer_ != address(0), "Airdrop: invalid fractal issuer");
    require(token_ != address(0), "Airdrop: invalid token");
    require(treasury_ != address(0), "Airdrop: invalid treasury");
    require(endTimestamp_ > block.timestamp, "Airdrop: invalid end timestamp");

    root = root_;
    fractalIssuer = fractalIssuer_;
    token = token_;
    treasury = treasury_;
    endTimestamp = endTimestamp_;
  }

  /**
   * @dev Allows `account` to claim `amount` tokens if the merkle proof and kyc is valid.
   * @notice This function can only be called by the Fractal.id message signer and
   * only if the airdrop hasn't ended yet.
   * @param account The address of the account to claim tokens for.
   * @param amount The amount of tokens to be claimed.
   * @param merkleProof The merkle proof for the account.
   * @param kycType The KYC type of the account.
   * @param countryOfIDIssuance The country of ID issuance of the account.
   * @param countryOfResidence The country of residence of the account.
   * @param rootHash The root hash of the KYC data.
   * @param issuerSignature The signature of the KYC data.
   */
  function claim(
    address account,
    uint256 amount,
    bytes32[] calldata merkleProof, 
    uint8 kycType,
    uint8 countryOfIDIssuance,
    uint8 countryOfResidence,
    bytes32 rootHash,
    bytes calldata issuerSignature
  ) external {
    require(block.timestamp <= endTimestamp, "Airdrop: finished");
    require(hasAirdrop(account, amount, merkleProof), "Airdrop: not in tree");
    require(hasValidKycSignature(account, kycType, countryOfIDIssuance, countryOfResidence, rootHash, issuerSignature), "Airdrop: invalid kyc");
    require(hasValidKycParameters(kycType, countryOfResidence), "Airdrop: invalid kyc params");
    require(!claimed[account], "Airdrop: already claimed");
    require(IERC20(token).balanceOf(address(this)) >= amount, "Airdrop: insufficient balance");

    claimed[account] = true;
    IERC20(token).safeTransfer(account, amount);
  }

  /**
   * @dev Allows the treasury to reclaim any tokens left
   * @notice This function can only be called if the airdrop has ended.
   * The function takes a token as a param in case the contract has been sent
   * tokens other than the airdrop token.
   */
  function drain(address tokenToDrain) external {
    require(block.timestamp > endTimestamp, "Airdrop: in progress");
    uint256 balance = IERC20(tokenToDrain).balanceOf(address(this));
    require(balance > 0, "Airdrop: Nothing to drain");
    IERC20(tokenToDrain).safeTransfer(treasury, balance);
  }

  /**
   * @dev Check if the account is included in the airdrop.
   * @notice This function checks the merkletree with the data provided.
   * @param account The address of the account to check.
   * @param amount The amount of tokens to be claimed.
   * @param merkleProof The merkle proof for the account.
   */
  function hasAirdrop(
    address account,
    uint256 amount,
    bytes32[] calldata merkleProof
  ) public view returns (bool) {
    bytes32 node = keccak256(abi.encodePacked(account, amount));
    return MerkleProof.verify(merkleProof, root, node);
  }

  /**
   * @dev Check if the account has a valid kyc signature. See: https://docs.developer.fractal.id/did-credentials
   * @notice This function checks the kyc signature with the data provided.
   * @param account The address of the account to check.
   * @param kycType The type of kyc.
   * @param countryOfIDIssuance The country of ID issuance.
   * @param countryOfResidence The country of residence.
   * @param rootHash The root hash of the kyc.
   * @param issuerSignature The signature of the issuer.
   */
  function hasValidKycSignature(
    address account,
    uint8 kycType,
    uint8 countryOfIDIssuance,
    uint8 countryOfResidence,
    bytes32 rootHash,
    bytes calldata issuerSignature
  ) internal view returns (bool) {
    bytes32 signedMessageHash = ECDSA.toEthSignedMessageHash(
      keccak256(abi.encodePacked(account, kycType, countryOfIDIssuance, countryOfResidence, rootHash))
    );
    return ECDSA.recover(signedMessageHash, issuerSignature) == fractalIssuer;
  }

  /**
   * @dev Check if the account has allowed KYC parameters
   * @notice This function checks the kyc parameters, see: https://docs.developer.fractal.id/did-credentials
   * @param kycType The type of kyc
   * @param countryOfResidence The country of residence, see: https://bit.ly/46fC5Cq
   */
  function hasValidKycParameters(
    uint8 kycType,
    uint8 countryOfResidence
  ) internal view returns (bool) {
    return (
      kycType == 1 && countryOfResidence != 7
    );
  }
}
