// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { SafeERC20MintableBurnable } from "contracts/common/SafeERC20MintableBurnable.sol";
import { IERC20MintableBurnable as IERC20 } from "contracts/common/IERC20MintableBurnable.sol";
// solhint-disable-next-line max-line-length
import { SafeERC20Upgradeable } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { LiquidityStrategy } from "./LiquidityStrategy.sol";
import { IFPMM } from "../interfaces/IFPMM.sol";
import { IReserve } from "../interfaces/IReserve.sol";

/**
 * @title ReserveLiquidityStrategy
 * @notice Liquidity strategy that uses the reserve as a liquidity source.
 */
contract ReserveLiquidityStrategy is LiquidityStrategy {
  using SafeERC20MintableBurnable for IERC20;
  using SafeERC20Upgradeable for IERC20;

  IReserve public reserve;

  /// @notice Struct to store pool rebalancing parameters.
  struct RebalanceParams {
    uint256 stableReserve;
    uint256 collateralReserve;
    uint256 stablePrecision;
    uint256 collateralPrecision;
  }

  /**
   * @notice Emitted when the reserve address is set.
   * @param reserve The address of the reserve that was set.
   */
  event ReserveSet(address indexed reserve);

  /* ==================== Constructor ==================== */

  /**
   * @dev Should be called with disable=true in deployments when it's accessed through a Proxy.
   * Call this with disable=false during testing, when used without a proxy.
   * @param disableInitializers Set to true to run `_disableInitializers()` inherited from
   * openzeppelin-contracts-upgradeable/Initializable.sol
   */
  constructor(bool disableInitializers) LiquidityStrategy(disableInitializers) {}

  /* ==================== Initializer ==================== */

  /**
   * @notice Initializes the ReserveLiquidityStrategy contract.
   * @param _reserve Address of the reserve contract.
   */
  function initialize(address _reserve) external initializer {
    __Ownable_init();
    setReserve(_reserve);
  }

  /* ==================== External Functions ==================== */

  /**
   * @notice Handles the callback from the pool after a rebalance.
   * @param sender The address that initiated the rebalance.
   * @param amount0Out The amount of token0 to move out of the pool.
   * @param amount1Out The amount of token1 to move out of the pool.
   * @param data The encoded data from the pool.
   */
  function hook(address sender, uint256 amount0Out, uint256 amount1Out, bytes calldata data) external {
    (uint256 amountIn, PriceDirection priceDirection, uint256 incentiveAmount) = abi.decode(
      data,
      (uint256, PriceDirection, uint256)
    );

    require(sender == address(this), "RLS: HOOK_SENDER_NOT_SELF");
    require(isPoolRegistered(msg.sender), "RLS: UNREGISTERED_POOL");

    IFPMM fpm = IFPMM(msg.sender);

    address stableToken = fpm.token0();
    address collateralToken = fpm.token1();

    if (priceDirection == PriceDirection.ABOVE_ORACLE) {
      // Expansion: mint stables to FPMM, transfer received collateral to reserve, collect incentive in strategy contract
      IERC20(stableToken).safeMint(msg.sender, amountIn - incentiveAmount);
      IERC20(stableToken).safeMint(address(this), incentiveAmount);
      IERC20(collateralToken).safeTransfer(address(reserve), amount1Out);
    } else {
      // Contraction: burn stables, pull collateral from reserve and send to FPMM, collect incentive in strategy contract
      IERC20(stableToken).safeBurn(amount0Out);
      require(
        reserve.transferExchangeCollateralAsset(collateralToken, payable(msg.sender), amountIn - incentiveAmount),
        "RLS: COLLATERAL_TRANSFER_FAILED"
      );
      require(
        reserve.transferExchangeCollateralAsset(collateralToken, payable(address(this)), incentiveAmount),
        "RLS: INCENTIVE_TRANSFER_FAILED"
      );
    }
  }

  /* ==================== Admin Functions ==================== */

  /**
   * @notice Sets the reserve address.
   * @param _reserve The address of the reserve.
   */
  function setReserve(address _reserve) public onlyOwner {
    require(_reserve != address(0), "RLS: ZERO_ADDRESS_RESERVE");
    reserve = IReserve(_reserve);
    emit ReserveSet(_reserve);
  }

  /* ==================== Internal Functions ==================== */

  /**
   * @notice Initiates the rebalance logic using the reserve as a liquidity source. This function
   *         initiates the movement of tokens out of the pool (either stable or collateral,
   *         depending on the rebalance direction). The rebalance is completed in the `hook`
   *         function, which is called by the pool, handling the corresponding token mints/burns
   *         and transfers to/from the reserve. The incentive is the reward for the strategy to
   *         incentivize the rebalance.
   * @param pool The address of the pool.
   * @param oraclePriceNumerator The numerator of the target price.
   * @param oraclePriceDenominator The denominator of the target price.
   * @param priceDirection Indicates if the pool price is above or below the oracle price.
   */
  function _executeRebalance(
    address pool,
    uint256 oraclePriceNumerator,
    uint256 oraclePriceDenominator,
    PriceDirection priceDirection
  ) internal override {
    IFPMM fpmm = IFPMM(pool);

    uint256 incentive = _getIncentive(fpmm);

    (uint256 stableOut, uint256 collateralOut, uint256 inputAmount) = _calculateRebalanceAmounts(
      fpmm,
      oraclePriceNumerator,
      oraclePriceDenominator,
      priceDirection,
      incentive
    );

    uint256 incentiveAmount = (inputAmount * incentive) / BPS_SCALE;

    bytes memory callbackData = abi.encode(inputAmount, priceDirection, incentiveAmount);

    emit RebalanceInitiated(
      pool,
      stableOut,
      collateralOut,
      inputAmount - incentiveAmount,
      incentiveAmount,
      priceDirection
    );
    fpmm.rebalance(stableOut, collateralOut, callbackData);
  }

  /* ==================== Private Functions ==================== */

  /**
   * @dev Calculates all amounts needed for a rebalance.
   * @param fpmm The pool contract.
   * @param oraclePriceNumerator The numerator of the target price.
   * @param oraclePriceDenominator The denominator of the target price.
   * @param priceDirection Indicates if the pool price is above or below the oracle price.
   * @param incentive The rebalance incentive in basis points.
   * @return stableOut Amount of stable tokens to move out of the pool.
   * @return collateralOut Amount of collateral tokens to move into the pool.
   * @return inputAmount Amount of tokens to move into the pool.
   */
  function _calculateRebalanceAmounts(
    IFPMM fpmm,
    uint256 oraclePriceNumerator,
    uint256 oraclePriceDenominator,
    PriceDirection priceDirection,
    uint256 incentive
  ) private view returns (uint256 stableOut, uint256 collateralOut, uint256 inputAmount) {
    // slither-disable-next-line unused-return
    (uint256 dec0, uint256 dec1, uint256 reserve0, uint256 reserve1, , ) = fpmm.metadata();

    require(dec0 <= 1e18 && dec1 <= 1e18, "RLS: TOKEN_DECIMALS_TOO_LARGE");

    // slither-disable-next-line uninitialized-local
    RebalanceParams memory params;
    params.stablePrecision = 1e18 / dec0;
    params.collateralPrecision = 1e18 / dec1;
    params.stableReserve = reserve0 * params.stablePrecision;
    params.collateralReserve = reserve1 * params.collateralPrecision;

    if (priceDirection == PriceDirection.ABOVE_ORACLE) {
      (collateralOut, inputAmount) = _calculateExpansionAmounts(
        params,
        oraclePriceNumerator,
        oraclePriceDenominator,
        incentive
      );
      stableOut = 0;
    } else {
      (stableOut, inputAmount) = _calculateContractionAmounts(
        params,
        oraclePriceNumerator,
        oraclePriceDenominator,
        incentive
      );
      collateralOut = 0;
    }
  }

  /**
   * @notice Calculates the amounts for contraction (when pool price is below oracle price)
   * @dev Contraction: move stables out of the pool and move collateral into the pool.
   *      StablesOut = (OraclePrice * StableReserve - CollateralReserve) / (OraclePrice + OraclePrice * (1 - incentive))
   *      CollateralIn = StablesOut * OraclePrice
   * @param params Struct containing rebalancing parameters.
   * @param oraclePriceNumerator The numerator of the target price.
   * @param oraclePriceDenominator The denominator of the target price.
   * @param incentive The rebalance incentive in basis points.
   * @return stableOut Amount of stable tokens to move out of the pool.
   * @return collateralIn Amount of collateral tokens to move into the pool.
   */
  function _calculateContractionAmounts(
    RebalanceParams memory params,
    uint256 oraclePriceNumerator,
    uint256 oraclePriceDenominator,
    uint256 incentive
  ) private pure returns (uint256 stableOut, uint256 collateralIn) {
    uint256 numerator = (params.stableReserve * oraclePriceNumerator) -
      (params.collateralReserve * oraclePriceDenominator);
    uint256 denominator = oraclePriceNumerator + ((oraclePriceNumerator * (BPS_SCALE - incentive)) / BPS_SCALE);
    uint256 stableOutRaw = numerator / denominator;
    // slither-disable-start divide-before-multiply
    stableOut = stableOutRaw / params.stablePrecision;

    uint256 collateralInRaw = (stableOut * params.stablePrecision * oraclePriceNumerator) / oraclePriceDenominator;

    collateralIn = collateralInRaw / params.collateralPrecision;
    // slither-disable-end divide-before-multiply
  }

  /**
   * @notice Calculates the amounts for expansion (when pool price is above oracle price)
   * @dev Expansion: move collateral out of the pool and move stables into the pool.
   *      CollateralOut = (CollateralReserve - OraclePrice * StableReserve) / (1 + 1 - incentive)
   *      StablesIn = CollateralOut / OraclePrice
   * @param params Struct containing rebalancing parameters.
   * @param oraclePriceNumerator The numerator of the target price.
   * @param oraclePriceDenominator The denominator of the target price.
   * @param incentive The rebalance incentive in basis points.
   * @return collateralOut Amount of collateral tokens to move out of the pool.
   * @return stablesIn Amount of stable tokens to move into the pool.
   */
  function _calculateExpansionAmounts(
    RebalanceParams memory params,
    uint256 oraclePriceNumerator,
    uint256 oraclePriceDenominator,
    uint256 incentive
  ) private pure returns (uint256 collateralOut, uint256 stablesIn) {
    uint256 numerator = params.collateralReserve -
      ((params.stableReserve * oraclePriceNumerator) / oraclePriceDenominator);
    uint256 denominator = BPS_SCALE * 2 - incentive;

    // slither-disable-start divide-before-multiply
    uint256 collateralOutRaw = (numerator * BPS_SCALE) / denominator;
    collateralOut = collateralOutRaw / params.collateralPrecision;

    uint256 stablesInRaw = (collateralOut * params.collateralPrecision * oraclePriceDenominator) / oraclePriceNumerator;
    stablesIn = stablesInRaw / params.stablePrecision;
    // slither-disable-end divide-before-multiply
  }

  /**
   * @notice Gets the incentive bps to be used for the given pool.
   *         The incentive is the lower of the strategy incentive and the pool incentive.
   * @param fpmm The pool contract.
   * @return incentive The incentive in basis points.
   */
  function _getIncentive(IFPMM fpmm) private view returns (uint256) {
    uint256 strategyIncentive = fpmmPoolConfigs[address(fpmm)].rebalanceIncentive;
    uint256 poolIncentive = fpmm.rebalanceIncentive();
    return strategyIncentive < poolIncentive ? strategyIncentive : poolIncentive;
  }
}
