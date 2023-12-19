// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.17;

library Arrays {
  function uints(uint256 e0) internal pure returns (uint256[] memory arr) {
    arr = new uint256[](1);
    arr[0] = e0;
    return arr;
  }

  function uints(uint256 e0, uint256 e1) internal pure returns (uint256[] memory arr) {
    arr = new uint256[](2);
    arr[0] = e0;
    arr[1] = e1;
    return arr;
  }

  function uints(
    uint256 e0,
    uint256 e1,
    uint256 e2
  ) internal pure returns (uint256[] memory arr) {
    arr = new uint256[](3);
    arr[0] = e0;
    arr[1] = e1;
    arr[2] = e2;
    return arr;
  }

  function uints(
    uint256 e0,
    uint256 e1,
    uint256 e2,
    uint256 e3
  ) internal pure returns (uint256[] memory arr) {
    arr = new uint256[](4);
    arr[0] = e0;
    arr[1] = e1;
    arr[2] = e2;
    arr[3] = e3;
    return arr;
  }

  function uints(
    uint256 e0,
    uint256 e1,
    uint256 e2,
    uint256 e3,
    uint256 e4
  ) internal pure returns (uint256[] memory arr) {
    arr = new uint256[](5);
    arr[0] = e0;
    arr[1] = e1;
    arr[2] = e2;
    arr[3] = e3;
    arr[4] = e4;
    return arr;
  }

  function uints(
    uint256 e0,
    uint256 e1,
    uint256 e2,
    uint256 e3,
    uint256 e4,
    uint256 e5
  ) internal pure returns (uint256[] memory arr) {
    arr = new uint256[](6);
    arr[0] = e0;
    arr[1] = e1;
    arr[2] = e2;
    arr[3] = e3;
    arr[4] = e4;
    arr[5] = e5;
    return arr;
  }

  function uints(
    uint256 e0,
    uint256 e1,
    uint256 e2,
    uint256 e3,
    uint256 e4,
    uint256 e5,
    uint256 e6
  ) internal pure returns (uint256[] memory arr) {
    arr = new uint256[](7);
    arr[0] = e0;
    arr[1] = e1;
    arr[2] = e2;
    arr[3] = e3;
    arr[4] = e4;
    arr[5] = e5;
    arr[6] = e6;
    return arr;
  }

  function addresses(address e0) internal pure returns (address[] memory arr) {
    arr = new address[](1);
    arr[0] = e0;
    return arr;
  }

  function addresses(address e0, address e1) internal pure returns (address[] memory arr) {
    arr = new address[](2);
    arr[0] = e0;
    arr[1] = e1;
    return arr;
  }

  function addresses(
    address e0,
    address e1,
    address e2
  ) internal pure returns (address[] memory arr) {
    arr = new address[](3);
    arr[0] = e0;
    arr[1] = e1;
    arr[2] = e2;
    return arr;
  }

  function addresses(
    address e0,
    address e1,
    address e2,
    address e3
  ) internal pure returns (address[] memory arr) {
    arr = new address[](4);
    arr[0] = e0;
    arr[1] = e1;
    arr[2] = e2;
    arr[3] = e3;
    return arr;
  }

  function addresses(
    address e0,
    address e1,
    address e2,
    address e3,
    address e4
  ) internal pure returns (address[] memory arr) {
    arr = new address[](5);
    arr[0] = e0;
    arr[1] = e1;
    arr[2] = e2;
    arr[3] = e3;
    arr[4] = e4;
    return arr;
  }

  function addresses(
    address e0,
    address e1,
    address e2,
    address e3,
    address e4,
    address e5,
    address e6
  ) internal pure returns (address[] memory arr) {
    arr = new address[](7);
    arr[0] = e0;
    arr[1] = e1;
    arr[2] = e2;
    arr[3] = e3;
    arr[4] = e4;
    arr[5] = e5;
    arr[6] = e6;
    return arr;
  }

  function bytes32s(bytes32 e0) internal pure returns (bytes32[] memory arr) {
    arr = new bytes32[](1);
    arr[0] = e0;
    return arr;
  }

  function bytes32s(bytes32 e0, bytes32 e1) internal pure returns (bytes32[] memory arr) {
    arr = new bytes32[](2);
    arr[0] = e0;
    arr[1] = e1;
    return arr;
  }

  function bytes32s(
    bytes32 e0,
    bytes32 e1,
    bytes32 e2
  ) internal pure returns (bytes32[] memory arr) {
    arr = new bytes32[](3);
    arr[0] = e0;
    arr[1] = e1;
    arr[2] = e2;
    return arr;
  }

  function bytes32s(
    bytes32 e0,
    bytes32 e1,
    bytes32 e2,
    bytes32 e3
  ) internal pure returns (bytes32[] memory arr) {
    arr = new bytes32[](4);
    arr[0] = e0;
    arr[1] = e1;
    arr[2] = e2;
    arr[3] = e3;
    return arr;
  }

  function bytes32s(
    bytes32 e0,
    bytes32 e1,
    bytes32 e2,
    bytes32 e3,
    bytes32 e4
  ) internal pure returns (bytes32[] memory arr) {
    arr = new bytes32[](5);
    arr[0] = e0;
    arr[1] = e1;
    arr[2] = e2;
    arr[3] = e3;
    arr[4] = e4;
    return arr;
  }

  function bytess(bytes memory e0) internal pure returns (bytes[] memory arr) {
    arr = new bytes[](1);
    arr[0] = e0;
    return arr;
  }

  function bytess(bytes memory e0, bytes memory e1) internal pure returns (bytes[] memory arr) {
    arr = new bytes[](2);
    arr[0] = e0;
    arr[1] = e1;
    return arr;
  }

  function bytess(
    bytes memory e0,
    bytes memory e1,
    bytes memory e2
  ) internal pure returns (bytes[] memory arr) {
    arr = new bytes[](3);
    arr[0] = e0;
    arr[1] = e1;
    arr[2] = e2;
    return arr;
  }

  function bytess(
    bytes memory e0,
    bytes memory e1,
    bytes memory e2,
    bytes memory e3
  ) internal pure returns (bytes[] memory arr) {
    arr = new bytes[](4);
    arr[0] = e0;
    arr[1] = e1;
    arr[2] = e2;
    arr[3] = e3;
    return arr;
  }

  function bytess(
    bytes memory e0,
    bytes memory e1,
    bytes memory e2,
    bytes memory e3,
    bytes memory e4
  ) internal pure returns (bytes[] memory arr) {
    arr = new bytes[](5);
    arr[0] = e0;
    arr[1] = e1;
    arr[2] = e2;
    arr[3] = e3;
    arr[4] = e4;
    return arr;
  }

  function bytess(
    bytes memory e0,
    bytes memory e1,
    bytes memory e2,
    bytes memory e3,
    bytes memory e4,
    bytes memory e5
  ) internal pure returns (bytes[] memory arr) {
    arr = new bytes[](6);
    arr[0] = e0;
    arr[1] = e1;
    arr[2] = e2;
    arr[3] = e3;
    arr[4] = e4;
    arr[5] = e5;
    return arr;
  }

  function bytess(
    bytes memory e0,
    bytes memory e1,
    bytes memory e2,
    bytes memory e3,
    bytes memory e4,
    bytes memory e5,
    bytes memory e6
  ) internal pure returns (bytes[] memory arr) {
    arr = new bytes[](7);
    arr[0] = e0;
    arr[1] = e1;
    arr[2] = e2;
    arr[3] = e3;
    arr[4] = e4;
    arr[5] = e5;
    arr[6] = e6;
    return arr;
  }
}
