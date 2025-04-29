// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IFPMMCallee {
  function hook(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}
