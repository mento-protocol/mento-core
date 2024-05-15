// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interfaces/IBancorExchangeProvider.sol";
import "./BancorFormula.sol";

contract BancorExchangeProvider is
  IBancorExchangeProvider,
  Initializable,
  AccessControlUpgradeable,
  PausableUpgradeable
{
  bytes32 public constant BROKER_ROLE = keccak256("BROKER_ROLE");
  bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

  error INVALID_EXCHANGE_ID();
  error UNSUPPORTED_EXCHANGE();

  mapping(bytes32 => BancorExchange) public exchanges;
  bytes32[] public exchangeIds;
  BancorFormula public bancor;

  uint256[50] private _reserved;

  function __BancorExchangeProvider_init(BancorFormula _bancor) internal onlyInitializing {
    __AccessControl_init();
    __Pausable_init();
    __BancorExchangeProvider_initialized_unchained(_bancor);
  }

  function __BancorExchangeProvider_initialized_unchained(BancorFormula _bancor) internal onlyInitializing {
    bancor = _bancor;
  }

  /**
   * @notice Create a PoolExchange with the provided data.
   * @param exchange The PoolExchange to be created.
   * @return exchangeId The id of the exchange.
   */
  function createExchange(BancorExchange calldata exchange) public onlyRole(MANAGER_ROLE) returns (bytes32 exchangeId) {
    exchangeId = keccak256(abi.encodePacked(exchange.reserveAsset, exchange.tokenAddress));
    exchanges[exchangeId] = exchange;
    for (uint i = 0; i < exchangeIds.length - 1; i++) {
      if (exchangeIds[i] == exchangeId) {
        return exchangeId;
      }
    }
    exchangeIds.push(exchangeId);
  }

  /**
   * @notice Delete a PoolExchange.
   * @param exchangeId The PoolExchange to be created.
   * @param exchangeIdIndex The index of the exchangeId in the exchangeIds array.
   * @return destroyed - true on successful delition.
   */
  function destroyExchange(
    bytes32 exchangeId,
    uint256 exchangeIdIndex
  ) public onlyRole(MANAGER_ROLE) returns (bool destroyed) {
    if (exchangeIds[exchangeIdIndex] != exchangeId) revert INVALID_EXCHANGE_ID();
    delete exchanges[exchangeId];
    exchangeIds[exchangeIdIndex] = exchangeIds[exchangeIds.length - 1];
    return true;
  }

  /**
   * @notice Set the exit contribution for a given exchange
   * @param exchangeId The id of the exchange
   * @param exitContribution The exit contribution to be set
   */
  function setExitContribution(bytes32 exchangeId, uint32 exitContribution) external onlyRole(MANAGER_ROLE) {
    exchanges[exchangeId].exitContribution = exitContribution;
  }

  /**
   * @notice Retrieves the pool with the specified exchangeId.
   * @param _exchangeId The id of the pool to be retrieved.
   * @return result The PoolExchange with that ID.
   */
  function getBancorExchange(bytes32 _exchangeId) external view returns (BancorExchange memory result) {
    return exchanges[_exchangeId];
  }

  /**
   * @notice Get all exchanges supported by the ExchangeProvider.
   * @return _exchanges An array of Exchange structs.
   */

  function getExchanges() external view returns (Exchange[] memory _exchanges) {
    _exchanges = new Exchange[](exchangeIds.length);
    for (uint i = 0; i < exchangeIds.length; i++) {
      BancorExchange memory exchange = exchanges[exchangeIds[i]];
      _exchanges[i].exchangeId = exchangeIds[i];
      _exchanges[i].assets = new address[](2);
      _exchanges[i].assets[0] = exchange.tokenAddress;
      _exchanges[i].assets[1] = exchange.reserveAsset;
    }
  }

  /**
   * @notice Get all exchange IDs.
   * @return _exchangeIds List of the exchangeIds.
   */
  function getExchangeIds() external view returns (bytes32[] memory _exchangeIds) {
    return exchangeIds;
  }

  /**
   * @notice gets the current price based of the bancor formula
   * @return price current price
   */
  function currentPrice(bytes32 exchangeId) public view returns (uint256 price) {
    BancorExchange memory exchange = exchanges[exchangeId];
    return (exchange.reserveBalance * 1e18 * 1e6) / ((exchange.tokenSupply * exchange.reserveRatio)); // mul by 1e18 to get price in 18 decimals. mul by 1e6 to balance reserveRatio ppm precision
  }

  /**
   * @notice Calculates the amount out given the amount in for a token exchange
   * @param exchangeId The exchange id
   * @param tokenIn The address of the token put in
   * @param tokenOut The address of the token taken out
   * @param amountIn The amount of tokens put in
   * @return amountOut The amount of tokens taken out
   */

  function getAmountOut(
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  ) public view returns (uint256 amountOut) {
    BancorExchange memory exchange = exchanges[exchangeId];

    //case sell
    if (tokenIn == exchange.tokenAddress && tokenOut == exchange.reserveAsset) {
      uint256 exitContribution = (amountIn * exchange.exitContribution) / 10000;
      return
        bancor.calculateSaleReturn(
          exchange.tokenSupply,
          exchange.reserveBalance,
          exchange.reserveRatio,
          amountIn - exitContribution
        );
    }

    // case buy
    if (tokenOut == exchange.tokenAddress && tokenIn == exchange.reserveAsset) {
      return
        bancor.calculatePurchaseReturn(exchange.tokenSupply, exchange.reserveBalance, exchange.reserveRatio, amountIn);
    }
    revert UNSUPPORTED_EXCHANGE();
  }

  function getAmountIn(
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountOut
  ) public view returns (uint256 amountIn) {
    BancorExchange memory exchange = exchanges[exchangeId];
    //case sell
    if (tokenIn == exchange.tokenAddress && tokenOut == exchange.reserveAsset) {
      amountIn = bancor.calculateLiquidateReturn(
        exchange.tokenSupply,
        exchange.reserveBalance,
        exchange.reserveRatio,
        amountOut
      );

      // amount + exitContribution required to get the amount out
      amountIn = (amountIn * 10000) / (10000 - exchange.exitContribution);
    }

    // case buy
    if (tokenOut == exchange.tokenAddress && tokenIn == exchange.reserveAsset) {
      return bancor.calculateFundCost(exchange.tokenSupply, exchange.reserveBalance, exchange.reserveRatio, amountOut);
    }
    revert UNSUPPORTED_EXCHANGE();
  }

  function swapOut(
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountOut
  ) external onlyRole(BROKER_ROLE) whenNotPaused returns (uint256 amountIn) {
    BancorExchange storage exchange = exchanges[exchangeId];

    // calling getAmount in enforces valid exchangeId, tokenIn and tokenOut
    amountIn = this.getAmountIn(exchangeId, tokenIn, tokenOut, amountOut);
    //case buy
    if (tokenIn == exchange.reserveAsset) {
      exchange.reserveBalance += amountIn;
      exchange.tokenSupply += amountOut;
    }
    // case sell
    else {
      exchange.reserveBalance -= amountOut;
      exchange.tokenSupply -= amountIn;
    }
  }

  function swapIn(
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  ) external onlyRole(BROKER_ROLE) whenNotPaused returns (uint256 amountOut) {
    BancorExchange storage exchange = exchanges[exchangeId];

    // calling getAmount in enforces valid exchangeId, tokenIn and tokenOut
    amountOut = this.getAmountOut(exchangeId, tokenIn, tokenOut, amountIn);

    //case buy
    if (tokenIn == exchange.reserveAsset) {
      exchange.reserveBalance += amountIn;
      exchange.tokenSupply += amountOut;
    }
    // case sell
    else {
      exchange.reserveBalance -= amountOut;
      exchange.tokenSupply -= amountIn;
    }
  }
}
