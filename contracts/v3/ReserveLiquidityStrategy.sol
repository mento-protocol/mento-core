// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20MintableBurnable } from "../common/IERC20MintableBurnable.sol";
import { IReserve } from "../interfaces/IReserve.sol";
import { IFPMM } from "../interfaces/IFPMM.sol";
import { LiquidityTypes as LQ } from "./libraries/LiquidityTypes.sol";
import { ILiquidityStrategy } from "./Interfaces/ILiquidityStrategy.sol";

/**
 * @title   ReserveLiquidityStrategy
 * @notice  Implements a liquidity strategy that sources liquidity directly
 *          from the Reserve by minting/burning debt tokens and
 *          moving collateral.
 */
contract ReserveLiquidityStrategy is ILiquidityStrategy, OwnableUpgradeable, ReentrancyGuardUpgradeable {
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

  event RebalanceExecuted(
    address indexed pool,
    LQ.Direction direction,
    uint256 debtAmount,
    uint256 collateralAmount,
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
    __ReentrancyGuard_init();

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
  function execute(LQ.Action calldata action) external nonReentrant returns (bool ok) {
    require(action.liquiditySource == LQ.LiquiditySource.Reserve, "RLS: WRONG_SOURCE");
    require(action.pool != address(0), "RLS: INVALID_POOL");
    require(trustedPools[action.pool], "RLS: UNTRUSTED_POOL");

    // Decode callback data from action
    (uint256 incentiveAmount, bool isToken0Debt) = abi.decode(action.data, (uint256, bool));

    // Combine and encode necessary callback data for the hook
    bytes memory hookData = abi.encode(action.inputAmount, incentiveAmount, action.dir, isToken0Debt);

    IFPMM(action.pool).rebalance(action.amount0Out, action.amount1Out, hookData);

    emit RebalanceExecuted(
      action.pool,
      action.dir,
      action.dir == LQ.Direction.Expand ? action.inputAmount : action.amount0Out + action.amount1Out,
      action.dir == LQ.Direction.Contract ? action.inputAmount : action.amount0Out + action.amount1Out,
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

    if (direction == LQ.Direction.Expand) {
      _handleExpansionCallback(
        msg.sender, // pool address
        amount0Out,
        amount1Out,
        inputAmount,
        incentiveAmount,
        isToken0Debt
      );
    } else {
      _handleContractionCallback(
        msg.sender, // pool address
        amount0Out,
        amount1Out,
        inputAmount,
        incentiveAmount,
        isToken0Debt
      );
    }
  }

  /* ============================================================ */
  /* =================== Internal Functions ===================== */
  /* ============================================================ */

  /**
   * @notice Handle expansion callback: mint debt to pool, move collateral to reserve
   * @dev Pool price > oracle price. Move collateral OUT, debt IN.
   */
  function _handleExpansionCallback(
    address pool,
    uint256 amount0Out,
    uint256 amount1Out,
    uint256 inputAmount,
    uint256 incentiveAmount,
    bool isToken0Debt
  ) internal {
    (, , , , address token0, address token1) = IFPMM(pool).metadata();
    address debtTokenAddr = isToken0Debt ? token0 : token1;
    address collateralTokenAddr = isToken0Debt ? token1 : token0;

    IERC20MintableBurnable debtToken = IERC20MintableBurnable(debtTokenAddr);
    IERC20 collateralToken = IERC20(collateralTokenAddr);

    // Mint debt tokens to the pool
    uint256 debtToMint = inputAmount - incentiveAmount;
    debtToken.mint(pool, debtToMint);

    // Mint incentive to the strategy
    debtToken.mint(address(this), incentiveAmount);

    // Transfer collateral to the reserve
    uint256 collateralAmount = isToken0Debt ? amount1Out : amount0Out;
    collateralToken.safeTransfer(address(reserve), collateralAmount);
  }

  /**
   * @notice Handle contraction callback: burn debt from pool, provide collateral from reserve
   * @dev Pool price < oracle price. Move debt OUT, collateral IN.
   */
  function _handleContractionCallback(
    address pool,
    uint256 amount0Out,
    uint256 amount1Out,
    uint256 inputAmount,
    uint256 incentiveAmount,
    bool isToken0Debt
  ) internal {
    (, , , , address token0, address token1) = IFPMM(pool).metadata();
    address debtTokenAddr = isToken0Debt ? token0 : token1;
    address collateralTokenAddr = isToken0Debt ? token1 : token0;

    IERC20MintableBurnable debtToken = IERC20MintableBurnable(debtTokenAddr);

    // Burn debt tokens received from the pool
    uint256 debtAmount = isToken0Debt ? amount0Out : amount1Out;
    debtToken.burn(debtAmount);

    // Transfer collateral from reserve to pool
    uint256 collateralToPoolAmount = inputAmount - incentiveAmount;
    require(
      reserve.transferExchangeCollateralAsset(collateralTokenAddr, payable(pool), collateralToPoolAmount),
      "RLS: COLLATERAL_TRANSFER_FAILED"
    );

    // Transfer incentive from reserve to the strategy
    require(
      reserve.transferExchangeCollateralAsset(collateralTokenAddr, payable(address(this)), incentiveAmount),
      "RLS: INCENTIVE_TRANSFER_FAILED"
    );
  }
}
