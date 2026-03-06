// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { LiquidityStrategy_BaseTest } from "../LiquidityStrategy/LiquidityStrategy_BaseTest.sol";
import { OpenLiquidityStrategyHarness } from "test/utils/harnesses/OpenLiquidityStrategyHarness.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/libraries/LiquidityStrategyTypes.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";
import { ILiquidityStrategy } from "contracts/interfaces/ILiquidityStrategy.sol";

contract OpenLiquidityStrategy_BaseTest is LiquidityStrategy_BaseTest {
  OpenLiquidityStrategyHarness public strategy;

  address public rebalancer = makeAddr("Rebalancer");

  function setUp() public virtual override {
    LiquidityStrategy_BaseTest.setUp();

    strategy = new OpenLiquidityStrategyHarness(owner);
    strategyAddr = address(strategy);
  }

  modifier addFpmm(
    uint32 cooldown,
    uint64 liquiditySourceIncentiveExpansion,
    uint64 protocolIncentiveExpansion,
    uint64 liquiditySourceIncentiveContraction,
    uint64 protocolIncentiveContraction
  ) {
    // Set FPMM rebalance incentive cap to match or exceed strategy incentive
    uint64 fpmmIncentive = liquiditySourceIncentiveExpansion + protocolIncentiveExpansion >=
      liquiditySourceIncentiveContraction + protocolIncentiveContraction
      ? liquiditySourceIncentiveExpansion + protocolIncentiveExpansion
      : liquiditySourceIncentiveContraction + protocolIncentiveContraction;

    // Convert from 1e18-denominated to bps
    fpmmIncentive = fpmmIncentive / 1e14;

    fpmm.setRebalanceIncentive(fpmmIncentive);

    ILiquidityStrategy.AddPoolParams memory params = _buildAddPoolParams(
      address(fpmm),
      debtToken,
      cooldown,
      protocolFeeRecipient,
      liquiditySourceIncentiveExpansion,
      protocolIncentiveExpansion,
      liquiditySourceIncentiveContraction,
      protocolIncentiveContraction
    );

    vm.prank(owner);
    strategy.addPool(params);

    // Fund rebalancer with both tokens and approve strategy
    MockERC20(debtToken).mint(rebalancer, 1_000_000e18);
    MockERC20(collToken).mint(rebalancer, 1_000_000e18);
    vm.startPrank(rebalancer);
    MockERC20(debtToken).approve(strategyAddr, type(uint256).max);
    MockERC20(collToken).approve(strategyAddr, type(uint256).max);
    vm.stopPrank();
    _;
  }

  modifier addFpmmWithIncentive(
    uint32 cooldown,
    uint16 rebalanceIncentive,
    uint64 liquiditySourceIncentiveExpansion,
    uint64 protocolIncentiveExpansion,
    uint64 liquiditySourceIncentiveContraction,
    uint64 protocolIncentiveContraction
  ) {
    fpmm.setRebalanceIncentive(rebalanceIncentive);

    ILiquidityStrategy.AddPoolParams memory params = _buildAddPoolParams(
      address(fpmm),
      debtToken,
      cooldown,
      protocolFeeRecipient,
      liquiditySourceIncentiveExpansion,
      protocolIncentiveExpansion,
      liquiditySourceIncentiveContraction,
      protocolIncentiveContraction
    );

    vm.prank(owner);
    strategy.addPool(params);

    // Fund rebalancer with both tokens and approve strategy
    MockERC20(debtToken).mint(rebalancer, 1_000_000e18);
    MockERC20(collToken).mint(rebalancer, 1_000_000e18);
    vm.startPrank(rebalancer);
    MockERC20(debtToken).approve(strategyAddr, type(uint256).max);
    MockERC20(collToken).approve(strategyAddr, type(uint256).max);
    vm.stopPrank();
    _;
  }

  /* ============================================================ */
  /* ================= Helper Functions ========================= */
  /* ============================================================ */

  /**
   * @notice Create a liquidity context for testing
   */
  function _createContext(
    uint256 reserveDen,
    uint256 reserveNum,
    uint256 oracleNum,
    uint256 oracleDen,
    bool poolPriceAbove,
    LQ.RebalanceIncentives memory incentives
  ) internal view returns (LQ.Context memory) {
    return
      _createContextWithDecimals(reserveDen, reserveNum, oracleNum, oracleDen, poolPriceAbove, 1e18, 1e18, incentives);
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
    uint256 token0Dec,
    uint256 token1Dec,
    LQ.RebalanceIncentives memory incentives
  ) internal view returns (LQ.Context memory) {
    return
      LQ.Context({
        pool: address(fpmm),
        reserves: LQ.Reserves({ reserveNum: reserveNum, reserveDen: reserveDen }),
        prices: LQ.Prices({
          oracleNum: oracleNum,
          oracleDen: oracleDen,
          poolPriceAbove: poolPriceAbove,
          rebalanceThreshold: 500
        }),
        token0Dec: uint64(token0Dec),
        token1Dec: uint64(token1Dec),
        token0: debtToken,
        token1: collToken,
        isToken0Debt: true,
        incentives: incentives
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
    bool isToken0Debt,
    LQ.RebalanceIncentives memory incentives
  ) internal view returns (LQ.Context memory) {
    return
      LQ.Context({
        pool: address(fpmm),
        reserves: LQ.Reserves({ reserveNum: reserveNum, reserveDen: reserveDen }),
        prices: LQ.Prices({
          oracleNum: oracleNum,
          oracleDen: oracleDen,
          poolPriceAbove: poolPriceAbove,
          rebalanceThreshold: 500
        }),
        token0Dec: 1e18,
        token1Dec: 1e18,
        token0: isToken0Debt ? debtToken : collToken,
        token1: isToken0Debt ? collToken : debtToken,
        isToken0Debt: isToken0Debt,
        incentives: incentives
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
    emit LiquidityMoved(
      _pool,
      _direction,
      _tokenGivenToPool,
      _amountGivenToPool,
      _tokenTakenFromPool,
      _amountTakenFromPool
    );
  }

  /**
   * @notice Expect an ERC20 transfer event from the strategy
   */
  function expectERC20Transfer(address token, address from, address to, uint256 amount) internal {
    vm.expectEmit(true, true, false, true, token);
    emit Transfer(from, to, amount);
  }

  /* ============================================================ */
  /* ======================= Events ============================= */
  /* ============================================================ */

  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);
}
