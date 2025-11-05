// SPDX-License-Identifier: MIT
// solhint-disable max-line-length, function-max-lines

pragma solidity 0.8.24;

import { TestStorage } from "./TestStorage.sol";
import { IERC20Metadata } from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

abstract contract LiquityHelpers is TestStorage {
  struct TroveSetup {
    uint256 collAmount;
    uint256 debtAmount;
    uint256 lastCollAmount;
    uint256 lastDebtAmount;
  }

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
    uint256 maxNumberOfTroves = _totalDebtAmount / $liquity.systemParams.MIN_DEBT();
    numberOfTroves = numberOfTroves > maxNumberOfTroves ? maxNumberOfTroves : numberOfTroves;

    TroveSetup memory troveSetup = _calculateDebtAndCollAmountPerTrove(_totalDebtAmount, numberOfTroves);

    for (uint256 i = 0; i < numberOfTroves; i++) {
      bool isLastTrove = i == numberOfTroves - 1;
      uint256 debtForThisTrove = isLastTrove ? troveSetup.lastDebtAmount : troveSetup.debtAmount;
      uint256 collAmountForThisTrove = isLastTrove ? troveSetup.lastCollAmount : troveSetup.collAmount;

      vm.startPrank($addresses.governance);
      $tokens.cdpCollToken.mint(_owner, collAmountForThisTrove + $liquity.systemParams.ETH_GAS_COMPENSATION());
      vm.stopPrank();

      _openTrove(_owner, i, collAmountForThisTrove, debtForThisTrove, _startingInterestRate);
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
    $tokens.cdpCollToken.approve(
      address($liquity.borrowerOperations),
      collAmount + $liquity.systemParams.ETH_GAS_COMPENSATION()
    );
    uint256 troveId = $liquity.borrowerOperations.openTrove(
      owner,
      ownerIndex,
      collAmount,
      debtAmount,
      0,
      0,
      interestRate,
      debtAmount,
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
  ) internal returns (TroveSetup memory troveSetup) {
    uint256 debtPerTrove = _totalDebtAmount / numberOfTroves;

    uint256 collAmountPerTrove = _calculateCollateralForTrove(debtPerTrove);

    uint256 debtRemaining = _totalDebtAmount % numberOfTroves;
    uint256 lastTroveDebt = debtPerTrove + debtRemaining;
    uint256 lastTroveColl = _calculateCollateralForTrove(lastTroveDebt);

    return
      TroveSetup({
        collAmount: collAmountPerTrove,
        debtAmount: debtPerTrove,
        lastCollAmount: lastTroveColl,
        lastDebtAmount: lastTroveDebt
      });
  }

  function _calculateCollateralForTrove(uint256 _debtAmount) internal returns (uint256) {
    uint256 collAmount = (_debtAmount * 1e18) / $liquity.priceFeed.fetchPrice();

    collAmount = (collAmount * ($liquity.systemParams.CCR() + 50e16)) / 100e16;
    collAmount = collAmount / 10 ** (18 - IERC20Metadata(address($tokens.cdpCollToken)).decimals());

    return collAmount;
  }

  function _redeemCollateral(uint256 _debtAmount, address _operator) internal {
    vm.startPrank(_operator);
    $collateralRegistry.redeemCollateral(_debtAmount, 10, 1e18);
    vm.stopPrank();
  }
}
