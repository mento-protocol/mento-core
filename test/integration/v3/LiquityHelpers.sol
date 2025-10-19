// SPDX-License-Identifier: MIT
// solhint-disable max-line-length, function-max-lines

pragma solidity 0.8.24;

import { TestStorage } from "./TestStorage.sol";
import { IERC20Metadata } from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

abstract contract LiquityHelpers is TestStorage {
  function _openTrove(address owner, uint256 collAmount, uint256 debtAmount) internal {
    vm.startPrank(owner);
    $tokens.cdpCollToken.approve(address($liquity.borrowerOperations), collAmount);
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

  function _openDemoTroves(
    uint256 _totalDebtAmount,
    uint256 _startingInterestRate,
    uint256 _interestRateSteps,
    address _owner,
    uint256 numberOfTroves
  ) public {
    (uint256 debtPerTrove, uint256 collAmountPerTrove) = _calculateDebtAndCollAmountPerTrove(
      _totalDebtAmount,
      numberOfTroves
    );
    uint256 collAmountPerTroveWithGasCompensation = collAmountPerTrove + $liquity.systemParams.ETH_GAS_COMPENSATION();

    vm.startPrank($addresses.governance);
    $tokens.cdpCollToken.mint(_owner, collAmountPerTroveWithGasCompensation * numberOfTroves);
    vm.stopPrank();

    for (uint256 i = 0; i < numberOfTroves; i++) {
      vm.startPrank(_owner);
      $tokens.cdpCollToken.approve(address($liquity.borrowerOperations), collAmountPerTroveWithGasCompensation);
      uint256 troveId = _openTrove(_owner, i, collAmountPerTrove, debtPerTrove, _startingInterestRate);
      vm.stopPrank();
      _startingInterestRate += _interestRateSteps;
    }
  }

  function _openTrove(
    address owner,
    uint256 ownerIndex,
    uint256 collAmount,
    uint256 debtAmount,
    uint256 interestRate
  ) private returns (uint256) {
    vm.startPrank(owner);
    uint256 troveId = $liquity.borrowerOperations.openTrove(
      owner,
      ownerIndex,
      collAmount,
      debtAmount,
      0,
      0,
      interestRate,
      1000e18,
      address(0),
      address(0),
      address(0)
    );
    vm.stopPrank();
    return troveId;
  }

  function _calculateDebtAndCollAmountPerTrove(
    uint256 _totalDebtAmount,
    uint256 numberOfTroves
  ) internal returns (uint256 debtPerTrove, uint256 collAmountPerTrove) {
    debtPerTrove = _totalDebtAmount / numberOfTroves;
    uint256 collAmountPerTrove = (debtPerTrove * 1e18) / $liquity.priceFeed.fetchPrice();
    collAmountPerTrove = (collAmountPerTrove * ($liquity.systemParams.CCR() + 50e16)) / 100e16;
    collAmountPerTrove = collAmountPerTrove / 10 ** (18 - IERC20Metadata(address($tokens.cdpCollToken)).decimals());
    return (debtPerTrove, collAmountPerTrove);
  }
}
