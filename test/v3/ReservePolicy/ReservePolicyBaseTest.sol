// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { Test } from "mento-std/Test.sol";
import { ReservePolicy } from "contracts/v3/ReservePolicy.sol";
import { LiquidityTypes as LQ } from "contracts/v3/libraries/LiquidityTypes.sol";

contract ReservePolicyBaseTest is Test {
  ReservePolicy public reservePolicy;

  address public constant POOL = address(0x1);
  address public constant DEBT_TOKEN = address(0x2);
  address public constant COLLATERAL_TOKEN = address(0x3);

  struct DecimalTest {
    uint256 debtDec;
    uint256 collateralDec;
    uint256 expectedScaleFactor;
  }

  function setUp() public virtual {
    reservePolicy = new ReservePolicy();
  }

  /* ============================================================ */
  /* ================= Helper Functions ========================= */
  /* ============================================================ */

  function _createContext(
    uint256 reserveDen,  // token0 reserves (denominator in pool price)
    uint256 reserveNum,  // token1 reserves (numerator in pool price)
    uint256 oracleNum,
    uint256 oracleDen,
    bool poolPriceAbove,
    uint256 incentiveBps
  ) internal pure returns (LQ.Context memory) {
    return
      _createContextWithDecimals(
        reserveDen,
        reserveNum,
        oracleNum,
        oracleDen,
        poolPriceAbove,
        incentiveBps,
        1e18, // 18 decimals for token0
        1e18 // 18 decimals for token1
      );
  }

  function _createContextWithDecimals(
    uint256 reserveDen,  // token0 reserves (denominator in pool price)
    uint256 reserveNum,  // token1 reserves (numerator in pool price) 
    uint256 oracleNum,
    uint256 oracleDen,
    bool poolPriceAbove,
    uint256 incentiveBps,
    uint256 token0Dec,
    uint256 token1Dec
  ) internal pure returns (LQ.Context memory) {
    return
      LQ.Context({
        pool: POOL,
        reserves: LQ.Reserves({ reserveNum: reserveNum, reserveDen: reserveDen }),
        prices: LQ.Prices({
          oracleNum: oracleNum,
          oracleDen: oracleDen,
          poolPriceAbove: poolPriceAbove,
          diffBps: 0 // Not used in ReservePolicy
        }),
        incentiveBps: uint128(incentiveBps),
        token0Dec: uint64(token0Dec),
        token1Dec: uint64(token1Dec),
        token0: DEBT_TOKEN,
        token1: COLLATERAL_TOKEN,
        isToken0Debt: true
      });
  }

  function _createContextWithTokenOrder(
    uint256 reserveDen,
    uint256 reserveNum,
    uint256 oracleNum,
    uint256 oracleDen,
    bool poolPriceAbove,
    uint256 incentiveBps,
    bool isToken0Debt
  ) internal pure returns (LQ.Context memory) {
    return
      LQ.Context({
        pool: POOL,
        reserves: LQ.Reserves({ reserveNum: reserveNum, reserveDen: reserveDen }),
        prices: LQ.Prices({
          oracleNum: oracleNum,
          oracleDen: oracleDen,
          poolPriceAbove: poolPriceAbove,
          diffBps: 0
        }),
        incentiveBps: uint128(incentiveBps),
        token0Dec: 1e18,
        token1Dec: 1e18,
        token0: isToken0Debt ? DEBT_TOKEN : COLLATERAL_TOKEN,
        token1: isToken0Debt ? COLLATERAL_TOKEN : DEBT_TOKEN,
        isToken0Debt: isToken0Debt
      });
  }
}