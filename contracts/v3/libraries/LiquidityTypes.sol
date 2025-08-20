// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

/**
 * @title LiquidityTypes
 * @author Mento Labs
 * @notice Shared types and helpers for the Liquidity Controller, Policies & Strategies.
 */
library LiquidityTypes {
  /* ============================================================ */
  /* ====================== Constants =========================== */
  /* ============================================================ */

  uint256 public constant BASIS_POINTS_DENOMINATOR = 10_000;

  /* ============================================================ */
  /* ======================= Enums ============================== */
  /* ============================================================ */

  /**
   * @notice Indicates how the pool should be rebalanced relative to the oracle price.
   * @dev
   * - Expand:   Pool price > oracle price (PP > P).
   *             Rebalance by moving debt tokens into the pool and taking collateral out.
   * - Contract: Pool price < oracle price (PP < P).
   *             Rebalance by moving collateral into the pool and taking debt tokens out.
   */
  enum Direction {
    Expand,
    Contract
  }

  /// TODO: Could get granular with the sources if necessary (e.g. StabilityPool, CollateralRegistry) ?

  /// @notice Indicates where the liquidity comes from
  enum LiquiditySource {
    Reserve,
    CDP
  }

  /* ============================================================ */
  /* ======================= Structs ============================ */
  /* ============================================================ */

  /// @notice Struct to store the reserves of the FPMM pool
  struct Reserves {
    uint256 debt;
    uint256 collateral;
  }

  /// @notice Price snapshot and deviation info
  struct Prices {
    uint256 oracleNum;
    uint256 oracleDen;
    bool poolPriceAbove;
    uint256 diffBps; // PP - P in bps
  }

  /// @notice Read-only context provided by the controller to a policy
  struct Context {
    address pool;
    Reserves reserves;
    Prices prices;
    uint256 incentiveBps; // min(strategy cap, pool cap)
    uint256 decDebt;
    uint256 decCollateral;
    address debtToken;
    address collateralToken;
  }

  /**
   * @notice A single rebalance step produced by a policy
   * @dev inputAmount is the amount moved into the pool before incentive fee
   */
  struct Action {
    address pool;
    Direction dir;
    LiquiditySource liquiditySource;
    uint256 debtOut; // amount of debt tokens to move out of pool
    uint256 collateralOut; // amount of collateral to move out of pool
    uint256 inputAmount; // amount moved into pool (pre-incentive)
    uint256 incentiveBps; // incentive bps applied to inputAmount
    bytes data; // strategy-specific data (optional)
  }

  /// @notice Standard payload used by strategies for FPMM callback encoding
  struct CallbackData {
    uint256 inputAmount;
    Direction dir;
    uint256 incentiveAmount;
    LiquiditySource liquiditySource;
    bool isToken0Debt;
    bytes extra; // extra strategy-specific data (optional)
  }

  /* ============================================================ */
  /* =================== Helper Functions ======================= */
  /* ============================================================ */

  /**
   * @notice Normalize a token amount to 18 decimals given its raw decimal factor.
   * @param amount raw token units
   * @param tokenDecimalsFactor 10**decimals (e.g., 1e6 for USDC, 1e18 for Mento tokens)
   * @dev There is no guard on tokenDecimalsFactor as it's expected that this function is used on context
   *      data that has been validated by the LiquidityController. If necessary, guard at the caller site.
   */
  function to1e18(uint256 amount, uint256 tokenDecimalsFactor) internal pure returns (uint256) {
    return amount * (1e18 / tokenDecimalsFactor);
  }

  /**
   * @notice Convert a 18d-normalized amount back to raw token units.
   * @param amount18 18d-normalized token units
   * @param tokenDecimalsFactor 10**decimals (e.g., 1e6 for USDC, 1e18 for Mento tokens)
   * @dev There is no guard on tokenDecimalsFactor as it's expected that this function is used on context
   *      data that has been validated by the LiquidityController. If necessary, guard at the caller site.
   */
  function from1e18(uint256 amount18, uint256 tokenDecimalsFactor) internal pure returns (uint256) {
    return amount18 / (1e18 / tokenDecimalsFactor);
  }

  /// @notice Calc an amount in bps.
  function mulBps(uint256 amount, uint256 bps) internal pure returns (uint256) {
    return (amount * bps) / BASIS_POINTS_DENOMINATOR;
  }

  /// @notice Incentive amount for a given input and bps.
  function incentiveAmount(uint256 inputAmount, uint256 incentiveBps) internal pure returns (uint256) {
    return mulBps(inputAmount, incentiveBps);
  }

  /// @notice Encode standard callback payload used by strategies in FPMM.rebalance hooks.
  function encodeCallback(CallbackData memory c) internal pure returns (bytes memory) {
    return abi.encode(c.inputAmount, c.dir, c.incentiveAmount, c.liquiditySource, c.isToken0Debt, c.extra);
  }

  /// @notice Decode standard callback payload used by strategies.
  function decodeCallback(bytes calldata data) internal pure returns (CallbackData memory c) {
    (c.inputAmount, c.dir, c.incentiveAmount, c.liquiditySource, c.isToken0Debt, c.extra) = abi.decode(
      data,
      (uint256, Direction, uint256, LiquiditySource, bool, bytes)
    );
  }

  /// @notice Convert debt/collateral amounts to token order based on isToken0Debt.
  function toTokenOrder(
    uint256 debtOut,
    uint256 collateralOut,
    bool isToken0Debt
  ) internal pure returns (uint256 amount0Out, uint256 amount1Out) {
    if (isToken0Debt) return (debtOut, collateralOut);
    return (collateralOut, debtOut);
  }

  /// @notice Convert token order amounts back to debt/collateral based on isToken0Debt.
  function fromTokenOrder(
    uint256 amount0Out,
    uint256 amount1Out,
    bool isToken0Debt
  ) internal pure returns (uint256 debtOut, uint256 collateralOut) {
    if (isToken0Debt) return (amount0Out, amount1Out);
    return (amount1Out, amount0Out);
  }
}
