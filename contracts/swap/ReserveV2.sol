// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { IReserveV2 } from "../interfaces/IReserveV2.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// solhint-disable-next-line max-line-length
import { EnumerableSetUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/utils/structs/EnumerableSetUpgradeable.sol";

/**
 * @title ReserveV2
 * @author Mento Labs
 * @notice This contract implements a reserve for the Mento Protocol.
 * @dev ReserveV2 is not backwards-compatible with the old Reserve contract.
 * It is based on the Reserve contract from the Mento Protocol v2 but removed unnecessary functionality.
 * The ReserveV2 contract maintains a list of:
 * - stable assets
 * - collateral assets
 * - other reserve addresses
 * - liquidity strategy spenders that can transfer collateral assets to any address
 * - reserve manager spenders that can transfer collateral assets to other reserve addresses
 * @dev The reserve is used to manage the assets of the protocol and to facilitate the transfer
 * of assets between the protocol and other contracts.
 */
contract ReserveV2 is IReserveV2, OwnableUpgradeable {
  using SafeERC20 for IERC20;
  using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

  // stable assets registered with the reserve
  EnumerableSetUpgradeable.AddressSet private stableAssets;

  // collateral assets registered with the reserve
  EnumerableSetUpgradeable.AddressSet private collateralAssets;

  // other reserve addresses registered with the reserve
  EnumerableSetUpgradeable.AddressSet private otherReserveAddresses;

  // liquidity strategy spenders registered with the reserve
  EnumerableSetUpgradeable.AddressSet private liquidityStrategySpenders;

  // reserve manager spenders registered with the reserve
  EnumerableSetUpgradeable.AddressSet private reserveManagerSpenders;

  modifier onlyReserveManagerSpender() {
    if (!reserveManagerSpenders.contains(msg.sender)) revert ReserveManagerSpenderNotRegistered();
    _;
  }

  modifier onlyLiquidityStrategySpender() {
    if (!liquidityStrategySpenders.contains(msg.sender)) revert LiquidityStrategySpenderNotRegistered();
    _;
  }

  modifier onlyCollateralAsset(address collateralAsset) {
    if (!collateralAssets.contains(collateralAsset)) revert CollateralAssetNotRegistered();
    _;
  }

  modifier onlyOtherReserveAddress(address otherReserveAddress) {
    if (!otherReserveAddresses.contains(otherReserveAddress)) revert OtherReserveAddressNotRegistered();
    _;
  }

  /**
   * @notice Constructor for the ReserveV2 contract
   * @param disable Boolean to disable initializers for implementation contract
   */
  constructor(bool disable) {
    if (disable) {
      _disableInitializers();
    }
  }

  /// @inheritdoc IReserveV2
  function initialize(
    address[] calldata _stableAssets,
    address[] calldata _collateralAssets,
    address[] calldata _otherReserveAddresses,
    address[] calldata _liquidityStrategySpenders,
    address[] calldata _reserveManagerSpenders,
    address _initialOwner
  ) external initializer {
    __Ownable_init();

    for (uint256 i = 0; i < _stableAssets.length; i++) {
      _registerStableAsset(_stableAssets[i]);
    }
    for (uint256 i = 0; i < _collateralAssets.length; i++) {
      _registerCollateralAsset(_collateralAssets[i]);
    }
    for (uint256 i = 0; i < _otherReserveAddresses.length; i++) {
      _registerOtherReserveAddress(_otherReserveAddresses[i]);
    }
    for (uint256 i = 0; i < _liquidityStrategySpenders.length; i++) {
      _registerLiquidityStrategySpender(_liquidityStrategySpenders[i]);
    }
    for (uint256 i = 0; i < _reserveManagerSpenders.length; i++) {
      _registerReserveManagerSpender(_reserveManagerSpenders[i]);
    }

    transferOwnership(_initialOwner);
  }

  receive() external payable {} // solhint-disable no-empty-blocks

  /* ============================================================ */
  /* ====================== View Functions ====================== */
  /* ============================================================ */

  /// @inheritdoc IReserveV2
  function isStableAsset(address _stableAsset) external view returns (bool) {
    return stableAssets.contains(_stableAsset);
  }

  /// @inheritdoc IReserveV2
  function isCollateralAsset(address _collateralAsset) external view returns (bool) {
    return collateralAssets.contains(_collateralAsset);
  }

  /// @inheritdoc IReserveV2
  function isOtherReserveAddress(address _otherReserveAddress) external view returns (bool) {
    return otherReserveAddresses.contains(_otherReserveAddress);
  }

  /// @inheritdoc IReserveV2
  function isLiquidityStrategySpender(address _liquidityStrategySpender) external view returns (bool) {
    return liquidityStrategySpenders.contains(_liquidityStrategySpender);
  }

  /// @inheritdoc IReserveV2
  function isReserveManagerSpender(address _reserveManagerSpender) external view returns (bool) {
    return reserveManagerSpenders.contains(_reserveManagerSpender);
  }

  /// @inheritdoc IReserveV2
  function getStableAssets() external view returns (address[] memory) {
    return stableAssets.values();
  }

  /// @inheritdoc IReserveV2
  function getCollateralAssets() external view returns (address[] memory) {
    return collateralAssets.values();
  }

  /// @inheritdoc IReserveV2
  function getOtherReserveAddresses() external view returns (address[] memory) {
    return otherReserveAddresses.values();
  }

  /// @inheritdoc IReserveV2
  function getLiquidityStrategySpenders() external view returns (address[] memory) {
    return liquidityStrategySpenders.values();
  }

  /// @inheritdoc IReserveV2
  function getReserveManagerSpenders() external view returns (address[] memory) {
    return reserveManagerSpenders.values();
  }

  /* ============================================================ */
  /* ==================== Mutative Functions ==================== */
  /* ============================================================ */
  /// @inheritdoc IReserveV2
  function registerStableAsset(address _stableAsset) external onlyOwner {
    _registerStableAsset(_stableAsset);
  }

  /// @inheritdoc IReserveV2
  function unregisterStableAsset(address _stableAsset) external onlyOwner {
    if (!stableAssets.remove(_stableAsset)) revert StableAssetNotRegistered();
    emit StableAssetUnregistered(_stableAsset);
  }

  /// @inheritdoc IReserveV2
  function registerCollateralAsset(address _collateralAsset) external onlyOwner {
    _registerCollateralAsset(_collateralAsset);
  }

  /// @inheritdoc IReserveV2
  function unregisterCollateralAsset(address _collateralAsset) external onlyOwner {
    if (!collateralAssets.remove(_collateralAsset)) revert CollateralAssetNotRegistered();
    emit CollateralAssetUnregistered(_collateralAsset);
  }

  /// @inheritdoc IReserveV2
  function registerOtherReserveAddress(address _otherReserveAddress) external onlyOwner {
    _registerOtherReserveAddress(_otherReserveAddress);
  }

  /// @inheritdoc IReserveV2
  function unregisterOtherReserveAddress(address _otherReserveAddress) external onlyOwner {
    if (!otherReserveAddresses.remove(_otherReserveAddress)) revert OtherReserveAddressNotRegistered();
    emit OtherReserveAddressUnregistered(_otherReserveAddress);
  }

  /// @inheritdoc IReserveV2
  function registerLiquidityStrategySpender(address _liquidityStrategySpender) external onlyOwner {
    _registerLiquidityStrategySpender(_liquidityStrategySpender);
  }

  /// @inheritdoc IReserveV2
  function unregisterLiquidityStrategySpender(address _liquidityStrategySpender) external onlyOwner {
    if (!liquidityStrategySpenders.remove(_liquidityStrategySpender)) revert LiquidityStrategySpenderNotRegistered();
    emit LiquidityStrategySpenderUnregistered(_liquidityStrategySpender);
  }

  /// @inheritdoc IReserveV2
  function registerReserveManagerSpender(address _reserveManagerSpender) external onlyOwner {
    _registerReserveManagerSpender(_reserveManagerSpender);
  }

  /// @inheritdoc IReserveV2
  function unregisterReserveManagerSpender(address _reserveManagerSpender) external onlyOwner {
    if (!reserveManagerSpenders.remove(_reserveManagerSpender)) revert ReserveManagerSpenderNotRegistered();
    emit ReserveManagerSpenderUnregistered(_reserveManagerSpender);
  }

  /* ============================================================ */
  /* ====================== External Functions ================== */
  /* ============================================================ */

  /// @inheritdoc IReserveV2
  function transferCollateralAssetToOtherReserve(
    address collateralAsset,
    address to,
    uint256 value
  ) external onlyReserveManagerSpender onlyOtherReserveAddress(to) onlyCollateralAsset(collateralAsset) returns (bool) {
    _transferCollateralAsset(collateralAsset, to, value);
    emit CollateralAssetTransferredReserveManagerSpender(msg.sender, collateralAsset, to, value);
    return true;
  }

  /// @inheritdoc IReserveV2
  function transferCollateralAsset(
    address collateralAsset,
    address to,
    uint256 value
  ) external onlyLiquidityStrategySpender onlyCollateralAsset(collateralAsset) returns (bool) {
    _transferCollateralAsset(collateralAsset, to, value);
    emit CollateralAssetTransferredLiquidityStrategySpender(msg.sender, collateralAsset, to, value);
    return true;
  }

  /* ============================================================ */
  /* ==================== Internal Functions ==================== */
  /* ============================================================ */
  /**
   * @notice Registers a stable asset with the reserve
   * @param _stableAsset The address of the stable asset to register
   */
  function _registerStableAsset(address _stableAsset) internal {
    if (_stableAsset == address(0)) revert StableAssetZeroAddress();
    if (!stableAssets.add(_stableAsset)) revert StableAssetAlreadyRegistered();
    emit StableAssetRegistered(_stableAsset);
  }

  /**
   * @notice Registers a collateral asset with the reserve
   * @param _collateralAsset The address of the collateral asset to register
   */
  function _registerCollateralAsset(address _collateralAsset) internal {
    if (_collateralAsset == address(0)) revert CollateralAssetZeroAddress();
    if (!collateralAssets.add(_collateralAsset)) revert CollateralAssetAlreadyRegistered();
    emit CollateralAssetRegistered(_collateralAsset);
  }

  /**
   * @notice Registers an other reserve address with the reserve
   * @param _otherReserveAddress The address of the other reserve address to register
   */
  function _registerOtherReserveAddress(address _otherReserveAddress) internal {
    if (_otherReserveAddress == address(0)) revert OtherReserveAddressZeroAddress();
    if (!otherReserveAddresses.add(_otherReserveAddress)) revert OtherReserveAddressAlreadyRegistered();
    emit OtherReserveAddressRegistered(_otherReserveAddress);
  }

  /**
   * @notice Registers a liquidity strategy spender with the reserve
   * @param _liquidityStrategySpender The address of the liquidity strategy spender to register
   */
  function _registerLiquidityStrategySpender(address _liquidityStrategySpender) internal {
    if (_liquidityStrategySpender == address(0)) revert LiquidityStrategySpenderZeroAddress();
    if (!liquidityStrategySpenders.add(_liquidityStrategySpender)) revert LiquidityStrategySpenderAlreadyRegistered();
    emit LiquidityStrategySpenderRegistered(_liquidityStrategySpender);
  }

  /**
   * @notice Registers a reserve manager spender with the reserve
   * @param _reserveManagerSpender The address of the reserve manager spender to register
   */
  function _registerReserveManagerSpender(address _reserveManagerSpender) internal {
    if (_reserveManagerSpender == address(0)) revert ReserveManagerSpenderZeroAddress();
    if (!reserveManagerSpenders.add(_reserveManagerSpender)) revert ReserveManagerSpenderAlreadyRegistered();
    emit ReserveManagerSpenderRegistered(_reserveManagerSpender);
  }

  /* ============================================================ */
  /* ==================== Internal Functions ================== */
  /* ============================================================ */

  /**
   * @notice Transfers a collateral asset to an address
   * @param collateralAsset The address of the collateral asset
   * @param to The address to transfer the collateral asset to
   * @param value The amount of collateral asset to transfer
   */
  function _transferCollateralAsset(address collateralAsset, address to, uint256 value) internal {
    if (IERC20(collateralAsset).balanceOf(address(this)) < value) revert InsufficientReserveBalance();
    IERC20(collateralAsset).safeTransfer(to, value);
  }
}
