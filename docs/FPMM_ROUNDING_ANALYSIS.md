# FPMM Rounding Analysis

This document provides a comprehensive analysis of all rounding points in the FPMM (Fixed-Point Market Maker) pricing functions and recommendations for rounding in favor of the protocol. It also covers how changes to FPMM rounding would affect the rebalancing logic.

## Table of Contents

1. [Overview](#overview)
2. [Current Rounding Behavior](#current-rounding-behavior)
3. [Rounding Points in FPMM](#rounding-points-in-fpmm)
4. [Recommendations: Rounding in Favor of Protocol](#recommendations-rounding-in-favor-of-protocol)
5. [Impact on Rebalancing Logic](#impact-on-rebalancing-logic)
6. [Implementation Considerations](#implementation-considerations)

---

## Overview

The FPMM uses integer arithmetic throughout, which means every division operation truncates (rounds down). This document identifies all points where rounding occurs and analyzes whether the current behavior favors the protocol, the user, or is neutral.

**Protocol-favorable rounding means:**
- Users receive less when withdrawing/swapping out
- Users pay more when depositing/swapping in
- The pool retains more value

---

## Current Rounding Behavior

All division operations in FPMM currently use Solidity's default integer division, which **truncates toward zero** (effectively rounding down for positive numbers).

### Key Files

| File | Purpose |
|------|---------|
| `contracts/swap/FPMM.sol` | Core FPMM implementation |
| `contracts/libraries/LiquidityStrategyTypes.sol` | Rebalancing math helpers |
| `contracts/swap/router/utils/Math.sol` | Math utilities (mulDiv, sqrt) |

---

## Rounding Points in FPMM

### 1. Swap Output Calculation (`getAmountOut`)

**Location:** `FPMM.sol:331-363`

**Function:** `_convertWithRateAndFee`

```solidity
function _convertWithRateAndFee(
    uint256 amount,
    uint256 fromDecimals,
    uint256 toDecimals,
    uint256 numerator,
    uint256 denominator,
    uint256 incentiveNum,
    uint256 incentiveDen
) internal pure returns (uint256) {
    return (amount * numerator * toDecimals * incentiveNum) / (denominator * fromDecimals * incentiveDen);
}
```

**Current Rounding:** DOWN (truncates)

**Analysis:**
- When calculating `amountOut`, rounding down means users receive **less** output
- This **favors the protocol** as the pool retains the rounding dust

**Recommendation:** Keep as-is (already protocol-favorable)

---

### 2. Swap Input Calculation (Implicit)

When users call `swap()` with a desired output, the contract validates that the input provided is sufficient. The validation uses the same `_convertWithRateAndFee` function.

**Location:** `FPMM.sol:866-892` (`_swapCheck`)

**Current Rounding:** DOWN

**Analysis:**
- Fee calculation: `fee = (amountOut * totalFeeBps) / (BASIS_POINTS_DENOMINATOR - totalFeeBps)`
- Rounding down means calculated fees are **less**, potentially allowing slightly underpaid swaps

**Recommendation:** Round UP for fee calculations to ensure protocol always receives full fees

```solidity
// Current (rounds down):
uint256 fee0 = (swapData.amount0Out * totalFeeBps) / (BASIS_POINTS_DENOMINATOR - totalFeeBps);

// Recommended (rounds up):
uint256 fee0 = Math.ceilDiv(swapData.amount0Out * totalFeeBps, BASIS_POINTS_DENOMINATOR - totalFeeBps);
```

---

### 3. Liquidity Provision (`mint`)

**Location:** `FPMM.sol:381-405`

#### 3a. Initial Liquidity (First Deposit)

```solidity
liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
```

**Current Rounding:** DOWN (sqrt uses Newton's method which converges downward)

**Analysis:**
- Rounding down means LP receives **fewer** LP tokens
- The `MINIMUM_LIQUIDITY` (1000 wei) is locked forever, preventing dust attacks
- This **favors the protocol** as LP tokens are slightly undervalued

**Recommendation:** Keep as-is (already protocol-favorable)

#### 3b. Subsequent Liquidity Additions

```solidity
liquidity = Math.min(
    (amount0 * totalSupply_) / $.reserve0,
    (amount1 * totalSupply_) / $.reserve1
);
```

**Current Rounding:** DOWN (both divisions truncate)

**Analysis:**
- Taking the minimum of two truncated values means LP receives the **lower** amount
- This **favors the protocol** as LPs get slightly fewer tokens

**Recommendation:** Keep as-is (already protocol-favorable)

---

### 4. Liquidity Removal (`burn`)

**Location:** `FPMM.sol:410-434`

```solidity
amount0 = (liquidity * balance0) / _totalSupply;
amount1 = (liquidity * balance1) / _totalSupply;
```

**Current Rounding:** DOWN (both divisions truncate)

**Analysis:**
- Rounding down means LP receives **less** of each token
- This **favors the protocol** as the pool retains rounding dust

**Recommendation:** Keep as-is (already protocol-favorable)

---

### 5. Price Calculation (`getPrices`)

**Location:** `FPMM.sol:251-290`

```solidity
reservePriceNumerator = $.reserve1 * (1e18 / $.decimals1);
reservePriceDenominator = $.reserve0 * (1e18 / $.decimals0);
```

**Current Rounding:** DOWN (if decimals > 18, the scaling factor truncates)

**Analysis:**
- This is used for price comparison, not value transfer
- Rounding affects price difference calculations which determine rebalancing thresholds

**Recommendation:** Consider using `mulDiv` for full precision when decimals differ significantly

---

### 6. Price Difference Calculation

**Location:** `FPMM.sol:781-795`

```solidity
priceDifference = (absolutePriceDiff * BASIS_POINTS_DENOMINATOR) / oracleCrossProduct;
```

**Current Rounding:** DOWN

**Analysis:**
- Rounding down means calculated price difference is **smaller**
- This could allow rebalancing to trigger slightly earlier than intended
- Impact is minimal (< 1 basis point)

**Recommendation:** Consider rounding UP to be conservative about when rebalancing is needed

---

### 7. Rebalance Incentive Validation

**Location:** `FPMM.sol:836-859`

```solidity
uint256 minAmount0In = _convertWithRateAndFee(
    swapData.amount1Out,
    $.decimals1,
    $.decimals0,
    swapData.rateDenominator,
    swapData.rateNumerator,
    BASIS_POINTS_DENOMINATOR - $.rebalanceIncentive,
    BASIS_POINTS_DENOMINATOR
);
```

**Current Rounding:** DOWN

**Analysis:**
- `minAmountIn` calculation rounds down, meaning the minimum required input is **lower**
- This could allow rebalancers to provide slightly less than intended
- The code has a comment: "allow for 10 wei difference due to rounding and precision loss"

**Recommendation:** Round UP for minimum input calculations

```solidity
// Recommended: Use mulDiv with rounding up
uint256 minAmount0In = Math.mulDiv(
    swapData.amount1Out * swapData.rateDenominator * $.decimals0,
    BASIS_POINTS_DENOMINATOR - $.rebalanceIncentive,
    swapData.rateNumerator * $.decimals1 * BASIS_POINTS_DENOMINATOR,
    Math.Rounding.Up
);
```

---

### 8. Total Value Calculation

**Location:** `FPMM.sol` (internal function `_totalValueInToken1Scaled`)

Used in swap validation to ensure reserve value doesn't decrease.

**Current Rounding:** DOWN

**Analysis:**
- Rounding down the total value makes the validation more strict
- This **favors the protocol** as it requires slightly more value to pass checks

**Recommendation:** Keep as-is (already protocol-favorable)

---

## Recommendations: Rounding in Favor of Protocol

### Summary Table

| Operation | Current | Recommended | Change Needed |
|-----------|---------|-------------|---------------|
| `getAmountOut` | DOWN | DOWN | No |
| Fee calculation in `_swapCheck` | DOWN | **UP** | **Yes** |
| Initial liquidity (sqrt) | DOWN | DOWN | No |
| Subsequent liquidity mint | DOWN | DOWN | No |
| Liquidity burn amounts | DOWN | DOWN | No |
| Price difference calculation | DOWN | UP | Optional |
| Rebalance min input | DOWN | **UP** | **Yes** |
| Total value calculation | DOWN | DOWN | No |

### Priority Changes

1. **High Priority:** Fee calculations should round UP
2. **High Priority:** Rebalance minimum input should round UP
3. **Medium Priority:** Price difference could round UP for conservative thresholds

### Implementation Pattern

Use the `Math.sol` library's `ceilDiv` or `mulDiv` with `Rounding.Up`:

```solidity
// For simple divisions:
uint256 result = Math.ceilDiv(numerator, denominator);

// For complex mul-then-div:
uint256 result = Math.mulDiv(a, b, c, Math.Rounding.Up);
```

---

## Impact on Rebalancing Logic

The rebalancing logic in `LiquidityStrategy.sol` and `LiquidityStrategyTypes.sol` duplicates some FPMM math. If FPMM rounding changes, the following areas are affected:

### 1. Amount Conversion Functions

**Location:** `LiquidityStrategyTypes.sol:435-445`

```solidity
function convertWithRateScalingAndFee(
    uint256 amount,
    uint256 fromDec,
    uint256 toDec,
    uint256 oracleNum,
    uint256 oracleDen,
    uint256 incentiveNum,
    uint256 incentiveDen
) internal pure returns (uint256) {
    return (amount * oracleNum).mulDiv(toDec * incentiveNum, fromDec * incentiveDen) / oracleDen;
}
```

**Impact if FPMM rounds UP for outputs:**
- Rebalancing calculates `token0In` based on `token1Out` using oracle price
- If FPMM expects more input (due to rounding up), rebalancing must provide more
- The rebalancing calculation should **also round UP** when calculating `amountOwedToPool`

**Recommendation:** Match FPMM's rounding direction:
```solidity
// If calculating amount TO GIVE to pool, round UP
// If calculating amount TO RECEIVE from pool, round DOWN
```

### 2. Target Amount Calculations

**Location:** `LiquidityStrategy.sol:314-351` (`_handlePoolPriceAbove`)
**Location:** `LiquidityStrategy.sol:363-401` (`_handlePoolPriceBelow`)

These functions calculate how much to rebalance to reach the target price.

```solidity
uint256 token1Out = LQ.scaleFromTo(numerator, denominator, 1e18, ctx.token1Dec);
uint256 token0In = LQ.convertWithRateScalingAndFee(...);
```

**Impact if FPMM rounds UP:**
- `token1Out` (amount taken FROM pool) should round DOWN (protocol keeps more)
- `token0In` (amount given TO pool) should round UP (protocol receives more)

**Current behavior:**
- Both round DOWN, which is correct for `token1Out` but not for `token0In`

**Recommendation:**
```solidity
// Taking from pool - round DOWN (user gets less)
uint256 tokenOut = LQ.scaleFromTo(numerator, denominator, 1e18, ctx.tokenOutDec);

// Giving to pool - round UP (user pays more)
uint256 tokenIn = LQ.convertWithRateScalingAndFeeRoundUp(...);
```

### 3. Incentive Calculations

**Location:** `LiquidityStrategyTypes.sol:453-465`

```solidity
function mulBps(uint256 amount, uint256 bps) internal pure returns (uint256) {
    return (amount * bps) / BASIS_POINTS_DENOMINATOR;
}
```

**Impact:**
- Protocol incentives are calculated by multiplying amount by basis points
- Rounding down means protocol receives **less** incentive

**Recommendation:** Round UP for protocol fee calculations:
```solidity
function mulBpsUp(uint256 amount, uint256 bps) internal pure returns (uint256) {
    return Math.ceilDiv(amount * bps, BASIS_POINTS_DENOMINATOR);
}
```

### 4. FPMM Validation Alignment

When FPMM validates a rebalance in `_rebalanceCheck`, it calculates `minAmountIn` and compares against actual input.

**Critical alignment issue:**
- If rebalancing calculates `amountIn` rounding DOWN
- But FPMM validates `minAmountIn` rounding UP
- The rebalance could fail validation

**Solution:** Ensure rebalancing always provides AT LEAST what FPMM expects:
```solidity
// In rebalancing: calculate what we'll provide
uint256 amountIn = calculateAmountIn(..., Rounding.Up);

// In FPMM: calculate minimum required
uint256 minAmountIn = calculateMinAmountIn(..., Rounding.Up);

// Validation passes: amountIn >= minAmountIn
```

### 5. Decimal Scaling

**Location:** `LiquidityStrategyTypes.sol:360-373`

```solidity
function to1e18(uint256 amount, uint256 tokenDecimalsFactor) internal pure returns (uint256) {
    return amount * (1e18 / tokenDecimalsFactor);
}

function from1e18(uint256 amount18, uint256 tokenDecimalsFactor) internal pure returns (uint256) {
    return amount18 / (1e18 / tokenDecimalsFactor);
}
```

**Impact:**
- `to1e18`: Scaling up, no rounding (multiplication only)
- `from1e18`: Scaling down, truncates

**Recommendation:** Add rounding-aware variants:
```solidity
function from1e18Up(uint256 amount18, uint256 tokenDecimalsFactor) internal pure returns (uint256) {
    return Math.ceilDiv(amount18, 1e18 / tokenDecimalsFactor);
}
```

---

## Implementation Considerations

### 1. Gas Costs

Using `Math.ceilDiv` or `Math.mulDiv` with rounding adds ~20-50 gas per operation. For swap-heavy operations, this could be noticeable but is generally acceptable for correctness.

### 2. Consistency

All related calculations must use consistent rounding:
- If FPMM rounds UP for fee calculations, all fee-related code must match
- Mismatched rounding between FPMM and rebalancing will cause validation failures

### 3. Testing

Changes require comprehensive testing:
- Fuzz tests with extreme values to catch edge cases
- Invariant tests ensuring protocol never loses value
- Integration tests verifying rebalancing still works

### 4. Migration

If deployed contracts need updating:
- New FPMM implementation via upgrade
- Rebalancing strategies may need redeployment
- Consider backward compatibility during transition

---

## Implementation Challenges Discovered

During an attempt to implement the recommended rounding changes, several challenges were discovered that require careful consideration:

### 1. Fee Calculation in `_swapCheck`

**Attempted change:** Round UP fee calculations to ensure protocol receives full fees.

**Problem encountered:** This made the validation TOO strict. The swap output (`getAmountOut`) already rounds DOWN, meaning users receive less - this IS the fee being captured implicitly. Rounding UP the expected fee in `_swapCheck` created a mismatch where the check expected more value than the swap actually produced.

**Resolution:** Keep fee calculation rounding DOWN. The protocol already benefits from `getAmountOut` rounding DOWN.

### 2. Rebalance `minAmountIn` Calculation

**Attempted change:** Round UP the minimum input calculation so rebalancers must provide at least the expected amount.

**Problem encountered:** When FPMM rounds UP for `minAmountIn` but rebalancing calculates `tokenIn` rounding DOWN:
- `tokenIn (rounded down) < minAmountIn (rounded up)` → Validation fails

Additionally, when rebalancing rounds UP for `tokenIn`:
- The rebalancer provides MORE value than calculated for the target price
- This pushes the price FURTHER than the target threshold
- Triggers `PriceDifferenceMovedTooFarFromThresholds` error

### 3. Interconnected Validation Constraints

The rebalancing system has multiple validation constraints that interact:

1. **Price movement constraint:** Price must move toward oracle but not past threshold
2. **Incentive constraint:** Rebalancer must provide at least `minAmountIn`
3. **Reserve value constraint:** Pool value must not decrease beyond incentive allowance

Changing rounding in one constraint affects the others:
- Rounding UP `minAmountIn` → requires more input
- More input → more price movement
- More price movement → potentially exceeds threshold

### 4. Current Tolerance Mechanism

The existing code has built-in tolerance:
```solidity
// allow for 10 wei difference due to rounding and precision loss
if (swapData.amount0In < minAmount0In) revert InsufficientAmount0In();
```

This tolerance was designed to handle the rounding discrepancies. Any changes to rounding behavior must consider this tolerance.

### Recommended Approach

Given these challenges, implementing rounding changes requires:

1. **Holistic design:** All rounding changes must be designed together, not incrementally
2. **Tolerance adjustment:** May need to add/adjust tolerance values to accommodate rounding differences
3. **Simulation:** Run extensive simulations with various decimal combinations before implementation
4. **Incremental rollout:** Consider implementing changes in phases with careful testing between each

---

## Conclusion

The current FPMM implementation largely rounds in favor of the protocol for value-transfer operations (swaps, mints, burns). The main areas needing attention are:

1. **Fee calculations** - Already effectively protocol-favorable due to `getAmountOut` rounding DOWN
2. **Rebalance validation** - Minimum input calculations could round UP, but requires coordinated changes
3. **Rebalancing math** - Must be designed holistically with FPMM validation

**Important:** Implementing rounding changes is more complex than initially anticipated due to the interconnected nature of FPMM validation constraints. Changes should be designed and tested holistically rather than incrementally to avoid cascading failures.
