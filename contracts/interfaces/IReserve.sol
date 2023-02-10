// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.5.13;

interface IReserve {
  function setTobinTaxStalenessThreshold(uint256) external;

  function addToken(address) external returns (bool);

  function removeToken(address, uint256) external returns (bool);

  function transferGold(address payable, uint256) external returns (bool);

  function transferExchangeGold(address payable, uint256) external returns (bool);

  function transferCollateralAsset(
    address collateralAsset,
    address payable to,
    uint256 value
  ) external returns (bool);

  function getReserveGoldBalance() external view returns (uint256);

  function getUnfrozenReserveGoldBalance() external view returns (uint256);

  function getOrComputeTobinTax() external returns (uint256, uint256);

  function getTokens() external view returns (address[] memory);

  function getReserveRatio() external view returns (uint256);

  function addExchangeSpender(address) external;

  function removeExchangeSpender(address, uint256) external;

  function addSpender(address) external;

  function removeSpender(address) external;

  function isStableAsset(address) external view returns (bool);

  function isCollateralAsset(address) external view returns (bool);

  function getDailySpendingRatioForCollateralAsset(address collateralAsset) external view returns (uint256);

  function isExchangeSpender(address exchange) external view returns (bool);

  function addCollateralAsset(address asset) external returns (bool);

  function transferExchangeCollateralAsset(
    address collateralAsset,
    address payable to,
    uint256 value
  ) external returns (bool);
}
