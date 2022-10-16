pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { IPricingModule } from "./interfaces/IPricingModule.sol";

import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";
import { Ownable } from "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import { Initializable } from "./common/Initializable.sol";
import { FixidityLib } from "./common/FixidityLib.sol";

contract ConstantProductPricingModule is IPricingModule, Initializable, Ownable {
  using SafeMath for uint256;
  using FixidityLib for FixidityLib.Fraction;

  /* ==================== Constructor ==================== */

  /**
   * @notice Sets initialized == true on implementation contracts
   * @param test Set to true to skip implementation initialization
   */
  constructor(bool test) public Initializable(test) {}

  /**
   * @notice Allows the contract to be upgradable via the proxy.
   */
  function initilize() external initializer {
    _transferOwnership(msg.sender);
  }

  /* ==================== View Functions ==================== */

  function getAmountOut(
    uint256 tokenInBucketSize,
    uint256 tokenOutBucketSize,
    uint256 spread,
    uint256 amountIn
  ) external view returns (uint256) {
    if (amountIn == 0) return 0;

    FixidityLib.Fraction memory spreadFraction = FixidityLib.wrap(spread);
    FixidityLib.Fraction memory netAmountIn = FixidityLib.fixed1().subtract(spreadFraction).multiply(
      FixidityLib.newFixed(amountIn)
    );

    FixidityLib.Fraction memory numerator = netAmountIn.multiply(FixidityLib.newFixed(tokenOutBucketSize));
    FixidityLib.Fraction memory denominator = FixidityLib.newFixed(tokenInBucketSize).add(netAmountIn);

    // Can't use FixidityLib.divide because numerator can easily be greater
    // than maxFixedDivisor.
    // Fortunately, we expect an integer result, so integer division gives us as
    // much precision as we could hope for.
    return numerator.unwrap().div(denominator.unwrap());
  }

  function getAmountIn(
    uint256 tokenInBucketSize,
    uint256 tokenOutBucketSize,
    uint256 spread,
    uint256 amountOut
  ) external view returns (uint256) {
    FixidityLib.Fraction memory spreadFraction = FixidityLib.wrap(spread);

    FixidityLib.Fraction memory numerator = FixidityLib.newFixed(amountOut.mul(tokenInBucketSize));
    FixidityLib.Fraction memory denominator = FixidityLib.newFixed(tokenOutBucketSize.sub(amountOut)).multiply(
      FixidityLib.fixed1().subtract(spreadFraction)
    );

    // See comment in getAmountOut.
    return numerator.unwrap().div(denominator.unwrap());
  }

  function name() external view returns (string memory) {
    return "ConstantProduct";
  }
}
