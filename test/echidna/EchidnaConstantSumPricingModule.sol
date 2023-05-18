pragma solidity ^0.5.13;

import { ConstantSumPricingModule } from "../../contracts/ConstantSumPricingModule.sol";
import { FixidityLib } from "../../contracts/common/FixidityLib.sol";

contract EchidnaConstantSumPricingModule {
  using FixidityLib for FixidityLib.Fraction;

  ConstantSumPricingModule public constantSumPricingModule;

  constructor() public {
    constantSumPricingModule = new ConstantSumPricingModule();
  }

  // TODO: Generate random inputs with constraints for these tests.

  /* ==================== GetAmountOut ==================== */

  function echidna_test_getAmountOut_zeroInputReturnsZeroOutput() public view {
    uint256 tokenOutBucketSize = 10000;
    uint256 spread = 500;
    uint256 amountIn = 0;

    uint256 amountOut = constantSumPricingModule.getAmountOut(0, tokenOutBucketSize, spread, amountIn);

    assert(amountOut == 0);
  }

  function echidna_test_getAmountOut_outputLteTokenOutBucket() public view {
    uint256 tokenOutBucketSize = 10000;
    uint256 spread = 500;
    uint256 amountIn = 500;

    uint256 amountOut = constantSumPricingModule.getAmountOut(0, tokenOutBucketSize, spread, amountIn);

    assert(amountOut <= tokenOutBucketSize);
  }

  /* ==================== GetAmountIn ==================== */

  function echidna_test_getAmountIn_zeroOutputReturnsZeroInput() public view {
    uint256 tokenOutBucketSize = 10000;
    uint256 spread = 500;
    uint256 amountOut = 0;

    uint256 amountIn = constantSumPricingModule.getAmountIn(0, tokenOutBucketSize, spread, amountOut);

    assert(amountIn == 0);
  }

  function echidna_test_getAmountIn_outputLteTokenOutBucket() public view {
    uint256 tokenOutBucketSize = 10000;
    uint256 spread = 500;
    uint256 amountOut = 500;

    uint256 amountIn = constantSumPricingModule.getAmountIn(0, tokenOutBucketSize, spread, amountOut);

    assert(amountIn <= tokenOutBucketSize);
  }

  /* ==================== Inverse Operations ==================== */

  function echidna_test_getAmountOut_getAmountIn_inverse() public view {
    uint256 tokenOutBucketSize = 10000;
    uint256 spread = 500;
    uint256 amountIn = 5000;

    // Make sure spread is between 0 and 1.
    spread = between(spread, 0, FixidityLib.unwrap(FixidityLib.fixed1()));

    uint256 amountOut = constantSumPricingModule.getAmountOut(tokenOutBucketSize, tokenOutBucketSize, spread, amountIn);
    uint256 amountInCalculated = constantSumPricingModule.getAmountIn(
      tokenOutBucketSize,
      tokenOutBucketSize,
      spread,
      amountOut
    );

    assert(amountInCalculated == amountIn);
  }

  function echidna_test_getAmountIn_getAmountOut_inverse() public view {
    uint256 tokenOutBucketSize = 10000;
    uint256 spread = 500;
    uint256 amountOut = 5000;

    // Make sure spread is between 0 and 1.
    spread = between(spread, 0, FixidityLib.unwrap(FixidityLib.fixed1()));

    uint256 amountIn = constantSumPricingModule.getAmountIn(tokenOutBucketSize, tokenOutBucketSize, spread, amountOut);
    uint256 amountOutCalculated = constantSumPricingModule.getAmountOut(
      tokenOutBucketSize,
      tokenOutBucketSize,
      spread,
      amountIn
    );

    assert(amountOutCalculated == amountOut);
  }

  /* ==================== Helper Functions ==================== */

  /**
   * @notice Checks if a given number falls within a specified range.
   * @param num The number to be checked.
   * @param lower The lower boundary of the range.
   * @param upper The upper boundary of the range.
   * @return The number if it falls within the range, the closest boundary otherwise.
   */
  function between(uint256 num, uint256 lower, uint256 upper) internal pure returns (uint256) {
    if (num < lower) {
      return lower;
    } else if (num > upper) {
      return upper;
    } else {
      return num;
    }
  }
}
