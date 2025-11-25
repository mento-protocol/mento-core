// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
// solhint-disable func-name-mixedcase

import { IOracleAdapter } from "./IOracleAdapter.sol";

import { IRPool } from "../swap/router/interfaces/IRPool.sol";
import { ITradingLimitsV2 } from "./ITradingLimitsV2.sol";

interface IFPMM is IRPool {
  /* ============================================================ */
  /* ======================== Structs ============================ */
  /* ============================================================ */

  /// @notice Struct to store FPMM contract state
  /// @custom:storage-location erc7201:mento.storage.FPMM
  struct FPMMStorage {
    // token0 is the stable token
    address token0;
    // token1 is the collateral token
    address token1;
    // decimals of token0 kepts as 10^decimals
    uint256 decimals0;
    // decimals of token1 kepts as 10^decimals
    uint256 decimals1;
    // reserve amount of token0
    uint256 reserve0;
    // reserve amount of token1
    uint256 reserve1;
    // timestamp of the last reserve update
    uint256 blockTimestampLast;
    // contract for querying oracle price feeds and trading modes
    IOracleAdapter oracleAdapter;
    // true if the rate feed should be inverted to quote asset0/asset1
    bool invertRateFeed;
    // identifier for the reference rate feed
    // required for querying the oracle adapter
    address referenceRateFeedID;
    // fee taken from the swap for liquidity providers
    uint256 lpFee;
    // fee taken from the swap for the protocol
    uint256 protocolFee;
    // recipient of the protocol fee
    address protocolFeeRecipient;
    // incentive percentage for rebalancing the pool
    uint256 rebalanceIncentive;
    // threshold for rebalancing the pool when reserve price > oracle price
    uint256 rebalanceThresholdAbove;
    // threshold for rebalancing the pool when reserve price < oracle price
    uint256 rebalanceThresholdBelow;
    // true if the address is a trusted liquidity strategy
    mapping(address => bool) liquidityStrategy;
    // Trading limits per token
    mapping(address => ITradingLimitsV2.TradingLimits) tradingLimits;
  }

  /// @notice Struct containing the initialization parameters for the FPMM contract
  struct FPMMParams {
    // fee taken from the swap for liquidity providers
    uint256 lpFee;
    // fee taken from the swap for the protocol
    uint256 protocolFee;
    // recipient of the protocol fee
    address protocolFeeRecipient;
    // incentive percentage for rebalancing the pool
    uint256 rebalanceIncentive;
    // threshold for rebalancing the pool when reserve price > oracle price
    uint256 rebalanceThresholdAbove;
    // threshold for rebalancing the pool when reserve price < oracle price
    uint256 rebalanceThresholdBelow;
  }

  /// @notice Struct to store swap data
  struct SwapData {
    uint256 rateNumerator;
    uint256 rateDenominator;
    uint256 initialReserveValue;
    uint256 initialPriceDifference;
    uint256 amount0In;
    uint256 amount1In;
    uint256 amount0Out;
    uint256 amount1Out;
    uint256 balance0;
    uint256 balance1;
    bool reservePriceAboveOraclePrice;
  }

  /* ============================================================ */
  /* ======================== Errors ============================ */
  /* ============================================================ */

  // @notice Throw when trying to get a price for a rate feed that is not set
  error ReferenceRateNotSet();
  // @notice Throw when the reserves are empty
  error ReservesEmpty();
  // @notice Throw when requesting an amount out for a token that is not the pool's tokens
  error InvalidToken();
  // @notice Throw when trying to set a zero address as a contract address
  error ZeroAddress();
  // @notice Throw when trying to set a protocol fee without a protocol fee recipient
  error ProtocolFeeRecipientRequired();
  // @notice Throw when trying to set a fee that is too high
  error FeeTooHigh();
  // @notice Throw when trying to mint less than the minimum liquidity
  error InsufficientLiquidityMinted();
  // @notice Throw when trying to burn only one of the pool's tokens
  error InsufficientLiquidityBurned();
  // @notice Throw when trying to swap with no output amount
  error InsufficientOutputAmount();
  // @notice Throw when trying to swap more than the available liquidity
  error InsufficientLiquidity();
  // @notice Throw when trying to swap to one of the pool's tokens as the to address
  error InvalidToAddress();
  // @notice Throw when trying to swap without an input amount
  error InsufficientInputAmount();
  // @notice Throw when a non-liquidity strategy tries to call rebalance
  error NotLiquidityStrategy();
  // @notice Throw when trying to rebalance with no output amount
  error OneOutputAmountRequired();
  // @notice Throw when trying to rebalance when the price difference is too small
  error PriceDifferenceTooSmall();
  // @notice Throw when the price difference doesnt improve after rebalance
  error PriceDifferenceNotImproved();
  // @notice Throw when a rebalance operation moves the price difference in the wrong direction
  error PriceDifferenceMovedInWrongDirection();
  // @notice Throw when trying to rebalance with an insufficient amount of token0 input
  error InsufficientAmount0In();
  // @notice Throw when trying to rebalance with an insufficient amount of token1 input
  error InsufficientAmount1In();
  // @notice Throw when the reserve value decreases after a swap
  error ReserveValueDecreased();
  // @notice Throw when trying to set a rebalance incentive that is too high
  error RebalanceIncentiveTooHigh();
  // @notice Throw when trying to set a rebalance threshold that is too high
  error RebalanceThresholdTooHigh();
  // @notice Throw when trying to rebalance with an invalid direction
  error RebalanceDirectionInvalid();
  // @notice Throw when trying to configure trading limits with a limit that doesn't fit in int120
  error LimitDoesNotFitInInt120();
  // @notice Throw when token decimals are invalid
  error InvalidTokenDecimals();

  /* ============================================================ */
  /* ======================== Events ============================ */
  /* ============================================================ */

  /**
   * @notice Emitted when liquidity is added to the pool
   * @param sender Address that initiated the mint
   * @param amount0 Amount of token0 added
   * @param amount1 Amount of token1 added
   * @param liquidity Amount of LP tokens minted
   * @param to Address that receives LP tokens
   */
  event Mint(address indexed sender, uint256 amount0, uint256 amount1, uint256 liquidity, address indexed to);

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
   * @notice Emitted when the LP fee is updated
   * @param oldFee Previous fee in basis points
   * @param newFee New fee in basis points
   */
  event LPFeeUpdated(uint256 oldFee, uint256 newFee);

  /**
   * @notice Emitted when the protocol fee is updated
   * @param oldFee Previous fee in basis points
   * @param newFee New fee in basis points
   */
  event ProtocolFeeUpdated(uint256 oldFee, uint256 newFee);

  /**
   * @notice Emitted when the protocol fee recipient is updated
   * @param oldRecipient Previous recipient of the protocol fee
   * @param newRecipient New recipient of the protocol fee
   */
  event ProtocolFeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

  /**
   * @notice Emitted when the rebalance incentive is updated
   * @param oldIncentive Previous incentive in basis points
   * @param newIncentive New incentive in basis points
   */
  event RebalanceIncentiveUpdated(uint256 oldIncentive, uint256 newIncentive);

  /**
   * @notice Emitted when the rebalance threshold is updated
   * @param oldThresholdAbove Previous threshold above in basis points
   * @param oldThresholdBelow Previous threshold below in basis points
   * @param newThresholdAbove New threshold above in basis points
   * @param newThresholdBelow New threshold below in basis points
   */
  event RebalanceThresholdUpdated(
    uint256 oldThresholdAbove,
    uint256 oldThresholdBelow,
    uint256 newThresholdAbove,
    uint256 newThresholdBelow
  );

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
  event ReferenceRateFeedIDUpdated(address indexed oldRateFeedID, address indexed newRateFeedID);

  /**
   * @notice Emitted when the OracleAdapter contract is updated
   * @param oldOracleAdapter Previous OracleAdapter address
   * @param newOracleAdapter New OracleAdapter address
   */
  event OracleAdapterUpdated(address indexed oldOracleAdapter, address indexed newOracleAdapter);

  /**
   * @notice Emitted when the invert rate feed flag is updated
   * @param oldInvertRateFeed Previous invert rate feed flag
   * @param newInvertRateFeed New invert rate feed flag
   */
  event InvertRateFeedUpdated(bool oldInvertRateFeed, bool newInvertRateFeed);

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
  event UpdateReserves(uint256 reserve0, uint256 reserve1, uint256 blockTimestamp);

  /**
   * @notice Emitted when trading limits are configured
   * @param token Address of the token
   * @param config Trading limits configuration
   */
  event TradingLimitConfigured(address indexed token, ITradingLimitsV2.Config config);

  /* ============================================================ */
  /* ====================== View Functions ====================== */
  /* ============================================================ */

  /**
   * @notice Returns the minimum liquidity that will be locked forever when creating a pool
   * @return Minimum liquidity amount
   */
  function MINIMUM_LIQUIDITY() external view returns (uint256);

  /**
   * @notice Returns the denominator for basis point calculations (10000 = 100%)
   * @return Denominator for basis points
   */
  function BASIS_POINTS_DENOMINATOR() external view returns (uint256);

  /**
   * @notice Returns the mode value for bidirectional trading from circuit breaker
   * @return Mode value for bidirectional trading
   */
  function TRADING_MODE_BIDIRECTIONAL() external view returns (uint256);

  /**
   * @notice Returns the timestamp of the last reserve update
   * @return Timestamp of the last reserve update
   */
  function blockTimestampLast() external view returns (uint256);

  /**
   * @notice Returns the OracleAdapter contract
   * @return Address of the OracleAdapter contract
   */
  function oracleAdapter() external view returns (IOracleAdapter);

  /**
   * @notice Returns the invert rate feed flag
   * @return Invert rate feed flag
   */
  function invertRateFeed() external view returns (bool);

  /**
   * @notice Returns the reference rate feed ID to query for oracle price
   * @return Address of the reference rate feed ID
   */
  function referenceRateFeedID() external view returns (address);

  /**
   * @notice Returns the LP fee in basis points (1 basis point = .01%)
   * @return LP fee in basis points
   */
  function lpFee() external view returns (uint256);

  /**
   * @notice Returns the protocol fee in basis points (1 basis point = .01%)
   * @return Protocol fee in basis points
   */
  function protocolFee() external view returns (uint256);

  /**
   * @notice Returns the recipient of the protocol fee
   * @return Recipient of the protocol fee
   */
  function protocolFeeRecipient() external view returns (address);

  /**
   * @notice Returns the slippage allowed for rebalance operations in basis points
   * @return Rebalance incentive in basis points
   */
  function rebalanceIncentive() external view returns (uint256);

  /**
   * @notice Returns the threshold for triggering rebalance when reserve price > oracle price in basis points
   * @return Rebalance threshold above in basis points
   */
  function rebalanceThresholdAbove() external view returns (uint256);

  /**
   * @notice Returns the threshold for triggering rebalance when reserve price < oracle price in basis points
   * @return Rebalance threshold below in basis points
   */
  function rebalanceThresholdBelow() external view returns (uint256);

  /**
   * @notice Checks if an address is a trusted liquidity strategy
   * @param strategy Address to check
   * @return Whether the address is a trusted liquidity strategy
   */
  function liquidityStrategy(address strategy) external view returns (bool);

  /**
   * @notice Gets current oracle and reserve prices
   * @return oraclePriceNumerator The numerator of the oracle price.
   * @return oraclePriceDenominator The denominator of the oracle price.
   * @return reservePriceNumerator The numerator of the pool reserve price.
   * @return reservePriceDenominator The denominator of the pool reserve price.
   * @return priceDifference The price difference between the oracle and pool reserve prices in basis points.
   * @return reservePriceAboveOraclePrice Whether the pool reserve price is above the oracle price.
   * @dev The prices are returned in 18 decimals.
   */
  function getPrices()
    external
    view
    returns (
      uint256 oraclePriceNumerator,
      uint256 oraclePriceDenominator,
      uint256 reservePriceNumerator,
      uint256 reservePriceDenominator,
      uint256 priceDifference,
      bool reservePriceAboveOraclePrice
    );

  /**
   * @notice Gets trading limits config and state for a token
   * @param token Address of the token
   * @return config Trading limits config for the token
   * @return state Trading limits state for the token
   */
  function getTradingLimits(
    address token
  ) external view returns (ITradingLimitsV2.Config memory config, ITradingLimitsV2.State memory state);

  /* ============================================================ */
  /* ==================== Mutative Functions ==================== */
  /* ============================================================ */

  /**
   * @notice Initializes the FPMM contract
   * @param _token0 Address of the first token
   * @param _token1 Address of the second token
   * @param _oracleAdapter Address of the OracleAdapter contract
   * @param _referenceRateFeedID Address of the reference rate feed ID
   * @param _invertRateFeed Whether to invert the rate feed
   * @param _initialOwner Address of the owner
   * @param _params Parameters for the FPMM contract
   */
  function initialize(
    address _token0,
    address _token1,
    address _oracleAdapter,
    address _referenceRateFeedID,
    bool _invertRateFeed,
    address _initialOwner,
    FPMMParams calldata _params
  ) external;

  /**
   * @notice Mints LP tokens by providing liquidity to the pool
   * @param to Address to receive LP tokens
   * @return liquidity Amount of LP tokens minted
   */
  function mint(address to) external returns (uint256 liquidity);

  /**
   * @notice Burns LP tokens to withdraw liquidity from the pool
   * @param to Address to receive the withdrawn tokens
   * @return amount0 Amount of token0 withdrawn
   * @return amount1 Amount of token1 withdrawn
   */
  function burn(address to) external returns (uint256 amount0, uint256 amount1);

  /**
   * @notice Rebalances the pool to align with oracle price
   * @dev Only callable by approved liquidity strategies
   * @param amount0Out Amount of token0 to output
   * @param amount1Out Amount of token1 to output
   * @param data Optional callback data
   */
  function rebalance(uint256 amount0Out, uint256 amount1Out, bytes calldata data) external;

  /**
   * @notice Sets LP fee
   * @param _lpFee New fee in basis points
   */
  function setLPFee(uint256 _lpFee) external;

  /**
   * @notice Sets protocol fee
   * @param _protocolFee New fee in basis points
   */
  function setProtocolFee(uint256 _protocolFee) external;

  /**
   * @notice Sets protocol fee recipient
   * @param _protocolFeeRecipient The recipient of the protocol fee
   */
  function setProtocolFeeRecipient(address _protocolFeeRecipient) external;

  /**
   * @notice Sets rebalance incentive
   * @param _rebalanceIncentive New incentive in basis points
   */
  function setRebalanceIncentive(uint256 _rebalanceIncentive) external;

  /**
   * @notice Sets rebalance threshold
   * @param _rebalanceThresholdAbove New threshold above in basis points
   * @param _rebalanceThresholdBelow New threshold below in basis points
   */
  function setRebalanceThresholds(uint256 _rebalanceThresholdAbove, uint256 _rebalanceThresholdBelow) external;

  /**
   * @notice Sets liquidity strategy status
   * @param strategy Address of the strategy
   * @param state New status (true = enabled, false = disabled)
   */
  function setLiquidityStrategy(address strategy, bool state) external;

  /**
   * @notice Sets the OracleAdapter contract
   * @param _oracleAdapter Address of the OracleAdapter contract
   */
  function setOracleAdapter(address _oracleAdapter) external;

  /**
   * @notice Sets the invert rate feed flag
   * @param _invertRateFeed Whether to invert the rate feed
   */
  function setInvertRateFeed(bool _invertRateFeed) external;

  /**
   * @notice Sets the reference rate feed ID
   * @param _referenceRateFeedID Address of the reference rate feed
   */
  function setReferenceRateFeedID(address _referenceRateFeedID) external;

  /**
   * @notice Configure trading limits for a token
   * @param token The token to configure limits for
   * @param limit0 The limit0 for the token in token decimals
   * @param limit1 The limit1 for the token in token decimals
   */
  function configureTradingLimit(address token, uint256 limit0, uint256 limit1) external;
}
