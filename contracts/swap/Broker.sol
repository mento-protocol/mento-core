// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
pragma experimental ABIEncoderV2;

import { Ownable } from "openzeppelin-contracts-next/contracts/access/Ownable.sol";
import { SafeERC20MintableBurnable } from "contracts/common/SafeERC20MintableBurnable.sol";
import { IERC20MintableBurnable as IERC20 } from "contracts/common/IERC20MintableBurnable.sol";

import { IExchangeProvider } from "../interfaces/IExchangeProvider.sol";
import { IBroker } from "../interfaces/IBroker.sol";
import { IBrokerAdmin } from "../interfaces/IBrokerAdmin.sol";
import { IReserve } from "../interfaces/IReserve.sol";
import { ITradingLimits } from "../interfaces/ITradingLimits.sol";

import { TradingLimits } from "../libraries/TradingLimits.sol";
import { Initializable } from "celo/contracts/common/Initializable.sol";
// TODO: ensure we can use latest impl of openzeppelin
import { ReentrancyGuard } from "openzeppelin-contracts-next/contracts/security/ReentrancyGuard.sol";

interface IERC20Metadata {
  /**
   * @dev Returns the decimals places of the token.
   */
  function decimals() external view returns (uint8);
}

/**
 * @title Broker
 * @notice The broker executes swaps and keeps track of spending limits per pair.
 */
contract Broker is IBroker, IBrokerAdmin, Initializable, Ownable, ReentrancyGuard {
  using TradingLimits for ITradingLimits.State;
  using TradingLimits for ITradingLimits.Config;
  using SafeERC20MintableBurnable for IERC20;

  /* ==================== State Variables ==================== */

  address[] public exchangeProviders;
  mapping(address => bool) public isExchangeProvider;
  mapping(bytes32 => ITradingLimits.State) public tradingLimitsState;
  mapping(bytes32 => ITradingLimits.Config) public tradingLimitsConfig;

  // Address of the reserve.
  uint256 public __deprecated0; // prev: IReserve public reserve;

  uint256 private constant MAX_INT256 = uint256(type(int256).max);

  mapping(address => address) public exchangeReserve;
  /* ==================== Constructor ==================== */

  /**
   * @notice Sets initialized == true on implementation contracts.
   * @param test Set to true to skip implementation initialization.
   */
  constructor(bool test) Initializable(test) {}

  /**
   * @notice Allows the contract to be upgradable via the proxy.
   * @param _exchangeProviders The addresses of the ExchangeProvider contracts.
   * @param _reserves The addresses of the Reserve contracts.
   */
  function initialize(address[] calldata _exchangeProviders, address[] calldata _reserves) external initializer {
    _transferOwnership(msg.sender);
    for (uint256 i = 0; i < _exchangeProviders.length; i++) {
      addExchangeProvider(_exchangeProviders[i], _reserves[i]);
    }
  }

  /**
   * @notice Set the reserves for the exchange providers.
   * @param _exchangeProviders The addresses of the ExchangeProvider contracts.
   * @param _reserves The addresses of the Reserve contracts.
   */
  function setReserves(
    address[] calldata _exchangeProviders,
    address[] calldata _reserves
  ) external override(IBroker, IBrokerAdmin) onlyOwner {
    for (uint256 i = 0; i < _exchangeProviders.length; i++) {
      require(isExchangeProvider[_exchangeProviders[i]], "ExchangeProvider does not exist");
      require(_reserves[i] != address(0), "Reserve address can't be 0");
      exchangeReserve[_exchangeProviders[i]] = _reserves[i];
      emit ReserveSet(_exchangeProviders[i], _reserves[i]);
    }
  }

  /* ==================== Mutative Functions ==================== */

  /**
   * @notice Add an exchange provider to the list of providers.
   * @param exchangeProvider The address of the exchange provider to add.
   * @param reserve The address of the reserve used by the exchange provider.
   * @return index The index of the newly added specified exchange provider.
   */
  function addExchangeProvider(
    address exchangeProvider,
    address reserve
  ) public override(IBroker, IBrokerAdmin) onlyOwner returns (uint256 index) {
    require(!isExchangeProvider[exchangeProvider], "ExchangeProvider already exists in the list");
    require(exchangeProvider != address(0), "ExchangeProvider address can't be 0");
    require(reserve != address(0), "Reserve address can't be 0");
    exchangeProviders.push(exchangeProvider);
    isExchangeProvider[exchangeProvider] = true;
    exchangeReserve[exchangeProvider] = reserve;
    emit ExchangeProviderAdded(exchangeProvider);
    emit ReserveSet(exchangeProvider, reserve);
    index = exchangeProviders.length - 1;
  }

  /**
   * @notice Remove an exchange provider from the list of providers.
   * @param exchangeProvider The address of the exchange provider to remove.
   * @param index The index of the exchange provider being removed.
   */
  function removeExchangeProvider(
    address exchangeProvider,
    uint256 index
  ) public override(IBroker, IBrokerAdmin) onlyOwner {
    require(exchangeProviders[index] == exchangeProvider, "index doesn't match provider");
    exchangeProviders[index] = exchangeProviders[exchangeProviders.length - 1];
    exchangeProviders.pop();
    delete isExchangeProvider[exchangeProvider];
    delete exchangeReserve[exchangeProvider];
    emit ExchangeProviderRemoved(exchangeProvider);
  }

  /**
   * @notice Calculate the amount of tokenIn to be sold for a given amountOut of tokenOut
   * @param exchangeProvider the address of the exchange manager for the pair
   * @param exchangeId The id of the exchange to use
   * @param tokenIn The token to be sold
   * @param tokenOut The token to be bought
   * @param amountOut The amount of tokenOut to be bought
   * @return amountIn The amount of tokenIn to be sold
   */
  function getAmountIn(
    address exchangeProvider,
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountOut
  ) external view returns (uint256 amountIn) {
    require(isExchangeProvider[exchangeProvider], "ExchangeProvider does not exist");
    amountIn = IExchangeProvider(exchangeProvider).getAmountIn(exchangeId, tokenIn, tokenOut, amountOut);
  }

  /**
   * @notice Calculate the amount of tokenOut to be bought for a given amount of tokenIn to be sold
   * @param exchangeProvider the address of the exchange manager for the pair
   * @param exchangeId The id of the exchange to use
   * @param tokenIn The token to be sold
   * @param tokenOut The token to be bought
   * @param amountIn The amount of tokenIn to be sold
   * @return amountOut The amount of tokenOut to be bought
   */
  function getAmountOut(
    address exchangeProvider,
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  ) external view returns (uint256 amountOut) {
    require(isExchangeProvider[exchangeProvider], "ExchangeProvider does not exist");
    amountOut = IExchangeProvider(exchangeProvider).getAmountOut(exchangeId, tokenIn, tokenOut, amountIn);
  }

  /**
   * @notice Execute a token swap with fixed amountIn.
   * @param exchangeProvider the address of the exchange provider for the pair.
   * @param exchangeId The id of the exchange to use.
   * @param tokenIn The token to be sold.
   * @param tokenOut The token to be bought.
   * @param amountIn The amount of tokenIn to be sold.
   * @param amountOutMin Minimum amountOut to be received - controls slippage.
   * @return amountOut The amount of tokenOut to be bought.
   */
  function swapIn(
    address exchangeProvider,
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMin
  ) external nonReentrant returns (uint256 amountOut) {
    require(isExchangeProvider[exchangeProvider], "ExchangeProvider does not exist");
    // slither-disable-next-line reentrancy-benign
    amountOut = IExchangeProvider(exchangeProvider).swapIn(exchangeId, tokenIn, tokenOut, amountIn);
    require(amountOut >= amountOutMin, "amountOutMin not met");
    guardTradingLimits(exchangeId, tokenIn, amountIn, tokenOut, amountOut);

    address reserve = exchangeReserve[exchangeProvider];
    transferIn(payable(msg.sender), tokenIn, amountIn, reserve);
    transferOut(payable(msg.sender), tokenOut, amountOut, reserve);
    emit Swap(exchangeProvider, exchangeId, msg.sender, tokenIn, tokenOut, amountIn, amountOut);
  }

  /**
   * @notice Execute a token swap with fixed amountOut.
   * @param exchangeProvider the address of the exchange provider for the pair.
   * @param exchangeId The id of the exchange to use.
   * @param tokenIn The token to be sold.
   * @param tokenOut The token to be bought.
   * @param amountOut The amount of tokenOut to be bought.
   * @param amountInMax Maximum amount of tokenIn that can be traded.
   * @return amountIn The amount of tokenIn to be sold.
   */
  function swapOut(
    address exchangeProvider,
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountOut,
    uint256 amountInMax
  ) external nonReentrant returns (uint256 amountIn) {
    require(isExchangeProvider[exchangeProvider], "ExchangeProvider does not exist");
    // slither-disable-next-line reentrancy-benign
    amountIn = IExchangeProvider(exchangeProvider).swapOut(exchangeId, tokenIn, tokenOut, amountOut);
    require(amountIn <= amountInMax, "amountInMax exceeded");
    guardTradingLimits(exchangeId, tokenIn, amountIn, tokenOut, amountOut);

    address reserve = exchangeReserve[exchangeProvider];
    transferIn(payable(msg.sender), tokenIn, amountIn, reserve);
    transferOut(payable(msg.sender), tokenOut, amountOut, reserve);
    emit Swap(exchangeProvider, exchangeId, msg.sender, tokenIn, tokenOut, amountIn, amountOut);
  }

  /**
   * @notice Permissionless way to burn stables from msg.sender directly.
   * @param token The token getting burned.
   * @param amount The amount of the token getting burned.
   * @return True if transaction succeeds.
   */
  function burnStableTokens(address token, uint256 amount) public returns (bool) {
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    IERC20(token).safeBurn(amount);
    return true;
  }

  /**
   * @notice Configure trading limits for an (exchangeId, token) touple.
   * @dev Will revert if the configuration is not valid according to the
   * TradingLimits library.
   * Resets existing state according to the TradingLimits library logic.
   * Can only be called by owner.
   * @param exchangeId the exchangeId to target.
   * @param token the token to target.
   * @param config the new trading limits config.
   */
  // TODO: Make this external with next update.
  // slither-disable-next-line external-function
  function configureTradingLimit(
    bytes32 exchangeId,
    address token,
    ITradingLimits.Config memory config
  ) public onlyOwner {
    config.validate();

    bytes32 limitId = exchangeId ^ bytes32(uint256(uint160(token)));
    tradingLimitsConfig[limitId] = config;
    tradingLimitsState[limitId] = tradingLimitsState[limitId].reset(config);
    emit TradingLimitConfigured(exchangeId, token, config);
  }

  /* ==================== Private Functions ==================== */

  /**
   * @notice Transfer a specified Mento asset to the given address.
   * If the specified asset is a stable asset it will be minted directly to the address. If
   * the asset is a collateral asset it will be transferred from the reserve to the given address.
   * @param to The address receiving the asset.
   * @param token The asset to transfer.
   * @param amount The amount of `token` to be transferred.
   * @param _reserve The address of the corresponding reserve.
   */
  function transferOut(address payable to, address token, uint256 amount, address _reserve) internal {
    IReserve reserve = IReserve(_reserve);
    if (reserve.isStableAsset(token)) {
      IERC20(token).safeMint(to, amount);
    } else if (reserve.isCollateralAsset(token)) {
      require(reserve.transferExchangeCollateralAsset(token, to, amount), "Transfer of the collateral asset failed");
    } else {
      revert("Token must be stable or collateral assert");
    }
  }

  /**
   * @notice Transfer a specified Mento asset into the reserve or the broker.
   * If the specified asset is a stable asset it will be transfered to the broker
   * and burned. If the asset is a collateral asset it will be transferred to the reserve.
   * @param from The address to transfer the asset from.
   * @param token The asset to transfer.
   * @param amount The amount of `token` to be transferred.
   * @param _reserve The address of the corresponding reserve.
   */
  function transferIn(address payable from, address token, uint256 amount, address _reserve) internal {
    IReserve reserve = IReserve(_reserve);
    if (reserve.isStableAsset(token)) {
      IERC20(token).safeTransferFrom(from, address(this), amount);
      IERC20(token).safeBurn(amount);
    } else if (reserve.isCollateralAsset(token)) {
      IERC20(token).safeTransferFrom(from, address(reserve), amount);
    } else {
      revert("Token must be stable or collateral assert");
    }
  }

  /**
   * @notice Verify trading limits for a trade in both directions.
   * @dev Reverts if the trading limits are met for outflow or inflow.
   * @param exchangeId the ID of the exchange being used.
   * @param _tokenIn the address of the token flowing in.
   * @param amountIn the amount of token flowing in.
   * @param _tokenOut the address of the token flowing out.
   * @param amountOut  the amount of token flowing out.
   */
  function guardTradingLimits(
    bytes32 exchangeId,
    address _tokenIn,
    uint256 amountIn,
    address _tokenOut,
    uint256 amountOut
  ) internal {
    bytes32 tokenIn = bytes32(uint256(uint160(_tokenIn)));
    bytes32 tokenOut = bytes32(uint256(uint160(_tokenOut)));
    require(amountIn <= uint256(MAX_INT256), "amountIn too large");
    require(amountOut <= uint256(MAX_INT256), "amountOut too large");

    guardTradingLimit(exchangeId ^ tokenIn, int256(amountIn), _tokenIn);
    guardTradingLimit(exchangeId ^ tokenOut, -1 * int256(amountOut), _tokenOut);
  }

  /**
   * @notice Updates and verifies a trading limit if it's configured.
   * @dev Will revert if the trading limit is exceeded by this trade.
   * @param tradingLimitId the ID of the trading limit associated with the token
   * @param deltaFlow the deltaflow of this token, negative for outflow, positive for inflow.
   * @param token the address of the token, used to lookup decimals.
   */
  function guardTradingLimit(bytes32 tradingLimitId, int256 deltaFlow, address token) internal {
    ITradingLimits.Config memory tradingLimitConfig = tradingLimitsConfig[tradingLimitId];
    if (tradingLimitConfig.flags > 0) {
      ITradingLimits.State memory tradingLimitState = tradingLimitsState[tradingLimitId];
      tradingLimitState = tradingLimitState.update(tradingLimitConfig, deltaFlow, IERC20Metadata(token).decimals());
      tradingLimitState.verify(tradingLimitConfig);
      tradingLimitsState[tradingLimitId] = tradingLimitState;
    }
  }

  /* ==================== View Functions ==================== */

  /**
   * @notice Get the list of registered exchange providers.
   * @dev This can be used by UI or clients to discover all pairs.
   * @return exchangeProviders the addresses of all exchange providers.
   */
  function getExchangeProviders() external view returns (address[] memory) {
    return exchangeProviders;
  }
}
