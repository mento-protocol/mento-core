// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { Test } from "mento-std/Test.sol";
import { ReserveLiquidityStrategy } from "contracts/v3/ReserveLiquidityStrategy.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/v3/libraries/LiquidityStrategyTypes.sol";
import { IERC20MintableBurnable } from "contracts/common/IERC20MintableBurnable.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";
import { IFPMM } from "contracts/interfaces/IFPMM.sol";

contract ReserveLiquidityStrategyBaseTest is Test {
  ReserveLiquidityStrategy public strategy;

  // Mock addresses
  address public reserve = makeAddr("Reserve");
  address public owner = makeAddr("Owner");
  address public notOwner = makeAddr("NotOwner");
  address public pool1 = makeAddr("Pool1");
  address public pool2 = makeAddr("Pool2");
  address public token0 = makeAddr("Token0");
  address public token1 = makeAddr("Token1");
  address public debtToken = makeAddr("DebtToken");
  address public collateralToken = makeAddr("CollateralToken");

  function setUp() public virtual {
    // New architecture uses constructor instead of initialize
    strategy = new ReserveLiquidityStrategy(owner, reserve);
  }

  /* ============================================================ */
  /* ================= Helper Functions ========================= */
  /* ============================================================ */

  function _mockFPMMMetadata(address _pool, address _token0, address _token1) internal {
    bytes memory metadataCalldata = abi.encodeWithSelector(IFPMM.metadata.selector);
    vm.mockCall(_pool, metadataCalldata, abi.encode(1e18, 1e18, 100e18, 200e18, _token0, _token1));
  }

  function _mockFPMMTokens(address _pool, address _token0, address _token1) internal {
    // Ensure tokens are in sorted order (smaller address first)
    (address orderedToken0, address orderedToken1) = _token0 < _token1 ? (_token0, _token1) : (_token1, _token0);

    bytes memory tokensCalldata = abi.encodeWithSelector(IFPMM.tokens.selector);
    vm.mockCall(_pool, tokensCalldata, abi.encode(orderedToken0, orderedToken1));
  }

  function _mockFPMMPrices(
    address _pool,
    uint256 oracleNum,
    uint256 oracleDen,
    uint256 reserveNum,
    uint256 reserveDen,
    uint256 diffBps,
    bool poolAbove
  ) internal {
    bytes memory pricesCalldata = abi.encodeWithSelector(IFPMM.getPrices.selector);
    vm.mockCall(_pool, pricesCalldata, abi.encode(oracleNum, oracleDen, reserveNum, reserveDen, diffBps, poolAbove));
  }

  function _mockFPMMRebalanceIncentive(address _pool, uint256 incentive) internal {
    bytes memory incentiveCalldata = abi.encodeWithSelector(IFPMM.rebalanceIncentive.selector);
    vm.mockCall(_pool, incentiveCalldata, abi.encode(incentive));
  }

  function _mockFPMMRebalanceThresholds(address _pool, uint256 above, uint256 below) internal {
    bytes memory aboveCalldata = abi.encodeWithSelector(IFPMM.rebalanceThresholdAbove.selector);
    vm.mockCall(_pool, aboveCalldata, abi.encode(above));

    bytes memory belowCalldata = abi.encodeWithSelector(IFPMM.rebalanceThresholdBelow.selector);
    vm.mockCall(_pool, belowCalldata, abi.encode(below));
  }

  function _mockFPMMRebalance(address _pool) internal {
    bytes memory rebalanceCalldata = abi.encodeWithSelector(IFPMM.rebalance.selector);
    vm.mockCall(_pool, rebalanceCalldata, abi.encode());
  }

  function _mockDebtTokenMint(address _debtToken) internal {
    bytes memory mintCalldata = abi.encodeWithSelector(IERC20MintableBurnable.mint.selector);
    vm.mockCall(_debtToken, mintCalldata, abi.encode());
    // Mock that debt tokens are stable assets (not collateral)
    _mockIsStableAsset(reserve, _debtToken, true);
    _mockIsCollateralAsset(reserve, _debtToken, false);
  }

  function _mockDebtTokenBurn(address _debtToken) internal {
    bytes memory burnCalldata = abi.encodeWithSelector(IERC20MintableBurnable.burn.selector);
    vm.mockCall(_debtToken, burnCalldata, abi.encode());
    // Mock that debt tokens are stable assets (not collateral)
    _mockIsStableAsset(reserve, _debtToken, true);
    _mockIsCollateralAsset(reserve, _debtToken, false);
  }

  function _mockCollateralTransfer(address _collateralToken) internal {
    bytes memory transferCalldata = abi.encodeWithSelector(bytes4(keccak256("safeTransfer(address,uint256)")));
    vm.mockCall(_collateralToken, transferCalldata, abi.encode());
    // Mock that collateral tokens are collateral assets (not stable)
    _mockIsCollateralAsset(reserve, _collateralToken, true);
    _mockIsStableAsset(reserve, _collateralToken, false);
  }

  function _mockReserveTransfer(address _reserve) internal {
    bytes memory transferCalldata = abi.encodeWithSelector(IReserve.transferExchangeCollateralAsset.selector);
    vm.mockCall(_reserve, transferCalldata, abi.encode(true));
  }

  function _mockIsStableAsset(address _reserve, address _token, bool _isStable) internal {
    bytes memory calldata_ = abi.encodeWithSelector(IReserve.isStableAsset.selector, _token);
    vm.mockCall(_reserve, calldata_, abi.encode(_isStable));
  }

  function _mockIsCollateralAsset(address _reserve, address _token, bool _isCollateral) internal {
    bytes memory calldata_ = abi.encodeWithSelector(IReserve.isCollateralAsset.selector, _token);
    vm.mockCall(_reserve, calldata_, abi.encode(_isCollateral));
  }

  function _mockERC20BalanceOf(address _token, address _account, uint256 _balance) internal {
    bytes memory calldata_ = abi.encodeWithSelector(bytes4(keccak256("balanceOf(address)")), _account);
    vm.mockCall(_token, calldata_, abi.encode(_balance));
  }

  /* ============================================================ */
  /* ======================= Events ============================= */
  /* ============================================================ */

  event PoolAdded(
    address indexed pool,
    address indexed debtToken,
    address indexed collateralToken,
    uint64 cooldown,
    uint32 incentiveBps
  );

  event PoolRemoved(address indexed pool);
  event RebalanceCooldownSet(address indexed pool, uint64 cooldown);
  event RebalanceIncentiveSet(address indexed pool, uint32 incentiveBps);
  event RebalanceExecuted(address indexed pool, uint256 diffBefore, uint256 diffAfter);
}
