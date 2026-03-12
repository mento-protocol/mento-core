// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { Test } from "forge-std/Test.sol";
import { BancorFormula } from "contracts/goodDollar/BancorFormula.sol";

/**
 * @notice Test harness that exposes BancorFormula's internal functions as external
 *         so they can be called from the test contract.
 *         Note: BancorFormula's functions are internal non-virtual, so the harness
 *         exposes them via differently-named wrappers rather than overrides.
 */
contract BancorFormulaHarness is BancorFormula {
  constructor() {
    init();
  }

  function exposed_purchaseTargetAmount(
    uint256 supply,
    uint256 reserveBalance,
    uint32 reserveWeight,
    uint256 amount
  ) external view returns (uint256) {
    return purchaseTargetAmount(supply, reserveBalance, reserveWeight, amount);
  }

  function exposed_saleTargetAmount(
    uint256 supply,
    uint256 reserveBalance,
    uint32 reserveWeight,
    uint256 amount
  ) external view returns (uint256) {
    return saleTargetAmount(supply, reserveBalance, reserveWeight, amount);
  }

  function exposed_saleCost(
    uint256 supply,
    uint256 reserveBalance,
    uint32 reserveWeight,
    uint256 amount
  ) external view returns (uint256) {
    return saleCost(supply, reserveBalance, reserveWeight, amount);
  }

  function exposed_fundCost(
    uint256 supply,
    uint256 reserveBalance,
    uint32 reserveRatio,
    uint256 amount
  ) external view returns (uint256) {
    return fundCost(supply, reserveBalance, reserveRatio, amount);
  }
}

/**
 * @title BancorFormulaTest
 * @notice Isolated unit tests for BancorFormula's four public-facing formulas:
 *         purchaseTargetAmount, saleTargetAmount, saleCost, and fundCost.
 *
 *         Tests cover:
 *         - Special-case branches (zero amount, full supply/reserve, 100% weight)
 *         - Input validation (zero supply/reserve, invalid weight, amount > supply)
 *         - Directional sanity (more deposit → more tokens; bigger sell → more reserve out)
 *         - Inverse consistency (sale undoes a purchase up to rounding)
 *         - Fuzz coverage of edge values
 */
contract BancorFormulaTest is Test {
  BancorFormulaHarness public formula;

  uint32 public constant MAX_WEIGHT = 100_000_000;

  // Representative pool: supply=300k, reserveBalance=60k, reserveWeight=20%
  uint256 public constant SUPPLY = 300_000e18;
  uint256 public constant RESERVE = 60_000e18;
  uint32 public constant WEIGHT_20 = uint32(MAX_WEIGHT / 5); // 20%
  uint32 public constant WEIGHT_50 = uint32(MAX_WEIGHT / 2); // 50%

  function setUp() public {
    formula = new BancorFormulaHarness();
  }

  // ================================================================
  // purchaseTargetAmount
  // ================================================================

  function test_purchaseTargetAmount_zeroDepositReturnsZero() public view {
    uint256 result = formula.exposed_purchaseTargetAmount(SUPPLY, RESERVE, WEIGHT_20, 0);
    assertEq(result, 0);
  }

  function test_purchaseTargetAmount_maxWeight_usesLinearFormula() public view {
    // At 100% weight: tokens_out = supply * amount / reserveBalance
    uint256 amount = 10_000e18;
    uint256 result = formula.exposed_purchaseTargetAmount(SUPPLY, RESERVE, MAX_WEIGHT, amount);
    uint256 expected = (SUPPLY * amount) / RESERVE;
    assertEq(result, expected);
  }

  function test_purchaseTargetAmount_normalCase_returnsPositive() public view {
    uint256 amount = 6_000e18; // 10% of reserve
    uint256 result = formula.exposed_purchaseTargetAmount(SUPPLY, RESERVE, WEIGHT_20, amount);
    assertGt(result, 0);
  }

  function test_purchaseTargetAmount_largerDeposit_yieldsDiminishingReturns() public view {
    // Bancor AMM: returns are sub-linear (diminishing returns) at weight < 100%
    uint256 small = formula.exposed_purchaseTargetAmount(SUPPLY, RESERVE, WEIGHT_20, 1_000e18);
    uint256 large = formula.exposed_purchaseTargetAmount(SUPPLY, RESERVE, WEIGHT_20, 2_000e18);
    // large must be > small but < 2 * small (diminishing returns)
    assertGt(large, small);
    assertLt(large, 2 * small);
  }

  function test_purchaseTargetAmount_revertOnZeroSupply() public {
    vm.expectRevert("ERR_INVALID_SUPPLY");
    formula.exposed_purchaseTargetAmount(0, RESERVE, WEIGHT_20, 1e18);
  }

  function test_purchaseTargetAmount_revertOnZeroReserve() public {
    vm.expectRevert("ERR_INVALID_RESERVE_BALANCE");
    formula.exposed_purchaseTargetAmount(SUPPLY, 0, WEIGHT_20, 1e18);
  }

  function test_purchaseTargetAmount_revertOnZeroWeight() public {
    vm.expectRevert("ERR_INVALID_RESERVE_WEIGHT");
    formula.exposed_purchaseTargetAmount(SUPPLY, RESERVE, 0, 1e18);
  }

  function test_purchaseTargetAmount_revertOnWeightAboveMax() public {
    vm.expectRevert("ERR_INVALID_RESERVE_WEIGHT");
    formula.exposed_purchaseTargetAmount(SUPPLY, RESERVE, MAX_WEIGHT + 1, 1e18);
  }

  // ================================================================
  // saleTargetAmount
  // ================================================================

  function test_saleTargetAmount_zeroAmountReturnsZero() public view {
    uint256 result = formula.exposed_saleTargetAmount(SUPPLY, RESERVE, WEIGHT_20, 0);
    assertEq(result, 0);
  }

  function test_saleTargetAmount_fullSupplyReturnsFullReserve() public view {
    // Selling the entire supply returns the entire reserve balance
    uint256 result = formula.exposed_saleTargetAmount(SUPPLY, RESERVE, WEIGHT_20, SUPPLY);
    assertEq(result, RESERVE);
  }

  function test_saleTargetAmount_maxWeight_usesLinearFormula() public view {
    // At 100% weight: reserve_out = reserveBalance * amount / supply
    uint256 sellAmount = 30_000e18;
    uint256 result = formula.exposed_saleTargetAmount(SUPPLY, RESERVE, MAX_WEIGHT, sellAmount);
    uint256 expected = (RESERVE * sellAmount) / SUPPLY;
    assertEq(result, expected);
  }

  function test_saleTargetAmount_normalCase_returnsPositive() public view {
    uint256 sellAmount = 30_000e18; // 10% of supply
    uint256 result = formula.exposed_saleTargetAmount(SUPPLY, RESERVE, WEIGHT_20, sellAmount);
    assertGt(result, 0);
    assertLt(result, RESERVE); // must not drain the whole reserve
  }

  function test_saleTargetAmount_revertWhenAmountExceedsSupply() public {
    vm.expectRevert("ERR_INVALID_AMOUNT");
    formula.exposed_saleTargetAmount(SUPPLY, RESERVE, WEIGHT_20, SUPPLY + 1);
  }

  function test_saleTargetAmount_revertOnZeroSupply() public {
    vm.expectRevert("ERR_INVALID_SUPPLY");
    formula.exposed_saleTargetAmount(0, RESERVE, WEIGHT_20, 0);
  }

  function test_saleTargetAmount_revertOnZeroReserve() public {
    vm.expectRevert("ERR_INVALID_RESERVE_BALANCE");
    formula.exposed_saleTargetAmount(SUPPLY, 0, WEIGHT_20, 1e18);
  }

  // ================================================================
  // saleCost (inverse of saleTargetAmount)
  // ================================================================

  function test_saleCost_zeroAmountReturnsZero() public view {
    uint256 result = formula.exposed_saleCost(SUPPLY, RESERVE, WEIGHT_20, 0);
    assertEq(result, 0);
  }

  function test_saleCost_fullReserveReturnsFullSupply() public view {
    // Withdrawing the entire reserve costs the full supply
    uint256 result = formula.exposed_saleCost(SUPPLY, RESERVE, WEIGHT_20, RESERVE);
    assertEq(result, SUPPLY);
  }

  function test_saleCost_maxWeight_usesLinearFormula() public view {
    // At 100% weight: tokens_in = supply * amount / reserveBalance, rounded up
    uint256 reserveOut = 6_000e18;
    uint256 result = formula.exposed_saleCost(SUPPLY, RESERVE, MAX_WEIGHT, reserveOut);
    // Expected (ceiling): supply * reserveOut / reserveBalance
    uint256 expected = (SUPPLY * reserveOut - 1) / RESERVE + 1;
    assertEq(result, expected);
  }

  function test_saleCost_normalCase_returnsPositive() public view {
    uint256 reserveOut = 6_000e18; // 10% of reserve
    uint256 result = formula.exposed_saleCost(SUPPLY, RESERVE, WEIGHT_20, reserveOut);
    assertGt(result, 0);
    assertLt(result, SUPPLY); // doesn't consume the whole supply
  }

  function test_saleCost_revertWhenAmountExceedsReserve() public {
    vm.expectRevert("ERR_INVALID_AMOUNT");
    formula.exposed_saleCost(SUPPLY, RESERVE, WEIGHT_20, RESERVE + 1);
  }

  function test_saleCost_roundsUp() public view {
    // saleCost should round up to protect the protocol
    uint256 smallReserveOut = 1; // 1 wei
    uint256 cost = formula.exposed_saleCost(SUPPLY, RESERVE, MAX_WEIGHT, smallReserveOut);
    // ceil(SUPPLY * 1 / RESERVE) >= 1
    assertGe(cost, 1);
  }

  // ================================================================
  // fundCost
  // ================================================================

  function test_fundCost_zeroAmountReturnsZero() public view {
    uint256 result = formula.exposed_fundCost(SUPPLY, RESERVE, WEIGHT_20 * 2, 0);
    assertEq(result, 0);
  }

  function test_fundCost_maxWeight_usesLinearFormula() public view {
    uint256 poolTokensWanted = 30_000e18;
    // At reserveRatio == MAX_WEIGHT: cost = ceil(amount * reserveBalance / supply)
    uint256 result = formula.exposed_fundCost(SUPPLY, RESERVE, MAX_WEIGHT, poolTokensWanted);
    uint256 expected = (poolTokensWanted * RESERVE - 1) / SUPPLY + 1;
    assertEq(result, expected);
  }

  function test_fundCost_normalCase_returnsPositive() public view {
    uint256 poolTokensWanted = 30_000e18; // 10% of supply
    uint256 result = formula.exposed_fundCost(SUPPLY, RESERVE, WEIGHT_20 * 2, poolTokensWanted);
    assertGt(result, 0);
  }

  function test_fundCost_revertOnZeroSupply() public {
    vm.expectRevert("ERR_INVALID_SUPPLY");
    formula.exposed_fundCost(0, RESERVE, WEIGHT_20 * 2, 1e18);
  }

  function test_fundCost_revertOnZeroReserve() public {
    vm.expectRevert("ERR_INVALID_RESERVE_BALANCE");
    formula.exposed_fundCost(SUPPLY, 0, WEIGHT_20 * 2, 1e18);
  }

  function test_fundCost_revertOnInvalidReserveRatio() public {
    // reserveRatio must be > 1
    vm.expectRevert("ERR_INVALID_RESERVE_RATIO");
    formula.exposed_fundCost(SUPPLY, RESERVE, 1, 1e18);
  }

  // ================================================================
  // Fuzz: purchase/sale directional consistency
  // ================================================================

  function testFuzz_purchaseTargetAmount_positiveMonotone(uint256 amount1, uint256 amount2) public view {
    // Larger deposit always yields more tokens (or equal at 0)
    amount1 = bound(amount1, 1, 1e24);
    amount2 = bound(amount2, amount1 + 1, 2e24);

    uint256 out1 = formula.exposed_purchaseTargetAmount(SUPPLY, RESERVE, WEIGHT_20, amount1);
    uint256 out2 = formula.exposed_purchaseTargetAmount(SUPPLY, RESERVE, WEIGHT_20, amount2);
    assertGe(out2, out1);
  }

  function testFuzz_saleTargetAmount_positiveMonotone(uint256 sell1, uint256 sell2) public view {
    // Cap at 90% of supply — the general formula path overflows near 100% supply (the exact
    // 100% case is handled by a special branch tested in test_saleTargetAmount_fullSupplyReturnsFullReserve).
    // Minimum of 1e15 avoids sub-precision degenerate cases where amount/supply rounds to 0.
    uint256 maxSell = (SUPPLY * 9) / 10;
    sell1 = bound(sell1, 1e15, maxSell - 1e15);
    sell2 = bound(sell2, sell1 + 1e15, maxSell);

    uint256 out1 = formula.exposed_saleTargetAmount(SUPPLY, RESERVE, WEIGHT_20, sell1);
    uint256 out2 = formula.exposed_saleTargetAmount(SUPPLY, RESERVE, WEIGHT_20, sell2);
    assertGe(out2, out1);
  }

  function testFuzz_saleCost_roundsUp(uint256 reserveOut) public view {
    // saleCost must always be >= saleTargetAmount inverse (i.e. cost >= what you'd get back)
    // Minimum of 1e15 avoids sub-precision cases where the formula underflows.
    reserveOut = bound(reserveOut, 1e15, RESERVE / 2);

    uint256 cost = formula.exposed_saleCost(SUPPLY, RESERVE, WEIGHT_50, reserveOut);
    uint256 roundTrip = formula.exposed_saleTargetAmount(SUPPLY, RESERVE, WEIGHT_50, cost);
    // Selling `cost` tokens should yield at least `reserveOut` (saleCost rounds up)
    assertGe(roundTrip, reserveOut);
  }

  function testFuzz_purchaseSale_maxWeight_isLinear(uint256 amount) public view {
    // At MAX_WEIGHT both functions use simple division — verify linearity holds
    amount = bound(amount, 1, RESERVE / 2);
    uint256 tokensOut = formula.exposed_purchaseTargetAmount(SUPPLY, RESERVE, MAX_WEIGHT, amount);
    uint256 reserveBack = formula.exposed_saleTargetAmount(SUPPLY + tokensOut, RESERVE + amount, MAX_WEIGHT, tokensOut);
    // Should recover at most the original deposit (no rounding gain)
    assertLe(reserveBack, amount);
  }
}
