// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { Test } from "mento-std/Test.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { FixidityLib } from "celo/contracts/common/FixidityLib.sol";

import { VirtualPool } from "contracts/swap/virtual/VirtualPool.sol";
import { IBiPoolManager } from "contracts/interfaces/IBiPoolManager.sol";
import { IBroker } from "contracts/interfaces/IBroker.sol";
import { IPricingModule } from "contracts/interfaces/IPricingModule.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";

contract VirtualPoolTest is Test {
  bytes32 public constant EXCHANGE_ID = bytes32(0);
  uint256 internal constant BUCKET0 = 100e18;
  uint256 internal constant BUCKET1 = 250e6;

  IPricingModule internal immutable PRICING_MODULE = IPricingModule(makeAddr("pricingModule"));
  address internal immutable REFERENCE_RATE = makeAddr("referenceRate");
  uint256 internal immutable LAST_UPDATE_TS = block.timestamp;

  address public broker = makeAddr("Broker");
  address public exchangeProvider = makeAddr("ExchangeProvider");

  address public token0;
  address public token1;

  VirtualPool public pool;

  function setUp() public {
    address a1 = vm.computeCreateAddress(address(this), 0);
    address a2 = vm.computeCreateAddress(address(this), 1);
    if (a1 < a2) {
      token0 = address(new MockERC20("Token0", "TOK0", 18));
      token1 = address(new MockERC20("Token1", "TOK1", 6));
    } else {
      token1 = address(new MockERC20("Token1", "TOK1", 6));
      token0 = address(new MockERC20("Token0", "TOK0", 18));
    }

    vm.mockCall(exchangeProvider, abi.encodeWithSelector(IBiPoolManager.broker.selector), abi.encode(broker));
    vm.mockCall(
      exchangeProvider,
      abi.encodeWithSelector(IBiPoolManager.exchanges.selector),
      abi.encode(_makeExchange(token0, token1, BUCKET0, BUCKET1, _bpsToFraction(30))) // 30 bps
    );

    pool = new VirtualPool(broker, exchangeProvider, EXCHANGE_ID, token0, token1, true);
  }

  function test_tokens_shouldBeSorted() public view {
    (address t0, address t1) = pool.tokens();
    assertEq(t0, token0);
    assertEq(t1, token1);
    assertEq(pool.token0(), t0);
    assertEq(pool.token1(), t1);
  }

  function test_metadata_shouldMatch() public view {
    (uint256 dec0, uint256 dec1, uint256 r0, uint256 r1, address t0, address t1) = pool.metadata();
    assertEq(dec0, 1e18);
    assertEq(dec1, 1e6);
    assertEq(r0, BUCKET0);
    assertEq(r1, BUCKET1);
    assertEq(t0, token0);
    assertEq(t1, token1);
    assertEq(pool.token0(), token0);
    assertEq(pool.token1(), token1);
    assertEq(pool.decimals0(), 1e18);
    assertEq(pool.decimals1(), 1e6);
  }

  function test_reserves_shouldMatch() public {
    vm.warp(block.timestamp + 100);
    (uint256 r0, uint256 r1, uint256 ts) = pool.getReserves();
    assertEq(r0, BUCKET0);
    assertEq(r1, BUCKET1);
    assertEq(ts, LAST_UPDATE_TS);

    assertEq(pool.reserve0(), BUCKET0);
    assertEq(pool.reserve1(), BUCKET1);
  }

  function test_protocolFee_shouldReturnBps() public view {
    assertEq(pool.protocolFee(), 30);
  }

  function test_getAmountOut_token0In() public {
    uint256 quoted = 42;
    _mockBrokerOutput(quoted);
    uint256 out = pool.getAmountOut(123, pool.token0());
    assertEq(out, quoted);
  }

  function test_getAmountOut_token1In() public {
    uint256 quoted = 777;
    _mockBrokerOutput(quoted);
    uint256 out = pool.getAmountOut(5, pool.token1());
    assertEq(out, quoted);
  }

  function test_getAmountOut_zeroAmount_shortCircuitsToZero() public {
    _mockBrokerOutput(999_999);
    assertEq(pool.getAmountOut(0, pool.token0()), 0);
    assertEq(pool.getAmountOut(0, pool.token1()), 0);
  }

  function test_getAmountOut_invalidToken_shouldRevert() public {
    vm.expectRevert("VirtualPool: INVALID_TOKEN");
    pool.getAmountOut(1, makeAddr("notATokenInThisPair"));
  }

  function test_swap_token0ToToken1_shouldWork() public {
    address to = makeAddr("recipient");

    uint256 amountIn = 2e18;
    MockERC20(token0).setBalance(address(pool), amountIn);

    uint256 amountOut = 43e6;
    MockERC20(token1).setBalance(address(pool), amountOut);

    _mockBrokerOutput(amountOut);

    vm.expectCall(token1, abi.encodeWithSelector(IERC20.transfer.selector, to, amountOut));
    pool.swap(0, amountOut, to, "");

    assertEq(MockERC20(token1).balanceOf(to), amountOut);
    assertEq(MockERC20(token1).balanceOf(address(pool)), 0);
    // NOTE: token0 balance is unchanged here because the mocked broker didn't actually pull tokens.
    assertEq(MockERC20(token0).balanceOf(address(pool)), amountIn);
  }

  function test_swap_token1ToToken0_shouldWork() public {
    address to = makeAddr("recipient2");

    uint256 amountIn = 987_654; // token1 (6 decimals)
    MockERC20(token1).setBalance(address(pool), amountIn);

    uint256 amountOut = 10e18; // token0 (18 decimals)
    MockERC20(token0).setBalance(address(pool), amountOut);

    _mockBrokerOutput(amountOut);

    // Direction: amount0Out != 0 ⇒ token1 -> token0
    vm.expectCall(token0, abi.encodeWithSelector(IERC20.transfer.selector, to, amountOut));
    pool.swap(amountOut, 0, to, "");

    assertEq(MockERC20(token0).balanceOf(to), amountOut);
    assertEq(MockERC20(token0).balanceOf(address(pool)), 0);
    assertEq(MockERC20(token1).balanceOf(address(pool)), amountIn);
  }

  function test_swap_whenBothOutZero_shouldRevert() public {
    vm.expectRevert("VirtualPool: INSUFFICIENT_OUTPUT_AMOUNT");
    pool.swap(0, 0, makeAddr("to"), "");
  }

  function test_swap_whenBothOutNonZero_shouldRevert() public {
    vm.expectRevert("VirtualPool: ONE_AMOUNT_MUST_BE_ZERO");
    pool.swap(1, 1, makeAddr("to"), "");
  }

  function test_swap_whenDataNonEmpty_shouldRevert() public {
    vm.expectRevert("VirtualPool: ONE_AMOUNT_MUST_BE_ZERO");
    pool.swap(0, 1, makeAddr("to"), "flash? no."); // flash swaps forbidden
  }

  function test_swap_whenToIsTokenAddress_shouldRevert() public {
    vm.expectRevert("VirtualPool: INVALID_TO_ADDRESS");
    pool.swap(0, 1, token0, "");
    vm.expectRevert("VirtualPool: INVALID_TO_ADDRESS");
    pool.swap(1, 0, token1, "");
  }

  function test_swap_whenToIsPoolItself_shouldRevert() public {
    vm.expectRevert("VirtualPool: INVALID_TO_ADDRESS");
    pool.swap(0, 1, address(pool), "");
  }

  function _mockBrokerOutput(uint256 amountOut) internal {
    vm.mockCall(broker, abi.encodeWithSelector(IBroker.getAmountOut.selector), abi.encode(amountOut));
    vm.mockCall(broker, abi.encodeWithSelector(IBroker.swapOut.selector), abi.encode(amountOut));
  }

  function _makeExchange(
    address asset0,
    address asset1,
    uint256 bucket0,
    uint256 bucket1,
    FixidityLib.Fraction memory spread
  ) internal view returns (IBiPoolManager.PoolExchange memory) {
    return
      IBiPoolManager.PoolExchange({
        asset0: asset0,
        asset1: asset1,
        pricingModule: PRICING_MODULE,
        bucket0: bucket0,
        bucket1: bucket1,
        lastBucketUpdate: LAST_UPDATE_TS,
        config: IBiPoolManager.PoolConfig({
          spread: spread,
          referenceRateFeedID: REFERENCE_RATE,
          referenceRateResetFrequency: 1,
          minimumReports: 1,
          stablePoolResetSize: 1
        })
      });
  }

  function _bpsToFraction(uint256 bps) internal pure returns (FixidityLib.Fraction memory) {
    return FixidityLib.newFixedFraction(bps, 10_000);
  }
}
