// solhint-disable max-line-length

pragma solidity ^0.5.13;

import { ConstantSumPricingModule } from "../../contracts/ConstantSumPricingModule.sol";
import { FixidityLib } from "../../contracts/common/FixidityLib.sol";
import { EchidnaHelpers } from "./EchidnaHelpers.sol";

/**
 * @dev Command for local running:
 *      echidna ./test/echidna/EchidnaConstantSumPricingModule.sol --contract EchidnaConstantSumPricingModule --config ./echidna.yaml --test-mode assertion
 */
contract EchidnaConstantSumPricingModule {
  using FixidityLib for FixidityLib.Fraction;

  ConstantSumPricingModule public constantSumPricingModule;
  EchidnaHelpers private helpers;

  constructor() public {
    constantSumPricingModule = new ConstantSumPricingModule();
    helpers = new EchidnaHelpers();
  }

  function getAmounts_inverseConsistent(
    uint256 tokenOutBucketSize,
    uint256 spread,
    uint256 amountIn
  ) public view returns (bool) {
    spread = helpers.between(spread, 0, FixidityLib.unwrap(FixidityLib.fixed1()));
    uint256 amountOut = constantSumPricingModule.getAmountOut(0, tokenOutBucketSize, spread, amountIn);
    uint256 r = constantSumPricingModule.getAmountIn(0, tokenOutBucketSize, spread, amountOut);
    return (r == amountIn);
  }
}
