// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { FPMM } from "contracts/swap/FPMM.sol";

contract FPMMAlternativeImplementation is FPMM {
  constructor(bool disable) FPMM(disable) {}

  function setLPFee(uint256 _lpFee) public override onlyOwner {
    FPMMStorage storage $ = _getFPMMStorage();

    if (_lpFee + $.protocolFee > 300) revert FeeTooHigh();

    uint256 oldFee = $.lpFee;
    $.lpFee = _lpFee;
    emit LPFeeUpdated(oldFee, _lpFee);
  }
}
