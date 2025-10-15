// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { FPMM } from "contracts/swap/FPMM.sol";

contract FPMMAlternativeImplementation is FPMM {
  constructor(bool disable) FPMM(disable) {}

  function setLPFee(uint256 _lpFee) public override onlyOwner {
    FPMMStorage storage $ = _getFPMMStorage();

    require(_lpFee + $.protocolFee <= 300, "FPMM: FEE_TOO_HIGH"); // Max 3% combined

    uint256 oldFee = $.lpFee;
    $.lpFee = _lpFee;
    emit LPFeeUpdated(oldFee, _lpFee);
  }
}
