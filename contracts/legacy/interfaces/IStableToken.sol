// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.17 <0.8.19;

/**
 * @title This interface describes the functions specific to Celo Stable Tokens, and in the
 * absence of interface inheritance is intended as a companion to IERC20.sol and ICeloToken.sol.
 */
interface IStableToken {
  function initialize(
    string calldata,
    string calldata,
    uint8,
    address,
    uint256,
    uint256,
    address[] calldata,
    uint256[] calldata,
    string calldata
  ) external;

  function mint(address, uint256) external returns (bool);

  function burn(uint256) external returns (bool);

  function setInflationParameters(uint256, uint256) external;

  function valueToUnits(uint256) external view returns (uint256);

  function unitsToValue(uint256) external view returns (uint256);

  function getInflationParameters()
    external
    view
    returns (
      uint256,
      uint256,
      uint256,
      uint256
    );

  function getExchangeRegistryId() external view returns (bytes32);

  // NOTE: duplicated with IERC20.sol, remove once interface inheritance is supported.
  function balanceOf(address) external view returns (uint256);

  function debitGasFees(address, uint256) external;

  function creditGasFees(
    address,
    address,
    address,
    address,
    uint256,
    uint256,
    uint256,
    uint256
  ) external;
}
