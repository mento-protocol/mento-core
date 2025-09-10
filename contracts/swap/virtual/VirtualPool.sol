// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

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
  uint8 internal immutable DECIMALS0;

  /// @dev Decimals of the second token.
  uint8 internal immutable DECIMALS1;

  /* ========== CONSTRUCTOR ========== */

  /**
   * @notice Contract constructor
   * @param broker Address of the broker contract.
   * @param exchangeProvider Address of the exchange provider.
   * @param exchangeId Address of the exchange ID for this pair.
   * @param _token0 Address of the first token.
   * @param _token1 Address of the second token.
   */
  constructor(address broker, address exchangeProvider, bytes32 exchangeId, address _token0, address _token1) {
    BROKER = IBroker(broker);
    EXCHANGE_PROVIDER = exchangeProvider;
    EXCHANGE_ID = exchangeId;
    TOKEN0 = _token0;
    TOKEN1 = _token1;
    DECIMALS0 = IERC20Metadata(_token0).decimals();
    DECIMALS1 = IERC20Metadata(_token1).decimals();
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
    return (DECIMALS0, DECIMALS1, exchange.bucket0, exchange.bucket1, TOKEN0, TOKEN1);
  }

  /// @inheritdoc IRPool
  function tokens() external view returns (address, address) {
    return (TOKEN0, TOKEN1);
  }

  /// @inheritdoc IRPool
  function getReserves() public view returns (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast) {
    IBiPoolManager.PoolExchange memory exchange = IBiPoolManager(EXCHANGE_PROVIDER).exchanges(EXCHANGE_ID);
    return (exchange.bucket0, exchange.bucket1, block.timestamp);
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
    return exchange.bucket0;
  }

  /// @inheritdoc IRPool
  function reserve1() external view returns (uint256) {
    IBiPoolManager.PoolExchange memory exchange = IBiPoolManager(EXCHANGE_PROVIDER).exchanges(EXCHANGE_ID);
    return exchange.bucket1;
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
    // Swaps that go through the router seem to always have one of the 2 amounts be zero.
    require(amount0Out == 0 || amount1Out == 0, "VirtualPool: Must swap through Router");
    // Flash swaps are not supported.
    require(data.length == 0, "VirtualPool: Must swap through Router");
    require(to != TOKEN0 && to != TOKEN1, "VirtualPool: INVALID_TO_ADDRESS");

    (address tokenIn, address tokenOut) = amount0Out == 0 ? (TOKEN0, TOKEN1) : (TOKEN1, TOKEN0);
    uint256 amountIn = IERC20(tokenIn).balanceOf(address(this));

    uint256 amountOut = BROKER.swapIn(EXCHANGE_PROVIDER, EXCHANGE_ID, tokenIn, tokenOut, amountIn, 0);
    IERC20(tokenOut).safeTransfer(to, amountOut);
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  /**
   * @notice Sorts two tokens by their address value.
   * @param tokenA The address of one token (needs to be different from address(0)).
   * @param tokenB The address of the other token (needs to be different from tokenA and address(0)).
   * @return _token0 The address of the first token.
   * @return _token1 The address of the second token.
   */
  function _sortTokens(address tokenA, address tokenB) public pure returns (address _token0, address _token1) {
    require(tokenA != tokenB, "VirtualPool: IDENTICAL_TOKEN_ADDRESSES");
    (_token0, _token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    require(_token0 != address(0), "VirtualPool: ZERO_ADDRESS");
  }
}
