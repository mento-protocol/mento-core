// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { MerkleProof } from "openzeppelin-contracts-next/contracts/utils/cryptography/MerkleProof.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/utils/SafeERC20.sol";
import { ECDSA } from "openzeppelin-contracts-next/contracts/utils/cryptography/ECDSA.sol";
import { Ownable } from "openzeppelin-contracts-next/contracts/access/Ownable.sol";

import { ILocking } from "locking-contracts/ILocking.sol";

/**
 * @title Airgrab
 * @author Mento Labs
 * @notice This contract implements a token airgrab gated by a MerkeTree and KYC using fractal.
 * The airgrab also forces claimers to immediately lock their tokens as veTokens otherwise
 * their amount to claim gets scaled depending on the chosen cliff and slope periods,
 * see the `getUnlockedAmount` for more details.
 * @dev The contract is only Ownable and Initializable because of the circular dependency
 * between Token and Airgrab. We use the initialize method to set the token address
 * after the Token contract has been deployed, and renounce ownership.
 */
contract Airgrab is Ownable {
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
  /// @notice The locking contract for veToken.
  ILocking public immutable lockingContract;
  /// @notice The treasury address where the tokens will be refunded.
  address payable public immutable treasury;
  /// @notice The timestamp when the airgrab ends.
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
  /// @notice The token in the airgrab.
  IERC20 public token;

  /**
   * @dev Constructor for the Airgrab contract.
   * @notice It checks and configures all immutable params and gives infinite approval to the
   * locking contract.
   * @param root_ The root of the merkle tree.
   * @param fractalIssuer_ The Fractal.id message signer for KYC/KYB.
   * @param treasury_ The treasury address where the tokens will be refunded.
   * @param endTimestamp_ The timestamp when the airgrab ends.
   * @param basePercentage_ The percentage that will be received based on the cliff period
   * @param cliffPercentage_ The minimum cliff period required to receive the full cliffPercentage
   * @param requiredCliffPeriod_ The precentage that will be received based on the slop period
   * @param slopePercentage_ The minimum slope period required to receive the full slopePercentage
   * @param requiredSlopePeriod_ The minimum slope period required to receive the full slopePercentage
   */
  constructor(
    bytes32 root_,
    address fractalIssuer_,
    address lockingContract_,
    address payable treasury_,
    uint256 endTimestamp_,
    uint256 basePercentage_,
    uint256 cliffPercentage_,
    uint32 requiredCliffPeriod_,
    uint256 slopePercentage_,
    uint32 requiredSlopePeriod_
  ) {
    require(root_ != bytes32(0), "Airgrab: invalid root");
    require(fractalIssuer_ != address(0), "Airgrab: invalid fractal issuer");
    require(lockingContract_ != address(0), "Airgrab: invalid locking contract");
    require(treasury_ != address(0), "Airgrab: invalid treasury");
    require(endTimestamp_ > block.timestamp, "Airgrab: invalid end timestamp");
    require(
      basePercentage_ + cliffPercentage_ + slopePercentage_ == PRECISION,
      "Airgrab: unlock percentages must add up to 1"
    );
    require(requiredCliffPeriod_ <= MAX_CLIFF_PERIOD, "Airgrab: required cliff period too large");
    require(requiredSlopePeriod_ <= MAX_SLOPE_PERIOD, "Airgrab: required slope period too large");

    root = root_;
    fractalIssuer = fractalIssuer_;
    lockingContract = ILocking(lockingContract_);
    treasury = treasury_;
    endTimestamp = endTimestamp_;
    basePercentage = basePercentage_;
    cliffPercentage = cliffPercentage_;
    requiredCliffPeriod = requiredCliffPeriod_;
    slopePercentage = slopePercentage_;
    requiredSlopePeriod = requiredSlopePeriod_;
  }

  /**
   * @dev Initializer for setting the token address, will be called
   * immediately during deployment, but is intended only as a workaround
   * for the circular dependency between Token and Airgrab.
   * @notice Sets the token address, gives infinite approval to the locking contract
   * and renounces ownership.
   * @param token_ The token in the airgrab.
   */
  function initialize(address token_) external onlyOwner {
    require(token_ != address(0), "Airgrab: invalid token");
    token = IERC20(token_);
    token.approve(address(lockingContract), type(uint256).max);
    _transferOwnership(address(0));
  }

  /**
   * @dev Allows `account` to claim `amount` tokens if the merkle proof and kyc is valid.
   * The function will either calcualte what portions of tokens gets unlocked depending on
   * the provided cliff and slope, and they either transfer dirrectly if the claimer
   * has chose no cliff and no slpe, or lock the tokens in the locking contract.
   * @notice This function can only be called by the Fractal.id message signer and
   * only if the airgrab hasn't ended yet.
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
    require(block.timestamp <= endTimestamp, "Airgrab: finished");
    require(hasAirgrab(account, amount, merkleProof), "Airgrab: not in tree");
    require(
      isValidKycSignature(account, kycType, countryOfIDIssuance, countryOfResidence, rootHash, issuerSignature),
      "Airgrab: invalid kyc signer"
    );
    require(isValidKyc(kycType, countryOfResidence), "Airgrab: invalid kyc params");
    require(!claimed[account], "Airgrab: already claimed");
    require(IERC20(token).balanceOf(address(this)) >= amount, "Airgrab: insufficient balance");

    unlockedAmount = getUnlockedAmount(amount, slope, cliff);
    require(unlockedAmount <= type(uint96).max, "Airgrab: amount too large");

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
   * @notice This function can only be called if the airgrab has ended.
   * The function takes a token as a param in case the contract has been sent
   * tokens other than the airgrab token.
   */
  function drain(address tokenToDrain) external {
    require(block.timestamp > endTimestamp, "Airgrab: not finished");
    uint256 balance = IERC20(tokenToDrain).balanceOf(address(this));
    require(balance > 0, "Airgrab: nothing to drain");
    IERC20(tokenToDrain).safeTransfer(treasury, balance);
    emit TokensDrained(tokenToDrain, balance);
  }

  /**
   * @dev Check if the account is included in the airgrab.
   * @notice This function checks the merkletree with the data provided.
   * @param account The address of the account to check.
   * @param amount The amount of tokens to be claimed.
   * @param merkleProof The merkle proof for the account.
   */
  function hasAirgrab(
    address account,
    uint256 amount,
    bytes32[] calldata merkleProof
  ) public view returns (bool) {
    bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(account, amount))));
    return MerkleProof.verify(merkleProof, root, leaf);
  }

  /**
   * @notice Calculate the total unlocked amount based on the selected values for
   * slope and cliff and the percentage settings that the contract was deployed with.
   * @dev The logic behind this is that the unlocked amount has three components:
   * the base, cliff and slope percentages, which add up to 100%.
   *
   *  <------------------------ 100% ---------------------------->
   * | basePercentage |   cliffPercentage    |   slopePercentage  |
   *
   * The base percentage is always unlocked, and the cliff and slope percentages
   * are scaled linearly by the duration of the cliff and slope lock periods.
   *
   * unlockedPercentage =
   *   basePercentage +
   *   (cliff/requiredCliffPeriod) * cliffPercentage +
   *   (slope/requiredSlopePeriod) * slopePercentage
   * unlockedAmount = amount * unlockedPercentage
   *
   * **Example:**
   * basePercentage = 20%
   * cliffPercentage = 30%
   * slopePercentage = 50%
   * requiredSlopePeriod = 14 (~3months)
   * requiredCliffPeriod = 14 (~3months)
   *
   * | cliff | slope | unlockedPercentage     |
   * |-------|-------|------------------------|
   * | 0     | 0     | 20% +  0% +  0% =  20% |
   *  | 0     | 7     | 20% +  0% + 25% =  45% |
   *  | 14    | 0     | 20% + 30% +  0% =  50% |
   *  | 14    | 14    | 20% + 30% + 50% = 100% |
   *
   * @param amount The total amount that can be unlocked
   * @param slope The selected slope period
   * @param cliff The selected cliff period
   */
  function getUnlockedAmount(
    uint256 amount,
    uint32 slope,
    uint32 cliff
  ) public view returns (uint256 unlockedAmount) {
    uint256 unlockedPercentage = basePercentage;

    if (cliff >= requiredCliffPeriod) {
      unlockedPercentage += cliffPercentage;
    } else {
      unlockedPercentage += (uint256(cliff) * cliffPercentage) / uint256(requiredCliffPeriod);
    }

    if (slope >= requiredSlopePeriod) {
      unlockedPercentage += slopePercentage;
    } else {
      unlockedPercentage += (uint256(slope) * slopePercentage) / uint256(requiredSlopePeriod);
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
  function isValidKyc(uint8 kycType, uint8 countryOfResidence) public pure returns (bool) {
    return (kycType == 1 && countryOfResidence != 7 && countryOfResidence < 9 && countryOfResidence > 0);
  }
}
