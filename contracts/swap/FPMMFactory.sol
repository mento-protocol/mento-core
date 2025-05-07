// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { TransparentUpgradeableProxy } from "openzeppelin-contracts-next/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { ICreateX } from "../interfaces/ICreateX.sol";

import { IFPMMFactory } from "../interfaces/IFPMMFactory.sol";
import { FPMM } from "./FPMM.sol";
import { FPMMProxy } from "./FPMMProxy.sol";
import { console } from "forge-std/console.sol";

contract FPMMFactory is IFPMMFactory, OwnableUpgradeable {
  address public sortedOracles;

  address public fpmmImplementation;

  address public proxyAdmin;

  mapping(address => mapping(address => FPMM)) public deployedFPMMs;

  address public constant CREATEX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
  bytes32 public constant CREATEX_BYTECODE_HASH = 0xbd8a7ea8cfca7b4e5f5041d7d4b17bc317c5ce42cfbc42066a00cf26b43eb53f;

  // Events
  event FPMMDeployed(address indexed token0, address indexed token1, address fpmm);
  event FPMMImplementationDeployed(address indexed implementation);
  event ProxyAdminSet(address indexed proxyAdmin);
  event SortedOraclesSet(address indexed sortedOracles);

  constructor(bool disable) {
    if (disable) {
      _disableInitializers();
    }
    require(keccak256(CREATEX.code) == CREATEX_BYTECODE_HASH, "FPMMFactory: CREATEX_BYTECODE_HASH_MISMATCH");
  }

  function initialize(address _sortedOracles, address _proxyAdmin) external initializer {
    require(_sortedOracles != address(0), "FPMMFactory: ZERO_ADDRESS");
    require(_proxyAdmin != address(0), "FPMMFactory: ZERO_ADDRESS");
    __Ownable_init();
    sortedOracles = _sortedOracles;
    emit SortedOraclesSet(_sortedOracles);
    proxyAdmin = _proxyAdmin;
    emit ProxyAdminSet(_proxyAdmin);
  }

  function setSortedOracles(address _sortedOracles) external onlyOwner {
    require(_sortedOracles != address(0), "FPMMFactory: ZERO_ADDRESS");
    sortedOracles = _sortedOracles;
    emit SortedOraclesSet(_sortedOracles);
  }

  function setProxyAdmin(address _proxyAdmin) external onlyOwner {
    require(_proxyAdmin != address(0), "FPMMFactory: ZERO_ADDRESS");

    proxyAdmin = _proxyAdmin;
    emit ProxyAdminSet(_proxyAdmin);
  }

  function deployFPMM(address token0, address token1) external returns (address, address) {
    require(token0 != address(0) && token1 != address(0), "FPMMFactory: ZERO_ADDRESS");
    require(token0 != token1, "FPMMFactory: IDENTICAL_TOKEN_ADDRESSES");

    if (fpmmImplementation == address(0)) {
      _deployFPMMImplementation();
    }
    address fpmmProxy = _deployFPMMProxy(token0, token1, sortedOracles);

    return (fpmmImplementation, fpmmProxy);
  }

  function _deployFPMMImplementation() internal {
    console.log("msg.sender", msg.sender);
    bytes memory implementationBytecode = type(FPMM).creationCode;
    bytes32 salt = bytes32(abi.encodePacked(address(msg.sender), hex"00", bytes11(uint88(361))));

    address expectedFPMMImplementation = ICreateX(CREATEX).computeCreate3Address(salt);
    console.log("expectedFPMMImplementation", expectedFPMMImplementation);

    fpmmImplementation = ICreateX(CREATEX).deployCreate3(salt, implementationBytecode);
    console.log("fpmmImplementation", fpmmImplementation);
    emit FPMMImplementationDeployed(fpmmImplementation);
  }

  function _deployFPMMProxy(address token0, address token1, address sortedOracles) internal returns (address) {
    bytes memory initData = abi.encodeWithSelector(FPMM.initialize.selector, token0, token1, sortedOracles);
    bytes memory proxyBytecode = abi.encodePacked(
      type(FPMMProxy).creationCode,
      abi.encode(fpmmImplementation, proxyAdmin, initData)
    );
    address newProxyAddress = ICreateX(CREATEX).deployCreate3(
      keccak256(abi.encodePacked(token0, token1)),
      proxyBytecode
    );
    deployedFPMMs[token0][token1] = FPMM(newProxyAddress);
    emit FPMMDeployed(token0, token1, newProxyAddress);
    return newProxyAddress;
  }
}
