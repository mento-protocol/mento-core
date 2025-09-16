// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

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
    // Address of the adaptore contract.
    address adaptore;
    // Address of the proxy admin contract.
    address proxyAdmin;
    // Address of the governance contract.
    address governance;
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
  }

  /* ===================================================== */
  /* ==================== Constructor ==================== */
  /* ===================================================== */

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
    require(keccak256(CREATEX.code) == CREATEX_BYTECODE_HASH, "FPMMFactory: CREATEX_BYTECODE_HASH_MISMATCH");
  }

  /// @inheritdoc IFPMMFactory
  function initialize(
    address _adaptore,
    address _proxyAdmin,
    address _governance,
    address _fpmmImplementation
  ) external initializer {
    __Ownable_init();
    setProxyAdmin(_proxyAdmin);
    setAdaptore(_adaptore);
    registerFPMMImplementation(_fpmmImplementation);
    setGovernance(_governance);
  }

  /* ======================================================== */
  /* ==================== View Functions ==================== */
  /* ======================================================== */

  /// @inheritdoc IFPMMFactory
  function adaptore() public view returns (address) {
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    return $.adaptore;
  }

  /// @inheritdoc IFPMMFactory
  function proxyAdmin() public view returns (address) {
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    return $.proxyAdmin;
  }

  /// @inheritdoc IFPMMFactory
  function governance() public view returns (address) {
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    return $.governance;
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
    (token0, token1) = sortTokens(token0, token1);

    address pool = getPool(token0, token1);
    if (pool != address(0)) {
      return pool;
    }

    (address precomputedProxyAddress, ) = _computeProxyAddressAndSalt(token0, token1);
    return precomputedProxyAddress;
  }
  // slither-disable-end encode-packed-collision

  /// @inheritdoc IFPMMFactory
  function sortTokens(address tokenA, address tokenB) public pure returns (address token0, address token1) {
    require(tokenA != tokenB, "FPMMFactory: IDENTICAL_TOKEN_ADDRESSES");
    (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    require(token0 != address(0), "FPMMFactory: ZERO_ADDRESS");
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
  /* ==================== Mutative Functions ==================== */
  /* ============================================================ */

  /// @inheritdoc IFPMMFactory
  function setAdaptore(address _adaptore) public onlyOwner {
    require(_adaptore != address(0), "FPMMFactory: ZERO_ADDRESS");
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    $.adaptore = _adaptore;
    emit AdaptoreSet(_adaptore);
  }

  /// @inheritdoc IFPMMFactory
  function setProxyAdmin(address _proxyAdmin) public onlyOwner {
    require(_proxyAdmin != address(0), "FPMMFactory: ZERO_ADDRESS");
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    $.proxyAdmin = _proxyAdmin;
    emit ProxyAdminSet(_proxyAdmin);
  }

  /// @inheritdoc IFPMMFactory
  function setGovernance(address _governance) public onlyOwner {
    // TODO: Discuss why do we need a seperate governance address if the governance is set as the owner?
    require(_governance != address(0), "FPMMFactory: ZERO_ADDRESS");
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    $.governance = _governance;
    transferOwnership(_governance);
    emit GovernanceSet(_governance);
  }

  /// @inheritdoc IFPMMFactory
  function registerFPMMImplementation(address fpmmImplementation) public onlyOwner {
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    require(fpmmImplementation != address(0), "FPMMFactory: ZERO_ADDRESS");
    require(!$.isRegisteredImplementation[fpmmImplementation], "FPMMFactory: IMPLEMENTATION_ALREADY_REGISTERED");
    $.isRegisteredImplementation[fpmmImplementation] = true;
    $.registeredImplementations.push(fpmmImplementation);
    emit FPMMImplementationRegistered(fpmmImplementation);
  }

  /// @inheritdoc IFPMMFactory
  function unregisterFPMMImplementation(address fpmmImplementation, uint256 index) public onlyOwner {
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    require($.isRegisteredImplementation[fpmmImplementation], "FPMMFactory: IMPLEMENTATION_NOT_REGISTERED");
    require(index < $.registeredImplementations.length, "FPMMFactory: INDEX_OUT_OF_BOUNDS");
    require($.registeredImplementations[index] == fpmmImplementation, "FPMMFactory: IMPLEMENTATION_INDEX_MISMATCH");
    $.isRegisteredImplementation[fpmmImplementation] = false;
    if ($.registeredImplementations.length > 1) {
      $.registeredImplementations[index] = $.registeredImplementations[$.registeredImplementations.length - 1];
    }
    $.registeredImplementations.pop();
    emit FPMMImplementationUnregistered(fpmmImplementation);
  }

  // bool revertRateFeed // TODO: Add this back in
  /// @inheritdoc IFPMMFactory
  function deployFPMM(
    address fpmmImplementation,
    address customAdaptore,
    address customProxyAdmin,
    address customGovernance,
    address token0,
    address token1,
    address referenceRateFeedID
  ) external onlyOwner returns (address) {
    (token0, token1) = sortTokens(token0, token1);

    FPMMFactoryStorage storage $ = _getFPMMStorage();

    require($.isRegisteredImplementation[fpmmImplementation], "FPMMFactory: IMPLEMENTATION_NOT_REGISTERED");
    require(customAdaptore != address(0), "FPMMFactory: ZERO_ADDRESS");
    require(customProxyAdmin != address(0), "FPMMFactory: ZERO_ADDRESS");
    require(customGovernance != address(0), "FPMMFactory: ZERO_ADDRESS");
    require(referenceRateFeedID != address(0), "FPMMFactory: ZERO_ADDRESS");
    require(getPool(token0, token1) == address(0), "FPMMFactory: PAIR_ALREADY_EXISTS");

    address fpmmProxy = _deployFPMMProxy(
      fpmmImplementation,
      customAdaptore,
      customProxyAdmin,
      customGovernance,
      token0,
      token1,
      referenceRateFeedID
    );

    emit FPMMDeployed(token0, token1, fpmmProxy, fpmmImplementation);
    return fpmmProxy;
  }

  // bool revertRateFeed // TODO: Add this back in
  // slither-disable-start reentrancy-no-eth
  /// @inheritdoc IFPMMFactory
  function deployFPMM(
    address fpmmImplementation,
    address token0,
    address token1,
    address referenceRateFeedID
  ) external onlyOwner returns (address) {
    (token0, token1) = sortTokens(token0, token1);

    FPMMFactoryStorage storage $ = _getFPMMStorage();
    require($.isRegisteredImplementation[fpmmImplementation], "FPMMFactory: IMPLEMENTATION_NOT_REGISTERED");

    require(getPool(token0, token1) == address(0), "FPMMFactory: PAIR_ALREADY_EXISTS");
    require(referenceRateFeedID != address(0), "FPMMFactory: ZERO_ADDRESS");

    address fpmmProxy = _deployFPMMProxy(
      fpmmImplementation,
      $.adaptore,
      $.proxyAdmin,
      $.governance,
      token0,
      token1,
      referenceRateFeedID
    );

    emit FPMMDeployed(token0, token1, fpmmProxy, fpmmImplementation);
    return fpmmProxy;
  }
  // slither-disable-end reentrancy-no-eth

  /* =========================================================== */
  /* ==================== Private Functions ==================== */
  /* =========================================================== */

  /**
   * @notice Deploys the FPMM proxy contract.
   * @param _fpmmImplementation The address of the FPMM implementation
   * @param _adaptore The address of the adaptore contract
   * @param _proxyAdmin The address of the proxy admin contract
   * @param _governance The address of the governance contract
   * @param _token0 The address of the first token
   * @param _token1 The address of the second token
   * @param _referenceRateFeedID The address of the reference rate feed
   * @return The address of the deployed FPMM proxy
   */
  // slither-disable-start reentrancy-benign
  // slither-disable-start reentrancy-events
  // slither-disable-start encode-packed-collision
  function _deployFPMMProxy(
    address _fpmmImplementation,
    address _adaptore,
    address _proxyAdmin,
    address _governance,
    address _token0,
    address _token1,
    address _referenceRateFeedID
  ) internal returns (address) {
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    (address expectedProxyAddress, bytes32 salt) = _computeProxyAddressAndSalt(_token0, _token1);
    bytes memory initData = abi.encodeWithSelector(
      IFPMM.initialize.selector,
      _token0,
      _token1,
      _adaptore,
      _referenceRateFeedID,
      false, // revertRateFeed
      _governance
    );
    bytes memory proxyBytecode = abi.encodePacked(
      type(FPMMProxy).creationCode,
      abi.encode(_fpmmImplementation, _proxyAdmin, initData)
    );
    address newProxyAddress = ICreateX(CREATEX).deployCreate3(salt, proxyBytecode);
    $.deployedFPMMs[_token0][_token1] = newProxyAddress;
    $.deployedFPMMs[_token1][_token0] = newProxyAddress; // populate the reverse mapping
    $.isPool[newProxyAddress] = true;
    $.deployedFPMMAddresses.push(newProxyAddress);
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
   * @dev copied from CREATEX contract to precaluclated deployment addresses
   *      see https://github.com/pcaversaccio/createx/blob/7ab1e452b8803cae1467efd455dee1530660373b/src/CreateX.sol#L952
   * @param a The first bytes32 value
   * @param b The second bytes32 value
   * @return hash The keccak256 hash of the two values
   */
  function _efficientHash(bytes32 a, bytes32 b) internal pure returns (bytes32 hash) {
    // Warniing ignored, because this is a helper function and copied from CREATEX contract
    // solhint-disable-next-line no-inline-assembly
    assembly ("memory-safe") {
      mstore(0x00, a)
      mstore(0x20, b)
      hash := keccak256(0x00, 0x40)
    }
  }
}
