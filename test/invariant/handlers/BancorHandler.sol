// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase
pragma solidity 0.8.19;

import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { StdUtils } from "forge-std/StdUtils.sol";

import { BancorExchangeProvider } from "contracts/goodDollar/BancorExchangeProvider.sol";
import { IBancorExchangeProvider } from "contracts/interfaces/IBancorExchangeProvider.sol";

/**
 * @title BancorHandler
 * @notice Handler for BancorExchangeProvider invariant tests.
 * Acts as the broker — calls swapIn/swapOut with bounded random inputs.
 * Ghost variables track total reserve in and token out for ratio assertions.
 */
contract BancorHandler is CommonBase, StdCheats, StdUtils {
  BancorExchangeProvider public provider;
  bytes32 public exchangeId;
  address public reserveAsset;
  address public tokenAddress;

  uint256 public totalSwapsIn; // reserve → token swaps
  uint256 public totalSwapsOut; // token → reserve swaps

  constructor(BancorExchangeProvider _provider, bytes32 _exchangeId) {
    provider = _provider;
    exchangeId = _exchangeId;
    IBancorExchangeProvider.PoolExchange memory ex = _provider.getPoolExchange(_exchangeId);
    reserveAsset = ex.reserveAsset;
    tokenAddress = ex.tokenAddress;
  }

  /**
   * @notice Swap reserve asset in for token (buy).
   * Bounded to avoid exhausting reserves.
   */
  function swapIn_reserveForToken(uint256 amountIn) external {
    IBancorExchangeProvider.PoolExchange memory ex = provider.getPoolExchange(exchangeId);
    // Bound to at most 1% of current reserve balance to keep pool alive
    uint256 maxIn = ex.reserveBalance / 100 + 1;
    amountIn = bound(amountIn, 1, maxIn);

    vm.prank(address(this)); // this contract IS the broker
    try provider.swapIn(exchangeId, reserveAsset, tokenAddress, amountIn) {
      totalSwapsIn++;
    } catch {
      // Revert is acceptable (e.g. amountOut == 0)
    }
  }

  /**
   * @notice Swap token in for reserve asset (sell).
   * Bounded to avoid draining the token supply entirely.
   */
  function swapIn_tokenForReserve(uint256 amountIn) external {
    IBancorExchangeProvider.PoolExchange memory ex = provider.getPoolExchange(exchangeId);
    // Bound to at most 0.5% of token supply to keep the pool alive
    uint256 maxIn = ex.tokenSupply / 200 + 1;
    amountIn = bound(amountIn, 1, maxIn);

    vm.prank(address(this));
    try provider.swapIn(exchangeId, tokenAddress, reserveAsset, amountIn) {
      totalSwapsOut++;
    } catch {
      // Acceptable (e.g. insufficient reserve)
    }
  }
}
