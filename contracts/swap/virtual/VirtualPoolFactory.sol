// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { VirtualPool } from "./VirtualPool.sol";
import { IBiPoolManager } from "contracts/interfaces/IBiPoolManager.sol";
import { IVirtualPoolFactory } from "contracts/interfaces/IVirtualPoolFactory.sol";
import { IRPoolFactory } from "contracts/swap/router/interfaces/IRPoolFactory.sol";
import { ICreateX } from "contracts/interfaces/ICreateX.sol";

contract VirtualPoolFactory is IRPoolFactory, IVirtualPoolFactory, Ownable {
  // Address of the CREATEX contract.
  address public constant CREATEX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

  // Bytecode hash of the CREATEX contract retrieved from celo mainnet
  // cast keccak $(cast code 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed --rpc-url https://forno.celo.org)
  bytes32 public constant CREATEX_BYTECODE_HASH = 0xbd8a7ea8cfca7b4e5f5041d7d4b17bc317c5ce42cfbc42066a00cf26b43eb53f;

  mapping(address token0 => mapping(address token1 => address poolAddress)) internal _pools;
  mapping(address pool => bool exists) internal _isPool;

  /* ============================================================ */
  /* ======================== Constructor ======================= */
  /* ============================================================ */

  constructor(address _owner) {
    bytes32 createXCodeHash;
    // solhint-disable-next-line no-inline-assembly
    assembly {
      createXCodeHash := extcodehash(CREATEX)
    }
    if (createXCodeHash != CREATEX_BYTECODE_HASH) revert InvalidCreateXBytecode();
    _transferOwnership(_owner);
  }

  /* ============================================================ */
  /* ==================== Mutative Functions ==================== */
  /* ============================================================ */

  // slither-disable-start reentrancy-no-eth
  // slither-disable-start reentrancy-benign
  // slither-disable-start reentrancy-events
  /// @inheritdoc IVirtualPoolFactory
  function deployVirtualPool(address exchangeProvider, bytes32 exchangeId) external onlyOwner returns (address pool) {
    address broker = IBiPoolManager(exchangeProvider).broker();
    (address token0, address token1, bool sameOrder) = _getExchangeTokens(exchangeProvider, exchangeId);
    if (_pools[token0][token1] != address(0)) {
      revert VirtualPoolAlreadyExistsForThisPair();
    }

    (address expectedPoolAddress, bytes32 salt) = _computePoolAddressAndSalt(token0, token1);

    // Deploy using CREATE3 via CREATEX with deterministic salt based on sorted token addresses
    bytes memory poolBytecode = abi.encodePacked(
      type(VirtualPool).creationCode,
      abi.encode(broker, exchangeProvider, exchangeId, token0, token1, sameOrder)
    );
    pool = ICreateX(CREATEX).deployCreate3(salt, poolBytecode);
    assert(pool == expectedPoolAddress);

    _pools[token0][token1] = pool;
    _pools[token1][token0] = pool;
    _isPool[pool] = true;
    emit VirtualPoolDeployed(pool, token0, token1);
  }
  // slither-disable-end reentrancy-no-eth
  // slither-disable-end reentrancy-benign
  // slither-disable-end reentrancy-events

  /* ============================================================ */
  /* ===================== View Functions ======================= */
  /* ============================================================ */

  // slither-disable-start encode-packed-collision
  /// @inheritdoc IRPoolFactory
  function getOrPrecomputeProxyAddress(address token0, address token1) external view returns (address) {
    // If pool is already deployed, return its address
    address existingPool = _pools[token0][token1];
    if (existingPool != address(0)) {
      return existingPool;
    }

    // Sort tokens to match deployment order
    (token0, token1) = _sortTokens(token0, token1);

    // Precompute CREATE3 address
    (address precomputedPoolAddress, ) = _computePoolAddressAndSalt(token0, token1);
    return precomputedPoolAddress;
  }
  // slither-disable-end encode-packed-collision

  /// @inheritdoc IRPoolFactory
  function isPool(address pool) external view returns (bool) {
    return _isPool[pool];
  }

  /// @inheritdoc IRPoolFactory
  function getPool(address token0, address token1) external view returns (address) {
    return _pools[token0][token1];
  }

  /* ============================================================ */
  /* =================== Internal Functions ===================== */
  /* ============================================================ */

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
   * @notice Gets the exchange tokens from an exchange provider.
   * @param exchangeProvider The address of the Exchange Provider.
   * @param exchangeId Exchange ID for this pair.
   * @return token0 Address of the first token.
   * @return token1 Address of the second token.
   * @return sameOrder Whether the token order matches the exchange.
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

  /**
   * @notice Computes the CREATE3 address for a VirtualPool.
   * @dev Apply permissioned deploy protection with factory address and custom salt
   *      see https://github.com/pcaversaccio/createx?tab=readme-ov-file for more details
   *      custom salt is a keccak256 hash of the token0 and token1 addresses
   * @param token0 The address of the first token (sorted).
   * @param token1 The address of the second token (sorted).
   * @return The precomputed CREATE3 address of the VirtualPool.
   * @return The salt used to deploy the VirtualPool.
   */
  // slither-disable-start encode-packed-collision
  function _computePoolAddressAndSalt(address token0, address token1) internal view returns (address, bytes32) {
    bytes11 customSalt = bytes11(uint88(uint256(keccak256(abi.encodePacked(token0, token1)))));
    bytes32 salt = bytes32(abi.encodePacked(address(this), hex"00", customSalt));
    bytes32 guardedSalt = _efficientHash({ a: bytes32(uint256(uint160(address(this)))), b: salt });

    address poolAddress = ICreateX(CREATEX).computeCreate3Address(guardedSalt);
    return (poolAddress, salt);
  }
  // slither-disable-end encode-packed-collision

  /**
   * @notice Hashes two bytes32 values efficiently.
   * @dev Copied from CREATEX contract to precalculate deployment addresses
   *      see https://github.com/pcaversaccio/createx/blob/7ab1e452b8803cae1467efd455dee1530660373b/src/CreateX.sol#L952
   * @param a The first bytes32 value
   * @param b The second bytes32 value
   * @return hash The keccak256 hash of the two values
   */
  function _efficientHash(bytes32 a, bytes32 b) internal pure returns (bytes32 hash) {
    // solhint-disable-next-line no-inline-assembly
    assembly ("memory-safe") {
      mstore(0x00, a)
      mstore(0x20, b)
      hash := keccak256(0x00, 0x40)
    }
  }
}
