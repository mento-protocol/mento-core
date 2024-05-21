// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IGoodDollarExpansionController {
  struct exchangeExpansionConfig {
    uint32 expansionRate;
    uint256 lastExpansion;
  }

  function setDistributionHelper(address distributionHelper) external;

  function setExpansionRate(bytes32 exchangeId, uint256 expansionRate) external;

  function mintUBIFromInterest(bytes32 exchangeId, uint256 collateralAmount) external returns (uint256 amountMinted);

  function mintUBIFromExpansion(bytes32 exchangeId) external returns (uint256 amountMinted);

  function getCurrentExpansionRate(bytes32 exchangeId) external view returns (uint32 expansionRate);

  function shouldExpand(bytes32 exchangeId) external view returns (bool);

  function mintRewardFromRR(
    bytes32 exchangeId,
    address to,
    uint256 amount
  ) external;
}
