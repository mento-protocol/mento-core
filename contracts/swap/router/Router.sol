// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;
// solhint-disable immutable-vars-naming
// slither-disable-start calls-loop

import { ERC2771Context } from "./utils/ERC2771.sol";
import { SafeERC20 } from "./utils/SafeERC20.sol";
import { Math } from "./utils/Math.sol";

import { IRouter } from "./interfaces/IRouter.sol";
import { IERC20 } from "./interfaces/IERC20.sol";
import { IFactoryRegistry } from "contracts/interfaces/IFactoryRegistry.sol";
import { IFPMM } from "../../interfaces/IFPMM.sol";

import { IRPoolFactory } from "./interfaces/IRPoolFactory.sol";
import { IRPool } from "./interfaces/IRPool.sol";

/// @title Protocol Router
/// @author velodrome.finance, @pegahcarter, Mento Labs
/// @notice Router allows routes through pools created by Mento protocol.
/// @dev This contract is a fork of Aerodrome/Velodrome's Router contract.
/// @dev github.com/aerodrome-finance/contracts/blob/a5fae2e87e490d6b10f133e28cc11bcc58c5346a/contracts/Router.sol
/// @dev It is modified to support the Mento protocol.
contract Router is IRouter, ERC2771Context {
  using SafeERC20 for IERC20;

  /// @inheritdoc IRouter
  address public immutable factoryRegistry;
  /// @inheritdoc IRouter
  address public immutable defaultFactory;

  uint256 internal constant MINIMUM_LIQUIDITY = 10 ** 3;

  modifier ensure(uint256 deadline) {
    _ensureDeadline(deadline);
    _;
  }

  function _ensureDeadline(uint256 deadline) internal view {
    if (deadline < block.timestamp) revert Expired();
  }

  constructor(address _forwarder, address _factoryRegistry, address _factory) ERC2771Context(_forwarder) {
    factoryRegistry = _factoryRegistry;
    defaultFactory = _factory;
  }

  /// @inheritdoc IRouter
  function sortTokens(address tokenA, address tokenB) public pure returns (address token0, address token1) {
    if (tokenA == tokenB) revert SameAddresses();
    (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    if (token0 == address(0)) revert ZeroAddress();
  }

  /// @inheritdoc IRouter
  function poolFor(address tokenA, address tokenB, address _factory) public view returns (address pool) {
    address _defaultFactory = defaultFactory;
    address factory = _factory == address(0) ? _defaultFactory : _factory;
    if (!IFactoryRegistry(factoryRegistry).isPoolFactoryApproved(factory)) revert PoolFactoryDoesNotExist();

    pool = IRPoolFactory(factory).getOrPrecomputeProxyAddress(tokenA, tokenB);
  }

  /// @dev given some amount of an asset and pool reserves, returns an equivalent amount of the other asset
  function quoteLiquidity(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
    // slither-disable-next-line incorrect-equality
    if (amountA == 0) revert InsufficientAmount();
    // slither-disable-next-line incorrect-equality
    if (reserveA == 0 || reserveB == 0) revert InsufficientLiquidity();
    amountB = (amountA * reserveB) / reserveA;
  }

  /// @inheritdoc IRouter
  function getReserves(
    address tokenA,
    address tokenB,
    address _factory
  ) public view returns (uint256 reserveA, uint256 reserveB) {
    (address token0, ) = sortTokens(tokenA, tokenB);
    // slither-disable-next-line unused-return
    (uint256 reserve0, uint256 reserve1, ) = IRPool(poolFor(tokenA, tokenB, _factory)).getReserves();
    (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
  }

  /// @inheritdoc IRouter
  function getAmountsOut(uint256 amountIn, Route[] memory routes) public view returns (uint256[] memory amounts) {
    if (routes.length < 1) revert InvalidPath();
    amounts = new uint256[](routes.length + 1);
    amounts[0] = amountIn;
    uint256 _length = routes.length;
    for (uint256 i = 0; i < _length; i++) {
      address factory = routes[i].factory == address(0) ? defaultFactory : routes[i].factory;
      address pool = poolFor(routes[i].from, routes[i].to, factory);
      if (!IRPoolFactory(factory).isPool(pool)) revert PoolDoesNotExist();
      amounts[i + 1] = IRPool(pool).getAmountOut(amounts[i], routes[i].from);
    }
  }

  /// @inheritdoc IRouter
  function quoteAddLiquidity(
    address tokenA,
    address tokenB,
    address _factory,
    uint256 amountADesired,
    uint256 amountBDesired
  ) public view returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
    address _pool = IRPoolFactory(_factory).getPool(tokenA, tokenB);
    (uint256 reserveA, uint256 reserveB) = (0, 0);
    uint256 _totalSupply = 0;
    if (_pool != address(0)) {
      _totalSupply = IERC20(_pool).totalSupply();
      (reserveA, reserveB) = getReserves(tokenA, tokenB, _factory);
    }
    if (reserveA == 0 && reserveB == 0) {
      (amountA, amountB) = (amountADesired, amountBDesired);
      liquidity = Math.sqrt(amountA * amountB) - MINIMUM_LIQUIDITY;
    } else {
      uint256 amountBOptimal = quoteLiquidity(amountADesired, reserveA, reserveB);
      if (amountBOptimal <= amountBDesired) {
        (amountA, amountB) = (amountADesired, amountBOptimal);
        liquidity = Math.min((amountA * _totalSupply) / reserveA, (amountB * _totalSupply) / reserveB);
      } else {
        uint256 amountAOptimal = quoteLiquidity(amountBDesired, reserveB, reserveA);
        (amountA, amountB) = (amountAOptimal, amountBDesired);
        liquidity = Math.min((amountA * _totalSupply) / reserveA, (amountB * _totalSupply) / reserveB);
      }
    }
  }

  /// @inheritdoc IRouter
  function quoteRemoveLiquidity(
    address tokenA,
    address tokenB,
    address _factory,
    uint256 liquidity
  ) public view returns (uint256 amountA, uint256 amountB) {
    address _pool = IRPoolFactory(_factory).getPool(tokenA, tokenB);

    if (_pool == address(0)) {
      return (0, 0);
    }

    (uint256 reserveA, uint256 reserveB) = getReserves(tokenA, tokenB, _factory);
    uint256 _totalSupply = IERC20(_pool).totalSupply();

    amountA = (liquidity * reserveA) / _totalSupply; // using balances ensures pro-rata distribution
    amountB = (liquidity * reserveB) / _totalSupply; // using balances ensures pro-rata distribution
  }

  function _addLiquidity(
    address tokenA,
    address tokenB,
    uint256 amountADesired,
    uint256 amountBDesired,
    uint256 amountAMin,
    uint256 amountBMin
  ) internal view returns (uint256 amountA, uint256 amountB) {
    if (amountADesired < amountAMin) revert InsufficientAmountADesired();
    if (amountBDesired < amountBMin) revert InsufficientAmountBDesired();
    // we don't create the pool if it doesn't exist yet
    address _pool = IRPoolFactory(defaultFactory).getPool(tokenA, tokenB);
    if (_pool == address(0)) {
      revert PoolDoesNotExist();
    }
    (uint256 reserveA, uint256 reserveB) = getReserves(tokenA, tokenB, defaultFactory);
    if (reserveA == 0 && reserveB == 0) {
      (amountA, amountB) = (amountADesired, amountBDesired);
    } else {
      uint256 amountBOptimal = quoteLiquidity(amountADesired, reserveA, reserveB);
      if (amountBOptimal <= amountBDesired) {
        if (amountBOptimal < amountBMin) revert InsufficientAmountB();
        (amountA, amountB) = (amountADesired, amountBOptimal);
      } else {
        uint256 amountAOptimal = quoteLiquidity(amountBDesired, reserveB, reserveA);
        assert(amountAOptimal <= amountADesired);
        if (amountAOptimal < amountAMin) revert InsufficientAmountA();
        (amountA, amountB) = (amountAOptimal, amountBDesired);
      }
    }
  }

  /// @inheritdoc IRouter
  function addLiquidity(
    address tokenA,
    address tokenB,
    uint256 amountADesired,
    uint256 amountBDesired,
    uint256 amountAMin,
    uint256 amountBMin,
    address to,
    uint256 deadline
  ) public ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
    (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
    address pool = poolFor(tokenA, tokenB, defaultFactory);
    _safeTransferFrom(tokenA, _msgSender(), pool, amountA);
    _safeTransferFrom(tokenB, _msgSender(), pool, amountB);
    liquidity = IFPMM(pool).mint(to);
  }

  // **** REMOVE LIQUIDITY ****

  /// @inheritdoc IRouter
  function removeLiquidity(
    address tokenA,
    address tokenB,
    uint256 liquidity,
    uint256 amountAMin,
    uint256 amountBMin,
    address to,
    uint256 deadline
  ) public ensure(deadline) returns (uint256 amountA, uint256 amountB) {
    address pool = poolFor(tokenA, tokenB, defaultFactory);
    IERC20(pool).safeTransferFrom(_msgSender(), pool, liquidity);
    (uint256 amount0, uint256 amount1) = IFPMM(pool).burn(to);
    (address token0, ) = sortTokens(tokenA, tokenB);
    (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
    if (amountA < amountAMin) revert InsufficientAmountA();
    if (amountB < amountBMin) revert InsufficientAmountB();
  }

  // **** SWAP ****
  /// @dev requires the initial amount to have already been sent to the first pool
  function _swap(uint256[] memory amounts, Route[] memory routes, address _to) internal virtual {
    uint256 _length = routes.length;
    address currentPool = poolFor(routes[0].from, routes[0].to, routes[0].factory);
    for (uint256 i = 0; i < _length; i++) {
      IRouter.Route memory currentRoute = routes[i];
      (address token0, ) = sortTokens(currentRoute.from, currentRoute.to);
      uint256 amountOut = amounts[i + 1];
      (uint256 amount0Out, uint256 amount1Out) = currentRoute.from == token0
        ? (uint256(0), amountOut)
        : (amountOut, uint256(0));
      // cache the destination pool address to use in the next iteration
      address to = i < _length - 1 ? poolFor(routes[i + 1].from, routes[i + 1].to, routes[i + 1].factory) : _to;
      IRPool(currentPool).swap(amount0Out, amount1Out, to, new bytes(0));
      currentPool = to;
    }
  }

  function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    Route[] calldata routes,
    address to,
    uint256 deadline
  ) external ensure(deadline) returns (uint256[] memory amounts) {
    amounts = getAmountsOut(amountIn, routes);
    if (amounts[amounts.length - 1] < amountOutMin) revert InsufficientOutputAmount();
    _safeTransferFrom(
      routes[0].from,
      _msgSender(),
      poolFor(routes[0].from, routes[0].to, routes[0].factory),
      amounts[0]
    );
    _swap(amounts, routes, to);
  }

  /// @inheritdoc IRouter
  function zapIn(
    address tokenIn,
    uint256 amountInA,
    uint256 amountInB,
    Zap calldata zapInPool,
    Route[] calldata routesA,
    Route[] calldata routesB,
    address to
  ) external payable returns (uint256 liquidity) {
    uint256 amountIn = amountInA + amountInB;
    address _tokenIn = tokenIn;

    if (msg.value != 0) revert ETHTransferFailed();
    _safeTransferFrom(_tokenIn, _msgSender(), address(this), amountIn);

    _zapSwap(_tokenIn, amountInA, amountInB, zapInPool, routesA, routesB);
    _zapInLiquidity(zapInPool);
    address pool = poolFor(zapInPool.tokenA, zapInPool.tokenB, zapInPool.factory);

    liquidity = IFPMM(pool).mint(to);

    _returnAssets(tokenIn);
    _returnAssets(zapInPool.tokenA);
    _returnAssets(zapInPool.tokenB);
  }

  /// @dev Handles swap leg of zap in (i.e. convert tokenIn into tokenA and tokenB).
  function _zapSwap(
    address tokenIn,
    uint256 amountInA,
    uint256 amountInB,
    Zap calldata zapInPool,
    Route[] calldata routesA,
    Route[] calldata routesB
  ) internal {
    address tokenA = zapInPool.tokenA;
    address tokenB = zapInPool.tokenB;
    address factory = zapInPool.factory;
    address pool = poolFor(tokenA, tokenB, factory);

    {
      // slither-disable-next-line unused-return
      (uint256 reserve0, uint256 reserve1, ) = IRPool(pool).getReserves();
      if (reserve0 <= MINIMUM_LIQUIDITY || reserve1 <= MINIMUM_LIQUIDITY) revert PoolDoesNotExist();
    }

    if (tokenIn != tokenA) {
      if (routesA[routesA.length - 1].to != tokenA) revert InvalidRouteA();
      _internalSwap(tokenIn, amountInA, zapInPool.amountOutMinA, routesA);
    }
    if (tokenIn != tokenB) {
      if (routesB[routesB.length - 1].to != tokenB) revert InvalidRouteB();
      _internalSwap(tokenIn, amountInB, zapInPool.amountOutMinB, routesB);
    }
  }

  /// @dev Handles liquidity adding component of zap in.
  function _zapInLiquidity(Zap calldata zapInPool) internal {
    address tokenA = zapInPool.tokenA;
    address tokenB = zapInPool.tokenB;
    address factory = zapInPool.factory;
    address pool = poolFor(tokenA, tokenB, factory);
    (uint256 amountA, uint256 amountB) = _quoteZapLiquidity(
      tokenA,
      tokenB,
      factory,
      IERC20(tokenA).balanceOf(address(this)),
      IERC20(tokenB).balanceOf(address(this)),
      zapInPool.amountAMin,
      zapInPool.amountBMin
    );
    _safeTransfer(tokenA, pool, amountA);
    _safeTransfer(tokenB, pool, amountB);
  }

  /// @dev Similar to _addLiquidity. Assumes a pool exists, and accepts a factory argument.
  function _quoteZapLiquidity(
    address tokenA,
    address tokenB,
    address _factory,
    uint256 amountADesired,
    uint256 amountBDesired,
    uint256 amountAMin,
    uint256 amountBMin
  ) internal view returns (uint256 amountA, uint256 amountB) {
    if (amountADesired < amountAMin) revert InsufficientAmountADesired();
    if (amountBDesired < amountBMin) revert InsufficientAmountBDesired();
    (uint256 reserveA, uint256 reserveB) = getReserves(tokenA, tokenB, _factory);
    if (reserveA == 0 && reserveB == 0) {
      (amountA, amountB) = (amountADesired, amountBDesired);
    } else {
      uint256 amountBOptimal = quoteLiquidity(amountADesired, reserveA, reserveB);
      if (amountBOptimal <= amountBDesired) {
        if (amountBOptimal < amountBMin) revert InsufficientAmountB();
        (amountA, amountB) = (amountADesired, amountBOptimal);
      } else {
        uint256 amountAOptimal = quoteLiquidity(amountBDesired, reserveB, reserveA);
        assert(amountAOptimal <= amountADesired);
        if (amountAOptimal < amountAMin) revert InsufficientAmountA();
        (amountA, amountB) = (amountAOptimal, amountBDesired);
      }
    }
  }

  /// @dev Handles swaps internally for zaps.
  function _internalSwap(address tokenIn, uint256 amountIn, uint256 amountOutMin, Route[] memory routes) internal {
    uint256[] memory amounts = getAmountsOut(amountIn, routes);
    if (amounts[amounts.length - 1] < amountOutMin) revert InsufficientOutputAmount();
    address pool = poolFor(routes[0].from, routes[0].to, routes[0].factory);
    _safeTransfer(tokenIn, pool, amountIn);
    _swap(amounts, routes, address(this));
  }

  /// @inheritdoc IRouter
  function zapOut(
    address tokenOut,
    uint256 liquidity,
    Zap calldata zapOutPool,
    Route[] calldata routesA,
    Route[] calldata routesB
  ) external {
    address tokenA = zapOutPool.tokenA;
    address tokenB = zapOutPool.tokenB;
    _zapOutLiquidity(liquidity, zapOutPool);

    uint256 balance;
    if (tokenA != tokenOut) {
      balance = IERC20(tokenA).balanceOf(address(this));
      if (routesA[routesA.length - 1].to != tokenOut) revert InvalidRouteA();
      _internalSwap(tokenA, balance, zapOutPool.amountOutMinA, routesA);
    }
    if (tokenB != tokenOut) {
      balance = IERC20(tokenB).balanceOf(address(this));
      if (routesB[routesB.length - 1].to != tokenOut) revert InvalidRouteB();
      _internalSwap(tokenB, balance, zapOutPool.amountOutMinB, routesB);
    }

    _returnAssets(tokenOut);
  }

  /// @dev Handles liquidity removing component of zap out.
  function _zapOutLiquidity(uint256 liquidity, Zap calldata zapOutPool) internal {
    address tokenA = zapOutPool.tokenA;
    address tokenB = zapOutPool.tokenB;
    address pool = poolFor(tokenA, tokenB, zapOutPool.factory);
    IERC20(pool).safeTransferFrom(msg.sender, pool, liquidity);
    (address token0, ) = sortTokens(tokenA, tokenB);
    (uint256 amount0, uint256 amount1) = IFPMM(pool).burn(address(this));
    (uint256 amountA, uint256 amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
    if (amountA < zapOutPool.amountAMin) revert InsufficientAmountA();
    if (amountB < zapOutPool.amountBMin) revert InsufficientAmountB();
  }

  /// @inheritdoc IRouter
  function generateZapInParams(
    address tokenA,
    address tokenB,
    address _factory,
    uint256 amountInA,
    uint256 amountInB,
    Route[] calldata routesA,
    Route[] calldata routesB
  ) external view returns (uint256 amountOutMinA, uint256 amountOutMinB, uint256 amountAMin, uint256 amountBMin) {
    amountOutMinA = amountInA;
    amountOutMinB = amountInB;
    uint256[] memory amounts;
    if (routesA.length > 0) {
      amounts = getAmountsOut(amountInA, routesA);
      amountOutMinA = amounts[amounts.length - 1];
    }
    if (routesB.length > 0) {
      amounts = getAmountsOut(amountInB, routesB);
      amountOutMinB = amounts[amounts.length - 1];
    }
    (amountAMin, amountBMin, ) = quoteAddLiquidity(tokenA, tokenB, _factory, amountOutMinA, amountOutMinB);
  }

  /// @inheritdoc IRouter
  function generateZapOutParams(
    address tokenA,
    address tokenB,
    address _factory,
    uint256 liquidity,
    Route[] calldata routesA,
    Route[] calldata routesB
  ) external view returns (uint256 amountOutMinA, uint256 amountOutMinB, uint256 amountAMin, uint256 amountBMin) {
    (amountAMin, amountBMin) = quoteRemoveLiquidity(tokenA, tokenB, _factory, liquidity);
    amountOutMinA = amountAMin;
    amountOutMinB = amountBMin;
    uint256[] memory amounts;
    if (routesA.length > 0) {
      amounts = getAmountsOut(amountAMin, routesA);
      amountOutMinA = amounts[amounts.length - 1];
    }
    if (routesB.length > 0) {
      amounts = getAmountsOut(amountBMin, routesB);
      amountOutMinB = amounts[amounts.length - 1];
    }
  }

  /// @dev Return residual assets from zapping.
  /// @param token token to return
  function _returnAssets(address token) internal {
    address sender = _msgSender();
    uint256 balance = IERC20(token).balanceOf(address(this));
    if (balance > 0) IERC20(token).safeTransfer(sender, balance);
  }

  function _safeTransferETH(address to, uint256 value) internal {
    (bool success, ) = to.call{ value: value }(new bytes(0));
    if (!success) revert ETHTransferFailed();
  }

  function _safeTransfer(address token, address to, uint256 value) internal {
    require(token.code.length > 0, "Not a contract");
    // solhint-disable-next-line avoid-low-level-calls
    (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
    // slither-disable-next-line incorrect-equality
    require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer failed");
  }

  function _safeTransferFrom(address token, address from, address to, uint256 value) internal {
    require(token.code.length > 0, "Not a contract");
    // solhint-disable-next-line avoid-low-level-calls
    (bool success, bytes memory data) = token.call(
      abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value)
    );
    // slither-disable-next-line incorrect-equality
    require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer failed");
  }
}
// slither-disable-end calls-loop
