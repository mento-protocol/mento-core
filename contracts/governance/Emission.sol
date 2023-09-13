// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { Ownable } from "openzeppelin-contracts-next/contracts/access/Ownable.sol";
import { MentoToken } from "./MentoToken.sol";

/**
 * @title Emission Contract for Mento Token
 * @author Mento Labs
 * @notice This contract handles the emission of Mento Tokens in an exponentially decaying manner.
 */
contract Emission is Ownable {
  uint256 public constant TOTAL_EMISSION_SUPPLY = 650_000_000 * 10**18;

  // Constants related to the exponential decay function.
  uint256 public constant A = 454968308; // EMISSION_HALF_LIFE / LN2
  uint256 public constant SCALER = 1e18;

  uint256 public immutable emissionStartTime;

  MentoToken public mentoToken;
  address public emissionTarget;
  uint256 public totalEmittedAmount;

  constructor() {
    emissionStartTime = block.timestamp;
  }

  /**
   * @notice Set the Mento Token contract address.
   * @param mentoToken_ Address of the Mento Token contract.
   */
  function setTokenContract(address mentoToken_) external onlyOwner {
    mentoToken = MentoToken(mentoToken_);
  }

  /**
   * @notice Set the recipient address for the emitted tokens.
   * @param emissionTarget_ Address of the emission target.
   */
  function setEmissionTarget(address emissionTarget_) external onlyOwner {
    emissionTarget = emissionTarget_;
  }

  /**
   * @notice Emit tokens based on the exponential decay formula.
   * @return amount The number of tokens emitted.
   */
  function emitTokens() external returns (uint256 amount) {
    amount = _calculateReleasableAmount();
    require(amount > 0, "Emission: no tokens to emit");
    totalEmittedAmount += amount;
    mentoToken.mint(emissionTarget, amount);
  }

  /**
   * @dev Calculate the releasable token amount using a predefined formula.
   * The Maclaurin series is used to create a simpler approximation of the exponential decaying formula.
   * Original formula: E(t) = supply * exp(-A * t)
   * Approximation: E(t) = supply * (1 - (t / A) + (t^2 / 2A^2) - (t^3 / 6A^3) + (t^4 / 24A^4) - (t^5 / 120A^5))
   * where A = HALF_LIFE / ln(e)
   * @dev A 5th term is added to ensure the entire supply is minted around 31.5 years.
   * @return amount Number of tokens that can be emitted.
   */
  function _calculateReleasableAmount() internal view returns (uint256 amount) {
    uint256 t = (block.timestamp - emissionStartTime);

    uint256 term1 = (t * SCALER) / A;
    uint256 term2 = (t * t * SCALER) / (2 * A * A);
    uint256 term3 = (t * t * t * SCALER) / (6 * A * A * A);
    uint256 term4 = (t * t * t * t * SCALER) / (24 * A * A * A * A);
    uint256 term5 = (t * t * t * t * t * SCALER) / (120 * A * A * A * A * A);

    uint256 addition = SCALER + term2 + term4;
    uint256 subtraction = term1 + term3 + term5;

    // Avoiding underflow
    if (addition < subtraction) {
      return TOTAL_EMISSION_SUPPLY - totalEmittedAmount;
    }

    uint256 scheduledAmount = (TOTAL_EMISSION_SUPPLY * (addition - subtraction)) / SCALER;

    amount = TOTAL_EMISSION_SUPPLY - scheduledAmount - totalEmittedAmount;
  }
}
