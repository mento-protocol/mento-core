// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { TokenDeployer } from "test/integration/v3/TokenDeployer.sol";
import { OracleAdapterDeployer } from "test/integration/v3/OracleAdapterDeployer.sol";
import { FPMMDeployer } from "test/integration/v3/FPMMDeployer.sol";
import { ITradingLimitsV2 } from "contracts/interfaces/ITradingLimitsV2.sol";
import { IERC20Metadata } from "bold/src/Interfaces/IBoldToken.sol";
import { LiquidityStrategyDeployer } from "test/integration/v3/LiquidityStrategyDeployer.sol";
import { IFPMM } from "contracts/interfaces/IFPMM.sol";

contract FPMMTradingLimitsTest is TokenDeployer, OracleAdapterDeployer, LiquidityStrategyDeployer, FPMMDeployer {
  address public trader = makeAddr("trader");
  address public lpProvider = makeAddr("lpProvider");

  uint256 constant L0_WINDOW = 5 minutes;
  uint256 constant L1_WINDOW = 1 days;

  function setUp() public {
    // ReserveFPMM:  token0 = USDC, token1 = USD.m
    // CDPFPMM:      token0 = EUR.m, token1 = USD.m
    _deployTokens({ isCollateralTokenToken0: false, isDebtTokenToken0: true });
    _deployOracleAdapter();
    _deployLiquidityStrategies();
    _deployFPMM({ invertCDPFPMMRate: false, invertReserveFPMMRate: false });

    // Setup liquidity on both pools
    _setupLiquidityReserveFPMM();
    _setupLiquidityCDPFPMM();

    // Mint tokens for traders
    _mintTokensForTraders();

    // Configure trading limits on both pools
    _configureTradingLimitsReserveFPMM();
    _configureTradingLimitsCDPFPMM();

    _checkSetup();
  }

  function _setupLiquidityReserveFPMM() internal {
    deal(address($tokens.resCollToken), lpProvider, 10_000_000e6);
    deal(address($tokens.resDebtToken), lpProvider, 10_000_000e18);

    _provideLiquidityToFPMM($fpmm.fpmmReserve, lpProvider, 5_000_000e18, 5_000_000e6);
  }

  function _setupLiquidityCDPFPMM() internal {
    deal(address($tokens.cdpCollToken), lpProvider, 10_000_000e18);
    deal(address($tokens.cdpDebtToken), lpProvider, 10_000_000e18);

    _provideLiquidityToFPMM($fpmm.fpmmCDP, lpProvider, 5_000_000e18, 5_000_000e18);
  }

  function _mintTokensForTraders() internal {
    deal(address($tokens.resCollToken), trader, 1_000_000e6);
    deal(address($tokens.resDebtToken), trader, 1_000_000e18);
    deal(address($tokens.cdpCollToken), trader, 1_000_000e18);
    deal(address($tokens.cdpDebtToken), trader, 1_000_000e18);
  }

  function _transferToFPMM(IFPMM fpmm, address sender, uint256 amount0In, uint256 amount1In) internal {
    require($fpmm.deployed, "FPMM_DEPLOYER: FPMM not deployed");

    address token0 = fpmm.token0();
    address token1 = fpmm.token1();

    vm.startPrank(sender);

    if (amount0In > 0) {
      IERC20Metadata(token0).transfer(address(fpmm), amount0In);
    }
    if (amount1In > 0) {
      IERC20Metadata(token1).transfer(address(fpmm), amount1In);
    }

    vm.stopPrank();
  }

  function _transferToFPMMAndSwap(
    IFPMM fpmm,
    address sender,
    uint256 amount0In,
    uint256 amount1In,
    uint256 amount0Out,
    uint256 amount1Out
  ) internal {
    require($fpmm.deployed, "FPMM_DEPLOYER: FPMM not deployed");

    address token0 = fpmm.token0();
    address token1 = fpmm.token1();

    vm.startPrank(sender);

    if (amount0In > 0) {
      IERC20Metadata(token0).transfer(address(fpmm), amount0In);
    }
    if (amount1In > 0) {
      IERC20Metadata(token1).transfer(address(fpmm), amount1In);
    }

    fpmm.swap(amount0Out, amount1Out, trader, "");

    vm.stopPrank();
  }

  function _swapFPMM(IFPMM fpmm, address sender, uint256 amount0Out, uint256 amount1Out) internal {
    require($fpmm.deployed, "FPMM_DEPLOYER: FPMM not deployed");

    vm.startPrank(sender);
    fpmm.swap(amount0Out, amount1Out, trader, "");
    vm.stopPrank();
  }

  function _configureTradingLimitsReserveFPMM() internal {
    // Configure limits for token0 (USDC)
    // L0: 100k USDC (5 minute window)
    // L1: 1M USDC (1 day window)
    uint256 limit0token0 = 100_000e6;
    uint256 limit1token0 = 1_000_000e6;
    _configureTradingLimits($fpmm.fpmmReserve, $fpmm.fpmmReserve.token0(), limit0token0, limit1token0);

    // Configure limits for token1 (USD.m)
    uint256 limit0token1 = 100_000e18;
    uint256 limit1token1 = 1_000_000e18;
    _configureTradingLimits($fpmm.fpmmReserve, $fpmm.fpmmReserve.token1(), limit0token1, limit1token1);
  }

  function _configureTradingLimitsCDPFPMM() internal {
    // Configure limits for token0 (EUR.m)
    // L0: 50k EUR.m (5 minute window)
    // L1: 500k EUR.m (1 day window)
    uint256 limit0token0 = 50_000e18;
    uint256 limit1token0 = 500_000e18;
    _configureTradingLimits($fpmm.fpmmCDP, $fpmm.fpmmCDP.token0(), limit0token0, limit1token0);

    // Configure limits for token1 (USD.m)
    uint256 limit0token1 = 50_000e18;
    uint256 limit1token1 = 500_000e18;
    _configureTradingLimits($fpmm.fpmmCDP, $fpmm.fpmmCDP.token1(), limit0token1, limit1token1);
  }

  function _checkSetup() internal {
    // Verify Reserve FPMM setup
    assertEq($fpmm.fpmmReserve.token0(), address($tokens.resCollToken), "ReserveFPMM token0 mismatch");
    assertEq($fpmm.fpmmReserve.token1(), address($tokens.resDebtToken), "ReserveFPMM token1 mismatch");
    assertGt($fpmm.fpmmReserve.reserve0(), 0, "ReserveFPMM should have liquidity");
    assertGt($fpmm.fpmmReserve.reserve1(), 0, "ReserveFPMM should have liquidity");

    // Verify CDP FPMM setup
    assertEq($fpmm.fpmmCDP.token0(), address($tokens.cdpDebtToken), "CDPFPMM token0 mismatch");
    assertEq($fpmm.fpmmCDP.token1(), address($tokens.cdpCollToken), "CDPFPMM token1 mismatch");
    assertGt($fpmm.fpmmCDP.reserve0(), 0, "CDPFPMM should have liquidity");
    assertGt($fpmm.fpmmCDP.reserve1(), 0, "CDPFPMM should have liquidity");

    // Verify trading limits configured on Reserve FPMM
    (ITradingLimitsV2.Config memory config0Reserve, ) = $fpmm.fpmmReserve.getTradingLimits($fpmm.fpmmReserve.token0());
    (ITradingLimitsV2.Config memory config1Reserve, ) = $fpmm.fpmmReserve.getTradingLimits($fpmm.fpmmReserve.token1());
    assertEq(config0Reserve.limit0, 100_000e15, "ReserveFPMM token0 L0 limit mismatch");
    assertEq(config0Reserve.limit1, 1_000_000e15, "ReserveFPMM token0 L1 limit mismatch");
    assertEq(config1Reserve.limit0, 100_000e15, "ReserveFPMM token1 L0 limit mismatch");
    assertEq(config1Reserve.limit1, 1_000_000e15, "ReserveFPMM token1 L1 limit mismatch");

    // Verify trading limits configured on CDP FPMM
    (ITradingLimitsV2.Config memory config0CDP, ) = $fpmm.fpmmCDP.getTradingLimits($fpmm.fpmmCDP.token0());
    (ITradingLimitsV2.Config memory config1CDP, ) = $fpmm.fpmmCDP.getTradingLimits($fpmm.fpmmCDP.token1());
    assertEq(config0CDP.limit0, 50_000e15, "CDPFPMM token0 L0 limit mismatch");
    assertEq(config0CDP.limit1, 500_000e15, "CDPFPMM token0 L1 limit mismatch");
    assertEq(config1CDP.limit0, 50_000e15, "CDPFPMM token1 L0 limit mismatch");
    assertEq(config1CDP.limit1, 500_000e15, "CDPFPMM token1 L1 limit mismatch");
  }

  // ============================================================
  // ============ Reserve FPMM Tests (USDC/USD.m) ===============
  // ============================================================

  function test_reserveFPMM_L0LimitEnforcement_whenMultipleSwapsWithin5Minutes_shouldRevert() public {
    // First swap: 80k USDC -> USD.m (within L0 limit)
    uint256 amount0In = 80_000e6;
    uint256 amount1Out = 79_760e18; // ~80k after 0.3% fee

    _transferToFPMMAndSwap($fpmm.fpmmReserve, trader, amount0In, 0, 0, amount1Out);

    vm.warp(block.timestamp + 3 minutes);

    // Second swap: 30k USDC -> USD.m (110k total, exceeds 100k L0 limit)
    uint256 amount0In2 = 30_000e6;
    uint256 amount1Out2 = 29_910e18;

    _transferToFPMM($fpmm.fpmmReserve, trader, amount0In2, 0);

    vm.expectRevert(ITradingLimitsV2.L0LimitExceeded.selector);
    _swapFPMM($fpmm.fpmmReserve, trader, 0, amount1Out2);
  }

  function test_reserveFPMM_L1LimitEnforcement_whenMultipleSwapsWithin1Day_shouldRevert() public {
    // Set lower L0 limit to test L1
    uint256 limit0token0 = 70_000e6;
    uint256 limit1token0 = 80_000e6;
    _configureTradingLimits($fpmm.fpmmReserve, $fpmm.fpmmReserve.token0(), limit0token0, limit1token0);

    // First swap: 60k USDC (within both L0 and L1 limits)
    uint256 amount0In = 60_000e6;
    uint256 amount1Out = 59_820e18;

    _transferToFPMMAndSwap($fpmm.fpmmReserve, trader, amount0In, 0, 0, amount1Out);

    // Warp past L0 window but within L1 window to reset L0
    vm.warp(block.timestamp + L0_WINDOW + 1);

    // Second swap: 30k USDC
    uint256 amount0In2 = 30_000e6;
    uint256 amount1Out2 = 29_910e18;

    _transferToFPMM($fpmm.fpmmReserve, trader, amount0In2, 0);

    vm.expectRevert(ITradingLimitsV2.L1LimitExceeded.selector);
    _swapFPMM($fpmm.fpmmReserve, trader, 0, amount1Out2);
  }

  function test_reserveFPMM_limitReset_whenL0WindowExpires_shouldAllowNewSwaps() public {
    // First swap: 90k USDC (within L0 limit)
    uint256 amount0In = 90_000e6;
    uint256 amount1Out = 89_730e18;

    uint256 balanceBefore = IERC20Metadata($fpmm.fpmmReserve.token1()).balanceOf(trader);

    _transferToFPMMAndSwap($fpmm.fpmmReserve, trader, amount0In, 0, 0, amount1Out);

    // Warp time by 5 minutes + 1 second to reset L0
    vm.warp(block.timestamp + L0_WINDOW + 1);

    // // Second swap: Another 90k USDC
    uint256 amount0In2 = 90_000e6;
    uint256 amount1Out2 = 89_730e18;

    _transferToFPMMAndSwap($fpmm.fpmmReserve, trader, amount0In2, 0, 0, amount1Out2);

    // Verify swap succeeded
    assertEq(
      IERC20Metadata($fpmm.fpmmReserve.token1()).balanceOf(trader),
      balanceBefore + amount1Out + amount1Out2,
      "Trader should have received both swap amounts"
    );
  }

  function test_reserveFPMM_swapWithinLimits_shouldSucceed() public {
    // Swap 50k USDC -> USD.m (within both L0 and L1 limits)
    uint256 amount0In = 50_000e6;
    uint256 amount1Out = 49_850e18;

    uint256 trader1BalanceBefore = IERC20Metadata($fpmm.fpmmReserve.token1()).balanceOf(trader);
    _transferToFPMMAndSwap($fpmm.fpmmReserve, trader, amount0In, 0, 0, amount1Out);
    uint256 trader1BalanceAfter = IERC20Metadata($fpmm.fpmmReserve.token1()).balanceOf(trader);

    assertEq(trader1BalanceAfter - trader1BalanceBefore, amount1Out, "Trader should receive expected amount");

    // Verify limits were updated
    (, ITradingLimitsV2.State memory stateToken0) = $fpmm.fpmmReserve.getTradingLimits($fpmm.fpmmReserve.token0());
    assertEq(stateToken0.netflow0, 50_000e15, "Netflow0 for token0 should be 50k");
    assertEq(stateToken0.netflow1, 50_000e15, "Netflow1 for token0 should be 50k");

    (, ITradingLimitsV2.State memory stateToken1) = $fpmm.fpmmReserve.getTradingLimits($fpmm.fpmmReserve.token1());
    assertEq(stateToken1.netflow0, -49_850e15, "Netflow0 for token1 should be -49.85k");
    assertEq(stateToken1.netflow1, -49_850e15, "Netflow1 for token1 should be -49.85k");
  }

  function test_reserveFPMM_netflowTracking_withBidirectionalSwaps_shouldAccumulateCorrectly() public {
    // Swap 1: Send 50k USDC in (netflow = -50k)
    uint256 amount0In = 50_000e6;
    uint256 amount1Out = 49_850e18;

    _transferToFPMMAndSwap($fpmm.fpmmReserve, trader, amount0In, 0, 0, amount1Out);

    (, ITradingLimitsV2.State memory stateToken0) = $fpmm.fpmmReserve.getTradingLimits($fpmm.fpmmReserve.token0());
    assertEq(stateToken0.netflow0, 50_000e15, "Netflow0 for token0 should be 50k after first swap");
    assertEq(stateToken0.netflow1, 50_000e15, "Netflow1 for token0 should be 50k after first swap");

    (, ITradingLimitsV2.State memory stateToken1) = $fpmm.fpmmReserve.getTradingLimits($fpmm.fpmmReserve.token1());
    assertEq(stateToken1.netflow0, -49_850e15, "Netflow0 for token1 should be -49.85k");
    assertEq(stateToken1.netflow1, -49_850e15, "Netflow1 for token1 should be -49.85k");

    // Swap 2: Receive 20k USDC out (netflow = -50k + 20k = -30k)
    uint256 amount0Out = 20_000e6;
    uint256 amount1In = 20_100e18;

    _transferToFPMMAndSwap($fpmm.fpmmReserve, trader, 0, amount1In, amount0Out, 0);

    (, stateToken0) = $fpmm.fpmmReserve.getTradingLimits($fpmm.fpmmReserve.token0());
    assertEq(stateToken0.netflow0, 30_000e15, "Netflow0 for token0 should be 30k after bidirectional swaps");
    assertEq(stateToken0.netflow1, 30_000e15, "Netflow1 for token0 should be 30k after bidirectional swaps");

    (, stateToken1) = $fpmm.fpmmReserve.getTradingLimits($fpmm.fpmmReserve.token1());
    // 49.85k - 20.10k = 29.75k
    assertEq(stateToken1.netflow0, -29_750e15, "Netflow0 for token1 should be -29.94k after bidirectional swaps");
    // 49.85k - 20.10k = 29.75k
    assertEq(stateToken1.netflow1, -29_750e15, "Netflow1 for token1 should be -29.95k after bidirectional swaps");
  }

  function test_reserveFPMM_netflowTracking_withSmallAmounts_shouldAccountCorrectly() public {
    // Swap 1: 1 wei USDC -> USD.m
    uint256 amount0In = 1;
    uint256 amount1Out = $fpmm.fpmmReserve.getAmountOut(amount0In, $fpmm.fpmmReserve.token0());

    _transferToFPMMAndSwap($fpmm.fpmmReserve, trader, amount0In, 0, 0, amount1Out);

    (, ITradingLimitsV2.State memory stateToken0) = $fpmm.fpmmReserve.getTradingLimits($fpmm.fpmmReserve.token0());
    // accounting in 15 decimals so 1 wei usdc is 1e9 in 15 decimals
    assertEq(stateToken0.netflow0, 1e9, "Netflow0 for token0 should be 1 wei");
    assertEq(stateToken0.netflow1, 1e9, "Netflow1 for token0 should be 1 wei");

    (, ITradingLimitsV2.State memory stateToken1) = $fpmm.fpmmReserve.getTradingLimits($fpmm.fpmmReserve.token1());
    // accounting in 15 decimals so usd.m amounts are scaled down by 1e3
    assertEq(stateToken1.netflow0, -int256(amount1Out / 1e3), "Netflow0 for token1 should be -amount1Out / 1e3");
    assertEq(stateToken1.netflow1, -int256(amount1Out / 1e3), "Netflow1 for token1 should be -amount1Out / 1e3");

    // Swap 2: 1e18 + 999 wei USD.m -> USDC
    uint256 amount1In = 1e18 + 999;
    uint256 amount0Out = $fpmm.fpmmReserve.getAmountOut(amount1In, $fpmm.fpmmReserve.token1());

    _transferToFPMMAndSwap($fpmm.fpmmReserve, trader, 0, amount1In, amount0Out, 0);

    (, ITradingLimitsV2.State memory stateToken0After) = $fpmm.fpmmReserve.getTradingLimits($fpmm.fpmmReserve.token0());
    // amountOut in USDC(6dec) is scaled up to 15 decimals so * 1e9
    assertEq(
      stateToken0After.netflow0,
      stateToken0.netflow0 - int256(amount0Out * 1e9),
      "Netflow0 for token0 should be the same as before - amount0Out * 1e9"
    );
    assertEq(
      stateToken0After.netflow1,
      stateToken0.netflow1 - int256(amount0Out * 1e9),
      "Netflow1 for token0 should be the same as before - amount0Out * 1e9"
    );

    (, ITradingLimitsV2.State memory stateToken1After) = $fpmm.fpmmReserve.getTradingLimits($fpmm.fpmmReserve.token1());
    // 1e18 + 999 wei USD.m is scaled down to 15 decimals so 1e15, 999 is dropped
    assertEq(
      stateToken1After.netflow0,
      stateToken1.netflow0 + 1e15,
      "Netflow0 for token1 should be the same as before + amount1In / 1e3"
    );
    assertEq(
      stateToken1After.netflow1,
      stateToken1.netflow1 + 1e15,
      "Netflow1 for token1 should be the same as before + amount1In / 1e3"
    );
  }

  // ============================================================
  // ============ CDP FPMM Tests (EUR.m/USD.m) ==================
  // ============================================================

  function test_cdpFPMM_L0LimitEnforcement_whenMultipleSwapsWithin5Minutes_shouldRevert() public {
    // First swap: 40k EUR.m -> USD.m
    uint256 amount0In = 40_000e18;
    uint256 amount1Out = 39_880e18;

    _transferToFPMMAndSwap($fpmm.fpmmCDP, trader, amount0In, 0, 0, amount1Out);

    vm.warp(block.timestamp + 3 minutes);

    // Second swap: 15k EUR.m -> USD.m (total 55k, exceeds 50k L0 limit)
    uint256 amount0In2 = 15_000e18;
    uint256 amount1Out2 = 14_955e18;

    _transferToFPMM($fpmm.fpmmCDP, trader, amount0In2, 0);

    vm.expectRevert(ITradingLimitsV2.L0LimitExceeded.selector);
    _swapFPMM($fpmm.fpmmCDP, trader, 0, amount1Out2);
  }

  function test_cdpFPMM_L1LimitEnforcement_whenMultipleSwapsWithin1Day_shouldRevert() public {
    uint256 limit0token0 = 55_000e18;
    uint256 limit1token0 = 60_000e18;
    _configureTradingLimits($fpmm.fpmmCDP, $fpmm.fpmmCDP.token0(), limit0token0, limit1token0);

    uint256 amount0In = 45_000e18;
    uint256 amount1Out = 44_865e18;

    _transferToFPMMAndSwap($fpmm.fpmmCDP, trader, amount0In, 0, 0, amount1Out);

    // Warp time past L0 window but within L1 window
    vm.warp(block.timestamp + L0_WINDOW + 1);

    uint256 amount0In2 = 20_000e18;
    uint256 amount1Out2 = 19_940e18;

    _transferToFPMM($fpmm.fpmmCDP, trader, amount0In2, 0);

    vm.expectRevert(ITradingLimitsV2.L1LimitExceeded.selector);
    _swapFPMM($fpmm.fpmmCDP, trader, 0, amount1Out2);
  }

  function test_cdpFPMM_limitReset_whenL0WindowExpires_shouldAllowNewSwaps() public {
    uint256 amount0In = 45_000e18;
    uint256 amount1Out = 44_865e18;
    uint256 traderBalanceBefore = IERC20Metadata($fpmm.fpmmCDP.token1()).balanceOf(trader);

    _transferToFPMMAndSwap($fpmm.fpmmCDP, trader, amount0In, 0, 0, amount1Out);

    vm.warp(block.timestamp + L0_WINDOW + 1);

    uint256 amount0In2 = 45_000e18;
    uint256 amount1Out2 = 44_865e18;

    _transferToFPMMAndSwap($fpmm.fpmmCDP, trader, amount0In2, 0, 0, amount1Out2);

    uint256 traderBalanceAfter = IERC20Metadata($fpmm.fpmmCDP.token1()).balanceOf(trader);

    assertEq(
      traderBalanceAfter - traderBalanceBefore,
      amount1Out + amount1Out2,
      "Trader should have received both swap amounts"
    );
  }

  function test_cdpFPMM_swapWithinLimits_shouldSucceed() public {
    uint256 amount0In = 30_000e18;
    uint256 amount1Out = 29_910e18;

    uint256 traderBalanceBefore = IERC20Metadata($fpmm.fpmmCDP.token1()).balanceOf(trader);

    _transferToFPMMAndSwap($fpmm.fpmmCDP, trader, amount0In, 0, 0, amount1Out);

    uint256 traderBalanceAfter = IERC20Metadata($fpmm.fpmmCDP.token1()).balanceOf(trader);

    assertEq(traderBalanceAfter - traderBalanceBefore, amount1Out, "Trader should receive expected amount");

    (, ITradingLimitsV2.State memory stateToken0) = $fpmm.fpmmCDP.getTradingLimits($fpmm.fpmmCDP.token0());
    assertEq(stateToken0.netflow0, 30_000e15, "Netflow0 for token0 should be 30k");
    assertEq(stateToken0.netflow1, 30_000e15, "Netflow1 for token0 should be 30k");

    (, ITradingLimitsV2.State memory stateToken1) = $fpmm.fpmmCDP.getTradingLimits($fpmm.fpmmCDP.token1());
    assertEq(stateToken1.netflow0, -29_910e15, "Netflow0 for token1 should be -29.91k");
    assertEq(stateToken1.netflow1, -29_910e15, "Netflow1 for token1 should be -29.91k");
  }

  function test_cdpFPMM_netflowTracking_withBidirectionalSwaps_shouldAccumulateCorrectly() public {
    uint256 amount0In = 30_000e18;
    uint256 amount1Out = 29_910e18;

    _transferToFPMMAndSwap($fpmm.fpmmCDP, trader, amount0In, 0, 0, amount1Out);

    (, ITradingLimitsV2.State memory stateToken0) = $fpmm.fpmmCDP.getTradingLimits($fpmm.fpmmCDP.token0());
    assertEq(stateToken0.netflow0, 30_000e15, "Netflow0 for token0 should be 30k after first swap");
    assertEq(stateToken0.netflow1, 30_000e15, "Netflow1 for token0 should be 30k after first swap");

    (, ITradingLimitsV2.State memory stateToken1) = $fpmm.fpmmCDP.getTradingLimits($fpmm.fpmmCDP.token1());
    assertEq(stateToken1.netflow0, -29_910e15, "Netflow0 for token1 should be -29.91k after first swap");
    assertEq(stateToken1.netflow1, -29_910e15, "Netflow1 for token1 should be -29.91k after first swap");

    uint256 amount0Out = 10_000e18;
    uint256 amount1In = 20_100e18;

    _transferToFPMMAndSwap($fpmm.fpmmCDP, trader, 0, amount1In, amount0Out, 0);

    (, stateToken0) = $fpmm.fpmmCDP.getTradingLimits($fpmm.fpmmCDP.token0());
    assertEq(stateToken0.netflow0, 20_000e15, "Netflow0 for token0 should be 20k after bidirectional swaps");
    assertEq(stateToken0.netflow1, 20_000e15, "Netflow1 for token0 should be 20k after bidirectional swaps");

    (, stateToken1) = $fpmm.fpmmCDP.getTradingLimits($fpmm.fpmmCDP.token1());
    // -29.91k + 20.10k = -9.81k
    assertEq(stateToken1.netflow0, -9_810e15, "Netflow0 for token1 should be -9.81k after bidirectional swaps");
    // -29.91k + 20.10k = -9.81k
    assertEq(stateToken1.netflow1, -9_810e15, "Netflow1 for token1 should be -9.81k after bidirectional swaps");
  }

  function test_bothPools_configureTradingLimit_onBothTokens_shouldApplyIndependently() public {
    uint256 amount0In = 90_000e6;
    uint256 amount1Out = 89_730e18;

    uint256 traderBalanceToken0Before = IERC20Metadata($fpmm.fpmmReserve.token0()).balanceOf(trader);
    uint256 traderBalanceToken1Before = IERC20Metadata($fpmm.fpmmReserve.token1()).balanceOf(trader);

    // Swap token0 (USDC) - should respect token0 limits
    _transferToFPMMAndSwap($fpmm.fpmmReserve, trader, amount0In, 0, 0, amount1Out);

    // Verify token0 limit is hit when trying to exceed it
    _transferToFPMM($fpmm.fpmmReserve, trader, 20_000e6, 0);
    vm.expectRevert(ITradingLimitsV2.L0LimitExceeded.selector);
    _swapFPMM($fpmm.fpmmReserve, trader, 0, 19_940e18);

    // Swap token1 (USD.m) in opposite direction - should have independent limits
    uint256 amount1In = 90_000e18;
    uint256 amount0Out = 89_730e6;

    _transferToFPMMAndSwap($fpmm.fpmmReserve, trader, 0, amount1In, amount0Out, 0);

    uint256 traderBalanceToken0After = IERC20Metadata($fpmm.fpmmReserve.token0()).balanceOf(trader);
    uint256 traderBalanceToken1After = IERC20Metadata($fpmm.fpmmReserve.token1()).balanceOf(trader);

    assertEq(
      traderBalanceToken0Before - amount0In + amount0Out - 20_000e6, // 20k deducted for the L0 limit exceeded attempt
      traderBalanceToken0After,
      "Trader should have received expected amount for token0"
    );
    assertEq(
      traderBalanceToken1Before - amount1In + amount1Out,
      traderBalanceToken1After,
      "Trader should have received expected amount for token1"
    );
  }
}
