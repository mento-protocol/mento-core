// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts-v4.9.5/contracts/token/ERC20/IERC20.sol";

interface IExchangeHelpers {
  function getCollFromBold(
    uint256 _boldAmount,
    IERC20 _collToken,
    uint256 _desiredCollAmount /* view */
  ) external returns (uint256, uint256);
}
