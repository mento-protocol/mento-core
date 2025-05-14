// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
// solhint-disable func-name-mixedcase

import { ISortedOracles } from "./ISortedOracles.sol";
import { IBreakerBox } from "./IBreakerBox.sol";

interface IFPMM {
  /* ========== STRUCTS ========== */

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
  event UpdateReserves(uint256 reserve0, uint256 reserve1, uint256 blockTimestamp);

  /* ========== VARIABLES ========== */

  /**
   * @notice Returns the minimum liquidity that will be locked forever when creating a pool
   * @return Minimum liquidity amount
   */
  function MINIMUM_LIQUIDITY() external view returns (uint256);

  /**
   * @notice Returns the address of the first token in the pair
   * @return Address of token0
   */
  function token0() external view returns (address);

  /**
   * @notice Returns the address of the second token in the pair
   * @return Address of token1
   */
  function token1() external view returns (address);

  /**
   * @notice Returns the scaling factor for token0 based on its decimals
   * @return Scaling factor for token0
   */
  function decimals0() external view returns (uint256);

  /**
   * @notice Returns the scaling factor for token1 based on its decimals
   * @return Scaling factor for token1
   */
  function decimals1() external view returns (uint256);

  /**
   * @notice Returns the reserve amount of token0
   * @return Reserve amount of token0
   */
  function reserve0() external view returns (uint256);

  /**
   * @notice Returns the reserve amount of token1
   * @return Reserve amount of token1
   */
  function reserve1() external view returns (uint256);

  /**
   * @notice Returns the timestamp of the last reserve update
   * @return Timestamp of the last reserve update
   */
  function blockTimestampLast() external view returns (uint256);

  /**
   * @notice Returns the contract for oracle price feeds
   * @return Address of the SortedOracles contract
   */
  function sortedOracles() external view returns (ISortedOracles);

  /**
   * @notice Returns the circuit breaker contract to enable/disable trading
   * @return Address of the BreakerBox contract
   */
  function breakerBox() external view returns (IBreakerBox);

  /**
   * @notice Returns the reference rate feed ID for oracle price
   * @return Address of the reference rate feed ID
   */
  function referenceRateFeedID() external view returns (address);

  /**
   * @notice Returns the protocol fee in basis points (1 basis point = .01%)
   * @return Protocol fee in basis points
   */
  function protocolFee() external view returns (uint256);

  /**
   * @notice Returns the slippage allowed for rebalance operations in basis points
   * @return Rebalance incentive in basis points
   */
  function rebalanceIncentive() external view returns (uint256);

  /**
   * @notice Returns the threshold for triggering rebalance in basis points
   * @return Rebalance threshold in basis points
   */
  function rebalanceThreshold() external view returns (uint256);

  /**
   * @notice Checks if an address is a trusted liquidity strategy
   * @param strategy Address to check
   * @return Whether the address is a trusted liquidity strategy
   */
  function liquidityStrategy(address strategy) external view returns (bool);

  /* ========== FUNCTIONS ========== */

  /**
   * @notice Initializes the FPMM contract
   * @param _token0 Address of the first token
   * @param _token1 Address of the second token
   * @param _sortedOracles Address of the SortedOracles contract
   * @param _breakerBox Address of the BreakerBox contract
   * @param _owner Address of the owner
   */
  function initialize(
    address _token0,
    address _token1,
    address _sortedOracles,
    address _breakerBox,
    address _owner
  ) external;

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
    returns (uint256 dec0, uint256 dec1, uint256 r0, uint256 r1, address t0, address t1);

  /**
   * @notice Returns addresses of both tokens in the pair
   * @return Address of token0 and token1
   */
  function tokens() external view returns (address, address);

  /**
   * @notice Returns current reserves and timestamp
   * @return _reserve0 Current reserve of token0
   * @return _reserve1 Current reserve of token1
   * @return _blockTimestampLast Timestamp of last reserve update
   */
  function getReserves() external view returns (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast);

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
  ) external view returns (uint256);

  /**
   * @notice Gets current oracle and reserve prices
   * @return oraclePrice Oracle price in 18 decimals
   * @return reservePrice Pool reserve price in 18 decimals
   * @return _decimals0 Scaling factor for token0
   * @return _decimals1 Scaling factor for token1
   */
  function getPrices()
    external
    view
    returns (uint256 oraclePrice, uint256 reservePrice, uint256 _decimals0, uint256 _decimals1);

  /**
   * @notice Calculates output amount for a given input
   * @param amountIn Input amount
   * @param tokenIn Address of input token
   * @return amountOut Output amount after fees
   */
  function getAmountOut(uint256 amountIn, address tokenIn) external view returns (uint256 amountOut);

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
  ) external pure returns (uint256);

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
   * @notice Swaps tokens based on oracle price
   * @param amount0Out Amount of token0 to output
   * @param amount1Out Amount of token1 to output
   * @param to Address receiving output tokens
   * @param data Optional callback data
   */
  function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;

  /**
   * @notice Rebalances the pool to align with oracle price
   * @dev Only callable by approved liquidity strategies
   * @param amount0Out Amount of token0 to output
   * @param amount1Out Amount of token1 to output
   * @param to Address receiving output tokens
   * @param data Optional callback data
   */
  function rebalance(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;

  /**
   * @notice Sets protocol fee
   * @param _protocolFee New fee in basis points
   */
  function setProtocolFee(uint256 _protocolFee) external;

  /**
   * @notice Sets rebalance incentive
   * @param _rebalanceIncentive New incentive in basis points
   */
  function setRebalanceIncentive(uint256 _rebalanceIncentive) external;

  /**
   * @notice Sets rebalance threshold
   * @param _rebalanceThreshold New threshold in basis points
   */
  function setRebalanceThreshold(uint256 _rebalanceThreshold) external;

  /**
   * @notice Sets liquidity strategy status
   * @param strategy Address of the strategy
   * @param state New status (true = enabled, false = disabled)
   */
  function setLiquidityStrategy(address strategy, bool state) external;

  /**
   * @notice Sets the SortedOracles contract
   * @param _sortedOracles Address of the SortedOracles contract
   */
  function setSortedOracles(address _sortedOracles) external;

  /**
   * @notice Sets the BreakerBox contract
   * @param _breakerBox Address of the BreakerBox contract
   */
  function setBreakerBox(address _breakerBox) external;

  /**
   * @notice Sets the reference rate feed ID
   * @param _referenceRateFeedID Address of the reference rate feed
   */
  function setReferenceRateFeedID(address _referenceRateFeedID) external;
}
