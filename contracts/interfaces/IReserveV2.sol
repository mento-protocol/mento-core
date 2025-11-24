// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >0.5.13 <0.9;

interface IReserveV2 {
  /* ============================================================ */
  /* ======================== Errors ============================ */
  /* ============================================================ */

  // @notice Throw when trying to register a stable asset that is already registered
  error StableAssetAlreadyRegistered();
  // @notice Throw when trying to unregister a stable asset that is not registered
  error StableAssetNotRegistered();
  // @notice Throw when trying to register a stable asset that is zero address
  error StableAssetZeroAddress();

  // @notice Throw when trying to register a collateral asset that is already registered
  error CollateralAssetAlreadyRegistered();
  // @notice Throw when trying to unregister a collateral asset that is not registered
  error CollateralAssetNotRegistered();
  // @notice Throw when trying to register a collateral asset that is zero address
  error CollateralAssetZeroAddress();

  // @notice Throw when trying to register an other reserve address that is already registered
  error OtherReserveAddressAlreadyRegistered();
  // @notice Throw when trying to unregister an other reserve address that is not registered
  error OtherReserveAddressNotRegistered();
  // @notice Throw when trying to register an other reserve address that is zero address
  error OtherReserveAddressZeroAddress();

  // @notice Throw when trying to register a liquidity strategy spender that is already registered
  error LiquidityStrategySpenderAlreadyRegistered();
  // @notice Throw when an address is not a registered liquidity strategy spender
  error LiquidityStrategySpenderNotRegistered();
  // @notice Throw when trying to register an liquidity strategy spender that is zero address
  error LiquidityStrategySpenderZeroAddress();

  // @notice Throw when trying to register a reserve manager spender that is already registered
  error ReserveManagerSpenderAlreadyRegistered();
  // @notice Throw when trying to unregister a reserve manager spender that is not registered
  error ReserveManagerSpenderNotRegistered();
  // @notice Throw when trying to register a reserve manager spender that is zero address
  error ReserveManagerSpenderZeroAddress();

  // @notice Throw when trying to remove an address from an empty array
  error ArrayEmpty();
  // @notice Throw when trying to remove an address that is not in the array
  error AddressNotInArray();

  // @notice Throw when trying to transfer an amount that is greater than the balance of the reserve
  error InsufficientReserveBalance();

  /* ============================================================ */
  /* ======================== Events ============================ */
  /* ============================================================ */

  /**
   * @notice Emitted when a stable asset is registered
   * @param stableAsset The address of the stable asset
   */
  event StableAssetRegistered(address indexed stableAsset);
  /**
   * @notice Emitted when a stable asset is unregistered
   * @param stableAsset The address of the stable asset
   */
  event StableAssetUnregistered(address indexed stableAsset);
  /**
   * @notice Emitted when a collateral asset is registered
   * @param collateralAsset The address of the collateral asset
   */
  event CollateralAssetRegistered(address indexed collateralAsset);
  /**
   * @notice Emitted when a collateral asset is unregistered
   * @param collateralAsset The address of the collateral asset
   */
  event CollateralAssetUnregistered(address indexed collateralAsset);
  /**
   * @notice Emitted when an other reserve address is registered
   * @param otherReserveAddress The address of the other reserve address
   */
  event OtherReserveAddressRegistered(address indexed otherReserveAddress);
  /**
   * @notice Emitted when an other reserve address is unregistered
   * @param otherReserveAddress The address of the other reserve address
   */
  event OtherReserveAddressUnregistered(address indexed otherReserveAddress);
  /**
   * @notice Emitted when a liquidity strategy spender is registered
   * @param liquidityStrategySpender The address of the liquidity strategy spender
   */
  event LiquidityStrategySpenderRegistered(address indexed liquidityStrategySpender);
  /**
   * @notice Emitted when a liquidity strategy spender is unregistered
   * @param liquidityStrategySpender The address of the liquidity strategy spender
   */
  event LiquidityStrategySpenderUnregistered(address indexed liquidityStrategySpender);
  /**
   * @notice Emitted when a reserve manager spender is registered
   * @param reserveManagerSpender The address of the reserve manager spender
   */
  event ReserveManagerSpenderRegistered(address indexed reserveManagerSpender);
  /**
   * @notice Emitted when a reserve manager spender is unregistered
   * @param reserveManagerSpender The address of the reserve manager spender
   */
  event ReserveManagerSpenderUnregistered(address indexed reserveManagerSpender);
  /**
   * @notice Emitted when a collateral asset is transferred to an other reserve address by a reserve manager spender
   * @param reserveManagerSpender The address of the reserve manager spender
   * @param collateralAsset The address of the collateral asset
   * @param otherReserveAddress The address of the other reserve address
   * @param value The amount of collateral asset to transfer
   */
  event CollateralAssetTransferredReserveManagerSpender(
    address indexed reserveManagerSpender,
    address indexed collateralAsset,
    address indexed otherReserveAddress,
    uint256 value
  );

  /**
   * @notice Emitted when a collateral asset is transferred by a liquidity strategy spender
   * @param liquidityStrategySpender The address of the liquidity strategy spender
   * @param collateralAsset The address of the collateral asset
   * @param to The address to transfer the collateral asset to
   * @param value The amount of collateral asset to transfer
   */
  event CollateralAssetTransferredLiquidityStrategySpender(
    address indexed liquidityStrategySpender,
    address indexed collateralAsset,
    address indexed to,
    uint256 value
  );

  /* ============================================================ */
  /* ====================== View Functions ====================== */
  /* ============================================================ */
  /**
   * @notice Checks if a asset is a registered stable asset
   * @param stableAsset The address of the stable asset
   * @return True if the stable asset is a registered stable asset
   */
  function isStableAsset(address stableAsset) external view returns (bool);
  /**
   * @notice Checks if a asset is a registered collateral asset
   * @param collateralAsset The address of the collateral asset
   * @return True if the collateral asset is a registered collateral asset
   */
  function isCollateralAsset(address collateralAsset) external view returns (bool);
  /**
   * @notice Checks if an other reserve address is a registered as an other reserve address
   * @param otherReserveAddress The address of the other reserve address
   * @return True if the other reserve address is a registered as an other reserve address
   */
  function isOtherReserveAddress(address otherReserveAddress) external view returns (bool);
  /**
   * @notice Checks if a spender is a registered as an liquidity strategy spender
   * @param spender The address of the liquidity strategy spender
   * @return True if the liquidity strategy spender is a registered as an liquidity strategy spender
   */
  function isLiquidityStrategySpender(address spender) external view returns (bool);
  /**
   * @notice Checks if a spender is a registered as a reserve manager spender
   * @param spender The address of the spender
   * @return True if the reserve manager spender is a registered as a reserve manager spender
   */
  function isReserveManagerSpender(address spender) external view returns (bool);

  /**
   * @notice Returns the list of all registered stable assets
   * @return An array of addresses of stable assets
   */
  function getStableAssets() external view returns (address[] memory);
  /**
   * @notice Returns the list of registered collateral assets
   * @return An array of addresses of collateral assets
   */
  function getCollateralAssets() external view returns (address[] memory);
  /**
   * @notice Returns the list of all registered other reserve addresses
   * @return An array of addresses of other reserve addresses
   */
  function getOtherReserveAddresses() external view returns (address[] memory);
  /**
   * @notice Returns the list of all registered liquidity strategy spenders
   * @return An array of addresses of liquidity strategy spenders
   */
  function getLiquidityStrategySpenders() external view returns (address[] memory);
  /**
   * @notice Returns the list of all registered reserve manager spenders
   * @return An array of addresses of reserve manager spenders
   */
  function getReserveManagerSpenders() external view returns (address[] memory);

  /* ============================================================ */
  /* ==================== Mutative Functions ==================== */
  /* ============================================================ */
  /**
   * @notice Initializes the reserve
   * @param _stableAssets The addresses of the stable assets
   * @param _collateralAssets The addresses of the collateral assets
   * @param _otherReserveAddresses The addresses of the other reserve addresses
   * @param _liquidityStrategySpenders The addresses of the liquidity strategy spenders
   * @param _reserveManagerSpenders The addresses of the reserve manager spenders
   * @param _initialOwner The address of the initial owner
   */
  function initialize(
    address[] calldata _stableAssets,
    address[] calldata _collateralAssets,
    address[] calldata _otherReserveAddresses,
    address[] calldata _liquidityStrategySpenders,
    address[] calldata _reserveManagerSpenders,
    address _initialOwner
  ) external;

  /**
   * @notice Registers a stable asset to the reserve
   * @param _stableAsset The address of the stable asset
   */
  function registerStableAsset(address _stableAsset) external;

  /**
   * @notice Unregisters a stable asset from the reserve
   * @param _stableAsset The address of the stable asset
   */
  function unregisterStableAsset(address _stableAsset) external;

  /**
   * @notice Registers a collateral asset to the reserve
   * @param _collateralAsset The address of the collateral asset
   */
  function registerCollateralAsset(address _collateralAsset) external;

  /**
   * @notice Unregisters a collateral asset from the reserve
   * @param _collateralAsset The address of the collateral asset
   */
  function unregisterCollateralAsset(address _collateralAsset) external;

  /**
   * @notice Registers an other reserve address to the reserve
   * @param _otherReserveAddress The address of the other reserve address
   */
  function registerOtherReserveAddress(address _otherReserveAddress) external;

  /**
   * @notice Unregisters an other reserve address from the reserve
   * @param _otherReserveAddress The address of the other reserve address
   */
  function unregisterOtherReserveAddress(address _otherReserveAddress) external;

  /**
   * @notice Registers an liquidity strategy spender to the reserve
   * @param _liquidityStrategySpender The address of the liquidity strategy spender
   */
  function registerLiquidityStrategySpender(address _liquidityStrategySpender) external;

  /**
   * @notice Unregisters an liquidity strategy spender from the reserve
   * @param _liquidityStrategySpender The address of the liquidity strategy spender
   */
  function unregisterLiquidityStrategySpender(address _liquidityStrategySpender) external;

  /**
   * @notice Registers a reserve manager spender to the reserve
   * @param _reserveManagerSpender The address of the reserve manager spender
   */
  function registerReserveManagerSpender(address _reserveManagerSpender) external;

  /**
   * @notice Unregisters a reserve manager spender from the reserve
   * @param _reserveManagerSpender The address of the reserve manager spender
   */
  function unregisterReserveManagerSpender(address _reserveManagerSpender) external;

  /* ============================================================ */
  /* ====================== External Functions ================== */
  /* ============================================================ */

  /**
   * @notice Transfers collateral asset to another reserve address, by a reserve manager spender
   * @param collateralAsset The address of the collateral asset
   * @param to The address of the other reserve address
   * @param value The amount of collateral asset to transfer
   * @return True if the transaction succeeds
   */
  function transferCollateralAssetToOtherReserve(
    address collateralAsset,
    address to,
    uint256 value
  ) external returns (bool);

  /**
   * @notice Transfers collateral asset by a liquidity strategy spender
   * @param collateralAsset The address of the collateral asset
   * @param to The address to transfer the collateral asset to
   * @param value The amount of collateral asset to transfer
   * @return True if the transaction succeeds
   */
  function transferCollateralAsset(address collateralAsset, address to, uint256 value) external returns (bool);
}
