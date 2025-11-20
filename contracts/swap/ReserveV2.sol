// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { IReserveV2 } from "../interfaces/IReserveV2.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
contract ReserveV2 is IReserveV2, OwnableUpgradeable {
  using SafeERC20 for IERC20;

  mapping(address => bool) public isStableAsset;
  address[] public stableAssets;

  mapping(address => bool) public isCollateralAsset;
  address[] public collateralAssets;

  mapping(address => bool) public isOtherReserveAddress;
  address[] public otherReserveAddresses;

  mapping(address => bool) public isLiquidityStrategySpender;
  address[] public liquidityStrategySpenders;

  mapping(address => bool) public isReserveManagerSpender;
  address[] public reserveManagerSpenders;

  modifier onlyReserveManagerSpender() {
    if (!isReserveManagerSpender[msg.sender]) revert ReserveManagerSpenderNotRegistered();
    _;
  }

  modifier onlyLiquidityStrategySpender() {
    if (!isLiquidityStrategySpender[msg.sender]) revert LiquidityStrategySpenderNotRegistered();
    _;
  }

  modifier onlyCollateralAsset(address collateralAsset) {
    if (!isCollateralAsset[collateralAsset]) revert CollateralAssetNotRegistered();
    _;
  }

  modifier onlyOtherReserveAddress(address otherReserveAddress) {
    if (!isOtherReserveAddress[otherReserveAddress]) revert OtherReserveAddressNotRegistered();
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
  function getStableAssets() external view returns (address[] memory) {
    return stableAssets;
  }

  /// @inheritdoc IReserveV2
  function getCollateralAssets() external view returns (address[] memory) {
    return collateralAssets;
  }

  /// @inheritdoc IReserveV2
  function getOtherReserveAddresses() external view returns (address[] memory) {
    return otherReserveAddresses;
  }

  /// @inheritdoc IReserveV2
  function getLiquidityStrategySpenders() external view returns (address[] memory) {
    return liquidityStrategySpenders;
  }

  /// @inheritdoc IReserveV2
  function getReserveManagerSpenders() external view returns (address[] memory) {
    return reserveManagerSpenders;
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
    if (!isStableAsset[_stableAsset]) revert StableAssetNotRegistered();
    isStableAsset[_stableAsset] = false;
    _removeAddressFromArray(stableAssets, _stableAsset);
    emit StableAssetUnregistered(_stableAsset);
  }

  /// @inheritdoc IReserveV2
  function registerCollateralAsset(address _collateralAsset) external onlyOwner {
    _registerCollateralAsset(_collateralAsset);
  }

  /// @inheritdoc IReserveV2
  function unregisterCollateralAsset(address _collateralAsset) external onlyOwner {
    if (!isCollateralAsset[_collateralAsset]) revert CollateralAssetNotRegistered();
    isCollateralAsset[_collateralAsset] = false;
    _removeAddressFromArray(collateralAssets, _collateralAsset);
    emit CollateralAssetUnregistered(_collateralAsset);
  }

  /// @inheritdoc IReserveV2
  function registerOtherReserveAddress(address _otherReserveAddress) external onlyOwner {
    _registerOtherReserveAddress(_otherReserveAddress);
  }

  /// @inheritdoc IReserveV2
  function unregisterOtherReserveAddress(address _otherReserveAddress) external onlyOwner {
    if (!isOtherReserveAddress[_otherReserveAddress]) revert OtherReserveAddressNotRegistered();
    isOtherReserveAddress[_otherReserveAddress] = false;
    _removeAddressFromArray(otherReserveAddresses, _otherReserveAddress);
    emit OtherReserveAddressUnregistered(_otherReserveAddress);
  }

  /// @inheritdoc IReserveV2
  function registerLiquidityStrategySpender(address _liquidityStrategySpender) external onlyOwner {
    _registerLiquidityStrategySpender(_liquidityStrategySpender);
  }

  /// @inheritdoc IReserveV2
  function unregisterLiquidityStrategySpender(address _liquidityStrategySpender) external onlyOwner {
    if (!isLiquidityStrategySpender[_liquidityStrategySpender]) revert LiquidityStrategySpenderNotRegistered();
    isLiquidityStrategySpender[_liquidityStrategySpender] = false;
    _removeAddressFromArray(liquidityStrategySpenders, _liquidityStrategySpender);
    emit LiquidityStrategySpenderUnregistered(_liquidityStrategySpender);
  }

  /// @inheritdoc IReserveV2
  function registerReserveManagerSpender(address _reserveManagerSpender) external onlyOwner {
    _registerReserveManagerSpender(_reserveManagerSpender);
  }

  /// @inheritdoc IReserveV2
  function unregisterReserveManagerSpender(address _reserveManagerSpender) external onlyOwner {
    if (!isReserveManagerSpender[_reserveManagerSpender]) revert ReserveManagerSpenderNotRegistered();
    isReserveManagerSpender[_reserveManagerSpender] = false;
    _removeAddressFromArray(reserveManagerSpenders, _reserveManagerSpender);
    emit ReserveManagerSpenderUnregistered(_reserveManagerSpender);
  }

  /* ============================================================ */
  /* ====================== External Functions ================== */
  /* ============================================================ */

  /// @inheritdoc IReserveV2
  function transferCollateralAssetToOtherReserve(
    address to,
    address collateralAsset,
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
    if (isStableAsset[_stableAsset]) revert StableAssetAlreadyRegistered();
    if (_stableAsset == address(0)) revert StableAssetZeroAddress();
    isStableAsset[_stableAsset] = true;
    stableAssets.push(_stableAsset);
    emit StableAssetRegistered(_stableAsset);
  }

  /**
   * @notice Registers a collateral asset with the reserve
   * @param _collateralAsset The address of the collateral asset to register
   */
  function _registerCollateralAsset(address _collateralAsset) internal {
    if (isCollateralAsset[_collateralAsset]) revert CollateralAssetAlreadyRegistered();
    if (_collateralAsset == address(0)) revert CollateralAssetZeroAddress();
    isCollateralAsset[_collateralAsset] = true;
    collateralAssets.push(_collateralAsset);
    emit CollateralAssetRegistered(_collateralAsset);
  }

  /**
   * @notice Registers an other reserve address with the reserve
   * @param _otherReserveAddress The address of the other reserve address to register
   */
  function _registerOtherReserveAddress(address _otherReserveAddress) internal {
    if (isOtherReserveAddress[_otherReserveAddress]) revert OtherReserveAddressAlreadyRegistered();
    if (_otherReserveAddress == address(0)) revert OtherReserveAddressZeroAddress();
    isOtherReserveAddress[_otherReserveAddress] = true;
    otherReserveAddresses.push(_otherReserveAddress);
    emit OtherReserveAddressRegistered(_otherReserveAddress);
  }

  /**
   * @notice Registers a liquidity strategy spender with the reserve
   * @param _liquidityStrategySpender The address of the liquidity strategy spender to register
   */
  function _registerLiquidityStrategySpender(address _liquidityStrategySpender) internal {
    if (isLiquidityStrategySpender[_liquidityStrategySpender]) revert LiquidityStrategySpenderAlreadyRegistered();
    if (_liquidityStrategySpender == address(0)) revert LiquidityStrategySpenderZeroAddress();
    isLiquidityStrategySpender[_liquidityStrategySpender] = true;
    liquidityStrategySpenders.push(_liquidityStrategySpender);
    emit LiquidityStrategySpenderRegistered(_liquidityStrategySpender);
  }

  /**
   * @notice Registers a reserve manager spender with the reserve
   * @param _reserveManagerSpender The address of the reserve manager spender to register
   */
  function _registerReserveManagerSpender(address _reserveManagerSpender) internal {
    if (isReserveManagerSpender[_reserveManagerSpender]) revert ReserveManagerSpenderAlreadyRegistered();
    if (_reserveManagerSpender == address(0)) revert ReserveManagerSpenderZeroAddress();
    isReserveManagerSpender[_reserveManagerSpender] = true;
    reserveManagerSpenders.push(_reserveManagerSpender);
    emit ReserveManagerSpenderRegistered(_reserveManagerSpender);
  }

  /* ============================================================ */
  /* ==================== Internal Functions ================== */
  /* ============================================================ */

  /**
   * @notice Removes an address from an array and returns the new array
   * @param array The array to remove the address from
   * @param _address The address to remove from the array
   */
  function _removeAddressFromArray(address[] storage array, address _address) internal {
    if (array.length == 0) revert ArrayEmpty();
    // slither-disable-next-line uninitialized-local
    uint256 index;
    for (uint256 i = 0; i < array.length; i++) {
      if (array[i] == _address) {
        index = i;
        break;
      }
    }
    if (array[index] != _address) revert AddressNotInArray();

    array[index] = array[array.length - 1];
    array.pop();
  }

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
