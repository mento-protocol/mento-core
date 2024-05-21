// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { PausableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol";

import { IGoodDollarExchangeProvider } from "./interfaces/IGoodDollarExchangeProvider.sol";
import { IGoodDollarExpansionController } from "./interfaces/IGoodDollarExpansionController.sol";
import { ISortedOracles } from "./interfaces/ISortedOracles.sol";

import { Test, console } from "forge-std-next/Test.sol";
import { BancorExchangeProvider } from "./BancorExchangeProvider.sol";
import { UD60x18, convert, unwrap, wrap } from "prb-math/src/UD60x18.sol";

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

  // Maps the reserve asset address to the corresponding USD rate feed.
  mapping(address => address) public reserveAssetUSDRateFeed;

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
    require(msg.sender == address(expansionController), "Only Expansion Controller can call this function");
    _;
  }

  /* ==================== View Functions ==================== */

  /**
   * @notice Returns the current price of the pool in USD.
   * @param exchangeId The id of the pool to get the price for.
   * @return priceUSD The current continous price of the pool in USD.
   */
  function currentPriceUSD(bytes32 exchangeId) external view returns (uint256 priceUSD) {
    require(exchanges[exchangeId].reserveAsset != address(0), "Exchange does not exist");
    uint256 price = currentPrice(exchangeId);
    (uint256 numerator, uint256 denominator) = sortedOracles.medianRate(
      reserveAssetUSDRateFeed[exchanges[exchangeId].reserveAsset]
    );
    return unwrap(wrap(price).mul(wrap(numerator)).div(wrap(denominator)));
  }

  /**
   * @notice Calculate amountOut of tokenOut received for a given amountIn of tokenIn
   * @dev applies expansion if nessesary
   * @param exchangeId The id of the exchange i.e PoolExchange to use
   * @param tokenIn The token to be sold
   * @param tokenOut The token to be bought
   * @param amountIn The amount of tokenIn to be sold
   * @return amountOut The amount of tokenOut to be bought
   */
  function getAmountOut(
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  ) external view override returns (uint256 amountOut) {
    PoolExchange memory exchange = getPoolExchange(exchangeId);
    uint32 expansionRate = expansionController.getCurrentExpansionRate(exchangeId);
    if (expansionRate > 0) {
      (exchange, ) = _calculateExpansion(exchangeId, expansionRate);
    }

    uint256 scaledAmountIn = amountIn * tokenPrecisionMultipliers[tokenIn];
    uint256 scaledAmountOut = _getAmountOut(exchange, tokenIn, tokenOut, scaledAmountIn);
    amountOut = scaledAmountOut / tokenPrecisionMultipliers[tokenOut];
    return amountOut;
  }

  /**
   * @notice Calculate amountIn of tokenIn for a given amountOut of tokenOut
   * @dev applies expansion if nessesary
   * @param exchangeId The id of the exchange i.e PoolExchange to use
   * @param tokenIn The token to be sold
   * @param tokenOut The token to be bought
   * @param amountOut The amount of tokenOut to be bought
   * @return amountIn The amount of tokenIn to be sold
   */
  function getAmountIn(
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountOut
  ) external view override returns (uint256 amountIn) {
    PoolExchange memory exchange = getPoolExchange(exchangeId);
    uint32 expansionRate = expansionController.getCurrentExpansionRate(exchangeId);
    if (expansionRate > 0) {
      (exchange, ) = _calculateExpansion(exchangeId, expansionRate);
    }
    uint256 scaledAmountOut = amountOut * tokenPrecisionMultipliers[tokenOut];
    uint256 scaledAmountIn = _getAmountIn(exchange, tokenIn, tokenOut, scaledAmountOut);
    amountIn = scaledAmountIn / tokenPrecisionMultipliers[tokenIn];
    return amountIn;
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
   * @notice Sets the address of the USD rate feed for the given reserve asset.
   * @param _reserveAsset The address of the reserve asset.
   * @param _usdRateFeed The address of the USD rate feed for the reserve asset.
   */
  function setReserveAssetUSDRateFeed(address _reserveAsset, address _usdRateFeed) public onlyOwner {
    require(reserve.isCollateralAsset(_reserveAsset), "Reserve asset must be a collateral asset");
    require(sortedOracles.numRates(_usdRateFeed) > 0, "USD rate feed must have rates");
    reserveAssetUSDRateFeed[_reserveAsset] = _usdRateFeed;
  }

  /**
   * @notice Creates a new exchange with the given parameters.
   * @param _exchange The PoolExchange struct holding the exchange parameters.
   * @param _usdRateFeed The address of the USD rate feed for the reserve asset.
   * @return exchangeId The id of the newly created exchange.
   */
  function createExchange(PoolExchange calldata _exchange, address _usdRateFeed)
    external
    onlyOwner
    returns (bytes32 exchangeId)
  {
    setReserveAssetUSDRateFeed(_exchange.reserveAsset, _usdRateFeed);
    exchangeId = createExchange(_exchange);
    return exchangeId;
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
  ) external override onlyBroker returns (uint256 amountOut) {
    if (expansionController.shouldExpand(exchangeId)) {
      expansionController.mintUBIFromExpansion(exchangeId);
    }

    PoolExchange memory exchange = getPoolExchange(exchangeId);
    uint256 scaledAmountIn = amountIn * tokenPrecisionMultipliers[tokenIn];
    uint256 scaledAmountOut = _getAmountOut(exchange, tokenIn, tokenOut, scaledAmountIn);
    executeSwap(exchangeId, tokenIn, scaledAmountIn, scaledAmountOut);

    amountOut = scaledAmountOut / tokenPrecisionMultipliers[tokenOut];
    return amountOut;
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
  ) external override onlyBroker returns (uint256 amountIn) {
    if (expansionController.shouldExpand(exchangeId)) {
      expansionController.mintUBIFromExpansion(exchangeId);
    }

    PoolExchange memory exchange = getPoolExchange(exchangeId);
    uint256 scaledAmountOut = amountOut * tokenPrecisionMultipliers[tokenOut];
    uint256 scaledAmountIn = _getAmountIn(exchange, tokenIn, tokenOut, scaledAmountOut);
    executeSwap(exchangeId, tokenIn, scaledAmountIn, scaledAmountOut);

    amountIn = scaledAmountIn / tokenPrecisionMultipliers[tokenIn];
    return amountIn;
  }

  /**
   * @notice Calculates the amount of tokens to be minted as a result of expansion.
   * @dev Calculates the amount of tokens that need to be minted as a result of the expansion
   *      while keeping the current price the same.
   *      calculation: amountToMint = tokenSupply * newRatio - tokenSupply * reserveRatio / newRatio
   * @param exchangeId The id of the pool to calculate expansion for.
   * @param expansionRate The rate of expansion.
   * @return amountToMint amount of tokens to be minted as a result of the expansion.
   */
  function calculateExpansion(bytes32 exchangeId, uint32 expansionRate)
    external
    onlyExpansionController
    returns (uint256 amountToMint)
  {
    (PoolExchange memory exchange, uint256 scaledAmountToMint) = _calculateExpansion(exchangeId, expansionRate);

    exchanges[exchangeId].tokenSupply = exchange.tokenSupply;
    exchanges[exchangeId].reserveRatio = exchange.reserveRatio;
    emit ReserveRatioUpdated(exchangeId, exchange.reserveRatio);

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
  function calculateInterest(bytes32 exchangeId, uint256 reserveInterest)
    external
    onlyExpansionController
    returns (uint256 amountToMint)
  {
    PoolExchange memory exchange = getPoolExchange(exchangeId);
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
  function calculateRatioForReward(bytes32 exchangeId, uint256 reward) external onlyExpansionController {
    PoolExchange memory exchange = getPoolExchange(exchangeId);

    uint256 currentPriceScaled = currentPrice(exchangeId) * tokenPrecisionMultipliers[exchange.reserveAsset];
    uint256 rewardScaled = reward * tokenPrecisionMultipliers[exchange.tokenAddress];

    UD60x18 numerator = wrap(exchange.reserveBalance);
    UD60x18 denominator = wrap(exchange.tokenSupply + rewardScaled).mul(wrap(currentPriceScaled));
    uint256 newRatioScaled = unwrap(numerator.div(denominator));

    exchanges[exchangeId].reserveRatio = uint32(newRatioScaled / 1e12);
    exchanges[exchangeId].tokenSupply += rewardScaled;

    emit ReserveRatioUpdated(exchangeId, exchange.reserveRatio);
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

  /* ==================== Private Functions ==================== */

  /**
   * @notice Calculates the amount of tokens to be minted as a result of expansion.
   * @dev Calculates the amount of tokens that need to be minted as a result of the expansion
   *      while keeping the current price the same.
   *      calculation: amountToMint = tokenSupply * newRatio - tokenSupply * reserveRatio / newRatio
   * @param exchangeId The id of the pool to calculate expansion for.
   * @param expansionRate The rate of expansion.
   * @return exchange The updated PoolExchange struct.
   * @return amountToMint amount of tokens to be minted as a result of the expansion.
   */
  function _calculateExpansion(bytes32 exchangeId, uint32 expansionRate)
    internal
    view
    returns (PoolExchange memory exchange, uint256 amountToMint)
  {
    PoolExchange memory exchange = getPoolExchange(exchangeId);

    UD60x18 scaledExpansion = wrap(uint256(expansionRate) * 1e12);
    UD60x18 scaledRatio = wrap(uint256(exchange.reserveRatio) * 1e12);
    UD60x18 newRatio = scaledRatio.mul(scaledExpansion);

    UD60x18 numerator = wrap(exchange.tokenSupply).mul(scaledRatio);
    numerator = numerator.sub(wrap(exchange.tokenSupply).mul(newRatio));

    uint256 scaledAmountToMint = unwrap(numerator.div(newRatio));

    exchange.tokenSupply += scaledAmountToMint;
    exchange.reserveRatio = uint32(unwrap(newRatio) / 1e12);

    return (exchange, scaledAmountToMint);
  }
}
