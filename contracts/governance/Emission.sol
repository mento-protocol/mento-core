// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { Ownable } from "openzeppelin-contracts-next/contracts/access/Ownable.sol";
import { MentoToken } from "./MentoToken.sol";

// import { console } from "forge-std-next/console.sol";

contract Emission is Ownable {
  uint256 public constant EMISSION_SUPPLY = 650_000_000 * 10**18;

  // EMISSION_HALF_LIFE = 10 * 365 days;
  // LN2 = 0.693147180559945309;
  uint256 public constant A = 454968308; // ~= EMISSION_HALF_LIFE / LN2
  uint256 public constant SCALER = 1e18;

  uint256 public immutable emissionStart;

  MentoToken public mentoToken;
  address public emissionTarget;
  uint256 public emittedAmount;

  constructor() {
    emissionStart = block.timestamp;
  }

  function setTokenContract(address mentoToken_) external onlyOwner {
    mentoToken = MentoToken(mentoToken_);
  }

  function setEmissionTarget(address emissionTarget_) external onlyOwner {
    emissionTarget = emissionTarget_;
  }

  function emitTokens() external returns (uint256 amount) {
    amount = _releasableAmount();
    // console.log(amount);
    require(amount > 0, "Emission: no emission due");
    emittedAmount += amount;
    mentoToken.mint(emissionTarget, amount);
  }

  function _releasableAmount() internal view returns (uint256 amount) {
    uint256 t = (block.timestamp - emissionStart);

    uint256 term1 = (t * SCALER) / A;
    // console.log(term1);
    uint256 term2 = (t * t * SCALER) / (2 * A * A);
    // console.log(term2);
    uint256 term3 = (t * t * t * SCALER) / (6 * A * A * A);
    // console.log(term3);
    uint256 term4 = (t * t * t * t * SCALER) / (24 * A * A * A * A);
    // console.log(term4);
    // console.log("h1");

    uint256 scheduledAmount = (EMISSION_SUPPLY * (SCALER + term2 + term4 - term1 - term3)) / SCALER;

    // console.log("2");
    // console.log(scheduledAmount);
    // console.log("a");
    amount = EMISSION_SUPPLY - scheduledAmount - emittedAmount;
  }
}
