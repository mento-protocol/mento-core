// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

library LibIntMapping {
  function addToItem(
    mapping(uint256 => int96) storage map,
    uint256 key,
    int96 value
  ) internal {
    map[key] = map[key] + (value);
  }

  function subFromItem(
    mapping(uint256 => int96) storage map,
    uint256 key,
    int96 value
  ) internal {
    map[key] = map[key] - (value);
  }
}
