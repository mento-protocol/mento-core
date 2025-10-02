// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;
// solhint-disable no-unused-vars

import { MockERC20 } from "./MockERC20.sol";

contract MockCollateralRegistry {
  MockERC20 public debtToken;
  MockERC20 public collateralToken;
  uint256 public redemptionRateWithDecay;
  uint256 public oracleNumerator;
  uint256 public oracleDenominator;

  constructor(address _debtToken, address _collateralToken) {
    debtToken = MockERC20(_debtToken);
    collateralToken = MockERC20(_collateralToken);
  }

  function setRedemptionRateWithDecay(uint256 _redemptionRateWithDecay) external {
    redemptionRateWithDecay = _redemptionRateWithDecay;
  }

  function setOracleRate(uint256 _oracleNumerator, uint256 _oracleDenominator) external {
    oracleNumerator = _oracleNumerator;
    oracleDenominator = _oracleDenominator;
  }

  function getRedemptionRateWithDecay() external view returns (uint256) {
    return redemptionRateWithDecay;
  }

  function redeemCollateral(uint256 _boldamount, uint256 _maxIterations, uint256 _maxFeePercentage) external {
    MockERC20(debtToken).burn(msg.sender, _boldamount);
    uint256 debtDecimals = 10 ** MockERC20(debtToken).decimals();
    uint256 collateralDecimals = 10 ** MockERC20(collateralToken).decimals();

    uint256 totalSupply = MockERC20(debtToken).totalSupply();
    uint256 redemptionFee = redemptionRateWithDecay + ((_boldamount * 1e18) / totalSupply);

    uint256 returnNumerator = _boldamount * oracleNumerator * collateralDecimals * (1e18 - redemptionFee);
    uint256 returnDenominator = oracleDenominator * debtDecimals * 1e18;
    uint256 returnAmount = returnNumerator / returnDenominator;
    MockERC20(collateralToken).mint(msg.sender, returnAmount);
  }
}
