// SPDX-License-Identifier: MIT
// solhint-disable max-line-length, function-max-lines

pragma solidity 0.8.24;

import { TestStorage } from "./TestStorage.sol";

abstract contract LiquityHelpers is TestStorage {
  function _openTrove(address owner, uint256 collAmount, uint256 debtAmount) internal {
    vm.startPrank(owner);
    $tokens.collateralToken.approve(address($liquity.borrowerOperations), collAmount);
    $liquity.borrowerOperations.openTrove(
      owner,
      0,
      collAmount,
      debtAmount,
      0,
      0,
      $liquity.systemParams.MIN_ANNUAL_INTEREST_RATE(),
      1000e18,
      address(0),
      address(0),
      address(0)
    );
    vm.stopPrank();
  }
}
