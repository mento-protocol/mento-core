// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import "../interfaces/IFPMM.sol";
import "./router/interfaces/IRPool.sol";
import { ERC20Upgradeable } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
// solhint-disable-next-line max-line-length
import { ReentrancyGuardUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import { MathUpgradeable as Math } from "openzeppelin-contracts-upgradeable/contracts/utils/math/MathUpgradeable.sol";
// solhint-disable-next-line max-line-length
import { SafeERC20Upgradeable } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
// solhint-disable-next-line max-line-length
import { IERC20Upgradeable as IERC20 } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import { IOracleAdapter } from "../interfaces/IOracleAdapter.sol";
import { IFPMMCallee } from "../interfaces/IFPMMCallee.sol";
import { ILiquidityStrategy } from "../interfaces/ILiquidityStrategy.sol";
import { TradingLimitsV2 } from "../libraries/TradingLimitsV2.sol";
import { ITradingLimitsV2 } from "../interfaces/ITradingLimitsV2.sol";

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
 * 4. Rebalance can change the direction of the price difference but not by more than the rebalance incentive
 */
contract FPMM is IRPool, IFPMM, ReentrancyGuardUpgradeable, ERC20Upgradeable, OwnableUpgradeable {
  using SafeERC20Upgradeable for IERC20;
  using TradingLimitsV2 for ITradingLimitsV2.State;
  using TradingLimitsV2 for ITradingLimitsV2.Config;
  using TradingLimitsV2 for ITradingLimitsV2.TradingLimits;

  /* ============================================================ */
  /* ======================== Constants ========================= */
  /* ============================================================ */

  /// @inheritdoc IFPMM
  uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

  /// @inheritdoc IFPMM
  uint256 public constant BASIS_POINTS_DENOMINATOR = 10_000;

  /// @inheritdoc IFPMM
  uint256 public constant TRADING_MODE_BIDIRECTIONAL = 0;

  // keccak256(abi.encode(uint256(keccak256("mento.storage.FPMM")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant _FPMM_STORAGE_LOCATION = 0xe40ad100017325097d9c1a3195cd4d2d97dcb316ccef4f208489777afd465d00;

  /* ============================================================ */
  /* ======================== Constructor ======================= */
  /* ============================================================ */

  /**
   * @notice Contract constructor
   * @param disable Boolean to disable initializers for implementation contract
   */
  constructor(bool disable) {
    if (disable) {
      _disableInitializers();
    }
  }

  /* ============================================================ */
  /* ==================== Initialization ======================== */
  /* ============================================================ */

  /// @inheritdoc IFPMM
  function initialize(
    address _token0,
    address _token1,
    address _oracleAdapter,
    address _referenceRateFeedID,
    bool _invertRateFeed,
    address _initialOwner,
    FPMMParams calldata _params
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

    uint8 token0Decimals = ERC20Upgradeable(_token0).decimals();
    uint8 token1Decimals = ERC20Upgradeable(_token1).decimals();

    if (token0Decimals > 18 || token1Decimals > 18) revert InvalidTokenDecimals();

    $.decimals0 = 10 ** token0Decimals;
    $.decimals1 = 10 ** token1Decimals;

    setLPFee(_params.lpFee);
    setProtocolFeeRecipient(_params.protocolFeeRecipient);
    setProtocolFee(_params.protocolFee);
    setRebalanceIncentive(_params.rebalanceIncentive);
    setRebalanceThresholds(_params.rebalanceThresholdAbove, _params.rebalanceThresholdBelow);

    setOracleAdapter(_oracleAdapter);
    setReferenceRateFeedID(_referenceRateFeedID);
    setInvertRateFeed(_invertRateFeed);
    transferOwnership(_initialOwner);
  }

  /* ============================================================ */
  /* ====================== View Functions ====================== */
  /* ============================================================ */

  /// @inheritdoc IRPool
  function metadata()
    external
    view
    returns (uint256 dec0, uint256 dec1, uint256 r0, uint256 r1, address t0, address t1)
  {
    FPMMStorage storage $ = _getFPMMStorage();

    return ($.decimals0, $.decimals1, $.reserve0, $.reserve1, $.token0, $.token1);
  }

  /// @inheritdoc IRPool
  function tokens() external view returns (address, address) {
    FPMMStorage storage $ = _getFPMMStorage();

    return ($.token0, $.token1);
  }

  /// @inheritdoc IRPool
  function getReserves() public view returns (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast) {
    FPMMStorage storage $ = _getFPMMStorage();

    _reserve0 = $.reserve0;
    _reserve1 = $.reserve1;
    _blockTimestampLast = $.blockTimestampLast;
  }

  /// @inheritdoc IRPool
  function token0() external view returns (address) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.token0;
  }

  /// @inheritdoc IRPool
  function token1() external view returns (address) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.token1;
  }

  /// @inheritdoc IRPool
  function decimals0() external view returns (uint256) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.decimals0;
  }

  /// @inheritdoc IRPool
  function decimals1() external view returns (uint256) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.decimals1;
  }

  /// @inheritdoc IRPool
  function reserve0() external view returns (uint256) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.reserve0;
  }

  /// @inheritdoc IRPool
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
  function oracleAdapter() external view returns (IOracleAdapter) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.oracleAdapter;
  }

  /// @inheritdoc IFPMM
  function invertRateFeed() external view returns (bool) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.invertRateFeed;
  }

  /// @inheritdoc IFPMM
  function referenceRateFeedID() external view returns (address) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.referenceRateFeedID;
  }

  /// @inheritdoc IFPMM
  function lpFee() external view returns (uint256) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.lpFee;
  }

  /// @inheritdoc IFPMM
  function protocolFee() external view override(IFPMM, IRPool) returns (uint256) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.protocolFee;
  }

  /// @inheritdoc IFPMM
  function protocolFeeRecipient() external view returns (address) {
    FPMMStorage storage $ = _getFPMMStorage();
    return $.protocolFeeRecipient;
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

    if ($.referenceRateFeedID == address(0)) revert ReferenceRateNotSet();
    if ($.reserve0 == 0 || $.reserve1 == 0) revert ReservesEmpty();

    (oraclePriceNumerator, oraclePriceDenominator) = _getRateFeed();

    // slither-disable-start divide-before-multiply
    reservePriceNumerator = $.reserve1 * (1e18 / $.decimals1);
    reservePriceDenominator = $.reserve0 * (1e18 / $.decimals0);
    // slither-disable-end divide-before-multiply

    (priceDifference, reservePriceAboveOraclePrice) = _calculatePriceDifference(
      oraclePriceNumerator,
      oraclePriceDenominator,
      reservePriceNumerator,
      reservePriceDenominator
    );

    return (
      oraclePriceNumerator,
      oraclePriceDenominator,
      reservePriceNumerator,
      reservePriceDenominator,
      priceDifference,
      reservePriceAboveOraclePrice
    );
  }

  /// @inheritdoc IRPool
  function getAmountOut(uint256 amountIn, address tokenIn) public view returns (uint256 amountOut) {
    FPMMStorage storage $ = _getFPMMStorage();

    if (tokenIn != $.token0 && tokenIn != $.token1) revert InvalidToken();

    if (amountIn == 0) return 0;

    (uint256 rateNumerator, uint256 rateDenominator) = _getRateFeed();

    if (tokenIn == $.token0) {
      return
        _convertWithRateAndFee(
          amountIn,
          $.decimals0,
          $.decimals1,
          rateNumerator,
          rateDenominator,
          BASIS_POINTS_DENOMINATOR - ($.lpFee + $.protocolFee),
          BASIS_POINTS_DENOMINATOR
        );
    } else {
      return
        _convertWithRateAndFee(
          amountIn,
          $.decimals1,
          $.decimals0,
          rateDenominator,
          rateNumerator,
          BASIS_POINTS_DENOMINATOR - ($.lpFee + $.protocolFee),
          BASIS_POINTS_DENOMINATOR
        );
    }
  }

  /// @inheritdoc IFPMM
  function getTradingLimits(
    address token
  ) external view returns (ITradingLimitsV2.Config memory config, ITradingLimitsV2.State memory state) {
    FPMMStorage storage $ = _getFPMMStorage();
    if (token != $.token0 && token != $.token1) revert InvalidToken();

    config = $.tradingLimits[token].config;
    state = $.tradingLimits[token].state;
  }

  /* ============================================================ */
  /* ====================== External Functions ================== */
  /* ============================================================ */

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

    if (liquidity <= MINIMUM_LIQUIDITY) revert InsufficientLiquidityMinted();
    _mint(to, liquidity);

    _update();

    emit Mint(msg.sender, amount0, amount1, liquidity, to);
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

    // slither-disable-next-line incorrect-equality
    if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidityBurned();

    _burn(address(this), liquidity);

    IERC20($.token0).safeTransfer(to, amount0);
    IERC20($.token1).safeTransfer(to, amount1);

    _update();

    emit Burn(msg.sender, amount0, amount1, liquidity, to);
  }

  // slither-disable-end reentrancy-benign
  // slither-disable-end reentrancy-no-eth

  // slither-disable-start reentrancy-no-eth
  /// @inheritdoc IRPool
  function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external nonReentrant {
    FPMMStorage storage $ = _getFPMMStorage();

    if (amount0Out == 0 && amount1Out == 0) revert InsufficientOutputAmount();
    if (amount0Out >= $.reserve0 || amount1Out >= $.reserve1) revert InsufficientLiquidity();
    if (to == $.token0 || to == $.token1) revert InvalidToAddress();

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
    // slither-disable-next-line incorrect-equality
    if (swapData.amount0In == 0 && swapData.amount1In == 0) revert InsufficientInputAmount();

    _transferProtocolFee(swapData.amount0In, swapData.amount1In);

    _applyTradingLimits($.token0, swapData.amount0In, swapData.amount0Out);
    _applyTradingLimits($.token1, swapData.amount1In, swapData.amount1Out);

    _update();

    _swapCheck(swapData);

    emit Swap(msg.sender, swapData.amount0In, swapData.amount1In, amount0Out, amount1Out, to);
  }

  // slither-disable-end reentrancy-no-eth

  // slither-disable-start reentrancy-no-eth
  // solhint-disable code-complexity
  /// @inheritdoc IFPMM
  function rebalance(uint256 amount0Out, uint256 amount1Out, bytes calldata data) external nonReentrant {
    FPMMStorage storage $ = _getFPMMStorage();

    if (!$.liquidityStrategy[msg.sender]) revert NotLiquidityStrategy();
    if ((amount0Out > 0) == (amount1Out > 0)) revert OneOutputAmountRequired();
    if (amount0Out >= $.reserve0 || amount1Out >= $.reserve1) revert InsufficientLiquidity();

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
    if (swapData.initialPriceDifference < threshold) revert PriceDifferenceTooSmall();

    if (amount0Out > 0) IERC20($.token0).safeTransfer(msg.sender, amount0Out);
    if (amount1Out > 0) IERC20($.token1).safeTransfer(msg.sender, amount1Out);

    if (data.length > 0) ILiquidityStrategy(msg.sender).onRebalance(msg.sender, amount0Out, amount1Out, data);

    uint256 balance0 = IERC20($.token0).balanceOf(address(this));
    uint256 balance1 = IERC20($.token1).balanceOf(address(this));

    uint256 amount0In = balance0 > $.reserve0 - amount0Out ? balance0 - ($.reserve0 - amount0Out) : 0;
    uint256 amount1In = balance1 > $.reserve1 - amount1Out ? balance1 - ($.reserve1 - amount1Out) : 0;

    // slither-disable-next-line incorrect-equality
    if (!((amount0Out > 0 && amount1In > 0 && amount0In == 0) || (amount1Out > 0 && amount0In > 0 && amount1In == 0)))
      revert RebalanceDirectionInvalid();

    swapData.amount0In = amount0In;
    swapData.amount1In = amount1In;

    _update();

    uint256 newPriceDifference = _rebalanceCheck(swapData);
    emit Rebalanced(msg.sender, swapData.initialPriceDifference, newPriceDifference);
  }

  // solhint-enable code-complexity
  // slither-disable-end reentrancy-no-eth

  /* ============================================================ */
  /* ===================== Admin Functions ====================== */
  /* ============================================================ */

  /// @inheritdoc IFPMM
  function setLPFee(uint256 _lpFee) public virtual onlyOwner {
    FPMMStorage storage $ = _getFPMMStorage();

    if (_lpFee + $.protocolFee > 100) revert FeeTooHigh(); // Max 1% combined

    uint256 oldFee = $.lpFee;
    $.lpFee = _lpFee;
    emit LPFeeUpdated(oldFee, _lpFee);
  }

  /// @inheritdoc IFPMM
  function setProtocolFee(uint256 _protocolFee) public onlyOwner {
    FPMMStorage storage $ = _getFPMMStorage();

    if (_protocolFee > 0 && $.protocolFeeRecipient == address(0)) revert ProtocolFeeRecipientRequired();
    if (_protocolFee + $.lpFee > 100) revert FeeTooHigh(); // Max 1% combined

    uint256 oldFee = $.protocolFee;
    $.protocolFee = _protocolFee;
    emit ProtocolFeeUpdated(oldFee, _protocolFee);
  }

  /// @inheritdoc IFPMM
  function setProtocolFeeRecipient(address _protocolFeeRecipient) public onlyOwner {
    FPMMStorage storage $ = _getFPMMStorage();

    if (_protocolFeeRecipient == address(0)) revert ZeroAddress();

    address oldRecipient = $.protocolFeeRecipient;
    $.protocolFeeRecipient = _protocolFeeRecipient;
    emit ProtocolFeeRecipientUpdated(oldRecipient, _protocolFeeRecipient);
  }

  /// @inheritdoc IFPMM
  function setRebalanceIncentive(uint256 _rebalanceIncentive) public onlyOwner {
    FPMMStorage storage $ = _getFPMMStorage();

    if (_rebalanceIncentive > 100) revert RebalanceIncentiveTooHigh(); // Max 1%
    uint256 oldIncentive = $.rebalanceIncentive;
    $.rebalanceIncentive = _rebalanceIncentive;
    emit RebalanceIncentiveUpdated(oldIncentive, _rebalanceIncentive);
  }

  /// @inheritdoc IFPMM
  function setRebalanceThresholds(uint256 _rebalanceThresholdAbove, uint256 _rebalanceThresholdBelow) public onlyOwner {
    FPMMStorage storage $ = _getFPMMStorage();

    if (_rebalanceThresholdAbove > 1000) revert RebalanceThresholdTooHigh(); // Max 10%
    if (_rebalanceThresholdBelow > 1000) revert RebalanceThresholdTooHigh(); // Max 10%
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
    if (strategy == address(0)) revert ZeroAddress();

    FPMMStorage storage $ = _getFPMMStorage();

    $.liquidityStrategy[strategy] = state;
    emit LiquidityStrategyUpdated(strategy, state);
  }

  /// @inheritdoc IFPMM
  function setOracleAdapter(address _oracleAdapter) public onlyOwner {
    if (_oracleAdapter == address(0)) revert ZeroAddress();

    FPMMStorage storage $ = _getFPMMStorage();

    address oldOracleAdapter = address($.oracleAdapter);
    $.oracleAdapter = IOracleAdapter(_oracleAdapter);
    emit OracleAdapterUpdated(oldOracleAdapter, _oracleAdapter);
  }

  function setInvertRateFeed(bool _invertRateFeed) public onlyOwner {
    FPMMStorage storage $ = _getFPMMStorage();

    bool oldInvertRateFeed = $.invertRateFeed;
    $.invertRateFeed = _invertRateFeed;

    emit InvertRateFeedUpdated(oldInvertRateFeed, _invertRateFeed);
  }

  /// @inheritdoc IFPMM
  function setReferenceRateFeedID(address _referenceRateFeedID) public onlyOwner {
    if (_referenceRateFeedID == address(0)) revert ZeroAddress();

    FPMMStorage storage $ = _getFPMMStorage();

    address oldRateFeedID = $.referenceRateFeedID;
    $.referenceRateFeedID = _referenceRateFeedID;
    emit ReferenceRateFeedIDUpdated(oldRateFeedID, _referenceRateFeedID);
  }

  /// @inheritdoc IFPMM
  function configureTradingLimit(address token, uint256 limit0, uint256 limit1) external onlyOwner {
    FPMMStorage storage $ = _getFPMMStorage();
    if (token != $.token0 && token != $.token1) revert InvalidToken();

    // slither-disable-next-line uninitialized-local
    ITradingLimitsV2.Config memory config;
    config.decimals = ERC20Upgradeable(token).decimals();

    // scale to 15 decimals for TradingLimitsV2 library internal precision
    limit0 = (limit0 * 1e15) / 10 ** config.decimals;
    limit1 = (limit1 * 1e15) / 10 ** config.decimals;

    if (limit0 > uint120(type(int120).max) || limit1 > uint120(type(int120).max)) revert LimitDoesNotFitInInt120();
    config.limit0 = int120(uint120(limit0));
    config.limit1 = int120(uint120(limit1));

    config.validate();

    $.tradingLimits[token].config = config;
    $.tradingLimits[token].state = $.tradingLimits[token].state.reset(config);

    emit TradingLimitConfigured(token, config);
  }

  /* ============================================================ */
  /* ==================== Internal Functions ==================== */
  /* ============================================================ */

  /**
   * @notice Returns the storage pointer for the FPMM contract
   * @return $ Pointer to the FPMM storage
   */
  function _getFPMMStorage() internal pure returns (FPMMStorage storage $) {
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
   * @notice Transfers the protocol fee to the protocol fee recipient
   * @param amount0In Amount of token0 in from swap
   * @param amount1In Amount of token1 in from swap
   */
  function _transferProtocolFee(uint256 amount0In, uint256 amount1In) private {
    FPMMStorage storage $ = _getFPMMStorage();

    uint256 fee = $.protocolFee;
    if (fee == 0) return;

    if (amount0In > 0) {
      uint256 feeAmount = (amount0In * fee) / BASIS_POINTS_DENOMINATOR;
      IERC20($.token0).safeTransfer($.protocolFeeRecipient, feeAmount);
    }

    if (amount1In > 0) {
      uint256 feeAmount = (amount1In * fee) / BASIS_POINTS_DENOMINATOR;
      IERC20($.token1).safeTransfer($.protocolFeeRecipient, feeAmount);
    }
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

    uint256 token0ValueInToken1 = _convertWithRate(amount0, $.decimals0, 1e18, rateNumerator, rateDenominator);
    // slither-disable-next-line divide-before-multiply
    amount1 = amount1 * (1e18 / $.decimals1);
    return token0ValueInToken1 + amount1;
  }

  function _getRateFeed() internal view virtual returns (uint256 rateNumerator, uint256 rateDenominator) {
    FPMMStorage storage $ = _getFPMMStorage();

    (rateNumerator, rateDenominator) = $.oracleAdapter.getFXRateIfValid($.referenceRateFeedID);

    if ($.invertRateFeed) {
      (rateNumerator, rateDenominator) = (rateDenominator, rateNumerator);
    }
  }

  /**
   * @notice Calculates the price difference between oracle and reserve prices
   * @param oraclePriceNumerator Oracle price numerator
   * @param oraclePriceDenominator Oracle price denominator
   * @param reservePriceNumerator Reserve price numerator
   * @param reservePriceDenominator Reserve price denominator
   * @return priceDifference Price difference in basis points
   * @return reservePriceAboveOraclePrice Whether reserve price is above oracle price
   */
  function _calculatePriceDifference(
    uint256 oraclePriceNumerator,
    uint256 oraclePriceDenominator,
    uint256 reservePriceNumerator,
    uint256 reservePriceDenominator
  ) internal pure returns (uint256 priceDifference, bool reservePriceAboveOraclePrice) {
    uint256 oracleCrossProduct = oraclePriceNumerator * reservePriceDenominator;
    uint256 reserveCrossProduct = reservePriceNumerator * oraclePriceDenominator;
    reservePriceAboveOraclePrice = reserveCrossProduct > oracleCrossProduct;

    uint256 absolutePriceDiff = reservePriceAboveOraclePrice
      ? reserveCrossProduct - oracleCrossProduct
      : oracleCrossProduct - reserveCrossProduct;
    priceDifference = (absolutePriceDiff * BASIS_POINTS_DENOMINATOR) / oracleCrossProduct;
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

    // slither-disable-start divide-before-multiply
    uint256 reservePriceNumerator = $.reserve1 * (1e18 / $.decimals1);
    uint256 reservePriceDenominator = $.reserve0 * (1e18 / $.decimals0);
    // slither-disable-end divide-before-multiply

    bool reservePriceAboveOraclePrice;
    (newPriceDifference, reservePriceAboveOraclePrice) = _calculatePriceDifference(
      swapData.rateNumerator,
      swapData.rateDenominator,
      reservePriceNumerator,
      reservePriceDenominator
    );

    // Ensure price difference is smaller than before
    if (newPriceDifference >= swapData.initialPriceDifference) revert PriceDifferenceNotImproved();
    // we allow the price difference to be moved in the wrong direction but not by more than the rebalance incentive
    // this is due to the dynamic rebalance fee on redemptions.
    // slither-disable-next-line incorrect-equality
    if (
      reservePriceAboveOraclePrice != swapData.reservePriceAboveOraclePrice &&
      newPriceDifference > (swapData.initialPriceDifference * $.rebalanceIncentive) / BASIS_POINTS_DENOMINATOR
    ) revert PriceDifferenceMovedInWrongDirection();

    if (swapData.amount0In > 0) {
      uint256 minAmount0In = _convertWithRateAndFee(
        swapData.amount1Out,
        $.decimals1,
        $.decimals0,
        swapData.rateDenominator,
        swapData.rateNumerator,
        BASIS_POINTS_DENOMINATOR - $.rebalanceIncentive,
        BASIS_POINTS_DENOMINATOR
      );
      if (swapData.amount0In < minAmount0In) revert InsufficientAmount0In();
    } else {
      uint256 minAmount1In = _convertWithRateAndFee(
        swapData.amount0Out,
        $.decimals0,
        $.decimals1,
        swapData.rateNumerator,
        swapData.rateDenominator,
        BASIS_POINTS_DENOMINATOR - $.rebalanceIncentive,
        BASIS_POINTS_DENOMINATOR
      );
      if (swapData.amount1In < minAmount1In) revert InsufficientAmount1In();
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
    uint256 expectedAmount0In = _convertWithRate(
      swapData.amount1Out,
      $.decimals1,
      $.decimals0,
      swapData.rateDenominator,
      swapData.rateNumerator
    );

    // TODO: think about rounding here
    uint256 expectedAmount1In = _convertWithRate(
      swapData.amount0Out,
      $.decimals0,
      $.decimals1,
      swapData.rateNumerator,
      swapData.rateDenominator
    );

    uint256 lpFeeBps = $.lpFee;
    uint256 totalFeeBps = lpFeeBps + $.protocolFee;

    uint256 fee0 = (expectedAmount0In * BASIS_POINTS_DENOMINATOR) /
      (BASIS_POINTS_DENOMINATOR - totalFeeBps) -
      expectedAmount0In;
    uint256 fee1 = (expectedAmount1In * BASIS_POINTS_DENOMINATOR) /
      (BASIS_POINTS_DENOMINATOR - totalFeeBps) -
      expectedAmount1In;

    fee0 = totalFeeBps > 0 ? (fee0 * lpFeeBps) / totalFeeBps : 0;
    fee1 = totalFeeBps > 0 ? (fee1 * lpFeeBps) / totalFeeBps : 0;

    uint256 fee0InToken1 = _convertWithRate(
      fee0,
      $.decimals0,
      $.decimals1,
      swapData.rateNumerator,
      swapData.rateDenominator
    );
    uint256 totalFeeInToken1 = fee0InToken1 + fee1;
    // convert to 18 decimals
    // slither-disable-next-line divide-before-multiply
    totalFeeInToken1 = totalFeeInToken1 * (1e18 / $.decimals1);

    // Check the reserve value is not decreased
    uint256 expectedReserveValue = swapData.initialReserveValue + totalFeeInToken1;
    if (newReserveValue < expectedReserveValue) revert ReserveValueDecreased();
  }

  function _convertWithRate(
    uint256 amount,
    uint256 fromDecimals,
    uint256 toDecimals,
    uint256 numerator,
    uint256 denominator
  ) internal pure returns (uint256) {
    return (amount * numerator * toDecimals) / (denominator * fromDecimals);
  }

  function _convertWithRateAndFee(
    uint256 amount,
    uint256 fromDecimals,
    uint256 toDecimals,
    uint256 numerator,
    uint256 denominator,
    uint256 incentiveNum,
    uint256 incentiveDen
  ) internal pure returns (uint256) {
    return (amount * numerator * toDecimals * incentiveNum) / (denominator * fromDecimals * incentiveDen);
  }

  /**
   * @notice Apply trading limits for a token
   * @param token Address of the token
   * @param amountIn Amount of token flowing into the pool
   * @param amountOut Amount of token flowing out of the pool
   */
  function _applyTradingLimits(address token, uint256 amountIn, uint256 amountOut) internal {
    FPMMStorage storage $ = _getFPMMStorage();
    $.tradingLimits[token].state = $.tradingLimits[token].applyTradingLimits(amountIn, amountOut);
  }
}
