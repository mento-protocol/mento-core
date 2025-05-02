// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

// TODO: To be removed once FPMM interface is done
interface IFPMM {
  function token0() external view returns (address);

  function token1() external view returns (address);

  function decimals0() external view returns (uint256);

  function decimals1() external view returns (uint256);

  function protocolFee() external view returns (uint256);

  function metadata()
    external
    view
    returns (uint256 dec0, uint256 dec1, uint256 r0, uint256 r1, address t0, address t1);

  // TODO: Funtions below should be added to the interface.
  function stableToken() external view returns (address);

  function collateralToken() external view returns (address);

  function stableReserve() external view returns (uint256);

  function collateralReserve() external view returns (uint256);

  function getPrices() external view returns (uint256 oraclePrice, uint256 poolPrice);

  function moveTokensOut(address token, uint256 amount, address to, bytes calldata callback) external;
}
