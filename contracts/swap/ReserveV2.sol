// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { IReserveV2 } from "../interfaces/IReserveV2.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
contract ReserveV2 is IReserveV2, OwnableUpgradeable {
  using SafeERC20 for IERC20;
  // maybe need to rename to isStableAsset
  mapping(address => bool) public isStableToken;
  address[] public stableTokens;
  // maybe need to rename to isCollateralAsset
  mapping(address => bool) public isCollateralToken;
  address[] public collateralTokens;

  mapping(address => bool) public isOtherReserveAddress;
  address[] public otherReserveAddresses;

  mapping(address => bool) public isExchangeSpender;
  address[] public exchangeSpenders;

  mapping(address => bool) public isSpender;
  address[] public spenders;

  modifier onlySpender() {
    if (!isSpender[msg.sender]) revert SpenderNotRegistered();
    _;
  }

  modifier onlyExchangeSpender() {
    if (!isExchangeSpender[msg.sender]) revert ExchangeSpenderNotRegistered();
    _;
  }

  modifier onlyCollateralToken(address collateralAsset) {
    if (!isCollateralToken[collateralAsset]) revert CollateralTokenNotRegistered();
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
    address[] calldata _stableTokens,
    address[] calldata _collateralTokens,
    address[] calldata _otherReserveAddresses,
    address[] calldata _exchangeSpenders,
    address[] calldata _spenders,
    address _initialOwner
  ) external initializer {
    __Ownable_init();

    for (uint256 i = 0; i < _stableTokens.length; i++) {
      _addStableToken(_stableTokens[i]);
    }
    for (uint256 i = 0; i < _collateralTokens.length; i++) {
      _addCollateralToken(_collateralTokens[i]);
    }
    for (uint256 i = 0; i < _otherReserveAddresses.length; i++) {
      _addOtherReserveAddress(_otherReserveAddresses[i]);
    }
    for (uint256 i = 0; i < _exchangeSpenders.length; i++) {
      _addExchangeSpender(_exchangeSpenders[i]);
    }
    for (uint256 i = 0; i < _spenders.length; i++) {
      _addSpender(_spenders[i]);
    }

    transferOwnership(_initialOwner);
  }

  receive() external payable {} // solhint-disable no-empty-blocks

  /* ============================================================ */
  /* ====================== View Functions ====================== */
  /* ============================================================ */

  /// @inheritdoc IReserveV2
  function getStableTokens() external view returns (address[] memory) {
    return stableTokens;
  }

  /// @inheritdoc IReserveV2
  function getCollateralTokens() external view returns (address[] memory) {
    return collateralTokens;
  }

  /// @inheritdoc IReserveV2
  function getOtherReserveAddresses() external view returns (address[] memory) {
    return otherReserveAddresses;
  }

  /// @inheritdoc IReserveV2
  function getExchangeSpenders() external view returns (address[] memory) {
    return exchangeSpenders;
  }

  /// @inheritdoc IReserveV2
  function getSpenders() external view returns (address[] memory) {
    return spenders;
  }

  /* ============================================================ */
  /* ==================== Mutative Functions ==================== */
  /* ============================================================ */
  /// @inheritdoc IReserveV2
  function addStableToken(address _stableToken) external onlyOwner {
    _addStableToken(_stableToken);
  }

  /// @inheritdoc IReserveV2
  function removeStableToken(address _stableToken) external onlyOwner {
    if (!isStableToken[_stableToken]) revert StableTokenNotAdded();
    isStableToken[_stableToken] = false;
    _removeAddressFromArray(stableTokens, _stableToken);
    emit StableTokenRemoved(_stableToken);
  }

  /// @inheritdoc IReserveV2
  function addCollateralToken(address _collateralToken) external onlyOwner {
    _addCollateralToken(_collateralToken);
  }

  /// @inheritdoc IReserveV2
  function removeCollateralToken(address _collateralToken) external onlyOwner {
    if (!isCollateralToken[_collateralToken]) revert CollateralTokenNotRegistered();
    isCollateralToken[_collateralToken] = false;
    _removeAddressFromArray(collateralTokens, _collateralToken);
    emit CollateralTokenRemoved(_collateralToken);
  }

  /// @inheritdoc IReserveV2
  function addOtherReserveAddress(address _otherReserveAddress) external onlyOwner {
    _addOtherReserveAddress(_otherReserveAddress);
  }

  /// @inheritdoc IReserveV2
  function removeOtherReserveAddress(address _otherReserveAddress) external onlyOwner {
    if (!isOtherReserveAddress[_otherReserveAddress]) revert OtherReserveAddressNotRegistered();
    isOtherReserveAddress[_otherReserveAddress] = false;
    _removeAddressFromArray(otherReserveAddresses, _otherReserveAddress);
    emit OtherReserveAddressRemoved(_otherReserveAddress);
  }

  /// @inheritdoc IReserveV2
  function addExchangeSpender(address _exchangeSpender) external onlyOwner {
    _addExchangeSpender(_exchangeSpender);
  }

  /// @inheritdoc IReserveV2
  function removeExchangeSpender(address _exchangeSpender) external onlyOwner {
    if (!isExchangeSpender[_exchangeSpender]) revert ExchangeSpenderNotRegistered();
    isExchangeSpender[_exchangeSpender] = false;
    _removeAddressFromArray(exchangeSpenders, _exchangeSpender);
    emit ExchangeSpenderRemoved(_exchangeSpender);
  }

  /// @inheritdoc IReserveV2
  function addSpender(address _spender) external onlyOwner {
    _addSpender(_spender);
  }

  /// @inheritdoc IReserveV2
  function removeSpender(address _spender) external onlyOwner {
    if (!isSpender[_spender]) revert SpenderNotRegistered();
    isSpender[_spender] = false;
    _removeAddressFromArray(spenders, _spender);
    emit SpenderRemoved(_spender);
  }

  /* ============================================================ */
  /* ====================== External Functions ================== */
  /* ============================================================ */

  /// @inheritdoc IReserveV2
  function transferCollateralAsset(
    address to,
    address collateralAsset,
    uint256 value
  ) external onlySpender onlyOtherReserveAddress(to) onlyCollateralToken(collateralAsset) returns (bool) {
    _transferCollateralAsset(collateralAsset, to, value);
    emit CollateralAssetTransferredSpender(msg.sender, collateralAsset, to, value);
    return true;
  }

  // maybe need to make to payable
  /// @inheritdoc IReserveV2
  function transferExchangeCollateralAsset(
    address collateralAsset,
    address to,
    uint256 value
  ) external onlyExchangeSpender onlyCollateralToken(collateralAsset) returns (bool) {
    _transferCollateralAsset(collateralAsset, to, value);
    emit CollateralAssetTransferredExchangeSpender(msg.sender, collateralAsset, to, value);
    return true;
  }

  /* ============================================================ */
  /* ==================== Internal Functions ==================== */
  /* ============================================================ */
  /**
   * @notice Registers a stable token with the reserve
   * @param _stableToken The address of the stable token to register
   */
  function _addStableToken(address _stableToken) internal {
    if (isStableToken[_stableToken]) revert StableTokenAlreadyAdded();
    if (_stableToken == address(0)) revert StableTokenZeroAddress();
    isStableToken[_stableToken] = true;
    stableTokens.push(_stableToken);
    emit StableTokenAdded(_stableToken);
  }

  /**
   * @notice Registers a collateral token with the reserve
   * @param _collateralToken The address of the collateral token to register
   */
  function _addCollateralToken(address _collateralToken) internal {
    if (isCollateralToken[_collateralToken]) revert CollateralTokenAlreadyAdded();
    if (_collateralToken == address(0)) revert CollateralTokenZeroAddress();
    isCollateralToken[_collateralToken] = true;
    collateralTokens.push(_collateralToken);
    emit CollateralTokenAdded(_collateralToken);
  }

  /**
   * @notice Registers an other reserve address with the reserve
   * @param _otherReserveAddress The address of the other reserve address to register
   */
  function _addOtherReserveAddress(address _otherReserveAddress) internal {
    if (isOtherReserveAddress[_otherReserveAddress]) revert OtherReserveAddressAlreadyAdded();
    if (_otherReserveAddress == address(0)) revert OtherReserveAddressZeroAddress();
    isOtherReserveAddress[_otherReserveAddress] = true;
    otherReserveAddresses.push(_otherReserveAddress);
    emit OtherReserveAddressAdded(_otherReserveAddress);
  }

  /**
   * @notice Registers an exchange spender with the reserve
   * @param _exchangeSpender The address of the exchange spender to register
   */
  function _addExchangeSpender(address _exchangeSpender) internal {
    if (isExchangeSpender[_exchangeSpender]) revert ExchangeSpenderAlreadyAdded();
    if (_exchangeSpender == address(0)) revert ExchangeSpenderZeroAddress();
    isExchangeSpender[_exchangeSpender] = true;
    exchangeSpenders.push(_exchangeSpender);
    emit ExchangeSpenderAdded(_exchangeSpender);
  }

  /**
   * @notice Registers a spender with the reserve
   * @param _spender The address of the spender to register
   */
  function _addSpender(address _spender) internal {
    if (isSpender[_spender]) revert SpenderAlreadyAdded();
    if (_spender == address(0)) revert SpenderZeroAddress();
    isSpender[_spender] = true;
    spenders.push(_spender);
    emit SpenderAdded(_spender);
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
