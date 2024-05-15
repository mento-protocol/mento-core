// SPDX-License-Identifier: MIT
import "./IBancorExchangeProvider.sol";

pragma solidity 0.8.18;

interface IGoodDollarExchangeProvider is IBancorExchangeProvider {
  struct ReserveParams {
    uint32 exitContribution; // in bps
    uint256 expansionRate;
    uint256 lastExpansion;
  }

  function updateMintExpansion(uint256 expansionRate) external returns (uint256);

  function updateMintInterest(uint256 reserveInterest) external returns (uint256);

  function updateMintReward(uint256 reward) external;

  function currentPriceUSD() external returns (uint256);

  function pause(bool _paused) external;
}
