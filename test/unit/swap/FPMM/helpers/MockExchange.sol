// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
pragma solidity ^0.8;

import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
contract MockExchange {
  address public token0;
  address public token1;
  uint256 public exchangeRate; // token1 per token0, multiplied by 1e18

  constructor(address _token0, address _token1, uint256 _exchangeRate) {
    token0 = _token0;
    token1 = _token1;
    exchangeRate = _exchangeRate;
  }

  function setExchangeRate(uint256 _exchangeRate) external {
    exchangeRate = _exchangeRate;
  }

  function swapToken0ForToken1(uint256 amount0) external returns (uint256) {
    uint256 amount1 = (amount0 * exchangeRate) / 1e18;

    IERC20(token0).transferFrom(msg.sender, address(this), amount0);
    IERC20(token1).transfer(msg.sender, amount1);

    return amount1;
  }

  function swapToken1ForToken0(uint256 amount1) external returns (uint256) {
    uint256 amount0 = (amount1 * 1e18) / exchangeRate;

    IERC20(token1).transferFrom(msg.sender, address(this), amount1);
    IERC20(token0).transfer(msg.sender, amount0);

    return amount0;
  }
}
