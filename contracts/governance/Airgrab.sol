// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { MerkleProof } from "openzeppelin-contracts-next/contracts/utils/cryptography/MerkleProof.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/utils/SafeERC20.sol";
import { ECDSA } from "openzeppelin-contracts-next/contracts/utils/cryptography/ECDSA.sol";
import { Ownable } from "openzeppelin-contracts-next/contracts/access/Ownable.sol";
import { SignatureChecker } from "openzeppelin-contracts-next/contracts/utils/cryptography/SignatureChecker.sol";
import { Strings } from "openzeppelin-contracts-next/contracts/utils/Strings.sol";

import { ILocking } from "locking-contracts/ILocking.sol";

/**
 * @title Airgrab
 * @author Mento Labs
 * @notice This contract implements a token airgrab gated by a MerkeTree and KYC using fractal.
 * The airgrab also forces claimers to immediately lock their tokens as veTokens for a 
 * predetermined period.
 * @dev The contract is only Ownable because of the circular dependency
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
   * @param cliff The selected cliff period
   * @param slope The selected slope period
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
  /// @notice The Fractal Credential message signer for KYC/KYB.
  address public immutable fractalSigner;
  /// @notice The Fractal Credential maximum age in seconds
  uint256 public immutable fractalMaxAge;
  /// @notice The locking contract for veToken.
  ILocking public immutable lockingContract;
  /// @notice The treasury address where the tokens will be refunded.
  address payable public immutable treasury;
  /// @notice The timestamp when the airgrab ends.
  uint256 public immutable endTimestamp;
  /// @notice The slope period that the airgrab will be locked for.
  uint32 public immutable slopePeriod;
  /// @notice The cliff period that the airgrab will be locked for.
  uint32 public immutable cliffPeriod;

  /// @notice The map of addresses that have claimed
  mapping(address => bool) public claimed;
  /// @notice The token in the airgrab.
  IERC20 public token;

  /**
   * @dev Check if the account has a valid kyc signature. See: https://docs.developer.fractal.id/did-credentials
   * @notice This function checks the kyc signature with the data provided.
   * @param account The address of the account to check.
   * @param proof The kyc proof for the account.
   * @param validUntil The kyc proof valid until timestamp.
   * @param approvedAt The kyc proof approved at timestamp.
   * @param fractalId The kyc proof fractal id.
   */
  modifier hasValidKyc(
    address account,
    bytes memory proof,
    uint256 validUntil,
    uint256 approvedAt,
    string memory fractalId
  ) {
    require(block.timestamp < validUntil, "Airgrab: KYC no longer valid");
    require(
      fractalMaxAge == 0 || block.timestamp < approvedAt + fractalMaxAge,
      "Airgrab: KYC not recent enough"
    );
    string memory sender = Strings.toHexString(
        uint256(uint160(account)),
        20
    );

    bytes32 signedMessageHash = 
      ECDSA.toEthSignedMessageHash(
        abi.encodePacked(
          sender,
          ";",
          fractalId,
          ";",
          Strings.toString(approvedAt),
          ";",
          Strings.toString(validUntil),
          ";",
          //  TODO: if we parameterize this at the contract level
          // it has to go in storage because solidity only supports
          // immutable base types. One way to work around this would
          // be to record a hash of this string as an immutable
          // value during initialization and then pass the actual
          // string from the caller and just verify its hash.
          // Otherwise we can just keep it static here.
          "level:plus;residency_not:ca,us" 
        )
      );

    require(
      SignatureChecker.isValidSignatureNow(
        fractalSigner,
        signedMessageHash,
        proof
      ),
      "Airgrab: Invalid KYC"
    );

    _;
  }

  /**
   * @dev Check if the account can cliam
   * @notice This modifier checks if the airgrab is still active,
   * if the account hasn't already claimed and if it's incldued
   * in the MerkleTree.
   * @param account The address of the account to check.
   * @param amount The amount of tokens to be claimed.
   * @param merkleProof The merkle proof for the account.
   */
  modifier canClaim(
    address account,
    uint256 amount,
    bytes32[] calldata merkleProof
  ) {
    require(block.timestamp <= endTimestamp, "Airgrab: finished");
    require(!claimed[account], "Airgrab: already claimed");
    bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(account, uint256(amount)))));
    require(MerkleProof.verify(merkleProof, root, leaf), "Airgrab: not in tree");
    _;
  }


  /**
   * @dev Constructor for the Airgrab contract.
   * @notice It checks and configures all immutable params
   * @param root_ The root of the merkle tree.
   * @param fractalSigner_ The Fractal message signer for KYC/KYB.
   * @param fractalMaxAge_ The Fractal Credential maximum age in seconds.
   * @param treasury_ The treasury address where the tokens will be refunded.
   * @param endTimestamp_ The timestamp when the airgrab ends.
   * @param cliffPeriod_ The cliff period that the airgrab will be locked for.
   * @param slopePeriod_ The slope period that the airgrab will be locked for.
   */
  constructor(
    bytes32 root_,
    address fractalSigner_,
    uint256 fractalMaxAge_,
    address lockingContract_,
    address payable treasury_,
    uint256 endTimestamp_,
    uint32 cliffPeriod_,
    uint32 slopePeriod_
  ) {
    require(root_ != bytes32(0), "Airgrab: invalid root");
    require(fractalSigner_ != address(0), "Airgrab: invalid fractal issuer");
    require(lockingContract_ != address(0), "Airgrab: invalid locking contract");
    require(treasury_ != address(0), "Airgrab: invalid treasury");
    require(endTimestamp_ > block.timestamp, "Airgrab: invalid end timestamp");
    require(cliffPeriod_ <= MAX_CLIFF_PERIOD, "Airgrab: cliff period too large");
    require(slopePeriod_ <= MAX_SLOPE_PERIOD, "Airgrab: slope period too large");

    root = root_;
    fractalSigner = fractalSigner_;
    fractalMaxAge = fractalMaxAge_;
    lockingContract = ILocking(lockingContract_);
    treasury = treasury_;
    endTimestamp = endTimestamp_;
    cliffPeriod = cliffPeriod_;
    slopePeriod = slopePeriod_;
  }

  /**
   * @dev Initializer for setting the token address, will be called
   * immediately during deployment, but is intended only as a workaround
   * for the circular dependency between Token and Airgrab.
   * @notice Sets the token address, gives infinite approval to the locking contract
   * and renounces ownership.q
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
   * The function will calculate what portions of tokens gets unlocked depending on
   * the provided cliff and slope, and then either transfer dirrectly if the claimer
   * has chosen no cliff and no slope, or lock the tokens in the locking contract.
   * @notice This function can be called by anybody, but the (account, amount) pair
   * must be in the merkle tree, has to not have claimed yet, and must have
   * an associated KYC signature from Fractal. And the airgrab must not have ended.
   * @param account The address of the account to claim tokens for.
   * @param amount The amount of tokens to be claimed.
   * @param merkleProof The merkle proof for the account.
   * @param fractalProof The Fractal KYC proof for the account.
   * @param fractalProofValidUntil The Fractal KYC proof valid until timestamp.
   * @param fractalProofApprovedAt The Fractal KYC proof approved at timestamp.
   * @param fractalId The Fractal KYC ID.
   */
  function claim(
    address account,
    uint96 amount,
    bytes32[] calldata merkleProof,
    bytes calldata fractalProof,
    uint256 fractalProofValidUntil,
    uint256 fractalProofApprovedAt,
    string memory fractalId
  ) 
    hasValidKyc(account, fractalProof, fractalProofValidUntil, fractalProofApprovedAt, fractalId)
    canClaim(account, amount, merkleProof)
    external 
  {
    require(IERC20(token).balanceOf(address(this)) >= amount, "Airgrab: insufficient balance");

    claimed[account] = true;
    lockingContract.lock(account, address(0), amount, slopePeriod, cliffPeriod);
    emit TokensClaimed(account, amount, slopePeriod, cliffPeriod);
  }

  /**
   * @dev Allows the treasury to reclaim any tokens after the airgrab has ended.
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
}
