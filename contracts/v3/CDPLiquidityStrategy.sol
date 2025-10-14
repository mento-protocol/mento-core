// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { ILiquidityStrategy } from "./Interfaces/ILiquidityStrategy.sol";
import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { LiquidityTypes as LQ } from "./libraries/LiquidityTypes.sol";
import { IFPMM } from "../interfaces/IFPMM.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { ICollateralRegistry } from "bold/Interfaces/ICollateralRegistry.sol";
import { IStabilityPool } from "bold/Interfaces/IStabilityPool.sol";

contract CDPLiquidityStrategy is ILiquidityStrategy, OwnableUpgradeable {
  using SafeERC20 for IERC20;

  mapping(address => bool) public trustedPools;

  constructor(bool disable) {
    if (disable) {
      _disableInitializers();
      _transferOwnership(msg.sender);
    }
  }

  function initialize() external initializer {
    __Ownable_init();
  }

  function setTrustedPools(address pool, bool isTrusted) external onlyOwner {
    trustedPools[pool] = isTrusted;
  }

  function execute(LQ.Action memory action) external override returns (bool ok) {
    (address debtToken, address collToken, address liquiditySource) = abi.decode(
      action.data,
      (address, address, address)
    );
    bytes memory hookData = abi.encode(
      action.inputAmount,
      action.incentiveBps,
      action.dir,
      debtToken,
      collToken,
      liquiditySource
    );

    IFPMM(action.pool).rebalance(action.amount0Out, action.amount1Out, hookData);
    return true;
  }

  function hook(address sender, uint256 amount0Out, uint256 amount1Out, bytes calldata data) external {
    require(trustedPools[msg.sender], "CDPLiquidityStrategy: UNTRUSTED_POOL");
    require(sender == address(this), "CDPLiquidityStrategy: INVALID_SENDER");

    (
      uint256 inputAmount,
      uint256 incentiveBps,
      LQ.Direction dir,
      address debtToken,
      address collToken,
      address liquiditySource
    ) = abi.decode(data, (uint256, uint256, LQ.Direction, address, address, address));
    uint256 amountOut = amount0Out > 0 ? amount0Out : amount1Out;
    if (dir == LQ.Direction.Expand) {
      _handleExpansionCallback(debtToken, collToken, amountOut, inputAmount, liquiditySource);
    } else {
      _handleContractionCallback(collToken, amountOut, inputAmount, incentiveBps, liquiditySource);
    }
  }

  function _handleExpansionCallback(
    address debtToken,
    address collToken,
    uint256 amountOut,
    uint256 inputAmount,
    address liquiditySource
  ) internal {
    // send collateral to stability pool
    IERC20(collToken).safeApprove(liquiditySource, amountOut);
    // swap collateral for debt
    IStabilityPool(liquiditySource).swapCollateralForStable(amountOut, inputAmount);
    // send debt to fpmm
    IERC20(debtToken).safeTransfer(msg.sender, inputAmount);
  }

  function _handleContractionCallback(
    address collToken,
    uint256 amountOut,
    uint256 inputAmount,
    uint256 incentiveBps,
    address liquiditySource
  ) internal {
    ICollateralRegistry(liquiditySource).redeemCollateral(amountOut, 100, incentiveBps);
    IERC20(collToken).safeTransfer(msg.sender, inputAmount);
  }
}
