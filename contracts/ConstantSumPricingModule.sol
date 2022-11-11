pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { IPricingModule } from "./interfaces/IPricingModule.sol";

import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";
import { FixidityLib } from "./common/FixidityLib.sol";

/**
 * @title ConstantSumPricingModule
 * @notice The ConstantSumPricingModule calculates the amount in and the amount out for a constant sum AMM.
 */

contract ConstantSumPricingModule is IPricingModule {
  using SafeMath for uint256;
  using FixidityLib for FixidityLib.Fraction;

  /* ==================== View Functions ==================== */
  /**
   * @notice Calculates the amount of tokens that should be received based on the given parameters
   * @dev amountOut = (1 - spread) * amountIn
   * @param tokenInBucketSize The bucket size of the token swapt in.
   * @param tokenOutBucketSize The bucket size of the token swapt out.
   * @param spread The spread that is applied to a swap.
   * @param amountIn The amount of tokens in wei that is swapt in.
   * @return amountOut The amount of tokens in wei that should be received.
   */
  function getAmountOut(
    uint256 tokenInBucketSize,
    uint256 tokenOutBucketSize,
    uint256 spread,
    uint256 amountIn
  ) external view returns (uint256 amountOut) {
    if (amountIn == 0) return 0;

    FixidityLib.Fraction memory spreadFraction = FixidityLib.fixed1().subtract(FixidityLib.wrap(spread));
    amountOut = spreadFraction.multiply(FixidityLib.newFixed(amountIn)).unwrap();
    amountOut = amountOut.div(FixidityLib.fixed1().unwrap());
    require(
      amountOut <= FixidityLib.newFixed(tokenOutBucketSize).unwrap(),
      "amountOut cant be greater then the tokenOutPool size"
    );
    return amountOut;
  }

  /**
   * @notice Calculates the amount of tokens that should be provided in order to receive the desired amount out.
   * @dev amountIn = amountOut / (1 - spread)
   * @param tokenInBucketSize The bucket size of the token swapt in.
   * @param tokenOutBucketSize The bucket size of the token swapt out.
   * @param spread The spread that is applied to a swap.
   * @param amountOut The amount of tokens in wei that should be swapt out.
   * @return amountIn The amount of tokens in wei that should be provided.
   */
  function getAmountIn(
    uint256 tokenInBucketSize,
    uint256 tokenOutBucketSize,
    uint256 spread,
    uint256 amountOut
  ) external view returns (uint256 amountIn) {
    require(amountOut <= tokenOutBucketSize, "amountOut cant be greater then the tokenOutPool size");
    if (amountOut == 0) return 0;

    FixidityLib.Fraction memory denominator = FixidityLib.fixed1().subtract(FixidityLib.wrap(spread));
    FixidityLib.Fraction memory numerator = FixidityLib.newFixed(amountOut);

    // Can't use FixidityLib.divide because numerator can be greater
    // than maxFixedDivisor.
    // Fortunately, we expect an integer result, so integer division gives us as
    // much precision as we could hope for.
    return numerator.unwrap().div(denominator.unwrap());
  }

  /**
   * @notice Returns the AMM that the IPricingModule implements
   * @return Constant Sum.
   */
  function name() external view returns (string memory) {
    return "ConstantSum";
  }
}
