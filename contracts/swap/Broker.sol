// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Ownable } from "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import { SafeERC20 } from "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";
import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";
import { IERC20 } from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

import { IExchangeProvider } from "../interfaces/IExchangeProvider.sol";
import { IBroker } from "../interfaces/IBroker.sol";
import { IBrokerAdmin } from "../interfaces/IBrokerAdmin.sol";
import { IReserve } from "../interfaces/IReserve.sol";
import { IERC20Metadata } from "../common/interfaces/IERC20Metadata.sol";
import { IStableTokenV2 } from "../interfaces/IStableTokenV2.sol";

import { Initializable } from "../common/Initializable.sol";
import { TradingLimits } from "../libraries/TradingLimits.sol";
import { ReentrancyGuard } from "../common/ReentrancyGuard.sol";

/**
 * @title Broker
 * @notice The broker executes swaps and keeps track of spending limits per pair.
 */
contract Broker is IBroker, IBrokerAdmin, Initializable, Ownable, ReentrancyGuard {
  using TradingLimits for TradingLimits.State;
  using TradingLimits for TradingLimits.Config;
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  /* ==================== State Variables ==================== */

  address[] public exchangeProviders;
  mapping(address => bool) public isExchangeProvider;
  mapping(bytes32 => TradingLimits.State) public tradingLimitsState;
  mapping(bytes32 => TradingLimits.Config) public tradingLimitsConfig;

  // Address of the reserve.
  IReserve public reserve;

  uint256 private constant MAX_INT256 = uint256(-1) / 2;

  /* ==================== Constructor ==================== */

  /**
   * @notice Sets initialized == true on implementation contracts.
   * @param test Set to true to skip implementation initialization.
   */
  constructor(bool test) public Initializable(test) {}

  /**
   * @notice Allows the contract to be upgradable via the proxy.
   * @param _exchangeProviders The addresses of the ExchangeProvider contracts.
   * @param _reserve The address of the Reserve contract.
   */
  function initialize(address[] calldata _exchangeProviders, address _reserve) external initializer {
    _transferOwnership(msg.sender);
    for (uint256 i = 0; i < _exchangeProviders.length; i++) {
      addExchangeProvider(_exchangeProviders[i]);
    }
    setReserve(_reserve);
  }

  /* ==================== Mutative Functions ==================== */

  /**
   * @notice Add an exchange provider to the list of providers.
   * @param exchangeProvider The address of the exchange provider to add.
   * @return index The index of the newly added specified exchange provider.
   */
  function addExchangeProvider(address exchangeProvider) public onlyOwner returns (uint256 index) {
    require(!isExchangeProvider[exchangeProvider], "ExchangeProvider already exists in the list");
    require(exchangeProvider != address(0), "ExchangeProvider address can't be 0");
    exchangeProviders.push(exchangeProvider);
    isExchangeProvider[exchangeProvider] = true;
    emit ExchangeProviderAdded(exchangeProvider);
    index = exchangeProviders.length.sub(1);
  }

  /**
   * @notice Remove an exchange provider from the list of providers.
   * @param exchangeProvider The address of the exchange provider to remove.
   * @param index The index of the exchange provider being removed.
   */
  function removeExchangeProvider(address exchangeProvider, uint256 index) public onlyOwner {
    require(exchangeProviders[index] == exchangeProvider, "index doesn't match provider");
    exchangeProviders[index] = exchangeProviders[exchangeProviders.length.sub(1)];
    exchangeProviders.pop();
    delete isExchangeProvider[exchangeProvider];
    emit ExchangeProviderRemoved(exchangeProvider);
  }

  /**
   * @notice Set the Mento reserve address.
   * @param _reserve The Mento reserve address.
   */
  function setReserve(address _reserve) public onlyOwner {
    require(_reserve != address(0), "Reserve address must be set");
    emit ReserveSet(_reserve, address(reserve));
    reserve = IReserve(_reserve);
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
    transferIn(msg.sender, tokenIn, amountIn);
    transferOut(msg.sender, tokenOut, amountOut);
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
    transferIn(msg.sender, tokenIn, amountIn);
    transferOut(msg.sender, tokenOut, amountOut);
    emit Swap(exchangeProvider, exchangeId, msg.sender, tokenIn, tokenOut, amountIn, amountOut);
  }

  /**
   * @notice Permissionless way to burn stables from msg.sender directly.
   * @param token The token getting burned.
   * @param amount The amount of the token getting burned.
   * @return True if transaction succeeds.
   */
  function burnStableTokens(address token, uint256 amount) public returns (bool) {
    require(reserve.isStableAsset(token), "Token must be a reserve stable asset");
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    require(IStableTokenV2(token).burn(amount), "Burning of the stable asset failed");
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
  function configureTradingLimit(
    bytes32 exchangeId,
    address token,
    TradingLimits.Config memory config
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
   */
  function transferOut(address payable to, address token, uint256 amount) internal {
    if (reserve.isStableAsset(token)) {
      require(IStableTokenV2(token).mint(to, amount), "Minting of the stable asset failed");
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
   */
  function transferIn(address payable from, address token, uint256 amount) internal {
    if (reserve.isStableAsset(token)) {
      IERC20(token).safeTransferFrom(from, address(this), amount);
      require(IStableTokenV2(token).burn(amount), "Burning of the stable asset failed");
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
    TradingLimits.Config memory tradingLimitConfig = tradingLimitsConfig[tradingLimitId];
    if (tradingLimitConfig.flags > 0) {
      TradingLimits.State memory tradingLimitState = tradingLimitsState[tradingLimitId];
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
