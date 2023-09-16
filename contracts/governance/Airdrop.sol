// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { MerkleProof } from "openzeppelin-contracts-next/contracts/utils/cryptography/MerkleProof.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/utils/SafeERC20.sol";
import { ECDSA } from "openzeppelin-contracts-next/contracts/utils/cryptography/ECDSA.sol";
import { ILocking } from "locking-contracts/ILocking.sol";

/**
 * @title Airdrop
 * @author Mento Labs
 * @notice This contract implements a token airdrop gated by a MerkeTree and KYC using fractal.
 * The airdrop also forces claimers to immediately lock their tokens as veTokens otherwise
 * their amount to claim gets scaled depending on the chosen cliff and slope periods,
 * and the configuration of the contract:
 * basePercentage     Base percentage received irrespective of cliff and slope periods.
 * cliffPercentage        The max percantage received if the cliff requirement is met.
 * requiredCliffPeriod  The cliff period which unlocks 100% of cliffPercentage,
 *                        if user's cliff < requiredCliffPeriod, the cliffPercentage
 *                        is scaled by cliff/requiredCliffPeriod
 * slopePercentage        The max percentage received if the slope requirement is met.
 * requiredSlopePeriod The slope period which unlocks 100% of slopePercentage,
 *                        if user's slope < requiredSlopePeriod, the slopePercentage
 *                        is scaled by cliff/requiredSlopePeriod
 * slopePercentage        The max percentage received if the slope requirement is met.
 * basePercentage + cliffPercentage + slopePercentage must equal 100
 */
contract Airdrop {
  using SafeERC20 for IERC20;

  uint256 public constant PRECISION = 1e18;
  uint32 public constant MAX_CLIFF_PERIOD = 103;
  uint32 public constant MAX_SLOPE_PERIOD = 104;

  /**
   * @notice Emitted when tokens are claimed 
   * @param claimer The account claiming the tokens
   * @param amount The amount of tokens being claimed
   * @param cliff The selected cliff duration
   * @param slope The selected slope duration
   */
  event TokensClaimed(address indexed claimer, uint256 indexed amount, uint32 slope, uint32 cliff);

  /**
   * @notice Emitted when tokens are drained
   * @param token The token addresses that was drained
   * @param amount The amount drained
   */
  event TokensDrained(address indexed token, uint256 amount);

  /// @notice The root of the merkle tree.
  bytes32 public immutable root;
  /// @notice The Fractal.id message signer for KYC/KYB.
  address public immutable fractalIssuer;
  /// @notice The token in the airdrop.
  IERC20 public immutable token;
  /// @notice The locking contract for veToken.
  ILocking public immutable lockingContract;
  /// @notice The treasury address where the tokens will be refunded.
  address payable public immutable treasury;
  /// @notice The timestamp when the airdrop ends.
  uint256 public immutable endTimestamp;
  /// @notice The minimum percentage that will be received irrespective of locking
  uint256 public immutable basePercentage;
  /// @notice The percentage that will be received based on the cliff period
  uint256 public immutable cliffPercentage;
  /// @notice The minimum cliff period required to receive the full cliffPercentage
  uint32 public immutable requiredCliffPeriod;
  /// @notice The precentage that will be received based on the slop period
  uint256 public immutable slopePercentage;
  /// @notice The minimum slope period required to receive the full slopePercentage
  uint32 public immutable requiredSlopePeriod;
  /// @notice The map of addresses that have claimed
  mapping(address => bool) public claimed;

  /**
   * @dev Constructor for the Airdrop contract.
   * @notice It checks and configures all immutable params and gives infinite approval to the
   * locking contract.
   * @param root_ The root of the merkle tree.
   * @param fractalIssuer_ The Fractal.id message signer for KYC/KYB.
   * @param token_ The token in the airdrop.
   * @param treasury_ The treasury address where the tokens will be refunded.
   * @param endTimestamp_ The timestamp when the airdrop ends.
   * @param basePercentage_ The percentage that will be received based on the cliff period
   * @param cliffPercentage_ The minimum cliff period required to receive the full cliffPercentage
   * @param requiredCliffPeriod_ The precentage that will be received based on the slop period
   * @param slopePercentage_ The minimum slope period required to receive the full slopePercentage
   * @param requiredSlopePeriod_ The minimum slope period required to receive the full slopePercentage
   */
  constructor(
    bytes32 root_,
    address fractalIssuer_,
    address token_,
    address lockingContract_,
    address payable treasury_,
    uint256 endTimestamp_,
    uint256 basePercentage_,
    uint256 cliffPercentage_,
    uint32 requiredCliffPeriod_,
    uint256 slopePercentage_,
    uint32 requiredSlopePeriod_
  ) {
    require(root_ != bytes32(0), "Airdrop: invalid root");
    require(fractalIssuer_ != address(0), "Airdrop: invalid fractal issuer");
    require(token_ != address(0), "Airdrop: invalid token");
    require(lockingContract_ != address(0), "Airdrop: invalid locking contract");
    require(treasury_ != address(0), "Airdrop: invalid treasury");
    require(endTimestamp_ > block.timestamp, "Airdrop: invalid end timestamp");
    require(basePercentage_ + cliffPercentage_ + slopePercentage_ == PRECISION, "Airdrop: unlock percentages must add up to 1");
    require(requiredCliffPeriod_ <= MAX_CLIFF_PERIOD, "Airdrop: required cliff period too large");
    require(requiredSlopePeriod_ <= MAX_SLOPE_PERIOD, "Airdrop: required slope period too large");

    root = root_;
    fractalIssuer = fractalIssuer_;
    token = IERC20(token_);
    lockingContract = ILocking(lockingContract_);
    treasury = treasury_;
    endTimestamp = endTimestamp_;
    basePercentage = basePercentage_;
    cliffPercentage = cliffPercentage_;
    requiredCliffPeriod = requiredCliffPeriod_;
    slopePercentage = slopePercentage_;
    requiredSlopePeriod = requiredSlopePeriod_;

    token.approve(address(lockingContract), type(uint256).max);
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
   * @param slope The period of the slope in weeks.
   * @param cliff The period of the slope in weeks.
   */
  function claim(
    address account,
    uint256 amount,
    bytes32[] calldata merkleProof, 
    uint8 kycType,
    uint8 countryOfIDIssuance,
    uint8 countryOfResidence,
    bytes32 rootHash,
    bytes calldata issuerSignature,
    uint32 slope,
    uint32 cliff
  ) external returns (uint256 unlockedAmount) {
    require(block.timestamp <= endTimestamp, "Airdrop: finished");
    require(hasAirdrop(account, amount, merkleProof), "Airdrop: not in tree");
    require(isValidKycSignature(account, kycType, countryOfIDIssuance, countryOfResidence, rootHash, issuerSignature), "Airdrop: invalid kyc signer");
    require(isValidKyc(kycType, countryOfResidence), "Airdrop: invalid kyc params");
    require(!claimed[account], "Airdrop: already claimed");
    require(IERC20(token).balanceOf(address(this)) >= amount, "Airdrop: insufficient balance");

    unlockedAmount = getUnlockedAmount(amount, slope, cliff);
    require(unlockedAmount <= type(uint96).max, "Airdrop: amount too large");

    claimed[account] = true;

    if (slope + cliff == 0) {
      token.safeTransfer(account, unlockedAmount);
    } else {
      lockingContract.lock(account, address(0), uint96(unlockedAmount), slope, cliff);
    }

    emit TokensClaimed(account, unlockedAmount, slope, cliff);
  }

  /**
   * @dev Allows the treasury to reclaim any tokens left
   * @notice This function can only be called if the airdrop has ended.
   * The function takes a token as a param in case the contract has been sent
   * tokens other than the airdrop token.
   */
  function drain(address tokenToDrain) external {
    require(block.timestamp > endTimestamp, "Airdrop: not finished");
    uint256 balance = IERC20(tokenToDrain).balanceOf(address(this));
    require(balance > 0, "Airdrop: nothing to drain");
    IERC20(tokenToDrain).safeTransfer(treasury, balance);
    emit TokensDrained(tokenToDrain, balance);
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
    bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(account, amount))));
    return MerkleProof.verify(merkleProof, root, leaf);
  }

  /**
   * @dev Calculate the total unlocked amount depending based on the selected values for slope and cliff
   * and the percentage settings that the contract was deployed with.
   * @param amount The total amount that can be unlocked
   * @param slope The selected slope period
   * @param cliff The selected cliff period
   */ 
  function getUnlockedAmount(uint256 amount, uint32 slope, uint32 cliff) public view returns (uint256 unlockedAmount) {
    uint256 unlockedPercentage = basePercentage;
    
    if (cliff >= requiredCliffPeriod) {
      unlockedPercentage += cliffPercentage;
    } else {
      unlockedPercentage += uint256(cliff) * cliffPercentage / uint256(requiredCliffPeriod);
    }

    if (slope >= requiredSlopePeriod) {
      unlockedPercentage += slopePercentage;
    } else {
      unlockedPercentage +=  uint256(slope) * slopePercentage / uint256(requiredSlopePeriod);
    }

    if (unlockedPercentage >= PRECISION) {
      unlockedAmount = amount;
    } else {
      unlockedAmount = (amount * unlockedPercentage) / PRECISION;
    }
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
  function isValidKycSignature(
    address account,
    uint8 kycType,
    uint8 countryOfIDIssuance,
    uint8 countryOfResidence,
    bytes32 rootHash,
    bytes calldata issuerSignature
  ) public view returns (bool) {
    bytes32 signedMessageHash = ECDSA.toEthSignedMessageHash(
      keccak256(abi.encodePacked(account, kycType, countryOfIDIssuance, countryOfResidence, rootHash))
    );
    return ECDSA.recover(signedMessageHash, issuerSignature) == fractalIssuer;
  }

  /**
   * @dev Check if the account has allowed KYC parameters
   * @notice This function checks the kyc parameters, see: https://docs.developer.fractal.id/did-credentials
   * @param kycType The type of kyc
   * @param countryOfResidence The country of residence tier, see: https://bit.ly/46fC5Cq
   */
  function isValidKyc(
    uint8 kycType,
    uint8 countryOfResidence
  ) public pure returns (bool) {
    return (
      kycType == 1 && 
      countryOfResidence != 7 && 
      countryOfResidence < 9 && 
      countryOfResidence > 0
    );
  }
}
