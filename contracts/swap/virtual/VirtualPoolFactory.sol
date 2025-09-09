// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { VirtualPool } from "./VirtualPool.sol";
import { IBiPoolManager } from "contracts/interfaces/IBiPoolManager.sol";
import { IRPoolFactory } from "contracts/swap/router/interfaces/IRPoolFactory.sol";

contract VirtualPoolFactory is IRPoolFactory, Ownable {
  event VirtualPoolDeployed(address indexed pool, address indexed token0, address indexed token1);

  mapping(address token0 => mapping(address token1 => address poolAddress)) internal _pools;
  mapping(address pool => bool exists) internal _isPool;

  /// TODO: Determine whether we use Create2, Create3, Clone
  /**
   * @notice Deploys a virtual pool contract.
   * @param _broker Address of the Broker contract.
   * @param _exchangeProvider Address of the Exchange Provider.
   * @param _exchangeId Exchange ID for this pair.
   */
  function deployVirtualPool(
    address _broker,
    address _exchangeProvider,
    bytes32 _exchangeId
  ) external onlyOwner returns (address) {
    IBiPoolManager.PoolExchange memory exchange = IBiPoolManager(_exchangeProvider).exchanges(_exchangeId);
    (address token0, address token1) = _sortTokens(exchange.asset0, exchange.asset1);
    address pool = address(new VirtualPool(_broker, _exchangeProvider, _exchangeId, token0, token1));
    _pools[token0][token1] = pool;
    _isPool[pool] = true;
    emit VirtualPoolDeployed(pool, token0, token1);
    return pool;
  }

  /// @inheritdoc IRPoolFactory
  function getOrPrecomputeProxyAddress(address tokenA, address tokenB) external view returns (address) {
    (address token0, address token1) = _sortTokens(tokenA, tokenB);
    return _pools[token0][token1];
  }

  /// @inheritdoc IRPoolFactory
  function isPool(address pool) external view returns (bool) {
    return _isPool[pool];
  }

  /// @inheritdoc IRPoolFactory
  function getPool(address tokenA, address tokenB) external view returns (address) {
    (address token0, address token1) = _sortTokens(tokenA, tokenB);
    return _pools[token0][token1];
  }

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
