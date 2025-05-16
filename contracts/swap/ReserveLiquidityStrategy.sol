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

    address stableToken = fpm.token0();
    address collateralToken = fpm.token1();

    UD60x18 stableReserve = ud(fpm.reserve0() * tokenPrecisionMultipliers[stableToken]);
    UD60x18 collateralReserve = ud(fpm.reserve1() * tokenPrecisionMultipliers[collateralToken]);

    UD60x18 oraclePriceUD = ud(oraclePrice);

    uint256 stableOut = 0;
    uint256 collateralOut = 0;
    uint256 inputAmount;

    if (priceDirection == PriceDirection.ABOVE_ORACLE) {
      // Contraction: Buy stables from the pool using collateral from reserve
      // Y = (S - P * C) / (2 * P)
      // X = Y * P
      UD60x18 numerator = stableReserve.sub(oraclePriceUD.mul(collateralReserve));
      UD60x18 denominator = oraclePriceUD.mul(ud(2e18));
      UD60x18 collateralToSell = numerator.div(denominator);
      UD60x18 stablesToBuy = collateralToSell.mul(oraclePriceUD);

      stableOut = stablesToBuy.unwrap() / tokenPrecisionMultipliers[stableToken];
      inputAmount = collateralToSell.unwrap() / tokenPrecisionMultipliers[collateralToken];
    } else {
      // Expansion: Buy collateral from the pool using newly minted stables
      // X = (C * P - S) / 2
      // Y = X / P
      UD60x18 numerator = (collateralReserve.mul(oraclePriceUD)).sub(stableReserve);
      UD60x18 denominator = ud(2e18);
      UD60x18 stablesToSell = numerator.div(denominator);
      UD60x18 collateralToBuy = stablesToSell.div(oraclePriceUD);

      collateralOut = collateralToBuy.unwrap() / tokenPrecisionMultipliers[collateralToken];
      inputAmount = stablesToSell.unwrap() / tokenPrecisionMultipliers[stableToken];
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
  function hook(address, uint256 amount0Out, uint256 amount1Out, bytes calldata data) external {
    (address pool, uint256 amountIn, PriceDirection priceDirection) = abi.decode(
      data,
      (address, uint256, PriceDirection)
    );

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
