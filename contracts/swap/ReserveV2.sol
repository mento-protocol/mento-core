// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { IReserveV2 } from "../interfaces/IReserveV2.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
contract ReserveV2 is IReserveV2, OwnableUpgradeable {
  using SafeERC20 for IERC20;

  mapping(address => bool) public isStableToken;
  address[] public stableTokens;

  mapping(address => bool) public isCollateralToken;
  address[] public collateralTokens;

  mapping(address => bool) public isOtherReserveAddress;
  address[] public otherReserveAddresses;

  mapping(address => bool) public isExchangeSpender;
  address[] public exchangeSpenders;

  mapping(address => bool) public isSpender;
  address[] public spenders;

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

    transferOwnership(_initialOwner);
  }

  /* ============================================================ */
  /* ==================== Mutative Functions ==================== */
  /* ============================================================ */
  /// @inheritdoc IReserveV2
  function addStableToken(address _stableToken) external onlyOwner {
    _addStableToken(_stableToken);
  }

  /// @inheritdoc IReserveV2
  function addCollateralToken(address _collateralToken) external onlyOwner {
    _addCollateralToken(_collateralToken);
  }

  /// @inheritdoc IReserveV2
  function addOtherReserveAddress(address _otherReserveAddress) external onlyOwner {
    _addOtherReserveAddress(_otherReserveAddress);
  }

  /// @inheritdoc IReserveV2
  function addExchangeSpender(address _exchangeSpender) external onlyOwner {
    _addExchangeSpender(_exchangeSpender);
  }

  /// @inheritdoc IReserveV2
  function addSpender(address _spender) external onlyOwner {
    _addSpender(_spender);
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
}
