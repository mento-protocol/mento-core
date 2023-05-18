pragma solidity ^0.5.13;

import { ConstantSumPricingModule } from "../../contracts/ConstantSumPricingModule.sol";
import { FixidityLib } from "../../contracts/common/FixidityLib.sol";
import { EchidnaHelpers } from "./EchidnaHelpers.sol";

/**
 * @dev Command for local running:
 * echidna ./test/echidna/EchidnaConstantSumPricingModule.sol --contract EchidnaConstantSumPricingModule --config ./echidna.yaml --test-mode assertion
 */
contract EchidnaConstantSumPricingModule {
  using FixidityLib for FixidityLib.Fraction;

  ConstantSumPricingModule public constantSumPricingModule;
  EchidnaHelpers private helpers;

  constructor() public {
    constantSumPricingModule = new ConstantSumPricingModule();
    helpers = new EchidnaHelpers();
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

  function echidna_test_getAmountOut_getAmountIn_inverse(
    uint256 tokenOutBucketSize,
    uint256 spread,
    uint256 amountIn
  ) public view {
    // uint256 tokenOutBucketSize = 10000;
    // uint256 spread = 500;
    // uint256 amountIn = 5000;

    tokenOutBucketSize = (tokenOutBucketSize % 10000) + 1;
    spread = spread % 1000;
    amountIn = (amountIn % 10000) + 1;

    // Make sure spread is between 0 and 1.
    spread = helpers.between(spread, 0, FixidityLib.unwrap(FixidityLib.fixed1()));

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
    spread = helpers.between(spread, 0, FixidityLib.unwrap(FixidityLib.fixed1()));

    uint256 amountIn = constantSumPricingModule.getAmountIn(tokenOutBucketSize, tokenOutBucketSize, spread, amountOut);
    uint256 amountOutCalculated = constantSumPricingModule.getAmountOut(
      tokenOutBucketSize,
      tokenOutBucketSize,
      spread,
      amountIn
    );

    assert(amountOutCalculated == amountOut);
  }
}
