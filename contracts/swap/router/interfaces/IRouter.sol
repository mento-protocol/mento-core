// solhint-disable
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IRouter {
  struct Route {
    address from;
    address to;
    address factory;
  }

  error ETHTransferFailed();
  error Expired();
  error InsufficientAmount();
  error InsufficientAmountA();
  error InsufficientAmountB();
  error InsufficientAmountADesired();
  error InsufficientAmountBDesired();
  error InsufficientAmountAOptimal();
  error InsufficientLiquidity();
  error InsufficientOutputAmount();
  error InvalidAmountInForETHDeposit();
  error InvalidTokenInForETHDeposit();
  error InvalidPath();
  error InvalidRouteA();
  error InvalidRouteB();
  error OnlyWETH();
  error PoolDoesNotExist();
  error PoolFactoryDoesNotExist();
  error SameAddresses();
  error ZeroAddress();

  /// @notice Address of FactoryRegistry.sol
  function factoryRegistry() external view returns (address);

  /// @notice Address of Protocol PoolFactory.sol
  function defaultFactory() external view returns (address);

  /// @dev Struct containing information necessary to zap in and out of pools
  /// @param tokenA           .
  /// @param tokenB           .
  /// @param factory          factory of pool
  /// @param amountOutMinA    Minimum amount expected from swap leg of zap via routesA
  /// @param amountOutMinB    Minimum amount expected from swap leg of zap via routesB
  /// @param amountAMin       Minimum amount of tokenA expected from liquidity leg of zap
  /// @param amountBMin       Minimum amount of tokenB expected from liquidity leg of zap
  struct Zap {
    address tokenA;
    address tokenB;
    address factory;
    uint256 amountOutMinA;
    uint256 amountOutMinB;
    uint256 amountAMin;
    uint256 amountBMin;
  }

  /// @notice Sort two tokens by which address value is less than the other
  /// @param tokenA   Address of token to sort
  /// @param tokenB   Address of token to sort
  /// @return token0  Lower address value between tokenA and tokenB
  /// @return token1  Higher address value between tokenA and tokenB
  function sortTokens(address tokenA, address tokenB) external pure returns (address token0, address token1);

  /// @notice Calculate the address of a pool by its' factory.
  ///         Used by all Router functions containing a `Route[]` or `_factory` argument.
  ///         Reverts if _factory is not approved by the FactoryRegistry
  /// @dev Returns a randomly generated address for a nonexistent pool
  /// @param tokenA   Address of token to query
  /// @param tokenB   Address of token to query
  /// @param _factory Address of factory which created the pool
  function poolFor(address tokenA, address tokenB, address _factory) external view returns (address pool);

  /// @notice Fetch and sort the reserves for a pool
  /// @param tokenA       .
  /// @param tokenB       .
  /// @param _factory     Address of PoolFactory for tokenA and tokenB
  /// @return reserveA    Amount of reserves of the sorted token A
  /// @return reserveB    Amount of reserves of the sorted token B
  function getReserves(
    address tokenA,
    address tokenB,
    address _factory
  ) external view returns (uint256 reserveA, uint256 reserveB);

  /// @notice Perform chained getAmountOut calculations on any number of pools
  function getAmountsOut(uint256 amountIn, Route[] memory routes) external view returns (uint256[] memory amounts);

  // **** ADD LIQUIDITY ****

  /// @notice Quote the amount deposited into a Pool
  /// @param tokenA           .
  /// @param tokenB           .
  /// @param _factory         Address of PoolFactory for tokenA and tokenB
  /// @param amountADesired   Amount of tokenA desired to deposit
  /// @param amountBDesired   Amount of tokenB desired to deposit
  /// @return amountA         Amount of tokenA to actually deposit
  /// @return amountB         Amount of tokenB to actually deposit
  /// @return liquidity       Amount of liquidity token returned from deposit
  function quoteAddLiquidity(
    address tokenA,
    address tokenB,
    address _factory,
    uint256 amountADesired,
    uint256 amountBDesired
  ) external view returns (uint256 amountA, uint256 amountB, uint256 liquidity);

  /// @notice Quote the amount of liquidity removed from a Pool
  /// @param tokenA       .
  /// @param tokenB       .
  /// @param _factory     Address of PoolFactory for tokenA and tokenB
  /// @param liquidity    Amount of liquidity to remove
  /// @return amountA     Amount of tokenA received
  /// @return amountB     Amount of tokenB received
  function quoteRemoveLiquidity(
    address tokenA,
    address tokenB,
    address _factory,
    uint256 liquidity
  ) external view returns (uint256 amountA, uint256 amountB);

  /// @notice Add liquidity of two tokens to a Pool
  /// @param tokenA           .
  /// @param tokenB           .
  /// @param amountADesired   Amount of tokenA desired to deposit
  /// @param amountBDesired   Amount of tokenB desired to deposit
  /// @param amountAMin       Minimum amount of tokenA to deposit
  /// @param amountBMin       Minimum amount of tokenB to deposit
  /// @param to               Recipient of liquidity token
  /// @param deadline         Deadline to receive liquidity
  /// @return amountA         Amount of tokenA to actually deposit
  /// @return amountB         Amount of tokenB to actually deposit
  /// @return liquidity       Amount of liquidity token returned from deposit
  function addLiquidity(
    address tokenA,
    address tokenB,
    uint256 amountADesired,
    uint256 amountBDesired,
    uint256 amountAMin,
    uint256 amountBMin,
    address to,
    uint256 deadline
  ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

  // **** REMOVE LIQUIDITY ****

  /// @notice Remove liquidity of two tokens from a Pool
  /// @param tokenA       .
  /// @param tokenB       .
  /// @param liquidity    Amount of liquidity to remove
  /// @param amountAMin   Minimum amount of tokenA to receive
  /// @param amountBMin   Minimum amount of tokenB to receive
  /// @param to           Recipient of tokens received
  /// @param deadline     Deadline to remove liquidity
  /// @return amountA     Amount of tokenA received
  /// @return amountB     Amount of tokenB received
  function removeLiquidity(
    address tokenA,
    address tokenB,
    uint256 liquidity,
    uint256 amountAMin,
    uint256 amountBMin,
    address to,
    uint256 deadline
  ) external returns (uint256 amountA, uint256 amountB);

  // **** SWAP ****

  /// @notice Swap one token for another
  /// @param amountIn     Amount of token in
  /// @param amountOutMin Minimum amount of desired token received
  /// @param routes       Array of trade routes used in the swap
  /// @param to           Recipient of the tokens received
  /// @param deadline     Deadline to receive tokens
  /// @return amounts     Array of amounts returned per route
  function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    Route[] calldata routes,
    address to,
    uint256 deadline
  ) external returns (uint256[] memory amounts);

  /// @notice Zap a token A into a pool (B, C). (A can be equal to B or C).
  ///         Supports standard ERC20 tokens only (i.e. not fee-on-transfer tokens etc).
  ///         Slippage is required for the initial swap.
  ///         Additional slippage may be required when adding liquidity as the
  ///         price of the token may have changed.
  /// @param tokenIn      Token you are zapping in from (i.e. input token).
  /// @param amountInA    Amount of input token you wish to send down routesA
  /// @param amountInB    Amount of input token you wish to send down routesB
  /// @param zapInPool    Contains zap struct information. See Zap struct.
  /// @param routesA      Route used to convert input token to tokenA
  /// @param routesB      Route used to convert input token to tokenB
  /// @param to           Address you wish to mint liquidity to.
  /// @return liquidity   Amount of LP tokens created from zapping in.
  function zapIn(
    address tokenIn,
    uint256 amountInA,
    uint256 amountInB,
    Zap calldata zapInPool,
    Route[] calldata routesA,
    Route[] calldata routesB,
    address to
  ) external payable returns (uint256 liquidity);

  /// @notice Zap out a pool (B, C) into A.
  ///         Supports standard ERC20 tokens only (i.e. not fee-on-transfer tokens etc).
  ///         Slippage is required for the removal of liquidity.
  ///         Additional slippage may be required on the swap as the
  ///         price of the token may have changed.
  /// @param tokenOut     Token you are zapping out to (i.e. output token).
  /// @param liquidity    Amount of liquidity you wish to remove.
  /// @param zapOutPool   Contains zap struct information. See Zap struct.
  /// @param routesA      Route used to convert tokenA into output token.
  /// @param routesB      Route used to convert tokenB into output token.
  function zapOut(
    address tokenOut,
    uint256 liquidity,
    Zap calldata zapOutPool,
    Route[] calldata routesA,
    Route[] calldata routesB
  ) external;

  /// @notice Used to generate params required for zapping in.
  ///         Zap in => swap input tokens then add liquidity.
  /// @dev IMPORTANT: These are optimistic estimates based on current pool state. Actual execution may differ due to:
  ///      - Pool state changes between this call and execution (MEV, other transactions)
  ///      - Self-inflicted price impact: swaps via routesA/routesB change reserves before liquidity addition
  ///      - Trading limits (TradingLimitsV2) are not checked and may cause reverts
  ///      Users SHOULD apply slippage tolerance to returned values.
  ///      For precise values, simulate the actual zapIn() call via eth_call.
  /// @param tokenA           .
  /// @param tokenB           .
  /// @param _factory         .
  /// @param amountInA        Amount of input token you wish to send down routesA
  /// @param amountInB        Amount of input token you wish to send down routesB
  /// @param routesA          Route used to convert input token to tokenA
  /// @param routesB          Route used to convert input token to tokenB
  /// @return amountOutMinA   Minimum output expected from swapping input token to tokenA.
  /// @return amountOutMinB   Minimum output expected from swapping input token to tokenB.
  /// @return amountAMin      Minimum amount of tokenA expected from depositing liquidity.
  /// @return amountBMin      Minimum amount of tokenB expected from depositing liquidity.
  function generateZapInParams(
    address tokenA,
    address tokenB,
    address _factory,
    uint256 amountInA,
    uint256 amountInB,
    Route[] calldata routesA,
    Route[] calldata routesB
  ) external view returns (uint256 amountOutMinA, uint256 amountOutMinB, uint256 amountAMin, uint256 amountBMin);

  /// @notice Used to generate params required for zapping out.
  ///         Zap out => remove liquidity then swap tokens to output token.
  /// @dev IMPORTANT: These are optimistic estimates based on current pool state. Actual execution may differ due to:
  ///      - Pool state changes between this call and execution (MEV, other transactions)
  ///      - Reduced swap liquidity: removing liquidity first reduces available reserves for subsequent swaps
  ///      - Trading limits (TradingLimitsV2) are not checked and may cause reverts
  ///      Users SHOULD apply slippage tolerance to returned values.
  ///      For precise values, simulate the actual zapOut() call via eth_call.
  /// @param tokenA           .
  /// @param tokenB           .
  /// @param _factory         .
  /// @param liquidity        Amount of liquidity being zapped out of into a given output token.
  /// @param routesA          Route used to convert tokenA into output token.
  /// @param routesB          Route used to convert tokenB into output token.
  /// @return amountOutMinA   Minimum output expected from swapping tokenA into output token.
  /// @return amountOutMinB   Minimum output expected from swapping tokenB into output token.
  /// @return amountAMin      Minimum amount of tokenA expected from withdrawing liquidity.
  /// @return amountBMin      Minimum amount of tokenB expected from withdrawing liquidity.
  function generateZapOutParams(
    address tokenA,
    address tokenB,
    address _factory,
    uint256 liquidity,
    Route[] calldata routesA,
    Route[] calldata routesB
  ) external view returns (uint256 amountOutMinA, uint256 amountOutMinB, uint256 amountAMin, uint256 amountBMin);
}
