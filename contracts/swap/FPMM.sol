// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { IFPMM } from "../interfaces/IFPMM.sol";
import { ERC20Upgradeable } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { ReentrancyGuard } from "openzeppelin-contracts-next/contracts/security/ReentrancyGuard.sol";
import { Math } from "openzeppelin-contracts-next/contracts/utils/math/Math.sol";
import { SafeERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20MintableBurnable as IERC20 } from "contracts/common/IERC20MintableBurnable.sol";
import { ISortedOracles } from "../interfaces/ISortedOracles.sol";
import { IFPMMCallee } from "../interfaces/IFPMMCallee.sol";
import { IBreakerBox } from "../interfaces/IBreakerBox.sol";

/**
 * @title Fixed Price Market Maker (FPMM)
 * @author Mento Labs
 * @notice This contract implements a fixed price market maker that manages a liquidity pool
 * of two tokens and facilitates swaps between them based on oracle rates and potential fallback
 * to internal pricing.
 */
contract FPMM is IFPMM, ReentrancyGuard, ERC20Upgradeable, OwnableUpgradeable {
  using SafeERC20 for IERC20;

  /* ========== CONSTANTS ========== */

  /// @notice Minimum liquidity that will be locked forever when creating a pool
  uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

  /// @notice Trading mode value for bidirectional trading from circuit breaker
  uint256 private constant TRADING_MODE_BIDIRECTIONAL = 0;

  /* ========== STATE VARIABLES ========== */

  /// @notice Address of the first token in the pair
  address public token0;

  /// @notice Address of the second token in the pair
  address public token1;

  /// @notice Scaling factor for token0 based on its decimals
  uint256 public decimals0;

  /// @notice Scaling factor for token1 based on its decimals
  uint256 public decimals1;

  /// @notice Reserve amount of token0
  uint256 public reserve0;

  /// @notice Reserve amount of token1
  uint256 public reserve1;

  /// @notice Timestamp of the last reserve update
  uint256 public blockTimestampLast;

  /// @notice Contract for oracle price feeds
  ISortedOracles public sortedOracles;

  /// @notice Circuit breaker contract to enable/disable trading
  IBreakerBox public breakerBox;

  /// @notice Reference rate feed ID for oracle price
  address public referenceRateFeedID;

  /// @notice Protocol fee in basis points (1 basis point = .01%)
  uint256 public protocolFee;

  /// @notice Slippage allowed for rebalance operations in basis points
  uint256 public rebalanceIncentive;

  /// @notice Threshold for triggering rebalance in basis points
  uint256 public rebalanceThreshold;

  /// @notice Mapping to track trusted contracts that can use the rebalance function
  mapping(address => bool) public liquidityStrategy;

  /// @notice Struct to store swap data
  struct SwapData {
    uint256 rateNumerator;
    uint256 rateDenominator;
    uint256 initialReserveValue;
    uint256 initialPriceDifference;
    uint256 amount0In;
    uint256 amount1In;
  }

  /* ========== EVENTS ========== */

  /**
   * @notice Emitted when tokens are swapped
   * @param sender Address that initiated the swap
   * @param amount0In Amount of token0 sent to the pool
   * @param amount1In Amount of token1 sent to the pool
   * @param amount0Out Amount of token0 sent to the receiver
   * @param amount1Out Amount of token1 sent to the receiver
   * @param to Address receiving the output tokens
   */
  event Swap(
    address indexed sender,
    uint256 amount0In,
    uint256 amount1In,
    uint256 amount0Out,
    uint256 amount1Out,
    address indexed to
  );

  /**
   * @notice Emitted when liquidity is added to the pool
   * @param sender Address that initiated the mint
   * @param amount0 Amount of token0 added
   * @param amount1 Amount of token1 added
   * @param liquidity Amount of LP tokens minted
   */
  event Mint(address indexed sender, uint256 amount0, uint256 amount1, uint256 liquidity);

  /**
   * @notice Emitted when liquidity is removed from the pool
   * @param sender Address that initiated the burn
   * @param amount0 Amount of token0 removed
   * @param amount1 Amount of token1 removed
   * @param liquidity Amount of LP tokens burned
   * @param to Address receiving the tokens
   */
  event Burn(address indexed sender, uint256 amount0, uint256 amount1, uint256 liquidity, address indexed to);

  /**
   * @notice Emitted when the protocol fee is updated
   * @param oldFee Previous fee in basis points
   * @param newFee New fee in basis points
   */
  event ProtocolFeeUpdated(uint256 oldFee, uint256 newFee);

  /**
   * @notice Emitted when the rebalance incentive is updated
   * @param oldIncentive Previous incentive in basis points
   * @param newIncentive New incentive in basis points
   */
  event RebalanceIncentiveUpdated(uint256 oldIncentive, uint256 newIncentive);

  /**
   * @notice Emitted when the rebalance threshold is updated
   * @param oldThreshold Previous threshold in basis points
   * @param newThreshold New threshold in basis points
   */
  event RebalanceThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

  /**
   * @notice Emitted when a liquidity strategy status is updated
   * @param strategy Address of the strategy
   * @param status New status (true = enabled, false = disabled)
   */
  event LiquidityStrategyUpdated(address indexed strategy, bool status);

  /**
   * @notice Emitted when the reference rate feed ID is updated
   * @param oldRateFeedID Previous rate feed ID
   * @param newRateFeedID New rate feed ID
   */
  event ReferenceRateFeedIDUpdated(address oldRateFeedID, address newRateFeedID);

  /**
   * @notice Emitted when the SortedOracles contract is updated
   * @param oldSortedOracles Previous SortedOracles address
   * @param newSortedOracles New SortedOracles address
   */
  event SortedOraclesUpdated(address oldSortedOracles, address newSortedOracles);

  /**
   * @notice Emitted when the BreakerBox contract is updated
   * @param oldBreakerBox Previous BreakerBox address
   * @param newBreakerBox New BreakerBox address
   */
  event BreakerBoxUpdated(address oldBreakerBox, address newBreakerBox);

  /**
   * @notice Emitted when a successful rebalance operation occurs
   * @param sender Address that initiated the rebalance
   * @param priceDifferenceBefore Price difference before rebalance in basis points
   * @param priceDifferenceAfter Price difference after rebalance in basis points
   */
  event Rebalanced(address indexed sender, uint256 priceDifferenceBefore, uint256 priceDifferenceAfter);

  /**
   * @notice Emitted when reserves are synchronized
   * @param reserve0 Updated amount of token0 in reserve
   * @param reserve1 Updated amount of token1 in reserve
   * @param blockTimestamp Current block timestamp
   */
  event SyncReserves(uint256 reserve0, uint256 reserve1, uint256 blockTimestamp);

  /* ========== CONSTRUCTOR ========== */

  /**
   * @notice Contract constructor
   * @param disable Boolean to disable initializers for implementation contract
   */
  constructor(bool disable) {
    if (disable) {
      _disableInitializers();
    }
  }

  /* ========== INITIALIZATION ========== */

  /**
   * @notice Initializes the FPMM contract
   * @param _token0 Address of the first token
   * @param _token1 Address of the second token
   * @param _sortedOracles Address of the SortedOracles contract
   * @param _breakerBox Address of the BreakerBox contract
   */
  function initialize(
    address _token0,
    address _token1,
    address _sortedOracles,
    address _breakerBox
  ) external initializer {
    (token0, token1) = (_token0, _token1);

    string memory symbol0 = ERC20Upgradeable(_token0).symbol();
    string memory symbol1 = ERC20Upgradeable(_token1).symbol();

    string memory name_ = string(abi.encodePacked("Mento Fixed Price MM - ", symbol0, "/", symbol1));
    string memory symbol_ = string(abi.encodePacked("FPMM-", symbol0, "/", symbol1));

    __ERC20_init(name_, symbol_);
    __Ownable_init();

    decimals0 = 10 ** ERC20Upgradeable(_token0).decimals();
    decimals1 = 10 ** ERC20Upgradeable(_token1).decimals();

    protocolFee = 30; // .3% fee (30 basis points)
    rebalanceIncentive = 50; // Default .5% incentive tolerance (50 basis points)
    rebalanceThreshold = 500; // Default 5% rebalance threshold (500 basis points)

    setSortedOracles(_sortedOracles);
    setBreakerBox(_breakerBox);
  }

  /* ========== VIEW FUNCTIONS ========== */

  /**
   * @notice Returns pool metadata
   * @return dec0 Scaling factor for token0
   * @return dec1 Scaling factor for token1
   * @return r0 Reserve amount of token0
   * @return r1 Reserve amount of token1
   * @return t0 Address of token0
   * @return t1 Address of token1
   */
  function metadata()
    external
    view
    returns (uint256 dec0, uint256 dec1, uint256 r0, uint256 r1, address t0, address t1)
  {
    return (decimals0, decimals1, reserve0, reserve1, token0, token1);
  }

  /**
   * @notice Returns addresses of both tokens in the pair
   * @return Address of token0 and token1
   */
  function tokens() external view returns (address, address) {
    return (token0, token1);
  }

  /**
   * @notice Returns current reserves and timestamp
   * @return _reserve0 Current reserve of token0
   * @return _reserve1 Current reserve of token1
   * @return _blockTimestampLast Timestamp of last reserve update
   */
  function getReserves() public view returns (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast) {
    _reserve0 = reserve0;
    _reserve1 = reserve1;
    _blockTimestampLast = blockTimestampLast;
  }

  /**
   * @notice Calculates total value of a given amount of tokens in terms of token1
   * @param amount0 Amount of token0
   * @param amount1 Amount of token1
   * @param rateNumerator Oracle rate numerator
   * @param rateDenominator Oracle rate denominator
   * @return Total value in token1
   */
  function totalValueInToken1(
    uint256 amount0,
    uint256 amount1,
    uint256 rateNumerator,
    uint256 rateDenominator
  ) public view returns (uint256) {
    uint256 token0ValueInToken1 = convertWithRate(amount0, decimals0, decimals1, rateNumerator, rateDenominator);
    return token0ValueInToken1 + amount1;
  }

  /**
   * @notice Gets current oracle and reserve prices
   * @return oraclePrice Oracle price in 18 decimals
   * @return reservePrice Pool reserve price in 18 decimals
   * @return _decimals0 Scaling factor for token0
   * @return _decimals1 Scaling factor for token1
   */
  function getPrices()
    public
    view
    returns (uint256 oraclePrice, uint256 reservePrice, uint256 _decimals0, uint256 _decimals1)
  {
    require(referenceRateFeedID != address(0), "FPMM: REFERENCE_RATE_NOT_SET");
    require(reserve0 > 0 && reserve1 > 0, "FPMM: RESERVES_EMPTY");

    _decimals0 = decimals0;
    _decimals1 = decimals1;

    (uint256 rateNumerator, uint256 rateDenominator) = sortedOracles.medianRate(referenceRateFeedID);

    oraclePrice = (rateNumerator * 1e18) / (rateDenominator);
    reservePrice = (reserve1 * _decimals0 * 1e18) / (reserve0 * _decimals1);
  }

  /**
   * @notice Calculates output amount for a given input
   * @param amountIn Input amount
   * @param tokenIn Address of input token
   * @return amountOut Output amount after fees
   */
  function getAmountOut(uint256 amountIn, address tokenIn) public view returns (uint256 amountOut) {
    require(tokenIn == token0 || tokenIn == token1, "FPMM: INVALID_TOKEN");

    if (amountIn == 0) return 0;

    (uint256 rateNumerator, uint256 rateDenominator) = sortedOracles.medianRate(referenceRateFeedID);

    uint256 amountInAfterFee = amountIn - ((amountIn * protocolFee) / 10000);

    if (tokenIn == token0) {
      return convertWithRate(amountInAfterFee, decimals0, decimals1, rateNumerator, rateDenominator);
    } else {
      return convertWithRate(amountInAfterFee, decimals1, decimals0, rateDenominator, rateNumerator);
    }
  }

  /**
   * @notice Converts token amount using the provided exchange rate and adjusts for decimals
   * @param amount Amount to convert
   * @param fromDecimals Source token decimal scaling factor
   * @param toDecimals Destination token decimal scaling factor
   * @param numerator Rate numerator
   * @param denominator Rate denominator
   * @return Converted amount
   */
  function convertWithRate(
    uint256 amount,
    uint256 fromDecimals,
    uint256 toDecimals,
    uint256 numerator,
    uint256 denominator
  ) public pure returns (uint256) {
    if (fromDecimals > toDecimals) {
      uint256 decimalAdjustment = fromDecimals / toDecimals;
      return (amount * numerator) / (denominator * decimalAdjustment);
    } else if (fromDecimals < toDecimals) {
      uint256 decimalAdjustment = toDecimals / fromDecimals;
      return (amount * numerator * decimalAdjustment) / denominator;
    } else {
      return (amount * numerator) / denominator;
    }
  }

  /* ========== EXTERNAL FUNCTIONS ========== */

  /**
   * @notice Mints LP tokens by providing liquidity to the pool
   * @param to Address to receive LP tokens
   * @return liquidity Amount of LP tokens minted
   */
  function mint(address to) external nonReentrant returns (uint256 liquidity) {
    (uint256 _reserve0, uint256 _reserve1) = (reserve0, reserve1);

    uint256 balance0 = IERC20(token0).balanceOf(address(this));
    uint256 balance1 = IERC20(token1).balanceOf(address(this));

    uint256 amount0 = balance0 - _reserve0;
    uint256 amount1 = balance1 - _reserve1;

    uint256 _totalSupply = totalSupply();

    if (_totalSupply == 0) {
      liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
      _mint(address(1), MINIMUM_LIQUIDITY);
    } else {
      liquidity = Math.min((amount0 * _totalSupply) / _reserve0, (amount1 * _totalSupply) / _reserve1);
    }

    require(liquidity > MINIMUM_LIQUIDITY, "FPMM: INSUFFICIENT_LIQUIDITY_MINTED");
    _mint(to, liquidity);

    _update();

    emit Mint(msg.sender, amount0, amount1, liquidity);
  }

  /**
   * @notice Burns LP tokens to withdraw liquidity from the pool
   * @param to Address to receive the withdrawn tokens
   * @return amount0 Amount of token0 withdrawn
   * @return amount1 Amount of token1 withdrawn
   */
  function burn(address to) external nonReentrant returns (uint256 amount0, uint256 amount1) {
    (address _token0, address _token1) = (token0, token1);

    uint256 balance0 = IERC20(_token0).balanceOf(address(this));
    uint256 balance1 = IERC20(_token1).balanceOf(address(this));

    uint256 liquidity = balanceOf(address(this));

    uint256 _totalSupply = totalSupply();

    amount0 = (liquidity * balance0) / _totalSupply;
    amount1 = (liquidity * balance1) / _totalSupply;

    require(amount0 > 0 && amount1 > 0, "FPMM: INSUFFICIENT_LIQUIDITY_BURNED");

    _burn(address(this), liquidity);

    IERC20(_token0).safeTransfer(to, amount0);
    IERC20(_token1).safeTransfer(to, amount1);

    _update();

    emit Burn(msg.sender, amount0, amount1, liquidity, to);
  }

  /**
   * @notice Swaps tokens based on oracle price
   * @param amount0Out Amount of token0 to output
   * @param amount1Out Amount of token1 to output
   * @param to Address receiving output tokens
   * @param data Optional callback data
   */
  function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external nonReentrant {
    _swap(amount0Out, amount1Out, to, data, false);
  }

  /**
   * @notice Rebalances the pool to align with oracle price
   * @dev Only callable by approved strategies
   * @param amount0Out Amount of token0 to output
   * @param amount1Out Amount of token1 to output
   * @param to Address receiving output tokens
   * @param data Optional callback data
   */
  function rebalance(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external nonReentrant {
    require(liquidityStrategy[msg.sender], "FPMM: NOT_LIQUIDITY_STRATEGY");
    _swap(amount0Out, amount1Out, to, data, true);
  }

  /* ========== ADMIN FUNCTIONS ========== */

  /**
   * @notice Sets protocol fee
   * @param _protocolFee New fee in basis points
   */
  function setProtocolFee(uint256 _protocolFee) external onlyOwner {
    require(_protocolFee <= 100, "FPMM: FEE_TOO_HIGH"); // Max 1%
    uint256 oldFee = protocolFee;
    protocolFee = _protocolFee;
    emit ProtocolFeeUpdated(oldFee, _protocolFee);
  }

  /**
   * @notice Sets rebalance incentive
   * @param _rebalanceIncentive New incentive in basis points
   */
  function setRebalanceIncentive(uint256 _rebalanceIncentive) external onlyOwner {
    require(_rebalanceIncentive <= 100, "FPMM: REBALANCE_INCENTIVE_TOO_HIGH"); // Max 1%
    uint256 oldIncentive = rebalanceIncentive;
    rebalanceIncentive = _rebalanceIncentive;
    emit RebalanceIncentiveUpdated(oldIncentive, _rebalanceIncentive);
  }

  /**
   * @notice Sets rebalance threshold
   * @param _rebalanceThreshold New threshold in basis points
   */
  function setRebalanceThreshold(uint256 _rebalanceThreshold) external onlyOwner {
    require(_rebalanceThreshold <= 1000, "FPMM: REBALANCE_THRESHOLD_TOO_HIGH"); // Max 10%
    uint256 oldThreshold = rebalanceThreshold;
    rebalanceThreshold = _rebalanceThreshold;
    emit RebalanceThresholdUpdated(oldThreshold, _rebalanceThreshold);
  }

  /**
   * @notice Sets liquidity strategy status
   * @param strategy Address of the strategy
   * @param state New status (true = enabled, false = disabled)
   */
  function setLiquidityStrategy(address strategy, bool state) external onlyOwner {
    liquidityStrategy[strategy] = state;
    emit LiquidityStrategyUpdated(strategy, state);
  }

  /**
   * @notice Sets the SortedOracles contract
   * @param _sortedOracles Address of the SortedOracles contract
   */
  function setSortedOracles(address _sortedOracles) public onlyOwner {
    require(_sortedOracles != address(0), "SortedOracles address must be set");
    address oldSortedOracles = address(sortedOracles);
    sortedOracles = ISortedOracles(_sortedOracles);
    emit SortedOraclesUpdated(oldSortedOracles, _sortedOracles);
  }

  /**
   * @notice Sets the BreakerBox contract
   * @param _breakerBox Address of the BreakerBox contract
   */
  function setBreakerBox(address _breakerBox) public onlyOwner {
    require(_breakerBox != address(0), "BreakerBox address must be set");
    address oldBreakerBox = address(breakerBox);
    breakerBox = IBreakerBox(_breakerBox);
    emit BreakerBoxUpdated(oldBreakerBox, _breakerBox);
  }

  /**
   * @notice Sets the reference rate feed ID
   * @param _referenceRateFeedID Address of the reference rate feed
   */
  function setReferenceRateFeedID(address _referenceRateFeedID) public onlyOwner {
    require(_referenceRateFeedID != address(0), "Reference rate feed ID must be set");
    address oldRateFeedID = referenceRateFeedID;
    referenceRateFeedID = _referenceRateFeedID;
    emit ReferenceRateFeedIDUpdated(oldRateFeedID, _referenceRateFeedID);
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  /**
   * @notice Updates reserves and timestamp
   * @dev Called after every balance-changing function
   */
  function _update() private {
    reserve0 = IERC20(token0).balanceOf(address(this));
    reserve1 = IERC20(token1).balanceOf(address(this));
    blockTimestampLast = block.timestamp;

    emit SyncReserves(reserve0, reserve1, blockTimestampLast);
  }

  /**
   * @notice Calculates price difference between oracle and reserves in basis points
   * @return priceDifference Price difference in basis points
   */
  function _calculatePriceDifference() internal view returns (uint256 priceDifference) {
    (uint256 oraclePrice, uint256 reservePrice, , ) = getPrices();

    if (oraclePrice > reservePrice) {
      priceDifference = ((oraclePrice - reservePrice) * 10000) / oraclePrice;
    } else {
      priceDifference = ((reservePrice - oraclePrice) * 10000) / oraclePrice;
    }
  }

  /**
   * @notice Internal swap function used by both swap and rebalance
   * @param amount0Out Amount of token0 to output
   * @param amount1Out Amount of token1 to output
   * @param to Address receiving output tokens
   * @param data Optional callback data
   * @param isRebalance Whether this is a rebalance operation
   */

  function _swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data, bool isRebalance) private {
    require(amount0Out > 0 || amount1Out > 0, "FPMM: INSUFFICIENT_OUTPUT_AMOUNT");
    (uint256 _reserve0, uint256 _reserve1) = (reserve0, reserve1);
    require(amount0Out < _reserve0 && amount1Out < _reserve1, "FPMM: INSUFFICIENT_LIQUIDITY");
    require(to != token0 && to != token1, "FPMM: INVALID_TO_ADDRESS");
    require(
      breakerBox.getRateFeedTradingMode(referenceRateFeedID) == TRADING_MODE_BIDIRECTIONAL,
      "FPMM: TRADING_SUSPENDED"
    );

    // used to avoid stack too deep error
    SwapData memory swapData;

    (swapData.rateNumerator, swapData.rateDenominator) = sortedOracles.medianRate(referenceRateFeedID);
    swapData.initialReserveValue = totalValueInToken1(
      _reserve0,
      _reserve1,
      swapData.rateNumerator,
      swapData.rateDenominator
    );
    swapData.initialPriceDifference = _calculatePriceDifference();

    if (isRebalance) {
      require(swapData.initialPriceDifference >= rebalanceThreshold, "FPMM: PRICE_DIFFERENCE_TOO_SMALL");
    }

    if (amount0Out > 0) IERC20(token0).safeTransfer(to, amount0Out);
    if (amount1Out > 0) IERC20(token1).safeTransfer(to, amount1Out);

    if (data.length > 0) IFPMMCallee(to).hook(msg.sender, amount0Out, amount1Out, data);

    uint256 balance0 = IERC20(token0).balanceOf(address(this));
    uint256 balance1 = IERC20(token1).balanceOf(address(this));

    swapData.amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
    swapData.amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
    require(swapData.amount0In > 0 || swapData.amount1In > 0, "FPMM: INSUFFICIENT_INPUT_AMOUNT");

    _update();

    if (isRebalance) {
      uint256 newPriceDifference = _rebalanceCheck(swapData);
      emit Rebalanced(msg.sender, swapData.initialPriceDifference, newPriceDifference);
    } else {
      _swapCheck(swapData);
    }
    emit Swap(msg.sender, swapData.amount0In, swapData.amount1In, amount0Out, amount1Out, to);
  }

  /**
   * @notice Rebalance checks
   * @param swapData Swap data
   * @return newPriceDifference New price difference
   */
  function _rebalanceCheck(SwapData memory swapData) internal view returns (uint256 newPriceDifference) {
    uint256 newReserveValue = totalValueInToken1(reserve0, reserve1, swapData.rateNumerator, swapData.rateDenominator);
    newPriceDifference = _calculatePriceDifference();

    // Ensure price difference is smaller than before
    require(newPriceDifference < swapData.initialPriceDifference, "FPMM: PRICE_DIFFERENCE_NOT_IMPROVED");
    require(newPriceDifference < rebalanceThreshold, "FPMM: POOL_NOT_REBALANCED");

    // Check for excessive value loss
    uint256 rebalanceIncentiveAmount = (swapData.initialReserveValue * rebalanceIncentive) / 10000;
    uint256 minAcceptableValue = swapData.initialReserveValue - rebalanceIncentiveAmount;
    require(newReserveValue >= minAcceptableValue, "FPMM: EXCESSIVE_VALUE_LOSS");
  }

  /**
   * @notice Swap checks
   * @param swapData Swap data
   */
  function _swapCheck(SwapData memory swapData) internal view {
    uint256 newReserveValue = totalValueInToken1(reserve0, reserve1, swapData.rateNumerator, swapData.rateDenominator);

    uint256 fee0 = (swapData.amount0In * protocolFee) / 10000;
    uint256 fee1 = (swapData.amount1In * protocolFee) / 10000;

    uint256 fee0InToken1 = convertWithRate(
      fee0,
      decimals0,
      decimals1,
      swapData.rateNumerator,
      swapData.rateDenominator
    );
    uint256 totalFeeInToken1 = fee0InToken1 + fee1;

    // Check the reserve value is not decreased
    uint256 expectedReserveValue = swapData.initialReserveValue + totalFeeInToken1;
    require(newReserveValue >= expectedReserveValue, "FPMM: RESERVE_VALUE_DECREASED");
  }
}
