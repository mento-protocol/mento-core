pragma solidity ^0.5.13;

import { ConstantProductPricingModule } from "../../contracts/ConstantProductPricingModule.sol";
import { FixidityLib } from "../../contracts/common/FixidityLib.sol";
import { EchidnaHelpers } from "./EchidnaHelpers.sol";

contract EchidnaConstantProductPricingModule {
  using FixidityLib for FixidityLib.Fraction;

  ConstantProductPricingModule public constantProductPricingModule;
  EchidnaHelpers private helpers;

  constructor() public {
    constantProductPricingModule = new ConstantProductPricingModule();
    helpers = new EchidnaHelpers();
  }

  /* ==================== GetAmountOut ==================== */

  function echidna_test_getAmountOut_zeroInputReturnsZeroOutput() public view {
    uint256 tokenOutBucketSize = 10000;
    uint256 spread = 500;
    uint256 amountIn = 0;

    uint256 amountOut = constantProductPricingModule.getAmountOut(0, tokenOutBucketSize, spread, amountIn);

    assert(amountOut == 0);
  }

  function echidna_test_getAmountOut_outputLteTokenOutBucket() public view {
    uint256 tokenOutBucketSize = 10000;
    uint256 spread = 500;
    uint256 amountIn = 500;

    uint256 amountOut = constantProductPricingModule.getAmountOut(0, tokenOutBucketSize, spread, amountIn);

    assert(amountOut <= tokenOutBucketSize);
  }

  /* ==================== GetAmountIn ==================== */

  function echidna_test_getAmountIn_zeroOutputReturnsZeroInput() public view {
    uint256 tokenOutBucketSize = 10000;
    uint256 spread = 500;
    uint256 amountOut = 0;

    uint256 amountIn = constantProductPricingModule.getAmountIn(0, tokenOutBucketSize, spread, amountOut);

    assert(amountIn == 0);
  }

  function echidna_test_getAmountIn_outputLteTokenOutBucket() public view {
    uint256 tokenOutBucketSize = 10000;
    uint256 spread = 500;
    uint256 amountOut = 500;

    uint256 amountIn = constantProductPricingModule.getAmountIn(0, tokenOutBucketSize, spread, amountOut);

    assert(amountIn <= tokenOutBucketSize);
  }

  /* ==================== Inverse Operations ==================== */

  function echidna_test_getAmountOut_getAmountIn_inverse() public view {
    uint256 tokenOutBucketSize = 10000;
    uint256 spread = 500;
    uint256 amountIn = 5000;

    spread = helpers.between(spread, 0, FixidityLib.unwrap(FixidityLib.fixed1()));

    uint256 amountOut = constantProductPricingModule.getAmountOut(
      tokenOutBucketSize,
      tokenOutBucketSize,
      spread,
      amountIn
    );
    uint256 amountInCalculated = constantProductPricingModule.getAmountIn(
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

    spread = helpers.between(spread, 0, FixidityLib.unwrap(FixidityLib.fixed1()));

    uint256 amountIn = constantProductPricingModule.getAmountIn(
      tokenOutBucketSize,
      tokenOutBucketSize,
      spread,
      amountOut
    );
    uint256 amountOutCalculated = constantProductPricingModule.getAmountOut(
      tokenOutBucketSize,
      tokenOutBucketSize,
      spread,
      amountIn
    );

    assert(amountOutCalculated == amountOut);
  }
}
