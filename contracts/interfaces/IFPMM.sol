// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

// TODO: To be removed once FPMM interface is done
interface IFPMM {
  function token0() external view returns (address);

  function token1() external view returns (address);

  function reserve0() external view returns (uint256);

  function reserve1() external view returns (uint256);

  function decimals0() external view returns (uint256);

  function decimals1() external view returns (uint256);

  function protocolFee() external view returns (uint256);

  function metadata()
    external
    view
    returns (uint256 dec0, uint256 dec1, uint256 r0, uint256 r1, address t0, address t1);

  // TODO: To be added to the FPMM contract.
  function getPrices() external view returns (uint256 oraclePrice, uint256 poolPrice);

  function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}
