// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { SafeERC20MintableBurnable } from "contracts/common/SafeERC20MintableBurnable.sol";
import { IERC20MintableBurnable as IERC20 } from "contracts/common/IERC20MintableBurnable.sol";
import { UD60x18, ud } from "prb-math/UD60x18.sol";

import { LiquidityStrategy } from "./LiquidityStrategy.sol";
import { IFPMM } from "../interfaces/IFPMM.sol";
import { IReserve } from "../interfaces/IReserve.sol";

/**
 * @title ReserveLiquidityStrategy
 * @notice Liquidity strategy that uses the reserve as a liquidity source.
 */
contract ReserveLiquidityStrategy is LiquidityStrategy {
  using SafeERC20MintableBurnable for IERC20;

  /**
   * @notice Emitted when the reserve address is set.
   * @param reserve The address of the reserve that was set.
   */
  event ReserveSet(address indexed reserve);

  IReserve public reserve;

  struct PoolReserves {
    UD60x18 stableReserve;
    UD60x18 collateralReserve;
    uint256 stablePrecision;
    uint256 collateralPrecision;
  }

  constructor(bool disableInitializers) LiquidityStrategy(disableInitializers) {}

  function initialize(address _reserve) external initializer {
    __Ownable_init();
    setReserve(_reserve);
  }

  /**
   * @notice Sets the reserve address.
   * @param _reserve The address of the reserve.
   */
  function setReserve(address _reserve) public onlyOwner {
    require(_reserve != address(0), "RLS: ZERO_ADDRESS_RESERVE");
    reserve = IReserve(_reserve);
    emit ReserveSet(_reserve);
  }

  /**
   * @notice Calculates the amounts for contraction (when pool price is below oracle price)
   * @param reserves Struct containing reserve amounts and scaling factors
   * @param oraclePrice The off-chain target price
   * @return stableOut Amount of stable tokens to move out of the pool
   * @return collateralIn Amount of collateral tokens to move into the pool
   */
  function _calculateContractionAmounts(
    PoolReserves memory reserves,
    UD60x18 oraclePrice
  ) private pure returns (uint256 stableOut, uint256 collateralIn) {
    // Contraction: Sell stables to buy collateral
    // Y = (P * S - C) / 2
    // X = (Y ^ 2) / P
    UD60x18 numerator = (oraclePrice.mul(reserves.stableReserve)).sub(reserves.collateralReserve);
    UD60x18 denominator = ud(2e18);

    UD60x18 collateralInUd = numerator.div(denominator);
    UD60x18 stableOutUd = collateralInUd.powu(2).div(oraclePrice);

    stableOut = stableOutUd.unwrap() / reserves.stablePrecision;
    collateralIn = collateralInUd.unwrap() / reserves.collateralPrecision;
  }

  /**
   * @notice Calculates the amounts for expansion (when pool price is above oracle price)
   * @param reserves Struct containing reserve amounts and scaling factors
   * @param oraclePrice The off-chain target price
   * @return collateralOut Amount of collateral tokens to move out of the pool
   * @return stablesIn Amount of stable tokens to move into the pool
   */
  function _calculateExpansionAmounts(
    PoolReserves memory reserves,
    UD60x18 oraclePrice
  ) private pure returns (uint256 collateralOut, uint256 stablesIn) {
    // Expansion: Sell collateral to buy stables
    // Y = (C - P * S) / 2
    // X = Y / P
    UD60x18 numerator = reserves.stableReserve.sub(reserves.stableReserve.mul(oraclePrice));
    UD60x18 denominator = ud(2e18);

    UD60x18 collateralOutUd = numerator.div(denominator);
    UD60x18 stablesInUd = collateralOutUd.div(oraclePrice);

    collateralOut = collateralOutUd.unwrap() / reserves.collateralPrecision;
    stablesIn = stablesInUd.unwrap() / reserves.stablePrecision;
  }

  /**
   * @notice Executes the rebalance logic using the reserve as a liquidity source. This function
   *         will initiate moving tokens out of the pool. The actual token transfers will be completed
   *         in the onRebalanceCallback function, which will be called by the pool.
   * @dev If the pool price is above the oracle price, meaning the stable token
   *      is undervalued(too much stable for the collateral), we buy stables from
   *      the pool, using collateral from the reserve, to be burned.
   *      If the pool price is below the oracle price, meaning the stable token
   *      is overvalued(too much collateral for the stable), we buy collateral
   *      from the pool, using newly minted stables, to be transferred to the reserve.
   * @param pool The address of the pool.
   * @param oraclePrice The off‑chain target price.
   * @param priceDirection The direction of the price movement.
   */
  function _executeRebalance(address pool, uint256 oraclePrice, PriceDirection priceDirection) internal override {
    IFPMM fpm = IFPMM(pool);

    // Get reserves and decimal scaling factors from the pool
    (uint256 decimals0, uint256 decimals1, uint256 reserve0, uint256 reserve1, , ) = fpm.metadata();
    require(decimals0 <= 18 && decimals1 <= 18, "RLS: TOKEN_DECIMALS_TOO_LARGE");

    // Create a reserves struct to pass to calculation functions
    PoolReserves memory reserves = PoolReserves({
      stableReserve: ud(reserve0 * (10 ** (18 - decimals0))),
      collateralReserve: ud(reserve1 * (10 ** (18 - decimals1))),
      stablePrecision: 10 ** (18 - decimals0),
      collateralPrecision: 10 ** (18 - decimals1)
    });

    uint256 stableOut;
    uint256 collateralOut;
    uint256 inputAmount;

    if (priceDirection == PriceDirection.ABOVE_ORACLE) {
      (collateralOut, inputAmount) = _calculateExpansionAmounts(reserves, ud(oraclePrice));
      stableOut = 0;
    } else {
      (stableOut, inputAmount) = _calculateContractionAmounts(reserves, ud(oraclePrice));
      collateralOut = 0;
    }

    bytes memory callbackData = abi.encode(pool, inputAmount, priceDirection);

    emit RebalanceInitiated(pool, stableOut, collateralOut, inputAmount, priceDirection);
    fpm.rebalance(stableOut, collateralOut, address(this), callbackData);
  }

  /**
   * @notice Handles the callback from the pool after a rebalance.
   * @param amount0Out The amount of token0 to move out of the pool.
   * @param amount1Out The amount of token1 to move out of the pool.
   * @param data The encoded data from the pool.
   */
  function hook(address sender, uint256 amount0Out, uint256 amount1Out, bytes calldata data) external {
    (address pool, uint256 amountIn, PriceDirection priceDirection) = abi.decode(
      data,
      (address, uint256, PriceDirection)
    );

    require(sender == address(this), "RLS: CALLER_NOT_REBALANCE_INITIATOR");
    require(msg.sender == pool, "RLS: CALLER_NOT_POOL");
    require(isPoolRegistered(pool), "RLS: UNREGISTERED_POOL");

    IFPMM fpm = IFPMM(pool);

    address stableToken = fpm.token0();
    address collateralToken = fpm.token1();

    if (priceDirection == PriceDirection.ABOVE_ORACLE) {
      // Contraction: burn stables, pull collateral from reserve and send to FPMM
      IERC20(stableToken).safeBurn(amount0Out);
      require(
        reserve.transferExchangeCollateralAsset(collateralToken, payable(pool), amountIn),
        "RLS: COLLATERAL_TRANSFER_FAILED"
      );
    } else {
      // Expansion: mint stables to FPMM, transfer received collateral to reserve
      IERC20(stableToken).safeMint(pool, amountIn);
      require(IERC20(collateralToken).transfer(address(reserve), amount1Out), "RLS: COLLATERAL_TRANSFER_FAILED");
    }
  }
}
