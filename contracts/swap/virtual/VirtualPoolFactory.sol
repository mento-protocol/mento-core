// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { VirtualPool } from "./VirtualPool.sol";
import { IBiPoolManager } from "contracts/interfaces/IBiPoolManager.sol";
import { IVirtualPoolFactory } from "contracts/interfaces/IVirtualPoolFactory.sol";
import { IRPoolFactory } from "contracts/swap/router/interfaces/IRPoolFactory.sol";

contract VirtualPoolFactory is IRPoolFactory, IVirtualPoolFactory, Ownable {
  mapping(address token0 => mapping(address token1 => address poolAddress)) internal _pools;
  mapping(address pool => bool exists) internal _isPool;

  /// TODO: Determine whether we use Create2, Create3, Clone
  /// @inheritdoc IVirtualPoolFactory
  function deployVirtualPool(address exchangeProvider, bytes32 exchangeId) external onlyOwner returns (address pool) {
    address broker = IBiPoolManager(exchangeProvider).broker();
    (address token0, address token1, bool sameOrder) = _getExchangeTokens(exchangeProvider, exchangeId);
    if (_pools[token0][token1] != address(0)) {
      revert VirtualPoolAlreadyExistsForThisPair();
    }
    // slither-disable-next-line reentrancy-benign,reentrancy-no-eth
    pool = address(new VirtualPool(broker, exchangeProvider, exchangeId, token0, token1, sameOrder));
    _pools[token0][token1] = pool;
    _pools[token1][token0] = pool;
    _isPool[pool] = true;
    // slither-disable-next-line reentrancy-events
    emit VirtualPoolDeployed(pool, token0, token1);
  }

  /// @inheritdoc IRPoolFactory
  function getOrPrecomputeProxyAddress(address token0, address token1) external view returns (address) {
    // TODO: Precompute the address
    return _pools[token0][token1];
  }

  /// @inheritdoc IRPoolFactory
  function isPool(address pool) external view returns (bool) {
    return _isPool[pool];
  }

  /// @inheritdoc IRPoolFactory
  function getPool(address token0, address token1) external view returns (address) {
    return _pools[token0][token1];
  }

  /**
   * @notice Sorts two tokens by their address value.
   * @param a The address of one token.
   * @param b The address of another token.
   * @return token0 The address of the first token (of which the address is the smaller uint160).
   * @return token1 The address of the second token (of which the address is the bigger uint160).
   */
  function _sortTokens(address a, address b) private pure returns (address, address) {
    return (a < b) ? (a, b) : (b, a);
  }

  /**
   * @notice Gets the broker address from an exchange provider and gracefully handles errors.
   * @param exchangeProvider The address of the Exchange Provider.
   * @param exchangeId Exchange ID for this pair.
   * @return token0 Address of the first token.
   * @return token1 Address of the second token.
   */
  function _getExchangeTokens(
    address exchangeProvider,
    bytes32 exchangeId
  ) internal view returns (address token0, address token1, bool sameOrder) {
    IBiPoolManager.PoolExchange memory exchange = IBiPoolManager(exchangeProvider).exchanges(exchangeId);
    (token0, token1) = _sortTokens(exchange.asset0, exchange.asset1);
    sameOrder = token0 == exchange.asset0;
    if (token0 == address(0)) {
      revert InvalidExchangeId();
    }
  }
}
