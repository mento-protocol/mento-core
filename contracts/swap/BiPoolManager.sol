// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Ownable } from "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";

import { IERC20Metadata } from "../common/interfaces/IERC20Metadata.sol";
import { IExchangeProvider } from "../interfaces/IExchangeProvider.sol";
import { IBiPoolManager } from "../interfaces/IBiPoolManager.sol";
import { IReserve } from "../interfaces/IReserve.sol";
import { IPricingModule } from "../interfaces/IPricingModule.sol";
import { ISortedOracles } from "../interfaces/ISortedOracles.sol";
import { IBreakerBox } from "../interfaces/IBreakerBox.sol";

import { Initializable } from "../common/Initializable.sol";
import { FixidityLib } from "../common/FixidityLib.sol";

/**
 * @title BiPoolExchangeManager
 * @notice An exchange manager that manages asset exchanges consisting of two assets
 */
contract BiPoolManager is IExchangeProvider, IBiPoolManager, Initializable, Ownable {
  using FixidityLib for FixidityLib.Fraction;
  using SafeMath for uint256;

  /* ==================== State Variables ==================== */

  // Address of the broker contract.
  address public broker;

  // Maps an exchange id to the corresponding PoolExchange struct.
  // exchangeId is in the format "asset0Symbol:asset1Symbol:pricingModuleName"
  mapping(bytes32 => PoolExchange) public exchanges;
  bytes32[] public exchangeIds;

  uint256 private constant TRADING_MODE_BIDIRECTIONAL = 0;

  // Address of the Mento Reserve contract
  IReserve public reserve;

  // Address of the Mento BreakerBox contract
  IBreakerBox public breakerBox;

  // Address of the Mento SortedOracles contract
  ISortedOracles public sortedOracles;

  // Token precision multiplier used to normalize values to the
  // same precision when calculating vAMM bucket sizes.
  mapping(address => uint256) public tokenPrecisionMultipliers;

  bytes32 public constant CONSTANT_SUM = keccak256(abi.encodePacked("ConstantSum"));
  bytes32 public constant CONSTANT_PRODUCT = keccak256(abi.encodePacked("ConstantProduct"));

  // Maps a pricing module identifier to the address of the pricing module contract.
  mapping(bytes32 => address) public pricingModules;

  /* ==================== Constructor ==================== */

  /**
   * @notice Sets initialized == true on implementation contracts.
   * @param test Set to true to skip implementation initialization.
   */
  // solhint-disable-next-line no-empty-blocks
  constructor(bool test) public Initializable(test) {}

  /**
   * @notice Allows the contract to be upgradable via the proxy.
   * @param _broker The address of the broker contract.
   * @param _reserve The address of the reserve contract.
   * @param _sortedOracles The address of the sorted oracles contract.
   * @param _breakerBox The address of the breaker box contract.
   */
  function initialize(
    address _broker,
    IReserve _reserve,
    ISortedOracles _sortedOracles,
    IBreakerBox _breakerBox
  ) external initializer {
    _transferOwnership(msg.sender);
    setBroker(_broker);
    setReserve(_reserve);
    setSortedOracles(_sortedOracles);
    setBreakerBox(_breakerBox);
  }

  /* ==================== Modifiers ==================== */

  modifier onlyBroker() {
    require(msg.sender == broker, "Caller is not the Broker");
    _;
  }

  modifier verifyExchangeTokens(
    address tokenIn,
    address tokenOut,
    PoolExchange memory exchange
  ) {
    require(
      (tokenIn == exchange.asset0 && tokenOut == exchange.asset1) ||
        (tokenIn == exchange.asset1 && tokenOut == exchange.asset0),
      "tokenIn and tokenOut must match exchange"
    );
    _;
  }

  /* ==================== View Functions ==================== */

  /**
   * @notice Get a PoolExchange from storage.
   * @param exchangeId the exchange id
   */
  function getPoolExchange(bytes32 exchangeId) public view returns (PoolExchange memory exchange) {
    exchange = exchanges[exchangeId];
    require(exchange.asset0 != address(0), "An exchange with the specified id does not exist");
  }

  /**
   * @notice Get all exchange IDs.
   * @return exchangeIds List of the exchangeIds.
   */
  function getExchangeIds() external view returns (bytes32[] memory) {
    return exchangeIds;
  }

  /**
   * @notice Get all exchanges (used by interfaces)
   * @dev We don't expect the number of exchanges to grow to
   * astronomical values so this is safe gas-wise as is.
   */
  function getExchanges() public view returns (Exchange[] memory _exchanges) {
    uint256 numExchanges = exchangeIds.length;
    _exchanges = new Exchange[](numExchanges);
    for (uint256 i = 0; i < numExchanges; i++) {
      _exchanges[i].exchangeId = exchangeIds[i];
      _exchanges[i].assets = new address[](2);
      _exchanges[i].assets[0] = exchanges[exchangeIds[i]].asset0;
      _exchanges[i].assets[1] = exchanges[exchangeIds[i]].asset1;
    }
  }

  /**
   * @notice Calculate amountOut of tokenOut received for a given amountIn of tokenIn
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
  ) external view returns (uint256 amountOut) {
    PoolExchange memory exchange = getPoolExchange(exchangeId);
    uint256 scaledAmountIn = amountIn.mul(tokenPrecisionMultipliers[tokenIn]);
    (uint256 scaledAmountOut, ) = _getAmountOut(exchange, tokenIn, tokenOut, scaledAmountIn);
    amountOut = scaledAmountOut.div(tokenPrecisionMultipliers[tokenOut]);
    return amountOut;
  }

  /**
   * @notice Calculate amountIn of tokenIn for a given amountOut of tokenOut
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
  ) external view returns (uint256 amountIn) {
    PoolExchange memory exchange = getPoolExchange(exchangeId);
    uint256 scaledAmountOut = amountOut.mul(tokenPrecisionMultipliers[tokenOut]);
    (uint256 scaledAmountIn, ) = _getAmountIn(exchange, tokenIn, tokenOut, scaledAmountOut);
    amountIn = scaledAmountIn.div(tokenPrecisionMultipliers[tokenIn]);
    return amountIn;
  }

  /* ==================== Mutative Functions ==================== */

  /**
   * @notice Sets the address of the broker contract.
   * @param _broker The new address of the broker contract.
   */
  function setBroker(address _broker) public onlyOwner {
    require(_broker != address(0), "Broker address must be set");
    broker = _broker;
    emit BrokerUpdated(_broker);
  }

  /**
   * @notice Sets the address of the reserve contract.
   * @param _reserve The new address of the reserve contract.
   */
  function setReserve(IReserve _reserve) public onlyOwner {
    require(address(_reserve) != address(0), "Reserve address must be set");
    reserve = _reserve;
    emit ReserveUpdated(address(_reserve));
  }

  /**
   * @notice Sets the address of the BreakerBox.
   * @param _breakerBox The new BreakerBox address.
   */
  function setBreakerBox(IBreakerBox _breakerBox) public onlyOwner {
    require(address(_breakerBox) != address(0), "BreakerBox address must be set");
    breakerBox = _breakerBox;
    emit BreakerBoxUpdated(address(_breakerBox));
  }

  /**
   * @notice Sets the address of the sortedOracles contract.
   * @param _sortedOracles The new address of the sorted oracles contract.
   */
  function setSortedOracles(ISortedOracles _sortedOracles) public onlyOwner {
    require(address(_sortedOracles) != address(0), "SortedOracles address must be set");
    sortedOracles = _sortedOracles;
    emit SortedOraclesUpdated(address(_sortedOracles));
  }

  /**
   * @notice Updates the pricing modules for a list of identifiers
   * @dev This function can only be called by the owner of the contract.
   *      The number of identifiers and modules provided must be the same.
   * @param identifiers An array of identifiers for which the pricing modules are to be set.
   * @param modules An array of module addresses corresponding to each identifier.
   */
  function setPricingModules(bytes32[] calldata identifiers, address[] calldata modules) external onlyOwner {
    require(identifiers.length == modules.length, "identifiers and modules must be the same length");
    for (uint256 i = 0; i < identifiers.length; i++) {
      pricingModules[identifiers[i]] = modules[i];
    }
    emit PricingModulesUpdated(identifiers, modules);
  }

  /**
   * @notice Creates a new exchange using the given parameters.
   * @param _exchange the PoolExchange to create.
   * @return exchangeId The id of the newly created exchange.
   */
  function createExchange(PoolExchange calldata _exchange) external onlyOwner returns (bytes32 exchangeId) {
    PoolExchange memory exchange = _exchange;
    require(address(exchange.pricingModule) != address(0), "pricingModule must be set");
    require(exchange.asset0 != address(0), "asset0 must be set");
    require(exchange.asset1 != address(0), "asset1 must be set");
    require(exchange.asset0 != exchange.asset1, "exchange assets can't be identical");
    require(
      pricingModules[pricingModuleIdentifier(exchange)] == address(exchange.pricingModule),
      "invalid pricingModule"
    );

    // slither-disable-next-line encode-packed-collision
    exchangeId = keccak256(
      abi.encodePacked(
        IERC20Metadata(exchange.asset0).symbol(),
        IERC20Metadata(exchange.asset1).symbol(),
        exchange.pricingModule.name()
      )
    );
    require(exchanges[exchangeId].asset0 == address(0), "An exchange with the specified assets and exchange exists");

    validate(exchange);
    (uint256 bucket0, uint256 bucket1) = getUpdatedBuckets(exchange);

    exchange.bucket0 = bucket0;
    exchange.bucket1 = bucket1;

    uint256 asset0Decimals = IERC20Metadata(exchange.asset0).decimals();
    uint256 asset1Decimals = IERC20Metadata(exchange.asset1).decimals();

    require(asset0Decimals <= 18, "asset0 decimals must be <= 18");
    require(asset1Decimals <= 18, "asset1 decimals must be <= 18");

    tokenPrecisionMultipliers[exchange.asset0] = 10**(18 - uint256(asset0Decimals));
    tokenPrecisionMultipliers[exchange.asset1] = 10**(18 - uint256(asset1Decimals));

    exchanges[exchangeId] = exchange;
    // slither-disable-next-line controlled-array-length
    exchangeIds.push(exchangeId);

    emit ExchangeCreated(exchangeId, exchange.asset0, exchange.asset1, address(exchange.pricingModule));
  }

  /**
   * @notice Destroys a exchange with the given parameters if it exists and frees up
   *         the collateral and stable allocation it was using.
   * @param exchangeId the id of the exchange to destroy
   * @param exchangeIdIndex The index of the exchangeId in the ids array
   * @return destroyed A boolean indicating whether or not the exchange was successfully destroyed.
   */
  function destroyExchange(bytes32 exchangeId, uint256 exchangeIdIndex) external onlyOwner returns (bool destroyed) {
    require(exchangeIdIndex < exchangeIds.length, "exchangeIdIndex not in range");
    require(exchangeIds[exchangeIdIndex] == exchangeId, "exchangeId at index doesn't match");
    PoolExchange memory exchange = exchanges[exchangeId];

    delete exchanges[exchangeId];
    exchangeIds[exchangeIdIndex] = exchangeIds[exchangeIds.length.sub(1)];
    exchangeIds.pop();
    destroyed = true;

    emit ExchangeDestroyed(exchangeId, exchange.asset0, exchange.asset1, address(exchange.pricingModule));
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
  ) external onlyBroker returns (uint256 amountOut) {
    PoolExchange memory exchange = getPoolExchange(exchangeId);
    require(
      breakerBox.getRateFeedTradingMode(exchange.config.referenceRateFeedID) == TRADING_MODE_BIDIRECTIONAL,
      "Trading is suspended for this reference rate"
    );

    uint256 scaledAmountIn = amountIn.mul(tokenPrecisionMultipliers[tokenIn]);
    (uint256 scaledAmountOut, bool bucketsUpdated) = _getAmountOut(exchange, tokenIn, tokenOut, scaledAmountIn);
    executeSwap(exchangeId, exchange, tokenIn, scaledAmountIn, scaledAmountOut, bucketsUpdated);

    amountOut = scaledAmountOut.div(tokenPrecisionMultipliers[tokenOut]);
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
  ) external onlyBroker returns (uint256 amountIn) {
    PoolExchange memory exchange = getPoolExchange(exchangeId);
    require(
      breakerBox.getRateFeedTradingMode(exchange.config.referenceRateFeedID) == TRADING_MODE_BIDIRECTIONAL,
      "Trading is suspended for this reference rate"
    );

    uint256 scaledAmountOut = amountOut.mul(tokenPrecisionMultipliers[tokenOut]);
    (uint256 scaledAmountIn, bool bucketsUpdated) = _getAmountIn(exchange, tokenIn, tokenOut, scaledAmountOut);
    executeSwap(exchangeId, exchange, tokenIn, scaledAmountIn, scaledAmountOut, bucketsUpdated);

    amountIn = scaledAmountIn.div(tokenPrecisionMultipliers[tokenIn]);
    return amountIn;
  }

  /* ==================== Private Functions ==================== */

  /**
   * @notice Execute a swap against the in memory exchange and write
   *         the new bucket sizes to storage.
   * @dev In constant sum exchanges, the virtual bucket ratio serve as the reference price
   *      and should remain constant between bucket updates.
   *      Thats why the amounts of a swap are only applied for constant product exchanges.
   * @param exchangeId The id of the exchange
   * @param exchange The exchange to operate on
   * @param tokenIn The token to be sold
   * @param scaledAmountIn The amount of tokenIn to be sold scaled to 18 decimals
   * @param scaledAmountOut The amount of tokenOut to be bought scaled to 18 decimals
   * @param bucketsUpdated whether the buckets updated during the swap
   */
  function executeSwap(
    bytes32 exchangeId,
    PoolExchange memory exchange,
    address tokenIn,
    uint256 scaledAmountIn,
    uint256 scaledAmountOut,
    bool bucketsUpdated
  ) internal {
    if (bucketsUpdated) {
      // solhint-disable-next-line not-rely-on-time
      exchanges[exchangeId].lastBucketUpdate = now;
      emit BucketsUpdated(exchangeId, exchange.bucket0, exchange.bucket1);
    }

    if (isConstantProduct(exchange)) {
      if (tokenIn == exchange.asset0) {
        exchange.bucket0 = exchange.bucket0.add(scaledAmountIn);
        exchange.bucket1 = exchange.bucket1.sub(scaledAmountOut);
      } else {
        exchange.bucket0 = exchange.bucket0.sub(scaledAmountOut);
        exchange.bucket1 = exchange.bucket1.add(scaledAmountIn);
      }
    }

    exchanges[exchangeId].bucket0 = exchange.bucket0;
    exchanges[exchangeId].bucket1 = exchange.bucket1;
  }

  /**
   * @notice Calculate amountOut of tokenOut received for a given amountIn of tokenIn
   * @param exchange The exchange to operate on
   * @param tokenIn The token to be sold
   * @param tokenOut The token to be bought
   * @param scaledAmountIn The amount of tokenIn to be sold scaled to 18 decimals
   * @return scaledAmountOut The amount of tokenOut to be bought scaled to 18 decimals
   * @return bucketsUpdated Wether the buckets were updated during the quote
   */
  function _getAmountOut(
    PoolExchange memory exchange,
    address tokenIn,
    address tokenOut,
    uint256 scaledAmountIn
  )
    internal
    view
    verifyExchangeTokens(tokenIn, tokenOut, exchange)
    returns (uint256 scaledAmountOut, bool bucketsUpdated)
  {
    (exchange, bucketsUpdated) = updateBucketsIfNecessary(exchange);

    if (tokenIn == exchange.asset0) {
      scaledAmountOut = exchange.pricingModule.getAmountOut(
        exchange.bucket0,
        exchange.bucket1,
        exchange.config.spread.unwrap(),
        scaledAmountIn
      );
    } else {
      scaledAmountOut = exchange.pricingModule.getAmountOut(
        exchange.bucket1,
        exchange.bucket0,
        exchange.config.spread.unwrap(),
        scaledAmountIn
      );
    }
  }

  /**
   * @notice Calculate amountIn of tokenIn for a given amountOut of tokenOut
   * @param exchange The exchange to operate on
   * @param tokenIn The token to be sold
   * @param tokenOut The token to be bought
   * @param scaledAmountOut The amount of tokenOut to be bought scaled to 18 decimals
   * @return scaledAmountIn The amount of tokenIn to be sold scaled to 18 decimals
   * @return bucketsUpdated Whether the buckets were updated during the quote
   */
  function _getAmountIn(
    PoolExchange memory exchange,
    address tokenIn,
    address tokenOut,
    uint256 scaledAmountOut
  )
    internal
    view
    verifyExchangeTokens(tokenIn, tokenOut, exchange)
    returns (uint256 scaledAmountIn, bool bucketsUpdated)
  {
    (exchange, bucketsUpdated) = updateBucketsIfNecessary(exchange);

    if (tokenIn == exchange.asset0) {
      scaledAmountIn = exchange.pricingModule.getAmountIn(
        exchange.bucket0,
        exchange.bucket1,
        exchange.config.spread.unwrap(),
        scaledAmountOut
      );
    } else {
      scaledAmountIn = exchange.pricingModule.getAmountIn(
        exchange.bucket1,
        exchange.bucket0,
        exchange.config.spread.unwrap(),
        scaledAmountOut
      );
    }
  }

  /**
   * @notice If conditions are met, update the exchange bucket sizes.
   * @dev This doesn't checkpoint the exchange, just updates the in-memory one
   * so it should be used in a context that then checkpoints the exchange.
   * @param exchange The exchange being updated.
   * @return exchangeAfter The updated exchange.
   */
  function updateBucketsIfNecessary(PoolExchange memory exchange)
    internal
    view
    returns (PoolExchange memory, bool updated)
  {
    if (shouldUpdateBuckets(exchange)) {
      (exchange.bucket0, exchange.bucket1) = getUpdatedBuckets(exchange);
      updated = true;
    }
    return (exchange, updated);
  }

  /**
   * @notice Determine if a exchange's buckets should be updated
   * based on staleness of buckets and oracle rates.
   * @param exchange The PoolExchange.
   * @return shouldUpdate
   */
  function shouldUpdateBuckets(PoolExchange memory exchange) internal view returns (bool) {
    bool hasValidMedian = oracleHasValidMedian(exchange);
    if (isConstantSum(exchange)) {
      require(hasValidMedian, "no valid median");
    }
    // solhint-disable-next-line not-rely-on-time
    bool timePassed = now >= exchange.lastBucketUpdate.add(exchange.config.referenceRateResetFrequency);
    return timePassed && hasValidMedian;
  }

  /**
   * @notice Determine if the median is valid based on the current oracle rates.
   * @param exchange The PoolExchange.
   * @return HasValidMedian.
   */
  function oracleHasValidMedian(PoolExchange memory exchange) internal view returns (bool) {
    // solhint-disable-next-line not-rely-on-time
    // slither-disable-next-line unused-return
    (bool isReportExpired, ) = sortedOracles.isOldestReportExpired(exchange.config.referenceRateFeedID);
    bool enoughReports = (sortedOracles.numRates(exchange.config.referenceRateFeedID) >=
      exchange.config.minimumReports);
    // solhint-disable-next-line not-rely-on-time
    bool medianReportRecent = sortedOracles.medianTimestamp(exchange.config.referenceRateFeedID) >
      now.sub(exchange.config.referenceRateResetFrequency);
    return !isReportExpired && enoughReports && medianReportRecent;
  }

  /**
   * @notice Calculate the new bucket sizes for a exchange.
   * @param exchange The PoolExchange in context.
   * @return bucket0 The size of bucket0.
   * @return bucket1 The size of bucket1.
   */
  function getUpdatedBuckets(PoolExchange memory exchange) internal view returns (uint256 bucket0, uint256 bucket1) {
    bucket0 = exchange.config.stablePoolResetSize;
    uint256 exchangeRateNumerator;
    uint256 exchangeRateDenominator;
    (exchangeRateNumerator, exchangeRateDenominator) = getOracleExchangeRate(exchange.config.referenceRateFeedID);

    bucket1 = exchangeRateDenominator.mul(bucket0).div(exchangeRateNumerator);
  }

  /**
   * @notice Get the exchange rate as numerator,denominator from sorted oracles
   * and protect in case of a 0-denominator.
   * @param target the reportTarget to read from SortedOracles
   * @return rateNumerator
   * @return rateDenominator
   */
  function getOracleExchangeRate(address target)
    internal
    view
    returns (uint256 rateNumerator, uint256 rateDenominator)
  {
    (rateNumerator, rateDenominator) = sortedOracles.medianRate(target);
    require(rateDenominator > 0, "exchange rate denominator must be greater than 0");
  }

  /**
   * @notice Valitates a PoolExchange's parameters and configuration
   * @dev Reverts if not valid
   * @param exchange The PoolExchange to validate
   */
  function validate(PoolExchange memory exchange) private view {
    require(reserve.isStableAsset(exchange.asset0), "asset0 must be a stable registered with the reserve");
    require(
      reserve.isStableAsset(exchange.asset1) || reserve.isCollateralAsset(exchange.asset1),
      "asset1 must be a stable or collateral"
    );
    require(FixidityLib.lte(exchange.config.spread, FixidityLib.fixed1()), "spread must be less than or equal to 1");
    require(exchange.config.referenceRateFeedID != address(0), "referenceRateFeedID must be set");
  }

  /**
   * @notice Get the identifier of the pricing module used by a exchange
   * @param exchange The exchange to get the pricing module identifier for
   * @return The encoded and hashed identifier of the pricing module
   */
  function pricingModuleIdentifier(PoolExchange memory exchange) internal view returns (bytes32) {
    return keccak256(abi.encodePacked(exchange.pricingModule.name()));
  }

  /**
   * @notice Determine whether an exchange is using a constant sum pricing module
   * @param exchange The exchange to check
   * @return bool indicating if the exchange is using a constant sum pricing module
   */
  function isConstantSum(PoolExchange memory exchange) internal view returns (bool) {
    return pricingModuleIdentifier(exchange) == CONSTANT_SUM;
  }

  /**
   * @notice Determine whether an exchange is using a constant product pricing module
   * @param exchange The exchange to check
   * @return bool indicating if the exchange is using a constant product pricing module
   */
  function isConstantProduct(PoolExchange memory exchange) internal view returns (bool) {
    return pricingModuleIdentifier(exchange) == CONSTANT_PRODUCT;
  }
}
