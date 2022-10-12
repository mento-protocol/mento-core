pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { IPricingModule } from "./interfaces/IPricingModule.sol";

import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";
import { Ownable } from "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import { Initializable } from "./common/Initializable.sol";
import { FixidityLib } from "./common/FixidityLib.sol";

contract ConstantSumPricingModule is IPricingModule, Initializable, Ownable {
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

    // amountOut = (1 - spread) * amountIn
  function getAmountOut(
    uint256 tokenInBucketSize, 
    uint256 tokenOutBucketSize, 
    uint256 spread, 
    uint256 amountIn
    ) external view returns (uint256 amountOut) {
    if (amountIn == 0) return 0;

    require(spread < FixidityLib.fixed1().value, "prevent substraction underflow");

    FixidityLib.Fraction memory spreadFraction = FixidityLib.fixed1().subtract(FixidityLib.wrap(spread));

    amountOut = spreadFraction.multiply(FixidityLib.newFixed(amountIn)).unwrap();
    require(amountOut <= FixidityLib.newFixed(tokenOutBucketSize).unwrap(), 
      "amountOut cant be greater then the tokenOutPool size");
  }

  // amountIn = amountOut / (1 - spread)
  function getAmountIn(
    uint256 tokenInBucketSize, 
    uint256 tokenOutBucketSize, 
    uint256 spread, 
    uint256 amountOut
    ) external view returns (uint256 amountIn){
    require(amountOut <= tokenOutBucketSize, "amountOut cant be greater then the tokenOutPool size");
    require(spread < FixidityLib.fixed1().value, "prevent substraction underflow");
    if (amountOut == 0) return 0;

    FixidityLib.Fraction memory spreadFraction = FixidityLib.fixed1().subtract(FixidityLib.wrap(spread));
    FixidityLib.Fraction memory numerator = FixidityLib.newFixed(amountOut);

    if(numerator.value < FixidityLib.maxNewFixed()) amountIn = numerator.divide(spreadFraction).unwrap();
    else amountIn = FixidityLib.multiply(numerator, FixidityLib.reciprocal(spreadFraction)).unwrap();
  }

  function name()external view returns (string memory) {
    return "ConstantSum";
  }

}