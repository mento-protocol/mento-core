// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;
// solhint-disable no-unused-vars

import { MockERC20 } from "./MockERC20.sol";

contract MockCollateralRegistry {
  MockERC20 public debtToken;
  MockERC20 public collateralToken;

  uint256 public oracleNumerator;
  uint256 public oracleDenominator;

  /// @notice Amount of collateral to withhold from redemption (simulates rounding loss)
  uint256 public redemptionShortfall;

  constructor(address _debtToken, address _collateralToken) {
    debtToken = MockERC20(_debtToken);
    collateralToken = MockERC20(_collateralToken);
  }

  function setOracleRate(uint256 _oracleNumerator, uint256 _oracleDenominator) external {
    oracleNumerator = _oracleNumerator;
    oracleDenominator = _oracleDenominator;
  }

  /// @notice Set the redemption shortfall to simulate rounding loss
  function setRedemptionShortfall(uint256 _shortfall) external {
    redemptionShortfall = _shortfall;
  }

  function redeemCollateralRebalancing(
    uint256 _boldamount,
    uint256 _maxIterationsPerCollateral,
    uint256 _troveOwnerFee
  ) external {
    uint256 liquiditySourceIncentiveContraction = (_boldamount * _troveOwnerFee) / 1e18;

    MockERC20(debtToken).transferFromWithoutAllowance(msg.sender, address(this), liquiditySourceIncentiveContraction);
    MockERC20(debtToken).burn(msg.sender, _boldamount - liquiditySourceIncentiveContraction);

    uint256 debtDecimals = 10 ** MockERC20(debtToken).decimals();
    uint256 collateralDecimals = 10 ** MockERC20(collateralToken).decimals();

    uint256 returnNumerator = _boldamount * oracleNumerator * collateralDecimals * (1e18 - _troveOwnerFee);
    uint256 returnDenominator = oracleDenominator * debtDecimals * 1e18;
    uint256 returnAmount = returnNumerator / returnDenominator;

    // Apply shortfall to simulate rounding loss
    if (redemptionShortfall > 0 && returnAmount > redemptionShortfall) {
      returnAmount -= redemptionShortfall;
    }

    MockERC20(collateralToken).mint(msg.sender, returnAmount);
  }
}
