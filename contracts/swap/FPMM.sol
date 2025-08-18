// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { IFPMM } from "../interfaces/IFPMM.sol";
import { ERC20Upgradeable } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
// solhint-disable-next-line max-line-length
import { ReentrancyGuardUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import { MathUpgradeable as Math } from "openzeppelin-contracts-upgradeable/contracts/utils/math/MathUpgradeable.sol";
// solhint-disable-next-line max-line-length
import { SafeERC20Upgradeable } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
// solhint-disable-next-line max-line-length
import { IERC20Upgradeable as IERC20 } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import { ISortedOracles } from "../interfaces/ISortedOracles.sol";
import { IFPMMCallee } from "../interfaces/IFPMMCallee.sol";
import { IBreakerBox } from "../interfaces/IBreakerBox.sol";

/**
 * @title Fixed Price Market Maker (FPMM)
 * @author Mento Labs
 * @notice This contract implements a fixed price market maker that manages a liquidity pool
 * of two tokens and facilitates swaps between them based on oracle rates and potential fallback
 * to internal pricing.
 * @dev Invariants of the pool:
 * 1. Swap does not decrease the total value of the pool
 * 2. Rebalance does not decrease the reserve value more than the rebalance incentive
 * 3. Rebalance moves the price difference towards 0
 * 4. Rebalance does not change the direction of the price difference
 */
contract FPMM is IFPMM, ReentrancyGuardUpgradeable, ERC20Upgradeable, OwnableUpgradeable {
  using SafeERC20Upgradeable for IERC20;

  /* ========== CONSTANTS ========== */

  /// @inheritdoc IFPMM
  uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

  /// @inheritdoc IFPMM
  uint256 public constant BASIS_POINTS_DENOMINATOR = 10_000;

  /// @inheritdoc IFPMM
  uint256 public constant TRADING_MODE_BIDIRECTIONAL = 0;

  // keccak256(abi.encode(uint256(keccak256("mento.storage.FPMM")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant _FPMM_STORAGE_LOCATION = 0xe40ad100017325097d9c1a3195cd4d2d97dcb316ccef4f208489777afd465d00;

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
    address _referenceRateFeedID,
    bool _revertRateFeed,
    address _breakerBox,
    address owner_
  ) external initializer {
    FPMMStorage storage $ = _getFPMMStorage();

    $.token0 = _token0;
    $.token1 = _token1;

    string memory symbol0 = ERC20Upgradeable(_token0).symbol();
    string memory symbol1 = ERC20Upgradeable(_token1).symbol();

    string memory name_ = string(abi.encodePacked("Mento Fixed Price MM - ", symbol0, "/", symbol1));
    string memory symbol_ = string(abi.encodePacked("FPMM-", symbol0, "/", symbol1));

    __ERC20_init(name_, symbol_);
    __Ownable_init();

    $.decimals0 = 10 ** ERC20Upgradeable(_token0).decimals();
    $.decimals1 = 10 ** ERC20Upgradeable(_token1).decimals();

    setProtocolFee(30); // .3% fee (30 basis points)
    setRebalanceIncentive(50); // Default .5% incentive tolerance (50 basis points)
    setRebalanceThresholds(500, 500); // Default 5% rebalance threshold (500 basis points)

    setSortedOracles(_sortedOracles);
    setBreakerBox(_breakerBox);
    setReferenceRateFeedID(_referenceRateFeedID);
    setRevertRateFeed(_revertRateFeed);
    transferOwnership(owner_);
  }

  /* ========== VIEW FUNCTIONS ========== */

  /// @inheritdoc IFPMM
  function metadata()
    external
    view
    returns (uint256 dec0, uint256 dec1, uint256 r0, uint256 r1, address t0, address t1)
  {
    FPMMStorage storage $ = _getFPMMStorage();

    return ($.decimals0, $.decimals1, $.reserve0, $.reserve1, $.token0, $.token1);
  }

  /// @inheritdoc IFPMM
  function tokens() external view returns (address, address) {
    FPMMStorage storage $ = _getFPMMStorage();

    return ($.token0, $.token1);
  }

  /// @inheritdoc IFPMM
  function getReserves() public view returns (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast) {
    FPMMStorage storage $ = _getFPMMStorage();

    _reserve0 = $.reserve0;
    _reserve1 = $.reserve1;
    _blockTimestampLast = $.blockTimestampLast;
  }

  /// @inheritdoc IFPMM
  function token0() external view returns (address) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.token0;
  }

  /// @inheritdoc IFPMM
  function token1() external view returns (address) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.token1;
  }

  /// @inheritdoc IFPMM
  function decimals0() external view returns (uint256) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.decimals0;
  }

  /// @inheritdoc IFPMM
  function decimals1() external view returns (uint256) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.decimals1;
  }

  /// @inheritdoc IFPMM
  function reserve0() external view returns (uint256) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.reserve0;
  }

  /// @inheritdoc IFPMM
  function reserve1() external view returns (uint256) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.reserve1;
  }

  /// @inheritdoc IFPMM
  function blockTimestampLast() external view returns (uint256) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.blockTimestampLast;
  }

  /// @inheritdoc IFPMM
  function sortedOracles() external view returns (ISortedOracles) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.sortedOracles;
  }

  /// @inheritdoc IFPMM
  function revertRateFeed() external view returns (bool) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.revertRateFeed;
  }

  /// @inheritdoc IFPMM
  function breakerBox() external view returns (IBreakerBox) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.breakerBox;
  }

  /// @inheritdoc IFPMM
  function referenceRateFeedID() external view returns (address) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.referenceRateFeedID;
  }

  /// @inheritdoc IFPMM
  function protocolFee() external view returns (uint256) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.protocolFee;
  }

  /// @inheritdoc IFPMM
  function rebalanceIncentive() external view returns (uint256) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.rebalanceIncentive;
  }

  /// @inheritdoc IFPMM
  function rebalanceThresholdAbove() external view returns (uint256) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.rebalanceThresholdAbove;
  }

  /// @inheritdoc IFPMM
  function rebalanceThresholdBelow() external view returns (uint256) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.rebalanceThresholdBelow;
  }

  /// @inheritdoc IFPMM
  function liquidityStrategy(address strategy) external view returns (bool) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.liquidityStrategy[strategy];
  }

  /// @inheritdoc IFPMM
  function getPrices()
    public
    view
    returns (
      uint256 oraclePriceNumerator,
      uint256 oraclePriceDenominator,
      uint256 reservePriceNumerator,
      uint256 reservePriceDenominator,
      uint256 priceDifference,
      bool reservePriceAboveOraclePrice
    )
  {
    FPMMStorage storage $ = _getFPMMStorage();

    require($.referenceRateFeedID != address(0), "FPMM: REFERENCE_RATE_NOT_SET");
    require($.reserve0 > 0 && $.reserve1 > 0, "FPMM: RESERVES_EMPTY");

    (oraclePriceNumerator, oraclePriceDenominator) = _getRateFeed();

    reservePriceNumerator = $.reserve1 * (1e18 / $.decimals1);
    reservePriceDenominator = $.reserve0 * (1e18 / $.decimals0);

    uint256 oracleCrossProduct = oraclePriceNumerator * reservePriceDenominator;
    uint256 reserveCrossProduct = reservePriceNumerator * oraclePriceDenominator;
    reservePriceAboveOraclePrice = reserveCrossProduct > oracleCrossProduct;

    uint256 absolutePriceDiff = reservePriceAboveOraclePrice
      ? reserveCrossProduct - oracleCrossProduct
      : oracleCrossProduct - reserveCrossProduct;
    priceDifference = (absolutePriceDiff * BASIS_POINTS_DENOMINATOR) / oracleCrossProduct;
    return (
      oraclePriceNumerator,
      oraclePriceDenominator,
      reservePriceNumerator,
      reservePriceDenominator,
      priceDifference,
      reservePriceAboveOraclePrice
    );
  }

  /// @inheritdoc IFPMM
  function getAmountOut(uint256 amountIn, address tokenIn) public view returns (uint256 amountOut) {
    FPMMStorage storage $ = _getFPMMStorage();

    require(
      $.breakerBox.getRateFeedTradingMode($.referenceRateFeedID) == TRADING_MODE_BIDIRECTIONAL,
      "FPMM: TRADING_SUSPENDED"
    );

    require(tokenIn == $.token0 || tokenIn == $.token1, "FPMM: INVALID_TOKEN");

    if (amountIn == 0) return 0;

    (uint256 rateNumerator, uint256 rateDenominator) = _getRateFeed();

    uint256 amountInAfterFee = amountIn - ((amountIn * $.protocolFee) / BASIS_POINTS_DENOMINATOR);

    if (tokenIn == $.token0) {
      return convertWithRate(amountInAfterFee, $.decimals0, $.decimals1, rateNumerator, rateDenominator);
    } else {
      return convertWithRate(amountInAfterFee, $.decimals1, $.decimals0, rateDenominator, rateNumerator);
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
    FPMMStorage storage $ = _getFPMMStorage();

    uint256 balance0 = IERC20($.token0).balanceOf(address(this));
    uint256 balance1 = IERC20($.token1).balanceOf(address(this));

    uint256 amount0 = balance0 - $.reserve0;
    uint256 amount1 = balance1 - $.reserve1;

    uint256 totalSupply_ = totalSupply();
    // slither-disable-next-line incorrect-equality
    if (totalSupply_ == 0) {
      liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
      _mint(address(1), MINIMUM_LIQUIDITY);
    } else {
      liquidity = Math.min((amount0 * totalSupply_) / $.reserve0, (amount1 * totalSupply_) / $.reserve1);
    }

    require(liquidity > MINIMUM_LIQUIDITY, "FPMM: INSUFFICIENT_LIQUIDITY_MINTED");
    _mint(to, liquidity);

    _update();

    emit Mint(msg.sender, amount0, amount1, liquidity);
  }

  // slither-disable-start reentrancy-benign
  // slither-disable-start reentrancy-no-eth
  /// @inheritdoc IFPMM
  function burn(address to) external nonReentrant returns (uint256 amount0, uint256 amount1) {
    FPMMStorage storage $ = _getFPMMStorage();

    uint256 balance0 = IERC20($.token0).balanceOf(address(this));
    uint256 balance1 = IERC20($.token1).balanceOf(address(this));

    uint256 liquidity = balanceOf(address(this));

    uint256 _totalSupply = totalSupply();

    amount0 = (liquidity * balance0) / _totalSupply;
    amount1 = (liquidity * balance1) / _totalSupply;

    require(amount0 > 0 && amount1 > 0, "FPMM: INSUFFICIENT_LIQUIDITY_BURNED");

    _burn(address(this), liquidity);

    IERC20($.token0).safeTransfer(to, amount0);
    IERC20($.token1).safeTransfer(to, amount1);

    _update();

    emit Burn(msg.sender, amount0, amount1, liquidity, to);
  }
  // slither-disable-end reentrancy-benign
  // slither-disable-end reentrancy-no-eth

  // slither-disable-start reentrancy-no-eth
  /// @inheritdoc IFPMM
  function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external nonReentrant {
    FPMMStorage storage $ = _getFPMMStorage();

    require(amount0Out > 0 || amount1Out > 0, "FPMM: INSUFFICIENT_OUTPUT_AMOUNT");
    require(amount0Out < $.reserve0 && amount1Out < $.reserve1, "FPMM: INSUFFICIENT_LIQUIDITY");
    require(to != $.token0 && to != $.token1, "FPMM: INVALID_TO_ADDRESS");
    require(
      $.breakerBox.getRateFeedTradingMode($.referenceRateFeedID) == TRADING_MODE_BIDIRECTIONAL,
      "FPMM: TRADING_SUSPENDED"
    );

    // used to avoid stack too deep error
    // slither-disable-next-line uninitialized-local
    SwapData memory swapData;

    swapData.amount0Out = amount0Out;
    swapData.amount1Out = amount1Out;

    (swapData.rateNumerator, swapData.rateDenominator) = _getRateFeed();
    swapData.initialReserveValue = _totalValueInToken1Scaled(
      $.reserve0,
      $.reserve1,
      swapData.rateNumerator,
      swapData.rateDenominator
    );

    if (amount0Out > 0) IERC20($.token0).safeTransfer(to, amount0Out);
    if (amount1Out > 0) IERC20($.token1).safeTransfer(to, amount1Out);

    if (data.length > 0) IFPMMCallee(to).hook(msg.sender, amount0Out, amount1Out, data);

    swapData.balance0 = IERC20($.token0).balanceOf(address(this));
    swapData.balance1 = IERC20($.token1).balanceOf(address(this));

    swapData.amount0In = swapData.balance0 > $.reserve0 - amount0Out
      ? swapData.balance0 - ($.reserve0 - amount0Out)
      : 0;
    swapData.amount1In = swapData.balance1 > $.reserve1 - amount1Out
      ? swapData.balance1 - ($.reserve1 - amount1Out)
      : 0;
    require(swapData.amount0In > 0 || swapData.amount1In > 0, "FPMM: INSUFFICIENT_INPUT_AMOUNT");

    _update();

    _swapCheck(swapData);

    emit Swap(msg.sender, swapData.amount0In, swapData.amount1In, amount0Out, amount1Out, to);
  }
  // slither-disable-end reentrancy-no-eth

  // slither-disable-start reentrancy-no-eth
  /// @inheritdoc IFPMM
  function rebalance(uint256 amount0Out, uint256 amount1Out, bytes calldata data) external nonReentrant {
    FPMMStorage storage $ = _getFPMMStorage();

    require($.liquidityStrategy[msg.sender], "FPMM: NOT_LIQUIDITY_STRATEGY");
    require((amount0Out > 0) != (amount1Out > 0), "FPMM: ONE_OUTPUT_AMOUNT_REQUIRED");
    require(amount0Out < $.reserve0 && amount1Out < $.reserve1, "FPMM: INSUFFICIENT_LIQUIDITY");
    require(
      $.breakerBox.getRateFeedTradingMode($.referenceRateFeedID) == TRADING_MODE_BIDIRECTIONAL,
      "FPMM: TRADING_SUSPENDED"
    );

    // used to avoid stack too deep error
    // slither-disable-next-line uninitialized-local
    SwapData memory swapData;

    swapData.amount0Out = amount0Out;
    swapData.amount1Out = amount1Out;

    (
      swapData.rateNumerator,
      swapData.rateDenominator,
      ,
      ,
      swapData.initialPriceDifference,
      swapData.reservePriceAboveOraclePrice
    ) = getPrices();

    swapData.initialReserveValue = _totalValueInToken1Scaled(
      $.reserve0,
      $.reserve1,
      swapData.rateNumerator,
      swapData.rateDenominator
    );

    uint256 threshold = swapData.reservePriceAboveOraclePrice ? $.rebalanceThresholdAbove : $.rebalanceThresholdBelow;
    require(swapData.initialPriceDifference >= threshold, "FPMM: PRICE_DIFFERENCE_TOO_SMALL");

    if (amount0Out > 0) IERC20($.token0).safeTransfer(msg.sender, amount0Out);
    if (amount1Out > 0) IERC20($.token1).safeTransfer(msg.sender, amount1Out);

    if (data.length > 0) IFPMMCallee(msg.sender).hook(msg.sender, amount0Out, amount1Out, data);

    uint256 balance0 = IERC20($.token0).balanceOf(address(this));
    uint256 balance1 = IERC20($.token1).balanceOf(address(this));

    uint256 amount0In = balance0 > $.reserve0 - amount0Out ? balance0 - ($.reserve0 - amount0Out) : 0;
    uint256 amount1In = balance1 > $.reserve1 - amount1Out ? balance1 - ($.reserve1 - amount1Out) : 0;

    // slither-disable-next-line incorrect-equality
    require(
      (amount0Out > 0 && amount1In > 0 && amount0In == 0) || (amount1Out > 0 && amount0In > 0 && amount1In == 0),
      "FPMM: REBALANCE_DIRECTION_INVALID"
    );

    swapData.amount0In = amount0In;
    swapData.amount1In = amount1In;

    _update();

    uint256 newPriceDifference = _rebalanceCheck(swapData);
    emit Rebalanced(msg.sender, swapData.initialPriceDifference, newPriceDifference);
  }
  // slither-disable-end reentrancy-no-eth

  /* ========== ADMIN FUNCTIONS ========== */

  /// @inheritdoc IFPMM
  function setProtocolFee(uint256 _protocolFee) public onlyOwner {
    require(_protocolFee <= 100, "FPMM: FEE_TOO_HIGH"); // Max 1%
    FPMMStorage storage $ = _getFPMMStorage();

    uint256 oldFee = $.protocolFee;
    $.protocolFee = _protocolFee;
    emit ProtocolFeeUpdated(oldFee, _protocolFee);
  }

  /// @inheritdoc IFPMM
  function setRebalanceIncentive(uint256 _rebalanceIncentive) public onlyOwner {
    FPMMStorage storage $ = _getFPMMStorage();

    require(_rebalanceIncentive <= 100, "FPMM: REBALANCE_INCENTIVE_TOO_HIGH"); // Max 1%
    uint256 oldIncentive = $.rebalanceIncentive;
    $.rebalanceIncentive = _rebalanceIncentive;
    emit RebalanceIncentiveUpdated(oldIncentive, _rebalanceIncentive);
  }

  /// @inheritdoc IFPMM
  function setRebalanceThresholds(uint256 _rebalanceThresholdAbove, uint256 _rebalanceThresholdBelow) public onlyOwner {
    FPMMStorage storage $ = _getFPMMStorage();

    require(_rebalanceThresholdAbove <= 1000, "FPMM: REBALANCE_THRESHOLD_TOO_HIGH"); // Max 10%
    require(_rebalanceThresholdBelow <= 1000, "FPMM: REBALANCE_THRESHOLD_TOO_HIGH"); // Max 10%
    uint256 oldThresholdAbove = $.rebalanceThresholdAbove;
    uint256 oldThresholdBelow = $.rebalanceThresholdBelow;
    $.rebalanceThresholdAbove = _rebalanceThresholdAbove;
    $.rebalanceThresholdBelow = _rebalanceThresholdBelow;

    emit RebalanceThresholdUpdated(
      oldThresholdAbove,
      oldThresholdBelow,
      _rebalanceThresholdAbove,
      _rebalanceThresholdBelow
    );
  }

  /// @inheritdoc IFPMM
  function setLiquidityStrategy(address strategy, bool state) external onlyOwner {
    FPMMStorage storage $ = _getFPMMStorage();

    $.liquidityStrategy[strategy] = state;
    emit LiquidityStrategyUpdated(strategy, state);
  }

  /// @inheritdoc IFPMM
  function setSortedOracles(address _sortedOracles) public onlyOwner {
    require(_sortedOracles != address(0), "FPMM: SORTED_ORACLES_ADDRESS_MUST_BE_SET");
    FPMMStorage storage $ = _getFPMMStorage();

    address oldSortedOracles = address($.sortedOracles);
    $.sortedOracles = ISortedOracles(_sortedOracles);
    emit SortedOraclesUpdated(oldSortedOracles, _sortedOracles);
  }

  function setRevertRateFeed(bool _revertRateFeed) public onlyOwner {
    FPMMStorage storage $ = _getFPMMStorage();
    $.revertRateFeed = _revertRateFeed;
  }

  /// @inheritdoc IFPMM
  function setBreakerBox(address _breakerBox) public onlyOwner {
    require(_breakerBox != address(0), "FPMM: BREAKER_BOX_ADDRESS_MUST_BE_SET");
    FPMMStorage storage $ = _getFPMMStorage();

    address oldBreakerBox = address($.breakerBox);
    $.breakerBox = IBreakerBox(_breakerBox);
    emit BreakerBoxUpdated(oldBreakerBox, _breakerBox);
  }

  /// @inheritdoc IFPMM
  function setReferenceRateFeedID(address _referenceRateFeedID) public onlyOwner {
    require(_referenceRateFeedID != address(0), "FPMM: REFERENCE_RATE_FEED_ID_MUST_BE_SET");
    FPMMStorage storage $ = _getFPMMStorage();

    address oldRateFeedID = $.referenceRateFeedID;
    $.referenceRateFeedID = _referenceRateFeedID;
    emit ReferenceRateFeedIDUpdated(oldRateFeedID, _referenceRateFeedID);
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  /**
   * @notice Returns the storage pointer for the FPMM contract
   * @return $ Pointer to the FPMM storage
   */
  function _getFPMMStorage() private pure returns (FPMMStorage storage $) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      $.slot := _FPMM_STORAGE_LOCATION
    }
  }

  /**
   * @notice Updates reserves and timestamp
   * @dev Called after every balance-changing function
   */
  function _update() private {
    FPMMStorage storage $ = _getFPMMStorage();

    $.reserve0 = IERC20($.token0).balanceOf(address(this));
    $.reserve1 = IERC20($.token1).balanceOf(address(this));
    $.blockTimestampLast = block.timestamp;

    emit UpdateReserves($.reserve0, $.reserve1, $.blockTimestampLast);
  }

  /**
   * @notice Calculates total value of a given amount of tokens in terms of token1 scaled to 18 decimals
   * @param amount0 Amount of token0
   * @param amount1 Amount of token1
   * @param rateNumerator Oracle rate numerator
   * @param rateDenominator Oracle rate denominator
   * @return Total value in token1
   */
  function _totalValueInToken1Scaled(
    uint256 amount0,
    uint256 amount1,
    uint256 rateNumerator,
    uint256 rateDenominator
  ) private view returns (uint256) {
    FPMMStorage storage $ = _getFPMMStorage();

    uint256 token0ValueInToken1 = convertWithRate(amount0, $.decimals0, 1e18, rateNumerator, rateDenominator);
    amount1 = amount1 * (1e18 / $.decimals1);
    return token0ValueInToken1 + amount1;
  }

  function _getRateFeed() private view returns (uint256 rateNumerator, uint256 rateDenominator) {
    FPMMStorage storage $ = _getFPMMStorage();
    (rateNumerator, rateDenominator) = $.sortedOracles.medianRate($.referenceRateFeedID);
    rateNumerator = rateNumerator / 1e6;
    rateDenominator = rateDenominator / 1e6;
    if ($.revertRateFeed) {
      (rateNumerator, rateDenominator) = (rateDenominator, rateNumerator);
    }
  }

  /**
   * @notice Rebalance checks to ensure the price difference is smaller than before,
   * the direction of the price difference is not changed,
   * and the reserve value is not decreased more than the rebalance incentive
   * @param swapData Swap data
   * @return newPriceDifference New price difference
   */
  function _rebalanceCheck(SwapData memory swapData) private view returns (uint256 newPriceDifference) {
    FPMMStorage storage $ = _getFPMMStorage();

    bool reservePriceAboveOraclePrice;
    (, , , , newPriceDifference, reservePriceAboveOraclePrice) = getPrices();

    // Ensure price difference is smaller than before
    require(newPriceDifference < swapData.initialPriceDifference, "FPMM: PRICE_DIFFERENCE_NOT_IMPROVED");
    // slither-disable-next-line incorrect-equality
    require(
      reservePriceAboveOraclePrice == swapData.reservePriceAboveOraclePrice || newPriceDifference == 0,
      "FPMM: PRICE_DIFFERENCE_MOVED_IN_WRONG_DIRECTION"
    );

    if (swapData.amount0In > 0) {
      uint256 expectedAmount0In = convertWithRate(
        swapData.amount1Out,
        $.decimals1,
        1e18,
        swapData.rateDenominator,
        swapData.rateNumerator
      );
      uint256 minAmount0In = expectedAmount0In - (expectedAmount0In * $.rebalanceIncentive) / BASIS_POINTS_DENOMINATOR;

      require(swapData.amount0In >= minAmount0In, "FPMM: INSUFFICIENT_AMOUNT_0_IN");
    } else {
      uint256 expectedAmount1In = convertWithRate(
        swapData.amount0Out,
        $.decimals0,
        1e18,
        swapData.rateNumerator,
        swapData.rateDenominator
      );
      expectedAmount1In = expectedAmount1In / (1e18 / $.decimals1);
      uint256 minAmount1In = expectedAmount1In - (expectedAmount1In * $.rebalanceIncentive) / BASIS_POINTS_DENOMINATOR;
      require(swapData.amount1In >= minAmount1In, "FPMM: INSUFFICIENT_AMOUNT_1_IN");
    }
  }

  /**
   * @notice Swap checks to ensure the reserve value is not decreased
   * @param swapData Swap data
   */
  function _swapCheck(SwapData memory swapData) private view {
    FPMMStorage storage $ = _getFPMMStorage();

    uint256 newReserveValue = _totalValueInToken1Scaled(
      $.reserve0,
      $.reserve1,
      swapData.rateNumerator,
      swapData.rateDenominator
    );

    // TODO: think about rounding here
    uint256 expectedAmount0In = convertWithRate(
      swapData.amount1Out,
      $.decimals1,
      $.decimals0,
      swapData.rateDenominator,
      swapData.rateNumerator
    );

    // TODO: think about rounding here
    uint256 expectedAmount1In = convertWithRate(
      swapData.amount0Out,
      $.decimals0,
      $.decimals1,
      swapData.rateNumerator,
      swapData.rateDenominator
    );

    uint256 fee0 = (expectedAmount0In * BASIS_POINTS_DENOMINATOR) /
      (BASIS_POINTS_DENOMINATOR - $.protocolFee) -
      expectedAmount0In;
    uint256 fee1 = (expectedAmount1In * BASIS_POINTS_DENOMINATOR) /
      (BASIS_POINTS_DENOMINATOR - $.protocolFee) -
      expectedAmount1In;

    uint256 fee0InToken1 = convertWithRate(
      fee0,
      $.decimals0,
      $.decimals1,
      swapData.rateNumerator,
      swapData.rateDenominator
    );
    uint256 totalFeeInToken1 = fee0InToken1 + fee1;
    // convert to 18 decimals
    totalFeeInToken1 = totalFeeInToken1 * (1e18 / $.decimals1);

    // Check the reserve value is not decreased
    uint256 expectedReserveValue = swapData.initialReserveValue + totalFeeInToken1;
    require(newReserveValue >= expectedReserveValue, "FPMM: RESERVE_VALUE_DECREASED");
  }
}
