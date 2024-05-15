// SPDX-License-Identifier: MIT
pragma solidity >=0.8;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IGoodDollarExchangeProvider.sol";

import "./BancorExchangeProvider.sol";

contract GoodDollarExchangeProvider is UUPSUpgradeable, BancorExchangeProvider, IGoodDollarExchangeProvider {
  bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");

  bytes32 public exchangeId;
  ReserveParams public reserveParams;
  uint256 lastExpansion;

  function initialize(
    BancorFormula _bancor,
    BancorExchange calldata _gdExchange,
    address _broker,
    address _avatar,
    address _governance
  ) public initializer {
    __BancorExchangeProvider_init(_bancor);
    _setupRole(BROKER_ROLE, _broker);
    _setupRole(MANAGER_ROLE, address(this));
    _setupRole(MANAGER_ROLE, _avatar);
    _setupRole(DEFAULT_ADMIN_ROLE, _governance);
    exchangeId = createExchange(_gdExchange);
    lastExpansion = block.timestamp;
  }

  function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE) {}

  function updateMintExpansion(
    uint256 dailyExpansionRate
  ) external onlyRole(CONTROLLER_ROLE) returns (uint256 mintedAmount) {
    BancorExchange memory exchange = exchanges[exchangeId];
    uint32 newRR = calculateNewReserveRatio(dailyExpansionRate);
    mintedAmount = (exchange.tokenSupply * exchange.reserveRatio - exchange.tokenSupply * newRR) / newRR;

    lastExpansion = block.timestamp;
    exchange.reserveRatio = newRR;
    exchange.tokenSupply += mintedAmount;
  }

  /**
   * @dev Calculates how much to decrease the reserve ratio for _token by
   * the `reserveRatioDailyExpansion`
   * @return reserveRatio The new reserve ratio
   */
  function calculateNewReserveRatio(uint256 _dailyExpansionRate) public view returns (uint32 reserveRatio) {
    BancorExchange storage exchange = exchanges[exchangeId];
    uint256 ratio = uint256(exchange.reserveRatio);
    if (ratio == 0) {
      ratio = 1e6;
    }
    ratio *= 1e21; //expand to e27 precision

    uint256 daysPassed = (block.timestamp - lastExpansion) / 1 days;
    for (uint256 i = 0; i < daysPassed; i++) {
      ratio = (ratio * _dailyExpansionRate) / 1e27;
    }

    return uint32(ratio / 1e21); // return to e6 precision
  }

  function updateMintInterest(
    uint256 reserveInterest
  ) external onlyRole(CONTROLLER_ROLE) returns (uint256 mintedAmount) {
    BancorExchange storage exchange = exchanges[exchangeId];

    mintedAmount = (reserveInterest * exchange.tokenSupply) / exchange.reserveBalance;
    exchange.tokenSupply += mintedAmount;
    exchange.reserveBalance += reserveInterest;
  }

  function updateMintReward(uint256 reward) external onlyRole(CONTROLLER_ROLE) {
    BancorExchange storage exchange = exchanges[exchangeId];
    uint256 newRR = (exchange.reserveBalance * 1e18 * 1e6) /
      ((exchange.tokenSupply + reward) * currentPrice(exchangeId));

    exchange.reserveRatio = uint32(newRR);
    exchange.tokenSupply += reward;
  }

  function pause(bool shouldPause) external onlyRole(MANAGER_ROLE) {
    if (shouldPause) _pause();
    else _unpause();
  }

  /**
   * @notice Retrieves the pool with the specified exchangeId.
   * @return result The PoolExchange with that ID.
   */
  function getBancorExchange() external view returns (BancorExchange memory result) {
    return exchanges[exchangeId];
  }

  /**
   * @notice gets the current price based of the bancor formula
   * @return price current price
   */
  function currentPrice() external view returns (uint256 price) {
    return currentPrice(exchangeId);
  }

  /**
   * @notice gets the current price based of the bancor formula
   * @return usdPrice current price in USD
   */
  function currentPriceUSD() external returns (uint256 usdPrice) {}
}
