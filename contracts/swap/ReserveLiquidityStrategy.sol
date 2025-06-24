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
   *         and transfers to/from the reserve.
   * @param pool The address of the pool.
   * @param oraclePrice The off‑chain target price.
   * @param priceDirection Indicates if the pool price is above or below the oracle price.
   */
  function _executeRebalance(address pool, uint256 oraclePrice, PriceDirection priceDirection) internal override {
    IFPMM fpmm = IFPMM(pool);

    (
      uint256 stableOut,
      uint256 collateralOut,
      uint256 inputAmount,
      uint256 incentiveAmount
    ) = _calculateRebalanceAmounts(fpmm, oraclePrice, priceDirection);

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
   */
  function _calculateRebalanceAmounts(
    IFPMM fpmm,
    uint256 oraclePrice,
    PriceDirection priceDirection
  ) private view returns (uint256 stableOut, uint256 collateralOut, uint256 inputAmount, uint256 incentiveAmount) {
    // slither-disable-next-line unused-return
    (uint256 dec0, uint256 dec1, uint256 reserve0, uint256 reserve1, , ) = fpmm.metadata();

    require(dec0 <= 1e18 && dec1 <= 1e18, "RLS: TOKEN_DECIMALS_TOO_LARGE");

    uint256 strategyIncentive = fpmmPoolConfigs[address(fpmm)].rebalanceIncentive;
    uint256 poolIncentive = fpmm.rebalanceIncentive();
    uint256 incentive = strategyIncentive < poolIncentive ? strategyIncentive : poolIncentive;

    RebalanceParams memory params = RebalanceParams({
      stableReserve: reserve0 * (1e18 / dec0),
      collateralReserve: reserve1 * (1e18 / dec1),
      stablePrecision: 1e18 / dec0,
      collateralPrecision: 1e18 / dec1
    });

    if (priceDirection == PriceDirection.ABOVE_ORACLE) {
      (collateralOut, inputAmount) = _calculateExpansionAmounts(params, oraclePrice, incentive);
      stableOut = 0;
    } else {
      (stableOut, inputAmount) = _calculateContractionAmounts(params, oraclePrice, incentive);
      collateralOut = 0;
    }

    incentiveAmount = (inputAmount * incentive) / BPS_SCALE;
  }

  /**
   * @notice Calculates the amounts for contraction (when pool price is below oracle price)
   * @param params Struct containing rebalancing parameters.
   * @param oraclePrice The off-chain target price.
   * @return stableOut Amount of stable tokens to move out of the pool.
   * @return collateralIn Amount of collateral tokens to move into the pool.
   */
  function _calculateContractionAmounts(
    RebalanceParams memory params,
    uint256 oraclePrice,
    uint256 incentive
  ) private pure returns (uint256 stableOut, uint256 collateralIn) {
    // Contraction: Sell stables to buy collateral
    // StablesOut = (OraclePrice * StableReserve - CollateralReserve) / (OraclePrice + OraclePrice * (1 - incentive))
    // CollateralIn = StablesOut * OraclePrice
    uint256 numerator = ((oraclePrice * params.stableReserve) / 1e18) - params.collateralReserve;
    uint256 denominator = oraclePrice + ((oraclePrice * (BPS_SCALE - incentive)) / BPS_SCALE);

    uint256 stableOutRaw = (numerator * 1e18) / denominator;
    uint256 collateralInRaw = (stableOutRaw * oraclePrice) / 1e18;

    stableOut = stableOutRaw / params.stablePrecision;
    collateralIn = collateralInRaw / params.collateralPrecision;
  }

  /**
   * @notice Calculates the amounts for expansion (when pool price is above oracle price)
   * @param params Struct containing rebalancing parameters.
   * @param oraclePrice The off-chain target price.
   * @return collateralOut Amount of collateral tokens to move out of the pool.
   * @return stablesIn Amount of stable tokens to move into the pool.
   */
  function _calculateExpansionAmounts(
    RebalanceParams memory params,
    uint256 oraclePrice,
    uint256 incentive
  ) private pure returns (uint256 collateralOut, uint256 stablesIn) {
    // Expansion: Sell collateral to buy stables
    // CollateralOut = (CollateralReserve - OraclePrice * StableReserve) / (1 + 1 - incentive)
    // StablesIn = CollateralOut / OraclePrice
    uint256 numerator = params.collateralReserve - ((oraclePrice * params.stableReserve) / 1e18);
    uint256 denominator = BPS_SCALE * 2 - incentive;

    uint256 collateralOutRaw = (numerator * BPS_SCALE) / denominator;
    uint256 stablesInRaw = (collateralOutRaw * 1e18) / oraclePrice;

    collateralOut = collateralOutRaw / params.collateralPrecision;
    stablesIn = stablesInRaw / params.stablePrecision;
  }
}
