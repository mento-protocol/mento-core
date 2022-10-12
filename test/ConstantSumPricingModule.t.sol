// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;

import { Test, console2 as console } from "celo-foundry/Test.sol";

import { ConstantSumPricingModule } from "contracts/ConstantSumPricingModule.sol";
import {ConstantProductPricingModule} from "contracts/ConstantProductPricingModule.sol";
import {IPricingModule} from "contracts/interfaces/IPricingModule.sol";
import { FixidityLib } from "contracts/common/FixidityLib.sol";



contract ConstantSumPricingModuleTest is Test {
    IPricingModule constantSum;
    IPricingModule constantProduct; 

    function setUp() public {
        constantSum = new ConstantSumPricingModule(true);
        constantProduct = new ConstantProductPricingModule(true);
    }

    // testing concrete Case
    //amountOut = (1-spread)*amountIn = (1-0.1)*50 = 0.9*50 = 45
    function test_getAmountOut_1() public {
        uint256 amountOut = constantSum.getAmountOut(1000, 1000, 100000000000000000000000 , 50);
        assertEq(amountOut, 45*FixidityLib.fixed1().value);
    }

    //Fuzz testing
    //uint176 for bucket since and amountIn since maximum value that can be converted to fix point in FixidityLib is uint177
    //uint80 for spread spread needs to be smaller than 1 this is also enforced by the Exchange contract when setting the spread   
    function test_getAmountOut_2(uint176 tokenInBucketSize, uint176 tokenOutBucketSize , uint80 spread, uint176 amountIn) public {
        vm.assume(spread < FixidityLib.fixed1().value);
        vm.assume(amountIn <= tokenOutBucketSize);

        uint256 amountOut = constantSum.getAmountOut(tokenInBucketSize, tokenOutBucketSize, spread, amountIn );
    }

    // testing concrete Case
    //amountIn = amountOut/(1-spread) = 45 / (1 - 0.1) = 45 / (0.9) = 50 
    function test_getAmountIn_1() public {
        uint256 amountOut = constantSum.getAmountIn(1000, 1000, 100000000000000000000000 , 45);
        assertEq(amountOut, 50*FixidityLib.fixed1().value);
    }
    //Fuzz testing
    //uint176 for bucket and amountOut since maximum value that can be converted to fix point in FixidityLib is uint177
    //uint80 for spread  since spread needs to be smaller than 1 in FixidityLib this is also enforced by the Exchange contract when setting the spread 
    function test_getAmountIn_2(uint176 tokenInBucketSize, uint176 tokenOutBucketSize , uint80 spread, uint176 amountOut) public {
        vm.assume(spread < FixidityLib.fixed1().value);
        vm.assume(amountOut<= tokenOutBucketSize);
        uint256 amountIn = constantSum.getAmountIn(tokenInBucketSize, tokenOutBucketSize, spread, amountOut); 
    }

    function test_precision(uint128 amountOut, uint24 spread) public {

        uint256 ds_x = constantSum.getAmountIn(10, 10, 100000000000000000000000, 5);
        //
        uint256 dp_x = constantProduct.getAmountIn(10, 10, 100000000000000000000000, 5);
        console.log(ds_x, dp_x);
    }
} 