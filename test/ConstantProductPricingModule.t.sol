// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Test, console2 as console } from "celo-foundry/Test.sol";
import { stdStorage } from "forge-std/Test.sol";

import { ConstantProductPricingModule } from "contracts/ConstantProductPricingModule.sol";
import { Exchange } from "contracts/Exchange.sol";
import { FixidityLib } from "contracts/common/FixidityLib.sol";

import { IPricingModule } from "contracts/interfaces/IPricingModule.sol";

import { MockSortedOracles } from "./mocks/MockSortedOracles.sol";
import { WithRegistry } from "./utils/WithRegistry.t.sol";

contract LegacyExchangeWrapper {
  address constant registryAddress = 0x000000000000000000000000000000000000ce10;
  using stdStorage for stdStorage.StdStorage;
  stdStorage.StdStorage internal stdstore;

  Exchange exchange;

  bytes4 constant STABLE_BUCKET_SIG = bytes4(keccak256("stableBucket()"));
  bytes4 constant GOLD_BUCKET_SIG = bytes4(keccak256("goldBucket()"));

  constructor() public {
    exchange = new Exchange(true);
    exchange.initialize(registryAddress, "StableToken", 5 * 1e23, 5 * 1e23, 60 * 60, 2);
  }

  function getAmountOut(
    uint256 tokenInBucketSize,
    uint256 tokenOutBucketSize,
    uint256 spread,
    uint256 amountIn
  ) external returns (uint256 amountOut) {
    setupExchange(tokenInBucketSize, tokenOutBucketSize, spread);
    return exchange.getBuyTokenAmount(amountIn, false);
  }

  function getAmountIn(
    uint256 tokenInBucketSize,
    uint256 tokenOutBucketSize,
    uint256 spread,
    uint256 amountOut
  ) external returns (uint256 amountIn) {
    setupExchange(tokenInBucketSize, tokenOutBucketSize, spread);
    return exchange.getSellTokenAmount(amountOut, false);
  }

  function setupExchange(
    uint256 stableBucket,
    uint256 goldBucket,
    uint256 spread
  ) internal {
    exchange.setSpread(spread);
    stdstore.target(address(exchange)).sig(STABLE_BUCKET_SIG).checked_write(stableBucket);
    stdstore.target(address(exchange)).sig(GOLD_BUCKET_SIG).checked_write(goldBucket);
  }
}

contract ConstantProductPricingModuleTest is Test, WithRegistry {
  IPricingModule constantProduct;
  LegacyExchangeWrapper legacyExchange;
  MockSortedOracles sortedOracles;

  uint256 pc1 = 1 * 1e22;
  uint256 pc5 = 5 * 1e22;
  uint256 pc10 = 1e23;

  function setUp() public {
    vm.warp(24 * 60 * 60);
    address deployer = actor("deployer");
    vm.startPrank(deployer);
    currentPrank = deployer;
    sortedOracles = new MockSortedOracles();
    sortedOracles.setNumRates(address(0), 10);

    registry.setAddressFor("SortedOracles", address(sortedOracles));
    constantProduct = new ConstantProductPricingModule();
    legacyExchange = new LegacyExchangeWrapper();
  }

  function test_getAmountOut_compareWithLegacyExchange_t1() public {
    uint256 expectedAmountOut = legacyExchange.getAmountOut(1e24, 2e24, pc1, 1e23);
    uint256 newAmountOut = constantProduct.getAmountOut(1e24, 2e24, pc1, 1e23);

    assertEq(newAmountOut, expectedAmountOut);
  }

  function test_getAmountOut_compareWithLegacyExchange_t2() public {
    uint256 expectedAmountOut = legacyExchange.getAmountOut(11e24, 23e24, pc5, 3e23);
    uint256 newAmountOut = constantProduct.getAmountOut(11e24, 23e24, pc5, 3e23);

    assertEq(newAmountOut, expectedAmountOut);
  }

  function test_getAmountIn_compareWithLegacyExchange_t1() public {
    uint256 expectedAmountIn = legacyExchange.getAmountIn(1e24, 2e24, pc1, 1e23);
    uint256 newAmountIn = constantProduct.getAmountIn(1e24, 2e24, pc1, 1e23);

    assertEq(newAmountIn, expectedAmountIn);
  }

  function test_getAmountIn_compareWithLegacyExchange_t2() public {
    uint256 expectedAmountIn = legacyExchange.getAmountIn(11e24, 23e24, pc5, 3e23);
    uint256 newAmountIn = constantProduct.getAmountIn(11e24, 23e24, pc5, 3e23);

    assertEq(newAmountIn, expectedAmountIn);
  }
}
