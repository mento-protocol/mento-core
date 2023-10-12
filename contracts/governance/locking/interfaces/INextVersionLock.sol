// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "../libs/LibBrokenLine.sol";

interface INextVersionLock {
  function initiateData(
    uint256 idLock,
    LibBrokenLine.Line memory line,
    address locker,
    address delegate
  ) external;
}
