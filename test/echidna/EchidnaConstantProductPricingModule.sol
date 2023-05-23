// solhint-disable max-line-length

pragma solidity ^0.5.13;

import { ConstantProductPricingModule } from "../../contracts/ConstantProductPricingModule.sol";
import { FixidityLib } from "../../contracts/common/FixidityLib.sol";
import { EchidnaHelpers } from "./EchidnaHelpers.sol";

/**
 * @dev Command for local running:
 *      echidna ./test/echidna/EchidnaConstantProductPricingModule.sol --contract EchidnaConstantProductPricingModule --config ./echidna.yaml --test-mode assertion
 */
contract EchidnaConstantProductPricingModule {
  using FixidityLib for FixidityLib.Fraction;

  ConstantProductPricingModule public constantProductPricingModule;
  EchidnaHelpers private helpers;

  constructor() public {
    constantProductPricingModule = new ConstantProductPricingModule();
    helpers = new EchidnaHelpers();
  }

  function getAmounts_inverseConsistent(
    uint256 tokenInBucketSize,
    uint256 tokenOutBucketSize,
    uint256 spread,
    uint256 amountIn
  ) public view {

    tokenInBucketSize = helpers.between(tokenInBucketSize, 1e18, uint256(-1));
    tokenOutBucketSize = helpers.between(tokenOutBucketSize, 1e18, uint256(-1));
    spread = helpers.between(spread, 0, FixidityLib.unwrap(FixidityLib.fixed1()));

    uint256 amountOut = constantProductPricingModule.getAmountOut(
      tokenInBucketSize,
      tokenOutBucketSize,
      spread,
      amountIn
    );
    uint256 r = constantProductPricingModule.getAmountIn(tokenInBucketSize, tokenOutBucketSize, spread, amountOut);
    uint256 spreadFraction = FixidityLib.fixed1().subtract(FixidityLib.wrap(spread)).multiply(FixidityLib.newFixed(2)).unwrap();

    assert(helpers.areClose(amountIn, r, spread));
  }
}
