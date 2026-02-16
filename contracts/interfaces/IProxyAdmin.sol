// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.13 <0.9;

interface IProxyAdmin {
  function getProxyImplementation(address proxy) external view returns (address);
  function getProxyAdmin(address proxy) external view returns (address);

  function transferOwnership(address newOwner) external;
}
