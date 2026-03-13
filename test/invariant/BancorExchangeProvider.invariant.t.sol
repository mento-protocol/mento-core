// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { ERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/ERC20.sol";

import { BancorExchangeProvider } from "contracts/goodDollar/BancorExchangeProvider.sol";
import { IBancorExchangeProvider } from "contracts/interfaces/IBancorExchangeProvider.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";

import { BancorHandler } from "./handlers/BancorHandler.sol";

/**
 * @title BancorExchangeProviderInvariantTest
 * @notice Foundry invariant tests for BancorExchangeProvider.
 *
 * Run with:
 *   forge test --match-contract BancorExchangeProviderInvariant --no-match-contract ForkTest -v
 *
 * Invariants verified:
 *   1. reserveBalance is always > 0 (pool never fully drained)
 *   2. tokenSupply is always > 0 (token supply never fully drained)
 *   3. reserveRatio stays within (0, MAX_WEIGHT] after any sequence of swaps
 *   4. currentPrice() never reverts after valid swaps
 *   5. getAmountOut() >= 1 for non-trivial amountIn (price is always positive)
 */
contract BancorExchangeProviderInvariantTest is Test {
  uint32 constant MAX_WEIGHT = 1e8;

  BancorExchangeProvider provider;
  BancorHandler handler;
  bytes32 exchangeId;

  ERC20 reserveToken;
  ERC20 token;

  address brokerAddress;
  address reserveAddress;

  function setUp() public {
    reserveToken = new ERC20("cUSD", "cUSD");
    token = new ERC20("Good$", "G$");

    brokerAddress = makeAddr("Broker");
    reserveAddress = makeAddr("Reserve");

    // Mock reserve interface calls
    vm.mockCall(
      reserveAddress,
      abi.encodeWithSelector(IReserve(reserveAddress).isStableAsset.selector, address(token)),
      abi.encode(true)
    );
    vm.mockCall(
      reserveAddress,
      abi.encodeWithSelector(IReserve(reserveAddress).isCollateralAsset.selector, address(reserveToken)),
      abi.encode(true)
    );

    // Deploy provider without proxy (disable=false for testing)
    provider = new BancorExchangeProvider(false);
    provider.initialize(brokerAddress, reserveAddress);

    // Create exchange
    IBancorExchangeProvider.PoolExchange memory poolExchange = IBancorExchangeProvider.PoolExchange({
      reserveAsset: address(reserveToken),
      tokenAddress: address(token),
      tokenSupply: 300_000 * 1e18,
      reserveBalance: 60_000 * 1e18,
      reserveRatio: uint32((MAX_WEIGHT * 20) / 100), // 20%
      exitContribution: uint32((MAX_WEIGHT * 1) / 100) // 1%
    });

    vm.prank(provider.owner());
    exchangeId = provider.createExchange(poolExchange);

    // Deploy handler — acts as the broker
    handler = new BancorHandler(provider, exchangeId);

    // Re-point provider's broker to the handler so swapIn/swapOut succeed
    vm.prank(provider.owner());
    provider.setBroker(address(handler));

    targetContract(address(handler));
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Invariant 1: reserveBalance always positive
  // ──────────────────────────────────────────────────────────────────────────

  function invariant_reserveBalance_positive() public view {
    IBancorExchangeProvider.PoolExchange memory ex = provider.getPoolExchange(exchangeId);
    assertGt(ex.reserveBalance, 0, "reserveBalance must be > 0");
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Invariant 2: tokenSupply always positive
  // ──────────────────────────────────────────────────────────────────────────

  function invariant_tokenSupply_positive() public view {
    IBancorExchangeProvider.PoolExchange memory ex = provider.getPoolExchange(exchangeId);
    assertGt(ex.tokenSupply, 0, "tokenSupply must be > 0");
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Invariant 3: reserveRatio within (0, MAX_WEIGHT]
  // ──────────────────────────────────────────────────────────────────────────

  function invariant_reserveRatio_in_bounds() public view {
    IBancorExchangeProvider.PoolExchange memory ex = provider.getPoolExchange(exchangeId);
    assertGt(ex.reserveRatio, 0, "reserveRatio must be > 0");
    assertLe(ex.reserveRatio, MAX_WEIGHT, "reserveRatio must be <= MAX_WEIGHT");
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Invariant 4: currentPrice() does not revert
  // ──────────────────────────────────────────────────────────────────────────

  function invariant_currentPrice_does_not_revert() public view {
    uint256 price = provider.currentPrice(exchangeId);
    assertGt(price, 0, "currentPrice must be > 0");
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Invariant 5: getAmountOut for a small amountIn returns > 0
  // ──────────────────────────────────────────────────────────────────────────

  function invariant_getAmountOut_positive_for_small_in() public view {
    // Probe with 1 unit of reserve (1e18 scaled)
    uint256 amountOut = provider.getAmountOut(exchangeId, address(reserveToken), address(token), 1e18);
    assertGt(amountOut, 0, "getAmountOut must return > 0 for non-trivial amountIn");
  }
}
