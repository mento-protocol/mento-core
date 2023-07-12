// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.13 <0.8.19;

interface IFreezer {
  function isFrozen(address) external view returns (bool);
}
