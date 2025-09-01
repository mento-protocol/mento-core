// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { Test } from "mento-std/Test.sol";
import { ReserveLiquidityStrategy } from "contracts/v3/ReserveLiquidityStrategy.sol";
import { LiquidityTypes as LQ } from "contracts/v3/libraries/LiquidityTypes.sol";
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
    strategy = new ReserveLiquidityStrategy();

    // Initialize the strategy
    strategy.initialize(reserve, owner);
  }

  /* ============================================================ */
  /* ================= Helper Functions ========================= */
  /* ============================================================ */

  function _createAction(
    address _pool,
    LQ.Direction _direction,
    uint256 _amount0Out,
    uint256 _amount1Out,
    uint256 _inputAmount,
    uint256 _incentiveBps,
    bool _isToken0Debt
  ) internal pure returns (LQ.Action memory) {
    uint256 incentiveAmount = (_inputAmount * _incentiveBps) / 10000;
    bytes memory data = abi.encode(incentiveAmount, _isToken0Debt);

    return
      LQ.Action({
        pool: _pool,
        dir: _direction,
        liquiditySource: LQ.LiquiditySource.Reserve,
        amount0Out: _amount0Out,
        amount1Out: _amount1Out,
        inputAmount: _inputAmount,
        incentiveBps: _incentiveBps,
        data: data
      });
  }

  function _mockFPMMMetadata(address _pool, address _token0, address _token1) internal {
    bytes memory metadataCalldata = abi.encodeWithSelector(IFPMM.metadata.selector);
    vm.mockCall(_pool, metadataCalldata, abi.encode(1e18, 1e18, 100e18, 200e18, _token0, _token1));
  }

  function _mockFPMMRebalance(address _pool) internal {
    bytes memory rebalanceCalldata = abi.encodeWithSelector(IFPMM.rebalance.selector);
    vm.mockCall(_pool, rebalanceCalldata, abi.encode());
  }

  function _mockDebtTokenMint(address _debtToken) internal {
    bytes memory mintCalldata = abi.encodeWithSelector(IERC20MintableBurnable.mint.selector);
    vm.mockCall(_debtToken, mintCalldata, abi.encode());
  }

  function _mockDebtTokenBurn(address _debtToken) internal {
    bytes memory burnCalldata = abi.encodeWithSelector(IERC20MintableBurnable.burn.selector);
    vm.mockCall(_debtToken, burnCalldata, abi.encode());
  }

  function _mockCollateralTransfer(address _collateralToken) internal {
    bytes memory transferCalldata = abi.encodeWithSelector(bytes4(keccak256("safeTransfer(address,uint256)")));
    vm.mockCall(_collateralToken, transferCalldata, abi.encode());
  }

  function _mockReserveTransfer(address _reserve) internal {
    bytes memory transferCalldata = abi.encodeWithSelector(IReserve.transferExchangeCollateralAsset.selector);
    vm.mockCall(_reserve, transferCalldata, abi.encode(true));
  }

  function _expectLiquidityMovedEvent(
    address _pool,
    LQ.Direction _direction,
    uint256 _debtAmount,
    uint256 _collateralAmount,
    uint256 _incentiveAmount
  ) internal {
    vm.expectEmit(true, false, false, true);
    emit LiquidityMoved(_pool, _direction, _debtAmount, _collateralAmount, _incentiveAmount);
  }

  /* ============================================================ */
  /* ======================= Events ============================= */
  /* ============================================================ */

  event LiquidityMoved(
    address indexed pool,
    LQ.Direction direction,
    uint256 debtAmount,
    uint256 collateralAmount,
    uint256 incentiveAmount
  );
}
