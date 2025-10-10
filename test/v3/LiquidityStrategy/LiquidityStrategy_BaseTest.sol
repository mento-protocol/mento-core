// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { Test } from "mento-std/Test.sol";
import { MockFPMM } from "test/utils/mocks/MockFPMM.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/v3/libraries/LiquidityStrategyTypes.sol";
import { ILiquidityStrategy } from "contracts/v3/interfaces/ILiquidityStrategy.sol";

/**
 * @title LiquidityStrategy_BaseTest
 * @notice Abstract base test contract for all LiquidityStrategy tests
 * @dev Provides common setup, helper functions, and MockFPMM utilities
 */
abstract contract LiquidityStrategy_BaseTest is Test {
  // Mock addresses
  address public owner = makeAddr("Owner");
  address public notOwner = makeAddr("NotOwner");
  address public token0 = makeAddr("Token0");
  address public token1 = makeAddr("Token1");
  address public debtToken;
  address public collateralToken;

  function setUp() public virtual {
    // Ensure token0 < token1 for ordering
    debtToken = token0;
    collateralToken = token1;
  }

  /* ============================================================ */
  /* ============== MockFPMM Creation Helpers =================== */
  /* ============================================================ */

  /**
   * @notice Creates a MockFPMM with standard configuration
   * @param _debtToken The debt token address
   * @param _collateralToken The collateral token address
   * @return mockPool The created MockFPMM instance
   */
  function _createMockFPMM(address _debtToken, address _collateralToken) internal returns (MockFPMM mockPool) {
    mockPool = new MockFPMM(_debtToken, _collateralToken, false);
    mockPool.setRebalanceIncentive(100); // 1% default
    return mockPool;
  }

  /**
   * @notice Creates a MockFPMM with custom prices
   * @param _debtToken The debt token address
   * @param _collateralToken The collateral token address
   * @param oracleNum Oracle price numerator
   * @param oracleDen Oracle price denominator
   * @param reserveNum Reserve/pool price numerator
   * @param reserveDen Reserve/pool price denominator
   * @param diffBps Price difference in basis points
   * @param poolAbove Whether pool price is above oracle price
   * @return mockPool The created MockFPMM instance
   */
  function _createMockFPMMWithPrices(
    address _debtToken,
    address _collateralToken,
    uint256 oracleNum,
    uint256 oracleDen,
    uint256 reserveNum,
    uint256 reserveDen,
    uint256 diffBps,
    bool poolAbove
  ) internal returns (MockFPMM mockPool) {
    mockPool = _createMockFPMM(_debtToken, _collateralToken);
    mockPool.setPrices(oracleNum, oracleDen, reserveNum, reserveDen, diffBps, poolAbove);
    return mockPool;
  }

  /**
   * @notice Creates a MockFPMM configured for expansion (pool price above oracle)
   * @param _debtToken The debt token address
   * @param _collateralToken The collateral token address
   * @return mockPool The created MockFPMM instance
   */
  function _createMockFPMMForExpansion(
    address _debtToken,
    address _collateralToken
  ) internal returns (MockFPMM mockPool) {
    // Pool price 10% above oracle: 1.1:1 vs 1:1
    return _createMockFPMMWithPrices(_debtToken, _collateralToken, 1e18, 1e18, 110e18, 100e18, 1000, true);
  }

  /**
   * @notice Creates a MockFPMM configured for contraction (pool price below oracle)
   * @param _debtToken The debt token address
   * @param _collateralToken The collateral token address
   * @return mockPool The created MockFPMM instance
   */
  function _createMockFPMMForContraction(
    address _debtToken,
    address _collateralToken
  ) internal returns (MockFPMM mockPool) {
    // Pool price 10% below oracle: 0.9:1 vs 1:1
    return _createMockFPMMWithPrices(_debtToken, _collateralToken, 1e18, 1e18, 90e18, 100e18, 1000, false);
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
