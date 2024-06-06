// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { PausableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol";

import { IGoodDollarExchangeProvider } from "./interfaces/IGoodDollarExchangeProvider.sol";
import { IGoodDollarExpansionController } from "./interfaces/IGoodDollarExpansionController.sol";
import { ISortedOracles } from "./interfaces/ISortedOracles.sol";

import { Test, console } from "forge-std-next/Test.sol";
import { BancorExchangeProvider } from "./BancorExchangeProvider.sol";
import { UD60x18, unwrap, wrap } from "prb-math/src/UD60x18.sol";

/**
 * @title GoodDollarExchangeProvider
 * @notice Provides exchange functionality for the GoodDollar system.
 */
contract GoodDollarExchangeProvider is IGoodDollarExchangeProvider, BancorExchangeProvider, PausableUpgradeable {
  /* ==================== State Variables ==================== */

  // Address of the Mento Sorted Oracles contract.
  ISortedOracles public sortedOracles;

  // Address of the Expansion Controller contract.
  IGoodDollarExpansionController public expansionController;

  // Address of the GoodDollar DAO contract.
  address public AVATAR;

  /* ==================== Constructor ==================== */

  /**
   * @dev Should be called with disable=true in deployments when
   * it's accessed through a Proxy.
   * Call this with disable=false during testing, when used
   * without a proxy.
   * @param disable Set to true to run `_disableInitializers()` inherited from
   * openzeppelin-contracts-upgradeable/Initializable.sol
   */
  constructor(bool disable) BancorExchangeProvider(disable) {}

  /**
   * @notice Initializes the contract with the given parameters.
   * @param _broker The address of the Broker contract.
   * @param _reserve The address of the Reserve contract.
   * @param _sortedOracles The address of the SortedOracles contract.
   * @param _expansionController The address of the ExpansionController contract.
   * @param _avatar The address of the GoodDollar DAO contract.
   */
  function initialize(
    address _broker,
    address _reserve,
    address _sortedOracles,
    address _expansionController,
    address _avatar
  ) public initializer {
    BancorExchangeProvider._initialize(_broker, _reserve);
    __Pausable_init();

    setSortedOracles(_sortedOracles);
    setExpansionController(_expansionController);
    setAvatar(_avatar);
  }

  /* ==================== Modifiers ==================== */

  modifier onlyAvatar() {
    require(msg.sender == AVATAR, "Only Avatar can call this function");
    _;
  }

  modifier onlyExpansionController() {
    require(msg.sender == address(expansionController), "Only ExpansionController can call this function");
    _;
  }

  /* ==================== Mutative Functions ==================== */

  /**
   * @notice Sets the address of the GoodDollar DAO contract.
   * @param _avatar The address of the DAO contract.
   */
  function setAvatar(address _avatar) public onlyOwner {
    require(_avatar != address(0), "Avatar address must be set");
    AVATAR = _avatar;
    emit AvatarUpdated(_avatar);
  }

  /**
   * @notice Sets the address of the Expansion Controller contract.
   * @param _expansionController The address of the Expansion Controller contract.
   */
  function setExpansionController(address _expansionController) public onlyOwner {
    require(_expansionController != address(0), "ExpansionController address must be set");
    expansionController = IGoodDollarExpansionController(_expansionController);
    emit ExpansionControllerUpdated(_expansionController);
  }

  /**
   * @notice Sets the address of the SortedOracles contract.
   * @param _sortedOracles The address of the SortedOracles contract.
   */
  function setSortedOracles(address _sortedOracles) public onlyOwner {
    require(_sortedOracles != address(0), "SortedOracles address must be set");
    sortedOracles = ISortedOracles(_sortedOracles);
    emit SortedOraclesUpdated(_sortedOracles);
  }

  /**
   * @notice Execute a token swap with fixed amountIn
   * @param exchangeId The id of exchange, i.e. PoolExchange to use
   * @param tokenIn The token to be sold
   * @param tokenOut The token to be bought
   * @param amountIn The amount of tokenIn to be sold
   * @return amountOut The amount of tokenOut to be bought
   */
  function swapIn(
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  ) public override onlyBroker whenNotPaused returns (uint256 amountOut) {
    amountOut = BancorExchangeProvider.swapIn(exchangeId, tokenIn, tokenOut, amountIn);
  }

  /**
   * @notice Execute a token swap with fixed amountOut
   * @param exchangeId The id of exchange, i.e. PoolExchange to use
   * @param tokenIn The token to be sold
   * @param tokenOut The token to be bought
   * @param amountOut The amount of tokenOut to be bought
   * @return amountIn The amount of tokenIn to be sold
   */
  function swapOut(
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountOut
  ) public override onlyBroker whenNotPaused returns (uint256 amountIn) {
    amountIn = BancorExchangeProvider.swapOut(exchangeId, tokenIn, tokenOut, amountOut);
  }

  /**
   * @notice Calculates the amount of tokens to be minted as a result of expansion.
   * @dev Calculates the amount of tokens that need to be minted as a result of the expansion
   *      while keeping the current price the same.
   *      calculation: amountToMint = (tokenSupply * reserveRatio - tokenSupply * newRatio) / newRatio
   * @param exchangeId The id of the pool to calculate expansion for.
   * @param expansionScaler Scaler for calculating the new reserve ratio.
   * @return amountToMint amount of tokens to be minted as a result of the expansion.
   */
  function mintFromExpansion(bytes32 exchangeId, uint256 expansionScaler)
    external
    onlyExpansionController
    whenNotPaused
    returns (uint256 amountToMint)
  {
    require(expansionScaler > 0, "Expansion rate must be greater than 0");
    PoolExchange memory exchange = getPoolExchange(exchangeId);

    if (expansionScaler == MAX_WEIGHT) {
      return 0;
    }

    UD60x18 scaledRatio = wrap(uint256(exchange.reserveRatio) * 1e12);
    UD60x18 newRatio = scaledRatio.mul(wrap(expansionScaler));

    UD60x18 numerator = wrap(exchange.tokenSupply).mul(scaledRatio);
    numerator = numerator.sub(wrap(exchange.tokenSupply).mul(newRatio));

    uint256 scaledAmountToMint = unwrap(numerator.div(newRatio));

    uint32 newRatioUint = uint32(unwrap(newRatio) / 1e12);
    exchanges[exchangeId].reserveRatio = newRatioUint;
    emit ReserveRatioUpdated(exchangeId, newRatioUint);

    exchanges[exchangeId].tokenSupply += scaledAmountToMint;

    amountToMint = scaledAmountToMint / tokenPrecisionMultipliers[exchange.tokenAddress];
    return amountToMint;
  }

  /**
   * @notice Calculates the amount of tokens to be minted as a result of collecting the reserve interest.
   * @dev Calculates the amount of tokens that need to be minted as a result of the reserve interest
   *      flowing into the reserve while keeping the current price the same.
   *      calculation: amountToMint = reserveInterest * tokenSupply / reserveBalance
   * @param exchangeId The id of the pool the reserve interest is added to.
   * @param reserveInterest The amount of reserve tokens collected from interest.
   * @return amountToMint amount of tokens to be minted as a result of the reserve interest.
   */
  function mintFromInterest(bytes32 exchangeId, uint256 reserveInterest)
    external
    onlyExpansionController
    whenNotPaused
    returns (uint256 amountToMint)
  {
    PoolExchange memory exchange = getPoolExchange(exchangeId);

    if (reserveInterest == 0) {
      return 0;
    }

    uint256 reserveinterestScaled = reserveInterest * tokenPrecisionMultipliers[exchange.reserveAsset];
    uint256 amountToMintScaled = unwrap(
      wrap(reserveinterestScaled).mul(wrap(exchange.tokenSupply)).div(wrap(exchange.reserveBalance))
    );
    amountToMint = amountToMintScaled / tokenPrecisionMultipliers[exchange.tokenAddress];

    exchanges[exchangeId].tokenSupply += amountToMintScaled;
    exchanges[exchangeId].reserveBalance += reserveinterestScaled;

    return amountToMint;
  }

  /**
   * @notice Calculates the reserve ratio needed to mint the reward.
   * @dev Calculates the new reserve ratio needed to mint the reward while keeping the current price the same.
   *      calculation: newRatio = reserveBalance / (tokenSupply + reward) * currentPrice
   * @param exchangeId The id of the pool the reward is minted from.
   * @param reward The amount of tokens to be minted as a reward.
   */
  function updateRatioForReward(bytes32 exchangeId, uint256 reward) external onlyExpansionController whenNotPaused {
    PoolExchange memory exchange = getPoolExchange(exchangeId);

    if (reward == 0) {
      return;
    }

    uint256 currentPriceScaled = currentPrice(exchangeId) * tokenPrecisionMultipliers[exchange.reserveAsset];
    uint256 rewardScaled = reward * tokenPrecisionMultipliers[exchange.tokenAddress];

    UD60x18 numerator = wrap(exchange.reserveBalance);
    UD60x18 denominator = wrap(exchange.tokenSupply + rewardScaled).mul(wrap(currentPriceScaled));
    uint256 newRatioScaled = unwrap(numerator.div(denominator));

    uint32 newRatioUint = uint32(newRatioScaled / 1e12);
    exchanges[exchangeId].reserveRatio = newRatioUint;
    emit ReserveRatioUpdated(exchangeId, newRatioUint);

    exchanges[exchangeId].tokenSupply += rewardScaled;
  }

  /**
   * @notice Pauses the contract.
   * @dev Functions is only callable by the GoodDollar DAO contract.
   */
  function pause() external virtual onlyAvatar {
    _pause();
  }

  /**
   * @notice Unpauses the contract.
   * @dev Functions is only callable by the GoodDollar DAO contract.
   */
  function unpause() external virtual onlyAvatar {
    _unpause();
  }
}
