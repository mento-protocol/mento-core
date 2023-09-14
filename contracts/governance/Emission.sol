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
  /// @notice The max amount that will be minted through emission
  uint256 public constant TOTAL_EMISSION_SUPPLY = 650_000_000 * 10**18;

  /// @notice Pre-calculated constant = EMISSION_HALF_LIFE / LN2.
  uint256 public constant A = 454968308;

  /// @notice Used to not lose precision in calculations.
  uint256 public constant SCALER = 1e18;

  /// @notice The timestamp when the emission process started.
  uint256 public immutable emissionStartTime;

  /// @notice The MentoToken contract reference.
  MentoToken public mentoToken;

  /// @notice The target address where emitted tokens are sent.
  address public emissionTarget;

  /// @notice The cumulative amount of tokens that have been emitted so far.
  uint256 public totalEmittedAmount;

  event TokenContractSet(address newTokenAddress);
  event EmissionTargetSet(address newTargetAddress);
  event TokensEmitted(address indexed target, uint256 amount);

  constructor() {
    emissionStartTime = block.timestamp;
  }

  /**
   * @notice Set the Mento Token contract address.
   * @param mentoToken_ Address of the Mento Token contract.
   */
  function setTokenContract(address mentoToken_) external onlyOwner {
    mentoToken = MentoToken(mentoToken_);
    emit TokenContractSet(mentoToken_);
  }

  /**
   * @notice Set the recipient address for the emitted tokens.
   * @param emissionTarget_ Address of the emission target.
   */
  function setEmissionTarget(address emissionTarget_) external onlyOwner {
    emissionTarget = emissionTarget_;

    emit EmissionTargetSet(emissionTarget_);
  }

  /**
   * @notice Emit tokens based on the exponential decay formula.
   * @return amount The number of tokens emitted.
   */
  function emitTokens() external returns (uint256 amount) {
    amount = calculateEmission();
    require(amount > 0, "Emission: no tokens to emit");
    totalEmittedAmount += amount;

    emit TokensEmitted(emissionTarget, amount);
    mentoToken.mint(emissionTarget, amount);
  }

  /**
   * @dev Calculate the releasable token amount using a predefined formula.
   * The Maclaurin series is used to create a simpler approximation of the exponential decay formula.
   * Original formula: E(t) = supply * exp(-A * t)
   * Approximation: E(t) = supply * (1 - (t / A) + (t^2 / 2A^2) - (t^3 / 6A^3) + (t^4 / 24A^4))
   * where A = HALF_LIFE / ln(e)
   * @dev A 5th term (t^5 / 120A^5) is added to ensure the entire supply is minted around 31.5 years.
   * @return amount Number of tokens that can be emitted.
   */
  function calculateEmission() public view returns (uint256 amount) {
    uint256 t = (block.timestamp - emissionStartTime);

    uint256 term1 = (SCALER * t) / A;
    uint256 term2 = (SCALER * t**2) / (2 * A**2);
    uint256 term3 = (SCALER * t**3) / (6 * A**3);
    uint256 term4 = (SCALER * t**4) / (24 * A**4);
    uint256 term5 = (SCALER * t**5) / (120 * A**5);

    uint256 positiveAggregate = SCALER + term2 + term4;
    uint256 negativeAggregate = term1 + term3 + term5;

    // Avoiding underflow in case the scheduled amount it bigger than the total supply
    if (positiveAggregate < negativeAggregate) {
      return TOTAL_EMISSION_SUPPLY - totalEmittedAmount;
    }

    uint256 scheduledAmount = (TOTAL_EMISSION_SUPPLY * (positiveAggregate - negativeAggregate)) / SCALER;

    amount = TOTAL_EMISSION_SUPPLY - scheduledAmount - totalEmittedAmount;
  }
}
