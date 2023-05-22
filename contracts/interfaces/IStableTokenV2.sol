// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.17 <0.9;

interface IStableTokenV2 {
  function totalSupply() external view returns (uint256);
  function balanceOf(address account) external view returns (uint256);
  function transfer(address recipient, uint256 amount) external returns (bool);
  function allowance(address owner, address spender) external view returns (uint256);
  function approve(address spender, uint256 amount) external returns (bool);
  function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
  function mint(address, uint256) external returns (bool);
  function burn(uint256) external returns (bool);

  function permit(
    address owner,
    address spender,
    uint256 value,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external;

  function transferWithComment(
    address to,
    uint256 value,
    string calldata comment
  ) external returns (bool);

  function initialize(
    string calldata _name,
    string calldata _symbol,
    uint8, // deprecated: decimals
    address, // deprecated: registryAddress,
    uint256, // deprecated: inflationRate,
    uint256, // deprecated:  inflationFactorUpdatePeriod,
    address[] calldata initialBalanceAddresses,
    uint256[] calldata initialBalanceValues,
    string calldata // deprecated: exchangeIdentifier
  ) external;

  function initializeV2(
    address _broker,
    address _validators,
    address _exchange
  ) external;

  function broker() external returns (address);
}
