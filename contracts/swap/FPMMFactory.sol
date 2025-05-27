// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

import { ICreateX } from "../interfaces/ICreateX.sol";

import { IFPMMFactory } from "../interfaces/IFPMMFactory.sol";
import { FPMM } from "./FPMM.sol";
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
    // Address of the sorted oracles contract.
    address sortedOracles;
    // Address of the proxy admin contract.
    address proxyAdmin;
    // Address of the breaker box contract.
    address breakerBox;
    // Address of the governance contract.
    address governance;
    // Address of the implementation of the FPMM contract.
    address fpmmImplementation;
    // Mapping of deployed FPMMs.
    mapping(address => mapping(address => address)) deployedFPMMs;
    // List of deployed FPMM addresses.
    address[] deployedFPMMAddresses;
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
    address _sortedOracles,
    address _proxyAdmin,
    address _breakerBox,
    address _governance
  ) external initializer {
    __Ownable_init();
    setProxyAdmin(_proxyAdmin);
    setSortedOracles(_sortedOracles);
    setBreakerBox(_breakerBox);
    setGovernance(_governance);
  }

  /* ======================================================== */
  /* ==================== View Functions ==================== */
  /* ======================================================== */

  /// @inheritdoc IFPMMFactory
  function sortedOracles() public view returns (address) {
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    return $.sortedOracles;
  }

  /// @inheritdoc IFPMMFactory
  function proxyAdmin() public view returns (address) {
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    return $.proxyAdmin;
  }

  /// @inheritdoc IFPMMFactory
  function breakerBox() public view returns (address) {
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    return $.breakerBox;
  }

  /// @inheritdoc IFPMMFactory
  function governance() public view returns (address) {
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    return $.governance;
  }

  /// @inheritdoc IFPMMFactory
  function fpmmImplementation() public view returns (address) {
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    return $.fpmmImplementation;
  }

  /// @inheritdoc IFPMMFactory
  function deployedFPMMs(address token0, address token1) public view returns (address) {
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    return $.deployedFPMMs[token0][token1];
  }

  /// @inheritdoc IFPMMFactory
  function deployedFPMMAddresses() public view returns (address[] memory) {
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    return $.deployedFPMMAddresses;
  }

  /// @inheritdoc IFPMMFactory
  function getOrPrecomputeImplementationAddress() public view returns (address) {
    FPMMFactoryStorage storage $ = _getFPMMStorage();

    if ($.fpmmImplementation != address(0)) {
      return $.fpmmImplementation;
    }

    (address precomputedImplementation, ) = _computeImplementationAddressAndSalt();
    return precomputedImplementation;
  }

  // slither-disable-start encode-packed-collision
  /// @inheritdoc IFPMMFactory
  function getOrPrecomputeProxyAddress(address token0, address token1) public view returns (address) {
    FPMMFactoryStorage storage $ = _getFPMMStorage();

    if ($.deployedFPMMs[token0][token1] != address(0)) {
      return $.deployedFPMMs[token0][token1];
    }

    (address precomputedProxyAddress, ) = _computeProxyAddressAndSalt(token0, token1);
    return precomputedProxyAddress;
  }
  // slither-disable-end encode-packed-collision

  /* ============================================================ */
  /* ==================== Mutative Functions ==================== */
  /* ============================================================ */

  /// @inheritdoc IFPMMFactory
  function setSortedOracles(address _sortedOracles) public onlyOwner {
    require(_sortedOracles != address(0), "FPMMFactory: ZERO_ADDRESS");
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    $.sortedOracles = _sortedOracles;
    emit SortedOraclesSet(_sortedOracles);
  }

  /// @inheritdoc IFPMMFactory
  function setProxyAdmin(address _proxyAdmin) public onlyOwner {
    require(_proxyAdmin != address(0), "FPMMFactory: ZERO_ADDRESS");
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    $.proxyAdmin = _proxyAdmin;
    emit ProxyAdminSet(_proxyAdmin);
  }

  /// @inheritdoc IFPMMFactory
  function setBreakerBox(address _breakerBox) public onlyOwner {
    require(_breakerBox != address(0), "FPMMFactory: ZERO_ADDRESS");
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    $.breakerBox = _breakerBox;
    emit BreakerBoxSet(_breakerBox);
  }

  /// @inheritdoc IFPMMFactory
  function setGovernance(address _governance) public onlyOwner {
    require(_governance != address(0), "FPMMFactory: ZERO_ADDRESS");
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    $.governance = _governance;
    transferOwnership(_governance);
    emit GovernanceSet(_governance);
  }

  // slither-disable-start reentrancy-no-eth
  /// @inheritdoc IFPMMFactory
  function deployFPMM(
    address token0,
    address token1,
    address referenceRateFeedID
  ) external onlyOwner returns (address, address) {
    FPMMFactoryStorage storage $ = _getFPMMStorage();
    require(token0 != address(0) && token1 != address(0), "FPMMFactory: ZERO_ADDRESS");
    require(token0 != token1, "FPMMFactory: IDENTICAL_TOKEN_ADDRESSES");
    require($.deployedFPMMs[token0][token1] == address(0), "FPMMFactory: PAIR_ALREADY_EXISTS");
    require(referenceRateFeedID != address(0), "FPMMFactory: ZERO_ADDRESS");

    if ($.fpmmImplementation == address(0)) {
      _deployFPMMImplementation($);
    }
    address fpmmProxy = _deployFPMMProxy($, token0, token1, referenceRateFeedID);

    return ($.fpmmImplementation, fpmmProxy);
  }
  // slither-disable-end reentrancy-no-eth

  /* =========================================================== */
  /* ==================== Private Functions ==================== */
  /* =========================================================== */

  /**
   * @notice Deploys the FPMM implementation contract if it is not already deployed.
   */
  // slither-disable-start reentrancy-events
  function _deployFPMMImplementation(FPMMFactoryStorage storage $) internal {
    bytes memory implementationBytecode = abi.encodePacked(type(FPMM).creationCode, abi.encode(true));

    (address expectedFPMMImplementation, bytes32 salt) = _computeImplementationAddressAndSalt();

    $.fpmmImplementation = ICreateX(CREATEX).deployCreate3(salt, implementationBytecode);
    assert($.fpmmImplementation == expectedFPMMImplementation);
    emit FPMMImplementationDeployed($.fpmmImplementation);
  }
  // slither-disable-end reentrancy-events

  /**
   * @notice Deploys the FPMM proxy contract.
   * @param token0 The address of the first token
   * @param token1 The address of the second token
   * @param referenceRateFeedID The address of the reference rate feed
   * @return The address of the deployed FPMM proxy
   */
  // slither-disable-start reentrancy-benign
  // slither-disable-start reentrancy-events
  // slither-disable-start encode-packed-collision
  function _deployFPMMProxy(
    FPMMFactoryStorage storage $,
    address token0,
    address token1,
    address referenceRateFeedID
  ) internal returns (address) {
    (address expectedProxyAddress, bytes32 salt) = _computeProxyAddressAndSalt(token0, token1);

    bytes memory initData = abi.encodeWithSelector(
      FPMM.initialize.selector,
      token0,
      token1,
      $.sortedOracles,
      referenceRateFeedID,
      $.breakerBox,
      $.governance
    );
    bytes memory proxyBytecode = abi.encodePacked(
      type(FPMMProxy).creationCode,
      abi.encode($.fpmmImplementation, $.proxyAdmin, initData)
    );

    address newProxyAddress = ICreateX(CREATEX).deployCreate3(salt, proxyBytecode);
    $.deployedFPMMs[token0][token1] = newProxyAddress;
    $.deployedFPMMAddresses.push(newProxyAddress);
    emit FPMMDeployed(token0, token1, newProxyAddress);
    assert(newProxyAddress == expectedProxyAddress);
    return newProxyAddress;
  }
  // slither-disable-end reentrancy-benign
  // slither-disable-end reentrancy-events
  // slither-disable-end encode-packed-collision

  /**
   * @notice Computes the address of the FPMM implementation contract.
   * @dev apply permissioned deploy protection with factory address and 0x00 flag
   *      see https://github.com/pcaversaccio/createx?tab=readme-ov-file for more details
   * @return The precomputed address of the FPMM implementation contract
   * @return The salt used to deploy the FPMM implementation contract
   */
  function _computeImplementationAddressAndSalt() internal view returns (address, bytes32) {
    bytes32 salt = bytes32(abi.encodePacked(address(this), hex"00", bytes11("FPMM_IMPLEM")));
    bytes32 guardedSalt = _efficientHash({ a: bytes32(uint256(uint160(address(this)))), b: salt });

    return (ICreateX(CREATEX).computeCreate3Address(guardedSalt), salt);
  }

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
