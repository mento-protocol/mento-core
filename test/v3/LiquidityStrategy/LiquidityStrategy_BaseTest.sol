// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { Test } from "mento-std/Test.sol";

import { FPMM } from "contracts/swap/FPMM.sol";
import { IFPMM } from "contracts/interfaces/IFPMM.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";

import { LiquidityStrategyTypes as LQ } from "contracts/v3/libraries/LiquidityStrategyTypes.sol";
import { IOracleAdapter } from "contracts/interfaces/IOracleAdapter.sol";

/**
 * @title LiquidityStrategy_BaseTest
 * @notice Abstract base test contract for all LiquidityStrategy tests
 * @dev Provides common setup, helper functions, and MockFPMM utilities
 */
abstract contract LiquidityStrategy_BaseTest is Test {
  FPMM public fpmm;
  IFPMM.FPMMParams internal defaultFPMMParams;

  address public owner = makeAddr("Owner");
  address public notOwner = makeAddr("NotOwner");
  address public debtToken;
  address public collToken;
  address public oracleAdapter = makeAddr("oracleAdapter");
  address public referenceRateFeedID = makeAddr("referenceRateFeedID");
  uint256 public oracleNumerator;
  uint256 public oracleDenominator;
  address public strategyAddr;

  function setUp() public virtual {
    fpmm = new FPMM(false);
    defaultFPMMParams = IFPMM.FPMMParams({
      lpFee: 30,
      protocolFee: 0,
      protocolFeeRecipient: makeAddr("protocolFeeRecipient"),
      rebalanceIncentive: 50,
      rebalanceThresholdAbove: 500,
      rebalanceThresholdBelow: 500
    });
  }

  /* ============================================================ */
  /* ============== MockFPMM Creation Helpers =================== */
  /* ============================================================ */

  modifier fpmmToken0Debt(uint8 debtDecimals, uint8 collateralDecimals) {
    // deploy debt and collateral with specified decimals and correct address order
    deployDebtAndCollateral(true, debtDecimals, collateralDecimals);
    // initialize fpmm and set liquidity strategy
    fpmm.initialize(debtToken, collToken, oracleAdapter, referenceRateFeedID, false, address(this), defaultFPMMParams);
    fpmm.setLiquidityStrategy(strategyAddr, true);
    // Fund the strategy with tokens for rebalancing
    if (strategyAddr != address(0)) {
      MockERC20(debtToken).mint(strategyAddr, 1000000e18);
      MockERC20(collToken).mint(strategyAddr, 1000000e18);
    }
    _;
  }

  modifier fpmmToken1Debt(uint8 debtDecimals, uint8 collateralDecimals) {
    // deploy debt and collateral with specified decimals and correct address order
    deployDebtAndCollateral(false, debtDecimals, collateralDecimals);
    // initialize fpmm and set liquidity strategy
    fpmm.initialize(collToken, debtToken, oracleAdapter, referenceRateFeedID, false, address(this), defaultFPMMParams);
    fpmm.setLiquidityStrategy(strategyAddr, true);
    // Fund the strategy with tokens for rebalancing
    if (strategyAddr != address(0)) {
      MockERC20(debtToken).mint(strategyAddr, 1000000e18);
      MockERC20(collToken).mint(strategyAddr, 1000000e18);
    }
    _;
  }

  /**
   * @notice Deploy debt and collateral tokens with specified decimals and correct address order
   * @param isToken0Debt True if the debt token is token0, false otherwise
   * @param debtDecimals Decimals of the debt token
   * @param collateralDecimals Decimals of the collateral token
   */
  function deployDebtAndCollateral(bool isToken0Debt, uint8 debtDecimals, uint8 collateralDecimals) public {
    uint256 currentNonce = vm.getNonce(address(this));
    address a1 = vm.computeCreateAddress(address(this), currentNonce);
    address a2 = vm.computeCreateAddress(address(this), currentNonce + 1);

    if ((a1 < a2 && isToken0Debt) || (a1 > a2 && !isToken0Debt)) {
      debtToken = address(new MockERC20("DebtToken", "DT", debtDecimals));
      collToken = address(new MockERC20("CollateralToken", "CT", collateralDecimals));
    } else if ((a1 < a2 && !isToken0Debt) || (a1 > a2 && isToken0Debt)) {
      collToken = address(new MockERC20("CollateralToken", "CT", collateralDecimals));
      debtToken = address(new MockERC20("DebtToken", "DT", debtDecimals));
    }

    vm.label(debtToken, "DebtToken");
    vm.label(collToken, "CollToken");
  }

  /**
   * @notice Provide liquidity to the FPMM
   * @param reserve0 Reserve of token0
   * @param reserve1 Reserve of token1
   */
  function provideFPMMReserves(uint256 reserve0, uint256 reserve1, bool isToken0Debt) public {
    if (isToken0Debt) {
      MockERC20(debtToken).mint(address(fpmm), reserve0);
      MockERC20(collToken).mint(address(fpmm), reserve1);
    } else {
      MockERC20(collToken).mint(address(fpmm), reserve0);
      MockERC20(debtToken).mint(address(fpmm), reserve1);
    }
    fpmm.mint(address(this));
  }

  /**
   * @notice Set the oracle rate
   * @param numerator Numerator of the oracle rate
   * @param denominator Denominator of the oracle rate
   */
  function setOracleRate(uint256 numerator, uint256 denominator) public {
    vm.mockCall(
      oracleAdapter,
      abi.encodeWithSelector(IOracleAdapter.getFXRateIfValid.selector, referenceRateFeedID),
      abi.encode(numerator, denominator)
    );
  }

  /**
   * @notice Set the total supply of the debt token
   * @param totalSupply Total supply of the debt token
   */
  function setDebtTokenTotalSupply(uint256 totalSupply) public {
    vm.mockCall(debtToken, abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(totalSupply));
  }

  /**
   * @notice Performs a swap in the FPMM
   * @param tokenIn Address of the token to swap in
   * @param amountIn Amount of the token to swap in
   */
  function swapIn(address tokenIn, uint256 amountIn) public {
    uint256 expectedOut = fpmm.getAmountOut(amountIn, tokenIn);
    MockERC20(tokenIn).mint(address(fpmm), amountIn);
    if (fpmm.token0() == tokenIn) {
      fpmm.swap(0, expectedOut, address(this), "");
    } else {
      fpmm.swap(expectedOut, 0, address(this), "");
    }
  }

  /**
   * @notice Assert that two Direction enum values are equal with a custom error message
   * @param expected The expected Direction value
   * @param given The actual Direction value
   * @param message Custom error message to display on assertion failure
   */
  function assertEq(LQ.Direction expected, LQ.Direction given, string memory message) internal pure {
    assertEq(uint256(expected), uint256(given), message);
  }

  /**
   * @notice Assert that two Direction enum values are equal
   * @param expected The expected Direction value
   * @param given The actual Direction value
   */
  function assertEq(LQ.Direction expected, LQ.Direction given) internal pure {
    assertEq(uint256(expected), uint256(given));
  }

  /* ============================================================ */
  /* ======================= Events ============================= */
  /* ============================================================ */

  event PoolAdded(address indexed pool, bool isToken0Debt, uint64 cooldown, uint32 incentiveBps);
  event PoolRemoved(address indexed pool);
  event RebalanceCooldownSet(address indexed pool, uint64 cooldown);
  event RebalanceIncentiveSet(address indexed pool, uint32 incentiveBps);
  event RebalanceExecuted(address indexed pool, uint256 diffBeforeBps, uint256 diffAfterBps);
  event LiquidityMoved(
    address indexed pool,
    LQ.Direction direction,
    uint256 tokenInAmount,
    uint256 tokenOutAmount,
    uint256 incentiveAmount
  );
}
