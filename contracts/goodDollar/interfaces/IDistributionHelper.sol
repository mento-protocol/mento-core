// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.5.17 <0.8.19;
pragma experimental ABIEncoderV2;

interface IDistributionHelper {
  function onDistribution(uint256 _amount) external;
}
