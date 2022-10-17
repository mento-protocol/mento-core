// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;

import { Test, console2 as console } from "celo-foundry/Test.sol";
import { ConstantSumPricingModule } from "contracts/ConstantSumPricingModule.sol";
import {IPricingModule} from "contracts/interfaces/IPricingModule.sol";
import { FixidityLib } from "contracts/common/FixidityLib.sol";

contract ConstantSumPricingModuleTest is Test {
    IPricingModule constantSum;

    function setUp() public {
        constantSum = new ConstantSumPricingModule(true);
    }

    //Testing concrete Case
    //amountOut = (1-spread)*amountIn = (1-0.1)*10^18 = 0.9*10^18 = 900000000000000000 Wei
    function test_getAmountOut_1() public {
        uint256 amountOut = constantSum.getAmountOut(10**24, 10**24, 100000000000000000000000 , 10**18);
        assertEq(amountOut, 900000000000000000);
    }

    //Fuzz testing
    //uint176 for bucket and amountIn, 
    //because the maximum value that can be converted to fix point in FixidityLib is uint177
    //uint80 for spread, because the spread needs to be smaller than 1. 
    //This is also enforced by the Exchange contract when settin a spread   
    function test_getAmountOut_2(
        uint176 tokenInBucketSize,
        uint176 tokenOutBucketSize, 
        uint80 spread,
        uint176 amountIn
        ) public {
        vm.assume(spread < FixidityLib.fixed1().value);
        vm.assume(amountIn <= tokenOutBucketSize);

        uint256 amountOut = constantSum.getAmountOut(tokenInBucketSize, tokenOutBucketSize, spread, amountIn );
    }

    //Testing concrete Case 
    //amountIn = amountOut/(1-spread) = 10^18 / (1 - 0.1) = 10^18 / (0.9) = 1111111111111111111.1111111111111111 
    //Wei = 1111111111111111111 Wei
    function test_getAmountIn_1() public {
        uint256 amountOut = constantSum.getAmountIn(10**24, 10**24, 100000000000000000000000 , 10**18);
        assertEq(amountOut, 1111111111111111111);
    }
    //Fuzz testing
    //uint176 for bucket and amountOut, 
    //because the maximum value that can be converted to fix point in FixidityLib is uint177.
    //uint80 for spread, because the spread needs to be smaller than 1.
    //This is also enforced by the Exchange contract when setting the spread. 
    function test_getAmountIn_2(
        uint176 tokenInBucketSize,
        uint176 tokenOutBucketSize,
        uint80 spread,
        uint176 amountOut) public {
        vm.assume(spread < FixidityLib.fixed1().value);
        vm.assume(amountOut<= tokenOutBucketSize);
        uint256 amountIn = constantSum.getAmountIn(tokenInBucketSize, tokenOutBucketSize, spread, amountOut); 
    }
} 