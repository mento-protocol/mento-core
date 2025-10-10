// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { LiquidityStrategy_BaseTest } from "../LiquidityStrategy/LiquidityStrategy_BaseTest.sol";
import { ReserveLiquidityStrategy } from "contracts/v3/ReserveLiquidityStrategy.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/v3/libraries/LiquidityStrategyTypes.sol";
import { IERC20MintableBurnable } from "contracts/common/IERC20MintableBurnable.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";

/**
 * @title ReserveLiquidityStrategyBaseTest
 * @notice Abstract base test contract for ReserveLiquidityStrategy tests
 * @dev Extends LiquidityStrategy_BaseTest with Reserve-specific mocking utilities
 */
abstract contract ReserveLiquidityStrategyBaseTest is LiquidityStrategy_BaseTest {
  ReserveLiquidityStrategy public strategy;

  // Reserve-specific addresses
  address public reserve = makeAddr("Reserve");
  address public pool1 = makeAddr("Pool1");
  address public pool2 = makeAddr("Pool2");

  function setUp() public virtual override {
    super.setUp();
    strategy = new ReserveLiquidityStrategy(owner, reserve);
  }

  /* ============================================================ */
  /* ============ Reserve-Specific Helper Functions ============= */
  /* ============================================================ */

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
}
