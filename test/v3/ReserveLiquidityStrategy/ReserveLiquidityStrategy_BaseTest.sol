// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { LiquidityStrategy_BaseTest } from "../LiquidityStrategy/LiquidityStrategy_BaseTest.sol";
import { ReserveLiquidityStrategyHarness } from "test/utils/harnesses/ReserveLiquidityStrategyHarness.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/libraries/LiquidityStrategyTypes.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";

contract ReserveLiquidityStrategy_BaseTest is LiquidityStrategy_BaseTest {
  ReserveLiquidityStrategyHarness public strategy;

  // Mock addresses
  address public reserve = makeAddr("Reserve");

  function setUp() public virtual override {
    LiquidityStrategy_BaseTest.setUp();
    strategy = new ReserveLiquidityStrategyHarness(owner, reserve);
    strategyAddr = address(strategy);
  }

  modifier addFpmm(uint64 cooldown, uint32 incentiveBps) {
    // Mock reserve to recognize debt token as stable asset and collateral token as collateral asset
    mockReserveStable(debtToken, true);
    mockReserveStable(collToken, false);
    mockReserveCollateral(debtToken, false);
    mockReserveCollateral(collToken, true);

    // Set FPMM rebalance incentive cap to match or exceed strategy incentive
    // Note: FPMM has a maximum cap, typically 1000 bps (10%)
    uint32 fpmmIncentive = incentiveBps > 1000 ? 1000 : incentiveBps;
    fpmm.setRebalanceIncentive(fpmmIncentive);

    vm.prank(owner);
    strategy.addPool(address(fpmm), debtToken, cooldown, incentiveBps);
    _;
  }

  /* ============================================================ */
  /* ================= Helper Functions ========================= */
  /* ============================================================ */

  /**
   * @notice Mock reserve to recognize an asset as collateral
   * @param asset The asset address
   * @param isCollateral Whether the asset is collateral
   */
  function mockReserveCollateral(address asset, bool isCollateral) internal {
    vm.mockCall(reserve, abi.encodeWithSelector(IReserve.isCollateralAsset.selector, asset), abi.encode(isCollateral));
  }

  /**
   * @notice Mock reserve to recognize an asset as stable
   * @param asset The asset address
   * @param isStable Whether the asset is stable
   */
  function mockReserveStable(address asset, bool isStable) internal {
    vm.mockCall(reserve, abi.encodeWithSelector(IReserve.isStableAsset.selector, asset), abi.encode(isStable));
  }

  /**
   * @notice Create a liquidity context for testing
   * @param reserveDen token0 reserves (denominator in pool price)
   * @param reserveNum token1 reserves (numerator in pool price)
   * @param oracleNum Oracle price numerator
   * @param oracleDen Oracle price denominator
   * @param poolPriceAbove Whether pool price is above oracle price
   * @param incentiveBps Incentive in basis points
   */
  function _createContext(
    uint256 reserveDen,
    uint256 reserveNum,
    uint256 oracleNum,
    uint256 oracleDen,
    bool poolPriceAbove,
    uint256 incentiveBps
  ) internal view returns (LQ.Context memory) {
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

  /**
   * @notice Create a liquidity context with custom decimals
   */
  function _createContextWithDecimals(
    uint256 reserveDen,
    uint256 reserveNum,
    uint256 oracleNum,
    uint256 oracleDen,
    bool poolPriceAbove,
    uint256 incentiveBps,
    uint256 token0Dec,
    uint256 token1Dec
  ) internal view returns (LQ.Context memory) {
    return
      LQ.Context({
        pool: address(fpmm),
        reserves: LQ.Reserves({ reserveNum: reserveNum, reserveDen: reserveDen }),
        prices: LQ.Prices({ oracleNum: oracleNum, oracleDen: oracleDen, poolPriceAbove: poolPriceAbove, diffBps: 0 }),
        incentiveBps: uint128(incentiveBps),
        token0Dec: uint64(token0Dec),
        token1Dec: uint64(token1Dec),
        token0: debtToken,
        token1: collToken,
        isToken0Debt: true
      });
  }

  /**
   * @notice Create a liquidity context with custom token order
   */
  function _createContextWithTokenOrder(
    uint256 reserveDen,
    uint256 reserveNum,
    uint256 oracleNum,
    uint256 oracleDen,
    bool poolPriceAbove,
    uint256 incentiveBps,
    bool isToken0Debt
  ) internal view returns (LQ.Context memory) {
    return
      LQ.Context({
        pool: address(fpmm),
        reserves: LQ.Reserves({ reserveNum: reserveNum, reserveDen: reserveDen }),
        prices: LQ.Prices({ oracleNum: oracleNum, oracleDen: oracleDen, poolPriceAbove: poolPriceAbove, diffBps: 0 }),
        incentiveBps: uint128(incentiveBps),
        token0Dec: 1e18,
        token1Dec: 1e18,
        token0: isToken0Debt ? debtToken : collToken,
        token1: isToken0Debt ? collToken : debtToken,
        isToken0Debt: isToken0Debt
      });
  }

  function _expectLiquidityMovedEvent(
    address _pool,
    LQ.Direction _direction,
    address _tokenGivenToPool,
    uint256 _amountGivenToPool,
    address _tokenTakenFromPool,
    uint256 _amountTakenFromPool
  ) internal {
    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(_pool, _direction, _tokenGivenToPool, _amountGivenToPool, _tokenTakenFromPool, _amountTakenFromPool);
  }

  /**
   * @notice Expect an ERC20 mint event (Transfer from address(0))
   * @param token The token address
   * @param to The recipient address
   * @param amount The amount to be minted
   */
  function expectERC20Mint(address token, address to, uint256 amount) internal {
    vm.expectEmit(true, true, false, true, token);
    emit Transfer(address(0), to, amount);
  }

  /**
   * @notice Expect an ERC20 transfer event from the strategy
   * @param token The token address
   * @param to The recipient address
   * @param amount The amount to be transferred
   */
  function expectERC20Transfer(address token, address to, uint256 amount) internal {
    vm.expectEmit(true, true, false, true, token);
    emit Transfer(address(strategy), to, amount);
  }

  /**
   * @notice Expect an ERC20 burn event (Transfer to address(0))
   * @param token The token address
   * @param amount The amount to be burned
   */
  function expectERC20Burn(address token, uint256 amount) internal {
    vm.expectEmit(true, true, false, true, token);
    emit Transfer(address(strategy), address(0), amount);
  }

  /**
   * @notice Expect and mock a reserve transfer of collateral
   * @param token The collateral token address
   * @param to The destination address
   * @param amount The amount to transfer
   */
  function expectReserveTransfer(address token, address to, uint256 amount) internal {
    // Mock the specific reserve transfer call to return true
    vm.mockCall(
      reserve,
      abi.encodeWithSelector(IReserve.transferExchangeCollateralAsset.selector, token, to, amount),
      abi.encode(true)
    );
  }

  /**
   * @notice Mock a reserve transfer to fail
   * @param token The collateral token address
   * @param to The destination address
   * @param amount The amount to transfer
   */
  function expectReserveTransferFailure(address token, address to, uint256 amount) internal {
    // Mock the specific reserve transfer call to return false
    vm.mockCall(
      reserve,
      abi.encodeWithSelector(IReserve.transferExchangeCollateralAsset.selector, token, to, amount),
      abi.encode(false)
    );
  }

  /* ============================================================ */
  /* ======================= Events ============================= */
  /* ============================================================ */

  event Transfer(address indexed from, address indexed to, uint256 value);
}
