// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { IBiPoolManager } from "contracts/interfaces/IBiPoolManager.sol";
import { IBroker } from "contracts/interfaces/IBroker.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { IRPool } from "contracts/swap/router/interfaces/IRPool.sol";
import { FixidityLib } from "celo/contracts/common/FixidityLib.sol";
import { ReentrancyGuard } from "openzeppelin-contracts-next/contracts/security/ReentrancyGuard.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

interface IERC20Metadata {
  /**
   * @dev Returns the decimals places of the token.
   */
  function decimals() external view returns (uint8);
}

/**
 * @title Virtual Pool (Broker Wrapper pre-configured with an immutable pair of assets).
 * @author Mento Labs
 * @notice This contract implements a virtual pool that is compatible with the IRPool interface
 * and routes trades via the Broker contract.
 */
contract VirtualPool is IRPool, ReentrancyGuard {
  using SafeERC20 for IERC20;
  /* ========== IMMUTABLES ========== */

  /// @dev Address of the Broker contract.
  IBroker internal immutable BROKER;

  /// @dev Address of the Exchange Provider.
  address internal immutable EXCHANGE_PROVIDER;

  /// @dev Exchange ID for this pair.
  bytes32 internal immutable EXCHANGE_ID;

  /// @dev Address of the first token.
  address internal immutable TOKEN0;

  /// @dev Address of the second token.
  address internal immutable TOKEN1;

  /// @dev Decimals of the first token.
  uint256 internal immutable DECIMALS0;

  /// @dev Decimals of the second token.
  uint256 internal immutable DECIMALS1;

  /// @dev Whether the token orders is the same as on the ExchangeProvider
  bool internal immutable SAME_TOKEN_ORDER;

  /* ========== CONSTRUCTOR ========== */

  /**
   * @notice Contract constructor
   * @param broker Address of the broker contract.
   * @param exchangeProvider Address of the exchange provider.
   * @param exchangeId Address of the exchange ID for this pair.
   * @param _token0 Address of the first token.
   * @param _token1 Address of the second token.
   */
  constructor(
    address broker,
    address exchangeProvider,
    bytes32 exchangeId,
    address _token0,
    address _token1,
    bool sameOrder
  ) {
    BROKER = IBroker(broker);
    EXCHANGE_PROVIDER = exchangeProvider;
    EXCHANGE_ID = exchangeId;
    TOKEN0 = _token0;
    TOKEN1 = _token1;
    DECIMALS0 = 10 ** uint256(IERC20Metadata(_token0).decimals());
    DECIMALS1 = 10 ** uint256(IERC20Metadata(_token1).decimals());
    SAME_TOKEN_ORDER = sameOrder;
    IERC20(_token0).safeApprove(broker, type(uint256).max);
    IERC20(_token1).safeApprove(broker, type(uint256).max);
  }

  /* ========== VIEW FUNCTIONS ========== */

  /// @inheritdoc IRPool
  function metadata()
    external
    view
    returns (uint256 dec0, uint256 dec1, uint256 r0, uint256 r1, address t0, address t1)
  {
    IBiPoolManager.PoolExchange memory exchange = IBiPoolManager(EXCHANGE_PROVIDER).exchanges(EXCHANGE_ID);
    (uint256 bucket0, uint256 bucket1) = SAME_TOKEN_ORDER
      ? (exchange.bucket0, exchange.bucket1)
      : (exchange.bucket1, exchange.bucket0);
    return (DECIMALS0, DECIMALS1, bucket0, bucket1, TOKEN0, TOKEN1);
  }

  /// @inheritdoc IRPool
  function tokens() external view returns (address, address) {
    return (TOKEN0, TOKEN1);
  }

  /// @inheritdoc IRPool
  function getReserves() public view returns (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast) {
    IBiPoolManager.PoolExchange memory exchange = IBiPoolManager(EXCHANGE_PROVIDER).exchanges(EXCHANGE_ID);
    (uint256 bucket0, uint256 bucket1) = SAME_TOKEN_ORDER
      ? (exchange.bucket0, exchange.bucket1)
      : (exchange.bucket1, exchange.bucket0);
    return (bucket0, bucket1, exchange.lastBucketUpdate);
  }

  /// @inheritdoc IRPool
  function token0() external view returns (address) {
    return TOKEN0;
  }

  /// @inheritdoc IRPool
  function token1() external view returns (address) {
    return TOKEN1;
  }

  /// @inheritdoc IRPool
  function decimals0() external view returns (uint256) {
    return DECIMALS0;
  }

  /// @inheritdoc IRPool
  function decimals1() external view returns (uint256) {
    return DECIMALS1;
  }

  /// @inheritdoc IRPool
  function reserve0() external view returns (uint256) {
    IBiPoolManager.PoolExchange memory exchange = IBiPoolManager(EXCHANGE_PROVIDER).exchanges(EXCHANGE_ID);
    return SAME_TOKEN_ORDER ? exchange.bucket0 : exchange.bucket1;
  }

  /// @inheritdoc IRPool
  function reserve1() external view returns (uint256) {
    IBiPoolManager.PoolExchange memory exchange = IBiPoolManager(EXCHANGE_PROVIDER).exchanges(EXCHANGE_ID);
    return SAME_TOKEN_ORDER ? exchange.bucket1 : exchange.bucket0;
  }

  /// @inheritdoc IRPool
  function protocolFee() external view returns (uint256) {
    IBiPoolManager.PoolExchange memory exchange = IBiPoolManager(EXCHANGE_PROVIDER).exchanges(EXCHANGE_ID);
    FixidityLib.Fraction memory spread = exchange.config.spread;
    return spread.value / 1e20;
  }

  /// @inheritdoc IRPool
  function getAmountOut(uint256 amountIn, address tokenIn) public view returns (uint256) {
    require(tokenIn == TOKEN0 || tokenIn == TOKEN1, "VirtualPool: INVALID_TOKEN");
    if (amountIn == 0) return 0;
    address tokenOut = tokenIn == TOKEN0 ? TOKEN1 : TOKEN0;

    return BROKER.getAmountOut(EXCHANGE_PROVIDER, EXCHANGE_ID, tokenIn, tokenOut, amountIn);
  }

  /* ========== EXTERNAL FUNCTIONS ========== */
  /// @inheritdoc IRPool
  function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external nonReentrant {
    require(amount0Out | amount1Out != 0, "VirtualPool: INSUFFICIENT_OUTPUT_AMOUNT");
    // Flash swaps are not supported.
    require(data.length == 0 && (amount0Out == 0 || amount1Out == 0), "VirtualPool: ONE_AMOUNT_MUST_BE_ZERO");
    require(to != TOKEN0 && to != TOKEN1 && to != address(this), "VirtualPool: INVALID_TO_ADDRESS");

    uint256 amount0In = IERC20(TOKEN0).balanceOf(address(this));
    uint256 amount1In = IERC20(TOKEN1).balanceOf(address(this));
    (address tokenIn, address tokenOut, uint256 amountInMax, uint256 amountOut) = amount0Out == 0
      ? (TOKEN0, TOKEN1, amount0In, amount1Out)
      : (TOKEN1, TOKEN0, amount1In, amount0Out);

    // slither-disable-next-line unused-return
    BROKER.swapOut(EXCHANGE_PROVIDER, EXCHANGE_ID, tokenIn, tokenOut, amountOut, amountInMax);
    IERC20(tokenOut).safeTransfer(to, amountOut);
    emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
  }
}
