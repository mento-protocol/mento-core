// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { Test } from "mento-std/Test.sol";
import { LiquidityStrategy_BaseTest } from "../LiquidityStrategy/LiquidityStrategy_BaseTest.sol";
import { ReserveLiquidityStrategy } from "contracts/v3/ReserveLiquidityStrategy.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/v3/libraries/LiquidityStrategyTypes.sol";
import { IERC20MintableBurnable } from "contracts/common/IERC20MintableBurnable.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";
import { IFPMM } from "contracts/interfaces/IFPMM.sol";

contract ReserveLiquidityStrategy_BaseTest is LiquidityStrategy_BaseTest {
  ReserveLiquidityStrategy public strategy;

  // Mock addresses
  address public reserve = makeAddr("Reserve");

  function setUp() public virtual override {
    LiquidityStrategy_BaseTest.setUp();
    strategy = new ReserveLiquidityStrategy(owner, reserve);
    strategyAddr = address(strategy);
  }

  modifier addFpmm(uint64 cooldown, uint32 incentiveBps) {
    // Mock reserve to recognize debt token as stable asset and collateral token as collateral asset
    vm.mockCall(reserve, abi.encodeWithSelector(IReserve.isStableAsset.selector, debtToken), abi.encode(true));
    vm.mockCall(reserve, abi.encodeWithSelector(IReserve.isStableAsset.selector, collToken), abi.encode(false));
    vm.mockCall(reserve, abi.encodeWithSelector(IReserve.isCollateralAsset.selector, debtToken), abi.encode(false));
    vm.mockCall(reserve, abi.encodeWithSelector(IReserve.isCollateralAsset.selector, collToken), abi.encode(true));

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
