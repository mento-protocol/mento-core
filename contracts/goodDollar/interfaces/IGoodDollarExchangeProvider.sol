// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IGoodDollarExchangeProvider {
  function calculateExpansion(bytes32 exchangeId, uint256 expansionRate) external returns (uint256);

  function calculateInterest(bytes32 exchangeId, uint256 reserveInterest) external returns (uint256);

  function calculateRatioForReward(bytes32 exchangeId, uint256 reward) external;

  function currentPriceUSD(bytes32 exchangeId) external returns (uint256);

  function pause() external;

  function unpause() external;
}
