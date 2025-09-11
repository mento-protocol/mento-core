// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20MintableBurnable } from "../common/IERC20MintableBurnable.sol";
import { IReserve } from "../interfaces/IReserve.sol";
import { IFPMM } from "../interfaces/IFPMM.sol";
import { LiquidityTypes as LQ } from "./libraries/LiquidityTypes.sol";
import { ILiquidityStrategy } from "./Interfaces/ILiquidityStrategy.sol";

/**
 * @title   ReserveLiquidityStrategy
 * @notice  Implements a liquidity strategy that sources liquidity directly from the Reserve.
 */
contract ReserveLiquidityStrategy is ILiquidityStrategy, OwnableUpgradeable {
  using SafeERC20 for IERC20;

  /* ============================================================ */
  /* ==================== State Variables ====================== */
  /* ============================================================ */

  /// @notice The reserve contract that holds collateral
  IReserve public reserve;

  /// @notice Mapping of trusted liquidity pools
  mapping(address => bool) public trustedPools;

  /* ============================================================ */
  /* ======================== Events ============================ */
  /* ============================================================ */

  event LiquidityMoved(
    address indexed pool,
    LQ.Direction direction,
    uint256 tokenInAmount,
    uint256 tokenOutAmount,
    uint256 incentiveAmount
  );

  event ReserveSet(address indexed oldReserve, address indexed newReserve);
  event TrustedPoolUpdated(address indexed pool, bool isTrusted);

  /* ============================================================ */
  /* ==================== Initialization ======================== */
  /* ============================================================ */

  /**
   * @notice Initialize the strategy with reserve address and owner
   * @param _reserve The reserve contract address
   * @param _owner The owner of the strategy
   */
  function initialize(address _reserve, address _owner) external initializer {
    __Ownable_init();

    require(_reserve != address(0), "RLS: INVALID_RESERVE");
    require(_owner != address(0), "RLS: INVALID_OWNER");

    reserve = IReserve(_reserve);
    _transferOwnership(_owner);

    emit ReserveSet(address(0), _reserve);
  }

  /* ============================================================ */
  /* ====================== Admin Functions ===================== */
  /* ============================================================ */

  /**
   * @notice Set the reserve contract address
   * @param _reserve The new reserve contract address
   */
  function setReserve(address _reserve) external onlyOwner {
    require(_reserve != address(0), "RLS: INVALID_RESERVE");

    address oldReserve = address(reserve);
    reserve = IReserve(_reserve);

    emit ReserveSet(oldReserve, _reserve);
  }

  /**
   * @notice Set a trusted liquidity pool
   * @param pool The address of the liquidity pool
   * @param isTrusted Whether the pool is trusted or not
   */
  function setTrustedPool(address pool, bool isTrusted) external onlyOwner {
    require(pool != address(0), "RLS: INVALID_POOL");
    trustedPools[pool] = isTrusted;
    emit TrustedPoolUpdated(pool, isTrusted);
  }

  /* ============================================================ */
  /* ===================== External Functions =================== */
  /* ============================================================ */

  /**
   * @notice Execute a liquidity action by calling FPMM.rebalance()
   * @param action The action to execute
   * @return ok True if execution succeeded
   */
  function execute(LQ.Action calldata action) external returns (bool ok) {
    require(action.liquiditySource == LQ.LiquiditySource.Reserve, "RLS: WRONG_SOURCE");
    require(action.pool != address(0), "RLS: INVALID_POOL");
    require(trustedPools[action.pool], "RLS: UNTRUSTED_POOL");

    // Decode callback data from action
    (uint256 incentiveAmount, bool isToken0Debt) = abi.decode(action.data, (uint256, bool));

    // Combine and encode necessary callback data for the hook
    bytes memory hookData = abi.encode(action.inputAmount, incentiveAmount, action.dir, isToken0Debt);

    IFPMM(action.pool).rebalance(action.amount0Out, action.amount1Out, hookData);

    emit LiquidityMoved(
      action.pool,
      action.dir,
      action.inputAmount,
      action.amount0Out + action.amount1Out,
      incentiveAmount
    );

    return true;
  }

  /**
   * @notice Hook called by FPMM during rebalance to complete the operation.
   * @param sender The address that initiated the rebalance. Should be this contract.
   * @param amount0Out The amount of token0 to move out of the pool.
   * @param amount1Out The amount of token1 to move out of the pool.
   * @param data Encoded callback data
   */
  function hook(address sender, uint256 amount0Out, uint256 amount1Out, bytes calldata data) external {
    require(trustedPools[msg.sender], "RLS: UNTRUSTED_POOL");
    require(sender == address(this), "RLS: INVALID_SENDER");

    (uint256 inputAmount, uint256 incentiveAmount, LQ.Direction direction, bool isToken0Debt) = abi.decode(
      data,
      (uint256, uint256, LQ.Direction, bool)
    );

    _handleRebalanceCallback(
      msg.sender,
      amount0Out,
      amount1Out,
      inputAmount,
      incentiveAmount,
      direction,
      isToken0Debt
    );
  }

  /* ============================================================ */
  /* =================== Internal Functions ===================== */
  /* ============================================================ */

  /**
   * @notice Handle rebalance callback: provide tokens IN to pool, receive tokens OUT
   * @dev Handles both expansion and contraction directions
   * @param pool The pool address
   * @param amount0Out Amount of token0 coming out of the pool
   * @param amount1Out Amount of token1 coming out of the pool
   * @param inputAmount Total amount going into the pool (including incentive)
   * @param incentiveAmount Incentive amount for the rebalancer
   * @param direction The rebalance direction (Expand or Contract)
   * @param isToken0Debt Whether token0 is the debt token
   */
  function _handleRebalanceCallback(
    address pool,
    uint256 amount0Out,
    uint256 amount1Out,
    uint256 inputAmount,
    uint256 incentiveAmount,
    LQ.Direction direction,
    bool isToken0Debt
  ) internal {
    (address token0, address token1) = IFPMM(pool).tokens();
    
    address tokenIn;
    address tokenOut;
    uint256 amountOut;
    
    if (direction == LQ.Direction.Expand) {
      // Expansion: Pool price > oracle price
      // Reserve provides debt to pool, receives collateral from pool
      tokenIn = isToken0Debt ? token0 : token1;  // debt
      tokenOut = isToken0Debt ? token1 : token0; // collateral
      amountOut = isToken0Debt ? amount1Out : amount0Out;
    } else {
      // Contraction: Pool price < oracle price
      // Reserve provides collateral to pool, receives debt from pool
      tokenIn = isToken0Debt ? token1 : token0;  // collateral
      tokenOut = isToken0Debt ? token0 : token1; // debt
      amountOut = isToken0Debt ? amount0Out : amount1Out;
    }

    // Handle token going INTO the pool
    uint256 amountToPool = inputAmount - incentiveAmount;
    _transferTokenIn(tokenIn, pool, amountToPool, incentiveAmount);
    
    // Handle token coming OUT of the pool
    _transferTokenOut(tokenOut, amountOut);
  }

  /**
   * @notice Transfer tokens into the pool and pay incentive
   * @param token The token to transfer in
   * @param pool The pool to transfer to
   * @param amountToPool Amount to send to the pool
   * @param incentiveAmount Incentive amount to send to this contract
   */
  function _transferTokenIn(
    address token,
    address pool,
    uint256 amountToPool,
    uint256 incentiveAmount
  ) internal {
    if (reserve.isStableAsset(token)) {
      // Mint stable assets directly
      IERC20MintableBurnable(token).mint(pool, amountToPool);
      if (incentiveAmount > 0) {
        IERC20MintableBurnable(token).mint(address(this), incentiveAmount);
      }
    } else if (reserve.isCollateralAsset(token)) {
      // Transfer collateral from reserve
      require(
        reserve.transferExchangeCollateralAsset(token, payable(pool), amountToPool),
        "RLS: COLLATERAL_TO_POOL_FAILED"
      );
      if (incentiveAmount > 0) {
        require(
          reserve.transferExchangeCollateralAsset(token, payable(address(this)), incentiveAmount),
          "RLS: INCENTIVE_TRANSFER_FAILED"
        );
      }
    } else {
      revert("RLS: TOKEN_IN_NOT_SUPPORTED");
    }
  }

  /**
   * @notice Transfer tokens out from the pool back to reserve
   * @param token The token to transfer out
   * @param amount The amount to transfer
   */
  function _transferTokenOut(address token, uint256 amount) internal {
    if (amount == 0) return;
    
    if (reserve.isStableAsset(token)) {
      // Burn stable assets received from pool
      IERC20MintableBurnable(token).burn(amount);
    } else if (reserve.isCollateralAsset(token)) {
      // Transfer collateral back to reserve
      IERC20(token).safeTransfer(address(reserve), amount);
    } else {
      revert("RLS: TOKEN_OUT_NOT_SUPPORTED");
    }
  }
}
