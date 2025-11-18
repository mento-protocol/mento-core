// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >0.5.13 <0.9;

interface IReserveV2 {
  /* ============================================================ */
  /* ======================== Errors ============================ */
  /* ============================================================ */

  // @notice Throw when trying to add a stable token that is already added
  error StableTokenAlreadyAdded();
  // @notice Throw when trying to add a stable token that is zero address
  error StableTokenZeroAddress();
  // @notice Throw when trying to add a collateral token that is already added
  error CollateralTokenAlreadyAdded();
  // @notice Throw when trying to add a collateral token that is zero address
  error CollateralTokenZeroAddress();
  // @notice Throw when trying to add an other reserve address that is already added
  error OtherReserveAddressAlreadyAdded();
  // @notice Throw when trying to add an other reserve address that is zero address
  error OtherReserveAddressZeroAddress();
  // @notice Throw when trying to add an exchange spender that is already added
  error ExchangeSpenderAlreadyAdded();
  // @notice Throw when trying to add an exchange spender that is zero address
  error ExchangeSpenderZeroAddress();
  // @notice Throw when trying to add a spender that is already added
  error SpenderAlreadyAdded();
  // @notice Throw when trying to add a spender that is zero address
  error SpenderZeroAddress();

  /* ============================================================ */
  /* ======================== Events ============================ */
  /* ============================================================ */

  /**
   * @notice Emitted when a stable token is added
   * @param token The address of the stable token
   */
  event StableTokenAdded(address indexed token);
  /**
   * @notice Emitted when a collateral token is added
   * @param token The address of the collateral token
   */
  event CollateralTokenAdded(address indexed token);
  /**
   * @notice Emitted when an other reserve address is added
   * @param otherReserveAddress The address of the other reserve address
   */
  event OtherReserveAddressAdded(address indexed otherReserveAddress);
  /**
   * @notice Emitted when an exchange spender is added
   * @param exchangeSpender The address of the exchange spender
   */
  event ExchangeSpenderAdded(address indexed exchangeSpender);
  /**
   * @notice Emitted when a spender is added
   * @param spender The address of the spender
   */
  event SpenderAdded(address indexed spender);

  /* ============================================================ */
  /* ====================== View Functions ====================== */
  /* ============================================================ */
  /**
   * @notice Checks if a token is a registered stable token
   * @param token The address of the token
   * @return True if the token is a registered stable token
   */
  function isStableToken(address token) external view returns (bool);
  /**
   * @notice Checks if a token is a registered collateral token
   * @param token The address of the token
   * @return True if the token is a registered collateral token
   */
  function isCollateralToken(address token) external view returns (bool);
  /**
   * @notice Checks if an other reserve address is a registered as an other reserve address
   * @param otherReserveAddress The address of the other reserve address
   * @return True if the other reserve address is a registered as an other reserve address
   */
  function isOtherReserveAddress(address otherReserveAddress) external view returns (bool);
  /**
   * @notice Checks if an exchange spender is a registered as an exchange spender
   * @param exchangeSpender The address of the exchange spender
   * @return True if the exchange spender is a registered as an exchange spender
   */
  function isExchangeSpender(address exchangeSpender) external view returns (bool);
  /**
   * @notice Checks if a spender is a registered as a spender
   * @param spender The address of the spender
   * @return True if the spender is a registered as a spender
   */
  function isSpender(address spender) external view returns (bool);

  /* ============================================================ */
  /* ==================== Mutative Functions ==================== */
  /* ============================================================ */
  /**
   * @notice Initializes the reserve
   * @param _stableTokens The addresses of the stable tokens
   * @param _collateralTokens The addresses of the collateral tokens
   * @param _otherReserveAddresses The addresses of the other reserve addresses
   * @param _exchangeSpenders The addresses of the exchange spenders
   * @param _spenders The addresses of the spenders
   * @param _initialOwner The address of the initial owner
   */
  function initialize(
    address[] calldata _stableTokens,
    address[] calldata _collateralTokens,
    address[] calldata _otherReserveAddresses,
    address[] calldata _exchangeSpenders,
    address[] calldata _spenders,
    address _initialOwner
  ) external;
  /**
   * @notice Adds a stable token to the reserve
   * @param _stableToken The address of the stable token
   */
  function addStableToken(address _stableToken) external;
  /**
   * @notice Adds a collateral token to the reserve
   * @param _collateralToken The address of the collateral token
   */
  function addCollateralToken(address _collateralToken) external;
  /**
   * @notice Adds an other reserve address to the reserve
   * @param _otherReserveAddress The address of the other reserve address
   */
  function addOtherReserveAddress(address _otherReserveAddress) external;
  /**
   * @notice Adds an exchange spender to the reserve
   * @param _exchangeSpender The address of the exchange spender
   */
  function addExchangeSpender(address _exchangeSpender) external;
  /**
   * @notice Adds a spender to the reserve
   * @param _spender The address of the spender
   */
  function addSpender(address _spender) external;
}
