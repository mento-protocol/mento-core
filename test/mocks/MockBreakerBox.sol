// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.5.13;

import { IBreakerBox } from "contracts/interfaces/IBreakerBox.sol";

contract MockBreakerBox is IBreakerBox {
  uint256 public tradingMode;

  function setTradingMode(uint256 _tradingMode) external {
    tradingMode = _tradingMode;
  }

  function getBreakers() external view returns (address[] memory) {
    return new address[](0);
  }

  function isBreaker(address) external view returns (bool) {
    return true;
  }

  function getRateFeedTradingMode(address) external view returns (uint256) {
    return 0;
  }

  function checkAndSetBreakers(address) external {}
}
