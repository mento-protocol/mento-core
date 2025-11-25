// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

import { ICreateX } from "../interfaces/ICreateX.sol";

import "../interfaces/IFPMMFactory.sol";
import { IFPMM } from "../interfaces/IFPMM.sol";
import { FPMMProxy } from "./FPMMProxy.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";

contract FPMMFactory is IFPMMFactory, OwnableUpgradeable {
  /* ========================================================= */
  /* ==================== State Variables ==================== */
  /* ========================================================= */

  // Address of the CREATEX contract.
  address public constant CREATEX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

  // Bytecode hash of the CREATEX contract retrieved from celo mainnet
  // cast keccak $(cast code 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed --rpc-url https://forno.celo.org)
  bytes32 public constant CREATEX_BYTECODE_HASH = 0xbd8a7ea8cfca7b4e5f5041d7d4b17bc317c5ce42cfbc42066a00cf26b43eb53f;

  // Storage location of the FPMMFactoryStorage struct
  // keccak256(abi.encode(uint256(keccak256("mento.storage.FPMMFactory")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant FPMM_FACTORY_STORAGE_LOCATION =
    0x68492e385e38c18b9b27d9179e6aab533cb32a63ce1a1d4414f8c6f6f2d53b00;

  /// @custom:storage-location erc7201:mento.storage.FPMMFactory
  struct FPMMFactoryStorage {
    // Address of the oracle adapter contract.
    address oracleAdapter;
    // Address of the proxy admin contract.
    address proxyAdmin;
    // Mapping of deployed FPMMs.
    mapping(address => mapping(address => address)) deployedFPMMs;
    // Mapping of allowed FPMM implementations.
    mapping(address => bool) isRegisteredImplementation;
    // List of deployed FPMM addresses.
    address[] deployedFPMMAddresses;
    // List of registered FPMM implementations.
    address[] registeredImplementations;
    // Mapping of deployed pools.
    mapping(address => bool) isPool;
    // Default parameters when deploying a new FPMM.
    IFPMM.FPMMParams defaultParams;
  }

  /* ============================================================ */
  /* ======================== Constructor ======================= */
  /* ============================================================ */

  /**
   * @dev Should be called with disable=true in deployments when it's accessed through a Proxy.
   * Call this with disable=false during testing, when used without a proxy.
   * @param disable Set to true to run `_disableInitializers()` inherited from
   * openzeppelin-contracts-upgradeable/Initializable.sol
   */
  constructor(bool disable) {
    if (disable) {
      _disableInitializers();
    }
    bytes32 createXCodeHash;
    // solhint-disable-next-line no-inline-assembly
    assembly {
      createXCodeHash := extcodehash(CREATEX)
    }
    if (createXCodeHash != CREATEX_BYTECODE_HASH) revert CreateXBytecodeHashMismatch();
  }

  /* ============================================================ */
  /* ==================== Initialization ======================== */
  /* ============================================================ */

  /// @inheritdoc IFPMMFactory
  function initialize(
    address _oracleAdapter,
    address _proxyAdmin,
    address _initialOwner,
    address _fpmmImplementation,
    IFPMM.FPMMParams calldata _defaultParams
  ) external initializer {
    __Ownable_init();
    setProxyAdmin(_proxyAdmin);
    setOracleAdapter(_oracleAdapter);
    registerFPMMImplementation(_fpmmImplementation);
    setDefaultParams(_defaultParams);
    transferOwnership(_initialOwner);
  }

  /* ============================================================ */
  /* ===================== View Functions ======================= */
  /* ============================================================ */

  /// @inheritdoc IFPMMFactory
  function oracleAdapter() public view returns (address) {
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    return $.oracleAdapter;
  }

  /// @inheritdoc IFPMMFactory
  function proxyAdmin() public view returns (address) {
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    return $.proxyAdmin;
  }

  /// @inheritdoc IFPMMFactory
  function defaultParams() public view returns (IFPMM.FPMMParams memory) {
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    return $.defaultParams;
  }

  /// @inheritdoc IFPMMFactory
  function deployedFPMMAddresses() public view returns (address[] memory) {
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    return $.deployedFPMMAddresses;
  }

  /// @inheritdoc IFPMMFactory
  function isRegisteredImplementation(address fpmmImplementation) public view returns (bool) {
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    return $.isRegisteredImplementation[fpmmImplementation];
  }

  /// @inheritdoc IFPMMFactory
  function registeredImplementations() public view returns (address[] memory) {
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    return $.registeredImplementations;
  }

  // slither-disable-start encode-packed-collision
  /// @inheritdoc IRPoolFactory
  function getOrPrecomputeProxyAddress(address token0, address token1) public view returns (address) {
    address pool = getPool(token0, token1);
    if (pool != address(0)) {
      return pool;
    }

    (token0, token1) = sortTokens(token0, token1);

    (address precomputedProxyAddress, ) = _computeProxyAddressAndSalt(token0, token1);
    return precomputedProxyAddress;
  }

  // slither-disable-end encode-packed-collision

  /// @inheritdoc IFPMMFactory
  function sortTokens(address tokenA, address tokenB) public pure returns (address token0, address token1) {
    if (tokenA == tokenB) revert IdenticalTokenAddresses();
    (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    if (token0 == address(0)) revert SortTokensZeroAddress();
  }

  /// @inheritdoc IRPoolFactory
  function getPool(address token0, address token1) public view returns (address) {
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    return $.deployedFPMMs[token0][token1];
  }

  /// @inheritdoc IRPoolFactory
  function isPool(address pool) public view returns (bool) {
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    return $.isPool[pool];
  }

  /* ============================================================ */
  /* ===================== Admin Functions ======================= */
  /* ============================================================ */

  /// @inheritdoc IFPMMFactory
  function setOracleAdapter(address _oracleAdapter) public onlyOwner {
    if (_oracleAdapter == address(0)) revert ZeroAddress();
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    $.oracleAdapter = _oracleAdapter;
    emit OracleAdapterSet(_oracleAdapter);
  }

  /// @inheritdoc IFPMMFactory
  function setProxyAdmin(address _proxyAdmin) public onlyOwner {
    if (_proxyAdmin == address(0)) revert ZeroAddress();
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    $.proxyAdmin = _proxyAdmin;
    emit ProxyAdminSet(_proxyAdmin);
  }

  /// @inheritdoc IFPMMFactory
  function setDefaultParams(IFPMM.FPMMParams calldata _defaultParams) public onlyOwner {
    if (_defaultParams.protocolFee + _defaultParams.lpFee > 100) revert FeeTooHigh();
    if (_defaultParams.protocolFeeRecipient == address(0)) revert ZeroAddress();
    if (_defaultParams.rebalanceIncentive > 100) revert RebalanceIncentiveTooHigh();
    if (_defaultParams.rebalanceThresholdAbove > 1000) revert RebalanceThresholdTooHigh();
    if (_defaultParams.rebalanceThresholdBelow > 1000) revert RebalanceThresholdTooHigh();

    FPMMFactoryStorage storage $ = _getFPMMStorage();
    $.defaultParams = _defaultParams;
    emit DefaultParamsSet(_defaultParams);
  }

  /// @inheritdoc IFPMMFactory
  function registerFPMMImplementation(address fpmmImplementation) public onlyOwner {
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    if (fpmmImplementation == address(0)) revert ZeroAddress();
    if ($.isRegisteredImplementation[fpmmImplementation]) revert ImplementationAlreadyRegistered();
    $.isRegisteredImplementation[fpmmImplementation] = true;
    $.registeredImplementations.push(fpmmImplementation);
    emit FPMMImplementationRegistered(fpmmImplementation);
  }

  /// @inheritdoc IFPMMFactory
  function unregisterFPMMImplementation(address fpmmImplementation, uint256 index) public onlyOwner {
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    if (!$.isRegisteredImplementation[fpmmImplementation]) revert ImplementationNotRegistered();
    if (index >= $.registeredImplementations.length) revert IndexOutOfBounds();
    if ($.registeredImplementations[index] != fpmmImplementation) revert ImplementationIndexMismatch();
    $.isRegisteredImplementation[fpmmImplementation] = false;
    if ($.registeredImplementations.length > 1) {
      $.registeredImplementations[index] = $.registeredImplementations[$.registeredImplementations.length - 1];
    }
    $.registeredImplementations.pop();
    emit FPMMImplementationUnregistered(fpmmImplementation);
  }

  /// @inheritdoc IFPMMFactory
  function deployFPMM(
    address fpmmImplementation,
    address customOracleAdapter,
    address customProxyAdmin,
    address customOwner,
    address token0,
    address token1,
    address referenceRateFeedID,
    bool invertRateFeed,
    IFPMM.FPMMParams calldata customParams
  ) external onlyOwner returns (address) {
    (token0, token1) = sortTokens(token0, token1);

    FPMMFactoryStorage storage $ = _getFPMMStorage();

    if (!$.isRegisteredImplementation[fpmmImplementation]) revert ImplementationNotRegistered();
    if (customOracleAdapter == address(0)) revert InvalidOracleAdapter();
    if (customProxyAdmin == address(0)) revert InvalidProxyAdmin();
    if (customOwner == address(0)) revert InvalidOwner();
    if (referenceRateFeedID == address(0)) revert InvalidReferenceRateFeedID();
    if (getPool(token0, token1) != address(0)) revert PairAlreadyExists();

    address fpmmProxy = _deployFPMMProxy(
      fpmmImplementation,
      customOracleAdapter,
      customProxyAdmin,
      customOwner,
      token0,
      token1,
      referenceRateFeedID,
      invertRateFeed,
      customParams
    );

    emit FPMMDeployed(token0, token1, fpmmProxy, fpmmImplementation);
    return fpmmProxy;
  }

  // slither-disable-start reentrancy-no-eth
  /// @inheritdoc IFPMMFactory
  function deployFPMM(
    address fpmmImplementation,
    address token0,
    address token1,
    address referenceRateFeedID,
    bool invertRateFeed
  ) external onlyOwner returns (address) {
    (token0, token1) = sortTokens(token0, token1);

    FPMMFactoryStorage storage $ = _getFPMMStorage();
    if (!$.isRegisteredImplementation[fpmmImplementation]) revert ImplementationNotRegistered();

    if (getPool(token0, token1) != address(0)) revert PairAlreadyExists();
    if (referenceRateFeedID == address(0)) revert InvalidReferenceRateFeedID();

    address fpmmProxy = _deployFPMMProxy(
      fpmmImplementation,
      $.oracleAdapter,
      $.proxyAdmin,
      owner(),
      token0,
      token1,
      referenceRateFeedID,
      invertRateFeed,
      $.defaultParams
    );

    emit FPMMDeployed(token0, token1, fpmmProxy, fpmmImplementation);
    return fpmmProxy;
  }

  // slither-disable-end reentrancy-no-eth

  /* ============================================================ */
  /* =================== Internal Functions ===================== */
  /* ============================================================ */

  /**
   * @notice Deploys the FPMM proxy contract.
   * @param _fpmmImplementation The address of the FPMM implementation
   * @param _oracleAdapter The address of the oracle adapter contract
   * @param _proxyAdmin The address of the proxy admin contract
   * @param _owner The address of the owner
   * @param _token0 The address of the first token
   * @param _token1 The address of the second token
   * @param _referenceRateFeedID The address of the reference rate feed
   * @param _invertRateFeed Whether to invert the rate feed
   * @param _params The parameters for the FPMM
   * @return The address of the deployed FPMM proxy
   */
  // slither-disable-start reentrancy-benign
  // slither-disable-start reentrancy-events
  // slither-disable-start encode-packed-collision
  function _deployFPMMProxy(
    address _fpmmImplementation,
    address _oracleAdapter,
    address _proxyAdmin,
    address _owner,
    address _token0,
    address _token1,
    address _referenceRateFeedID,
    bool _invertRateFeed,
    IFPMM.FPMMParams memory _params
  ) internal returns (address) {
    FPMMFactoryStorage storage $ = _getFPMMStorage();

    address newProxyAddress = _deployNewProxy(
      _fpmmImplementation,
      _oracleAdapter,
      _proxyAdmin,
      _owner,
      _token0,
      _token1,
      _referenceRateFeedID,
      _invertRateFeed,
      _params
    );

    $.deployedFPMMs[_token0][_token1] = newProxyAddress;
    $.deployedFPMMs[_token1][_token0] = newProxyAddress;
    $.isPool[newProxyAddress] = true;
    $.deployedFPMMAddresses.push(newProxyAddress);

    return newProxyAddress;
  }

  /**
   * @notice Internal helper function to deploy a new FPMM proxy contract.
   * @param _fpmmImplementation The address of the FPMM implementation
   * @param _oracleAdapter The address of the oracle adapter contract
   * @param _proxyAdmin The address of the proxy admin contract
   * @param _owner The address of the owner
   * @param _token0 The address of the first token
   * @param _token1 The address of the second token
   * @param _referenceRateFeedID The address of the reference rate feed
   * @param _invertRateFeed Whether to invert the rate feed
   * @param _params The parameters for the FPMM
   * @return The address of the deployed FPMM proxy
   */
  function _deployNewProxy(
    address _fpmmImplementation,
    address _oracleAdapter,
    address _proxyAdmin,
    address _owner,
    address _token0,
    address _token1,
    address _referenceRateFeedID,
    bool _invertRateFeed,
    IFPMM.FPMMParams memory _params
  ) internal returns (address) {
    (address expectedProxyAddress, bytes32 salt) = _computeProxyAddressAndSalt(_token0, _token1);
    bytes memory initData = abi.encodeWithSelector(
      IFPMM.initialize.selector,
      _token0,
      _token1,
      _oracleAdapter,
      _referenceRateFeedID,
      _invertRateFeed,
      _owner,
      _params
    );
    bytes memory proxyBytecode = abi.encodePacked(
      type(FPMMProxy).creationCode,
      abi.encode(_fpmmImplementation, _proxyAdmin, initData)
    );
    address newProxyAddress = ICreateX(CREATEX).deployCreate3(salt, proxyBytecode);
    assert(newProxyAddress == expectedProxyAddress);

    return newProxyAddress;
  }

  // slither-disable-end reentrancy-benign
  // slither-disable-end reentrancy-events
  // slither-disable-end encode-packed-collision

  /**
   * @notice Computes the address of the FPMM proxy contract.
   * @dev apply permissioned deploy protection with factory address and custom salt
   *      see https://github.com/pcaversaccio/createx?tab=readme-ov-file for more details
   *      custom salt is a keccak256 hash of the token0 and token1 symbols
   * @param token0 The address of the first token
   * @param token1 The address of the second token
   * @return The precomputed address of the FPMM proxy contract
   * @return The salt used to deploy the FPMM proxy contract
   */
  // slither-disable-start encode-packed-collision
  function _computeProxyAddressAndSalt(address token0, address token1) internal view returns (address, bytes32) {
    bytes11 customSalt = bytes11(
      uint88(uint256(keccak256(abi.encodePacked(IERC20(token0).symbol(), IERC20(token1).symbol()))))
    );
    bytes32 salt = bytes32(abi.encodePacked(address(this), hex"00", customSalt));
    bytes32 guardedSalt = _efficientHash({ a: bytes32(uint256(uint160(address(this)))), b: salt });

    address proxyAddress = ICreateX(CREATEX).computeCreate3Address(guardedSalt);
    return (proxyAddress, salt);
  }

  // slither-disable-end encode-packed-collision

  /**
   * @notice Returns the pointer to the FPMMFactoryStorage struct.
   * @return $ The pointer to the FPMMFactoryStorage struct
   */
  function _getFPMMStorage() private pure returns (FPMMFactoryStorage storage $) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      $.slot := FPMM_FACTORY_STORAGE_LOCATION
    }
  }

  /**
   * @notice Hashes two bytes32 values efficiently.
   * @dev copied from CREATEX contract to precalculated deployment addresses
   *      see https://github.com/pcaversaccio/createx/blob/7ab1e452b8803cae1467efd455dee1530660373b/src/CreateX.sol#L952
   * @param a The first bytes32 value
   * @param b The second bytes32 value
   * @return hash The keccak256 hash of the two values
   */
  function _efficientHash(bytes32 a, bytes32 b) internal pure returns (bytes32 hash) {
    // Warning ignored, because this is a helper function and copied from CREATEX contract
    // solhint-disable-next-line no-inline-assembly
    assembly ("memory-safe") {
      mstore(0x00, a)
      mstore(0x20, b)
      hash := keccak256(0x00, 0x40)
    }
  }
}
