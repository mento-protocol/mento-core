// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { IntegrationTest } from "./Integration.t.sol";

contract ReserveFPMM is IntegrationTest {
  function test_expansion() public {
    _mintReserveCollateralToken(reserveMultisig, 10_000_000e6);
    _mintCollateralToken(reserveMultisig, 10_000_000e18);

    _provideLiquidityToOneToOneFPMM(reserveMultisig, 10_000_000e6, 5_000_000e18);
    $liquidityStrategies.reserveLiquidityStrategy.rebalance(address($fpmm.fpmmReserve));

    // amountGivenToPool: 2506265664160
    // reserve0 = 10_000_000e6 - 2506265664160
    // reserve1 = 5_000_000e18 + ((2506265664160 * 9950) / 10_000) * 1e12
    assertEq($fpmm.fpmmReserve.reserve0(), 10_000_000e6 - 2506265664160);
    assertEq($fpmm.fpmmReserve.reserve1(), 5_000_000e18 + ((2506265664160 * 9950) / 10_000) * 1e12);
  }

  function test_contraction() public {
    _mintReserveCollateralToken(address($liquidityStrategies.reserve), 10_000_000e6);
    _mintReserveCollateralToken(reserveMultisig, 10_000_000e6);
    _mintCollateralToken(reserveMultisig, 10_000_000e18);

    _provideLiquidityToOneToOneFPMM(reserveMultisig, 5_000_000e6, 10_000_000e18);
    $liquidityStrategies.reserveLiquidityStrategy.rebalance(address($fpmm.fpmmReserve));

    // amountTakenFromPool: 2506265664160401002506265
    // reserve0 = 5_000_000e6 + 2506265664160401002506265 * 9950 / 10000 / 1e12
    // reserve1 = 10_000_000e18 - 2506265664160401002506265
    assertEq($fpmm.fpmmReserve.reserve0(), 5_000_000e6 + uint256(2506265664160401002506265 * 9950) / 1e16);
    assertEq($fpmm.fpmmReserve.reserve1(), 10_000_000e18 - 2506265664160401002506265);
  }
}
