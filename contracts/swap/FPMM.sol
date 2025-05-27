// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

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

  /// @inheritdoc IFPMM
  uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

  /// @inheritdoc IFPMM
  uint256 public constant BASIS_POINTS_DENOMINATOR = 10_000;

  /// @inheritdoc IFPMM
  uint256 public constant TRADING_MODE_BIDIRECTIONAL = 0;

  /* ========== STATE VARIABLES ========== */

  /// @inheritdoc IFPMM
  address public token0;

  /// @inheritdoc IFPMM
  address public token1;

  /// @inheritdoc IFPMM
  uint256 public decimals0;

  /// @inheritdoc IFPMM
  uint256 public decimals1;

  /// @inheritdoc IFPMM
  uint256 public reserve0;

  /// @inheritdoc IFPMM
  uint256 public reserve1;

  /// @inheritdoc IFPMM
  uint256 public blockTimestampLast;

  /// @inheritdoc IFPMM
  ISortedOracles public sortedOracles;

  /// @inheritdoc IFPMM
  IBreakerBox public breakerBox;

  /// @inheritdoc IFPMM
  address public referenceRateFeedID;

  /// @inheritdoc IFPMM
  uint256 public protocolFee;

  /// @inheritdoc IFPMM
  uint256 public rebalanceIncentive;

  /// @inheritdoc IFPMM
  uint256 public rebalanceThresholdAbove; // For when reserve price > oracle price
  uint256 public rebalanceThresholdBelow; // For when reserve price < oracle price

  /// @inheritdoc IFPMM
  mapping(address => bool) public liquidityStrategy;

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

  /// @inheritdoc IFPMM
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

    setProtocolFee(30); // .3% fee (30 basis points)
    setRebalanceIncentive(50); // Default .5% incentive tolerance (50 basis points)
    setRebalanceThresholds(500, 500); // Default 5% rebalance threshold (500 basis points)

    setSortedOracles(_sortedOracles);
    setBreakerBox(_breakerBox);
  }

  /* ========== VIEW FUNCTIONS ========== */

  /// @inheritdoc IFPMM
  function metadata()
    external
    view
    returns (uint256 dec0, uint256 dec1, uint256 r0, uint256 r1, address t0, address t1)
  {
    return (decimals0, decimals1, reserve0, reserve1, token0, token1);
  }

  /// @inheritdoc IFPMM
  function tokens() external view returns (address, address) {
    return (token0, token1);
  }

  /// @inheritdoc IFPMM
  function getReserves() public view returns (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast) {
    _reserve0 = reserve0;
    _reserve1 = reserve1;
    _blockTimestampLast = blockTimestampLast;
  }

  /// @inheritdoc IFPMM
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

  /// @inheritdoc IFPMM
  function getAmountOut(uint256 amountIn, address tokenIn) public view returns (uint256 amountOut) {
    require(tokenIn == token0 || tokenIn == token1, "FPMM: INVALID_TOKEN");

    if (amountIn == 0) return 0;

    (uint256 rateNumerator, uint256 rateDenominator) = sortedOracles.medianRate(referenceRateFeedID);

    uint256 amountInAfterFee = amountIn - ((amountIn * protocolFee) / BASIS_POINTS_DENOMINATOR);

    if (tokenIn == token0) {
      return convertWithRate(amountInAfterFee, decimals0, decimals1, rateNumerator, rateDenominator);
    } else {
      return convertWithRate(amountInAfterFee, decimals1, decimals0, rateDenominator, rateNumerator);
    }
  }

  // slither-disable-start divide-before-multiply
  /// @inheritdoc IFPMM
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
  // slither-disable-end divide-before-multiply

  /* ========== EXTERNAL FUNCTIONS ========== */

  /// @inheritdoc IFPMM
  function mint(address to) external nonReentrant returns (uint256 liquidity) {
    (uint256 _reserve0, uint256 _reserve1) = (reserve0, reserve1);

    uint256 balance0 = IERC20(token0).balanceOf(address(this));
    uint256 balance1 = IERC20(token1).balanceOf(address(this));

    uint256 amount0 = balance0 - _reserve0;
    uint256 amount1 = balance1 - _reserve1;

    uint256 _totalSupply = totalSupply();
    // slither-disable-next-line incorrect-equality
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

  /// @inheritdoc IFPMM
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

    // slither-disable-start reentrancy-benign
    IERC20(_token0).safeTransfer(to, amount0);
    IERC20(_token1).safeTransfer(to, amount1);
    // slither-disable-end reentrancy-benign

    _update();

    emit Burn(msg.sender, amount0, amount1, liquidity, to);
  }

  /// @inheritdoc IFPMM
  function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external nonReentrant {
    _swap(amount0Out, amount1Out, to, data, false);
  }

  /// @inheritdoc IFPMM
  function rebalance(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external nonReentrant {
    require(liquidityStrategy[msg.sender], "FPMM: NOT_LIQUIDITY_STRATEGY");
    require(msg.sender == to, "FPMM: INVALID_TO_ADDRESS");
    _swap(amount0Out, amount1Out, to, data, true);
  }

  /* ========== ADMIN FUNCTIONS ========== */

  /// @inheritdoc IFPMM
  function setProtocolFee(uint256 _protocolFee) public onlyOwner {
    require(_protocolFee <= 100, "FPMM: FEE_TOO_HIGH"); // Max 1%
    uint256 oldFee = protocolFee;
    protocolFee = _protocolFee;
    emit ProtocolFeeUpdated(oldFee, _protocolFee);
  }

  /// @inheritdoc IFPMM
  function setRebalanceIncentive(uint256 _rebalanceIncentive) public onlyOwner {
    require(_rebalanceIncentive <= 100, "FPMM: REBALANCE_INCENTIVE_TOO_HIGH"); // Max 1%
    uint256 oldIncentive = rebalanceIncentive;
    rebalanceIncentive = _rebalanceIncentive;
    emit RebalanceIncentiveUpdated(oldIncentive, _rebalanceIncentive);
  }

  /// @inheritdoc IFPMM
  function setRebalanceThresholds(uint256 _rebalanceThresholdAbove, uint256 _rebalanceThresholdBelow) public onlyOwner {
    require(_rebalanceThresholdAbove <= 1000, "FPMM: REBALANCE_THRESHOLD_TOO_HIGH"); // Max 10%
    require(_rebalanceThresholdBelow <= 1000, "FPMM: REBALANCE_THRESHOLD_TOO_HIGH"); // Max 10%
    uint256 oldThresholdAbove = rebalanceThresholdAbove;
    uint256 oldThresholdBelow = rebalanceThresholdBelow;
    rebalanceThresholdAbove = _rebalanceThresholdAbove;
    rebalanceThresholdBelow = _rebalanceThresholdBelow;
    emit RebalanceThresholdUpdated(
      oldThresholdAbove,
      oldThresholdBelow,
      _rebalanceThresholdAbove,
      _rebalanceThresholdBelow
    );
  }

  /// @inheritdoc IFPMM
  function setLiquidityStrategy(address strategy, bool state) external onlyOwner {
    liquidityStrategy[strategy] = state;
    emit LiquidityStrategyUpdated(strategy, state);
  }

  /// @inheritdoc IFPMM
  function setSortedOracles(address _sortedOracles) public onlyOwner {
    require(_sortedOracles != address(0), "FPMM: SORTED_ORACLES_ADDRESS_MUST_BE_SET");
    address oldSortedOracles = address(sortedOracles);
    sortedOracles = ISortedOracles(_sortedOracles);
    emit SortedOraclesUpdated(oldSortedOracles, _sortedOracles);
  }

  /// @inheritdoc IFPMM
  function setBreakerBox(address _breakerBox) public onlyOwner {
    require(_breakerBox != address(0), "FPMM: BREAKER_BOX_ADDRESS_MUST_BE_SET");
    address oldBreakerBox = address(breakerBox);
    breakerBox = IBreakerBox(_breakerBox);
    emit BreakerBoxUpdated(oldBreakerBox, _breakerBox);
  }

  /// @inheritdoc IFPMM
  function setReferenceRateFeedID(address _referenceRateFeedID) public onlyOwner {
    require(_referenceRateFeedID != address(0), "FPMM: REFERENCE_RATE_FEED_ID_MUST_BE_SET");
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

    emit UpdateReserves(reserve0, reserve1, blockTimestampLast);
  }

  /**
   * @notice Calculates total value of a given amount of tokens in terms of token1
   * @param amount0 Amount of token0
   * @param amount1 Amount of token1
   * @param rateNumerator Oracle rate numerator
   * @param rateDenominator Oracle rate denominator
   * @return Total value in token1
   */
  function _totalValueInToken1(
    uint256 amount0,
    uint256 amount1,
    uint256 rateNumerator,
    uint256 rateDenominator
  ) private view returns (uint256) {
    uint256 token0ValueInToken1 = convertWithRate(amount0, decimals0, decimals1, rateNumerator, rateDenominator);
    return token0ValueInToken1 + amount1;
  }

  /**
   * @notice Calculates price difference between oracle and reserves in basis points
   * @return priceDifference Price difference in basis points
   */
  function _calculatePriceDifference()
    private
    view
    returns (uint256 priceDifference, bool reservePriceAboveOraclePrice)
  {
    (uint256 oraclePrice, uint256 reservePrice, , ) = getPrices();

    if (reservePrice > oraclePrice) {
      priceDifference = ((reservePrice - oraclePrice) * BASIS_POINTS_DENOMINATOR) / oraclePrice;
      reservePriceAboveOraclePrice = true;
    } else {
      priceDifference = ((oraclePrice - reservePrice) * BASIS_POINTS_DENOMINATOR) / oraclePrice;
      reservePriceAboveOraclePrice = false;
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
  // slither-disable-start reentrancy-no-eth
  // slither-disable-start reentrancy-benign
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
    // slither-disable-next-line uninitialized-local
    SwapData memory swapData;

    (swapData.rateNumerator, swapData.rateDenominator) = sortedOracles.medianRate(referenceRateFeedID);
    swapData.initialReserveValue = _totalValueInToken1(
      _reserve0,
      _reserve1,
      swapData.rateNumerator,
      swapData.rateDenominator
    );
    (swapData.initialPriceDifference, swapData.reservePriceAboveOraclePrice) = _calculatePriceDifference();

    if (isRebalance) {
      if (swapData.reservePriceAboveOraclePrice) {
        require(swapData.initialPriceDifference >= rebalanceThresholdAbove, "FPMM: PRICE_DIFFERENCE_TOO_SMALL");
      } else {
        require(swapData.initialPriceDifference >= rebalanceThresholdBelow, "FPMM: PRICE_DIFFERENCE_TOO_SMALL");
      }
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
  // slither-disable-end reentrancy-no-eth
  // slither-disable-end reentrancy-benign

  /**
   * @notice Rebalance checks to ensure the price difference is smaller than before and
   * the reserve value is not decreased more than the rebalance incentive
   * @param swapData Swap data
   * @return newPriceDifference New price difference
   */
  function _rebalanceCheck(SwapData memory swapData) private view returns (uint256 newPriceDifference) {
    uint256 newReserveValue = _totalValueInToken1(reserve0, reserve1, swapData.rateNumerator, swapData.rateDenominator);
    bool reservePriceAboveOraclePrice;
    (newPriceDifference, reservePriceAboveOraclePrice) = _calculatePriceDifference();

    // Ensure price difference is smaller than before
    require(newPriceDifference < swapData.initialPriceDifference, "FPMM: PRICE_DIFFERENCE_NOT_IMPROVED");
    if (reservePriceAboveOraclePrice) {
      require(newPriceDifference < rebalanceThresholdAbove, "FPMM: POOL_NOT_REBALANCED");
    } else {
      require(newPriceDifference < rebalanceThresholdBelow, "FPMM: POOL_NOT_REBALANCED");
    }

    // Check for excessive value loss
    uint256 rebalanceIncentiveAmount = (swapData.initialReserveValue * rebalanceIncentive) / BASIS_POINTS_DENOMINATOR;
    uint256 minAcceptableValue = swapData.initialReserveValue - rebalanceIncentiveAmount;
    require(newReserveValue >= minAcceptableValue, "FPMM: EXCESSIVE_VALUE_LOSS");
  }

  /**
   * @notice Swap checks to ensure the reserve value is not decreased
   * @param swapData Swap data
   */
  function _swapCheck(SwapData memory swapData) private view {
    uint256 newReserveValue = _totalValueInToken1(reserve0, reserve1, swapData.rateNumerator, swapData.rateDenominator);

    uint256 fee0 = (swapData.amount0In * protocolFee) / BASIS_POINTS_DENOMINATOR;
    uint256 fee1 = (swapData.amount1In * protocolFee) / BASIS_POINTS_DENOMINATOR;

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
