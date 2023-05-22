// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.17 <0.9;

interface IProxy {
  function _getImplementation() external view returns (address);
  function _getOwner() external view returns (address);
  function _setImplementation(address implementation) external;
  function _setOwner(address owner) external;
  function _transferOwnership(address newOwner) external;
}
