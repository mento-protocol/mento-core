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

  /* we use the Maclaurin series to create a simpler approximation of exponential decaying formula
   * original formula: E(t) = supply * exp(-A * t)
   * approximate: E(t) = supply * (1 - (t / A) + (t^2 / 2A^2) - (t^3 / 6A^3) + (t^4 / 24A^4) - (t^5 / 120A^5))
   * where A = HALF_LIFE / ln(e)
   * note: we added a 5th term to mint the whole supply around 31.5 years
   */
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
    uint256 term5 = (t * t * t * t * t * SCALER) / (120 * A * A * A * A * A);

    uint256 addition = SCALER + term2 + term4;
    uint256 subtraction = term1 + term3 + term5;

    // avoiding underflow
    if (addition < subtraction) {
      return EMISSION_SUPPLY - emittedAmount;
    }

    uint256 scheduledAmount = (EMISSION_SUPPLY * (addition - subtraction)) / SCALER;

    // console.log("2");
    // console.log(scheduledAmount);
    // console.log(emittedAmount);
    // console.log("a");
    amount = EMISSION_SUPPLY - scheduledAmount - emittedAmount;
  }
}
