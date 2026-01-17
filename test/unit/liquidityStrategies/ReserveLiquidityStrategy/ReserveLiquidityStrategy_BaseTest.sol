// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { LiquidityStrategy_BaseTest } from "../LiquidityStrategy/LiquidityStrategy_BaseTest.sol";
import { ReserveLiquidityStrategyHarness } from "test/utils/harnesses/ReserveLiquidityStrategyHarness.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/libraries/LiquidityStrategyTypes.sol";
import { IReserveV2 } from "contracts/interfaces/IReserveV2.sol";
import { ReserveV2 } from "contracts/swap/ReserveV2.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";
import { ILiquidityStrategy } from "contracts/interfaces/ILiquidityStrategy.sol";

contract ReserveLiquidityStrategy_BaseTest is LiquidityStrategy_BaseTest {
  ReserveLiquidityStrategyHarness public strategy;

  // Reserve V2 contract
  ReserveV2 public reserve;

  function setUp() public virtual override {
    LiquidityStrategy_BaseTest.setUp();
    reserve = new ReserveV2(false);

    strategy = new ReserveLiquidityStrategyHarness(owner, address(reserve));
    strategyAddr = address(strategy);

    address[] memory stableAssets = new address[](0);
    address[] memory collateralAssets = new address[](0);
    address[] memory otherReserveAddresses = new address[](0);
    address[] memory liquidityStrategySpenders = new address[](1);
    liquidityStrategySpenders[0] = strategyAddr;
    address[] memory reserveManagerSpenders = new address[](0);

    reserve.initialize(
      stableAssets,
      collateralAssets,
      otherReserveAddresses,
      liquidityStrategySpenders,
      reserveManagerSpenders,
      owner
    );
  }

  modifier addFpmm(
    uint64 cooldown,
    uint16 liquiditySourceIncentiveBpsExpansion,
    uint16 protocolIncentiveBpsExpansion,
    uint16 liquiditySourceIncentiveBpsContraction,
    uint16 protocolIncentiveBpsContraction
  ) {
    // Set FPMM rebalance incentive cap to match or exceed strategy incentive
    // Note: FPMM has a maximum cap, typically 100 bps (1%)
    uint32 fpmmIncentive = liquiditySourceIncentiveBpsExpansion + protocolIncentiveBpsExpansion >=
      liquiditySourceIncentiveBpsContraction + protocolIncentiveBpsContraction
      ? liquiditySourceIncentiveBpsExpansion + protocolIncentiveBpsExpansion
      : liquiditySourceIncentiveBpsContraction + protocolIncentiveBpsContraction;

    fpmm.setRebalanceIncentive(fpmmIncentive);

    ILiquidityStrategy.AddPoolParams memory params = _buildAddPoolParams(
      address(fpmm),
      debtToken,
      cooldown,
      liquiditySourceIncentiveBpsExpansion,
      protocolIncentiveBpsExpansion,
      liquiditySourceIncentiveBpsContraction,
      protocolIncentiveBpsContraction,
      protocolFeeRecipient
    );

    vm.startPrank(owner);
    strategy.addPool(params);
    reserve.registerCollateralAsset(collToken);
    reserve.registerStableAsset(debtToken);
    MockERC20(collToken).mint(address(reserve), 1000000e18);
    vm.stopPrank();
    _;
  }

  /* ============================================================ */
  /* ================= Helper Functions ========================= */
  /* ============================================================ */

  /**
   * @notice Create a liquidity context for testing
   * @param reserveDen token0 reserves (denominator in pool price)
   * @param reserveNum token1 reserves (numerator in pool price)
   * @param oracleNum Oracle price numerator
   * @param oracleDen Oracle price denominator
   * @param poolPriceAbove Whether pool price is above oracle price
   * @param incentives The incentives for the rebalance
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
  function expectReserveTransfer(address strategyAddr, address token, address to, uint256 amount) internal {
    vm.expectEmit(true, true, true, true, address(reserve));
    emit IReserveV2.CollateralAssetTransferredLiquidityStrategySpender(strategyAddr, token, to, amount);
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
      address(reserve),
      abi.encodeWithSelector(IReserveV2.transferCollateralAsset.selector, token, to, amount),
      abi.encode(false)
    );
  }

  /* ============================================================ */
  /* ======================= Events ============================= */
  /* ============================================================ */

  event Transfer(address indexed from, address indexed to, uint256 value);
}
