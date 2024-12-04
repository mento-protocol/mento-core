// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { IGoodDollarExpansionController } from "contracts/interfaces/IGoodDollarExpansionController.sol";
import { IGoodDollarExchangeProvider } from "contracts/interfaces/IGoodDollarExchangeProvider.sol";
import { IBancorExchangeProvider } from "contracts/interfaces/IBancorExchangeProvider.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "openzeppelin-contracts-next/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IGoodDollar } from "contracts/goodDollar/interfaces/IGoodProtocol.sol";
import { IDistributionHelper } from "contracts/goodDollar/interfaces/IGoodProtocol.sol";

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { unwrap, wrap, powu } from "prb/math/UD60x18.sol";

/**
 * @title GoodDollarExpansionController
 * @notice Provides functionality to expand the supply of GoodDollars.
 */
contract GoodDollarExpansionController is IGoodDollarExpansionController, OwnableUpgradeable {
  /* ========================================================= */
  /* ==================== State Variables ==================== */
  /* ========================================================= */

  // EXPANSION_MAX_WEIGHT is the max rate that can be assigned to an exchange
  uint256 public constant EXPANSION_MAX_WEIGHT = 1e18;

  // BANCOR_MAX_WEIGHT is used for BPS calculations in GoodDollarExchangeProvider
  uint32 public constant BANCOR_MAX_WEIGHT = 1e8;

  // Address of the distribution helper contract
  IDistributionHelper public distributionHelper;

  // Address of reserve contract holding the GoodDollar reserve
  address public reserve;

  // Address of the GoodDollar exchange provider
  IGoodDollarExchangeProvider public goodDollarExchangeProvider;

  // Maps exchangeId to exchangeExpansionConfig
  mapping(bytes32 exchangeId => ExchangeExpansionConfig) public exchangeExpansionConfigs;

  // Address of the GoodDollar DAO contract.
  // solhint-disable-next-line var-name-mixedcase
  address public AVATAR;

  /* ===================================================== */
  /* ==================== Constructor ==================== */
  /* ===================================================== */

  /**
   * @dev Should be called with disable=true in deployments when it's accessed through a Proxy.
   * Call this with disable=false during testing, when used without a proxy.
   * @param disable Set to true to run `_disableInitializers()` inherited from
   * openzeppelin-contracts-upgradeable/Initializable.sol
   */
  constructor(bool disable) {
    if (disable) {
      _disableInitializers();
    }
  }

  /// @inheritdoc IGoodDollarExpansionController
  function initialize(
    address _goodDollarExchangeProvider,
    address _distributionHelper,
    address _reserve,
    address _avatar
  ) public initializer {
    __Ownable_init();

    setGoodDollarExchangeProvider(_goodDollarExchangeProvider);
    _setDistributionHelper(_distributionHelper);
    setReserve(_reserve);
    setAvatar(_avatar);
  }

  /* =================================================== */
  /* ==================== Modifiers ==================== */
  /* =================================================== */

  modifier onlyAvatar() {
    require(msg.sender == AVATAR, "Only Avatar can call this function");
    _;
  }

  /* ======================================================== */
  /* ==================== View Functions ==================== */
  /* ======================================================== */

  /// @inheritdoc IGoodDollarExpansionController
  function getExpansionConfig(bytes32 exchangeId) public view returns (ExchangeExpansionConfig memory) {
    require(exchangeExpansionConfigs[exchangeId].expansionRate > 0, "Expansion config not set");
    return exchangeExpansionConfigs[exchangeId];
  }

  /* ============================================================ */
  /* ==================== Mutative Functions ==================== */
  /* ============================================================ */

  /// @inheritdoc IGoodDollarExpansionController
  function setGoodDollarExchangeProvider(address _goodDollarExchangeProvider) public onlyOwner {
    require(_goodDollarExchangeProvider != address(0), "GoodDollarExchangeProvider address must be set");
    goodDollarExchangeProvider = IGoodDollarExchangeProvider(_goodDollarExchangeProvider);
    emit GoodDollarExchangeProviderUpdated(_goodDollarExchangeProvider);
  }

  /// @inheritdoc IGoodDollarExpansionController
  function setDistributionHelper(address _distributionHelper) public onlyAvatar {
    return _setDistributionHelper(_distributionHelper);
  }

  /// @inheritdoc IGoodDollarExpansionController
  function setReserve(address _reserve) public onlyOwner {
    require(_reserve != address(0), "Reserve address must be set");
    reserve = _reserve;
    emit ReserveUpdated(_reserve);
  }

  /// @inheritdoc IGoodDollarExpansionController
  function setAvatar(address _avatar) public onlyOwner {
    require(_avatar != address(0), "Avatar address must be set");
    AVATAR = _avatar;
    emit AvatarUpdated(_avatar);
  }

  /// @inheritdoc IGoodDollarExpansionController
  function setExpansionConfig(bytes32 exchangeId, uint64 expansionRate, uint32 expansionFrequency) external onlyAvatar {
    require(expansionRate < EXPANSION_MAX_WEIGHT, "Expansion rate must be less than 100%");
    require(expansionRate > 0, "Expansion rate must be greater than 0");
    require(expansionFrequency > 0, "Expansion frequency must be greater than 0");

    exchangeExpansionConfigs[exchangeId].expansionRate = expansionRate;
    exchangeExpansionConfigs[exchangeId].expansionFrequency = expansionFrequency;

    emit ExpansionConfigSet(exchangeId, expansionRate, expansionFrequency);
  }

  /// @inheritdoc IGoodDollarExpansionController
  function mintUBIFromInterest(bytes32 exchangeId, uint256 reserveInterest) external returns (uint256 amountMinted) {
    require(reserveInterest > 0, "Reserve interest must be greater than 0");
    IBancorExchangeProvider.PoolExchange memory exchange = IBancorExchangeProvider(address(goodDollarExchangeProvider))
      .getPoolExchange(exchangeId);

    require(IERC20(exchange.reserveAsset).transferFrom(msg.sender, reserve, reserveInterest), "Transfer failed");

    uint256 reserveInterestScaled = reserveInterest * (10 ** (18 - IERC20Metadata(exchange.reserveAsset).decimals()));
    amountMinted = goodDollarExchangeProvider.mintFromInterest(exchangeId, reserveInterestScaled);

    IGoodDollar(exchange.tokenAddress).mint(address(distributionHelper), amountMinted);

    // Ignored, because contracts only interacts with trusted contracts and tokens
    // slither-disable-next-line reentrancy-events
    emit InterestUBIMinted(exchangeId, amountMinted);
  }

  /// @inheritdoc IGoodDollarExpansionController
  function mintUBIFromReserveBalance(bytes32 exchangeId) external returns (uint256 amountMinted) {
    IBancorExchangeProvider.PoolExchange memory exchange = IBancorExchangeProvider(address(goodDollarExchangeProvider))
      .getPoolExchange(exchangeId);

    uint256 contractReserveBalance = IERC20(exchange.reserveAsset).balanceOf(reserve) *
      (10 ** (18 - IERC20Metadata(exchange.reserveAsset).decimals()));

    uint256 additionalReserveBalance = contractReserveBalance - exchange.reserveBalance;
    if (additionalReserveBalance > 0) {
      amountMinted = goodDollarExchangeProvider.mintFromInterest(exchangeId, additionalReserveBalance);
      IGoodDollar(exchange.tokenAddress).mint(address(distributionHelper), amountMinted);

      // Ignored, because contracts only interacts with trusted contracts and tokens
      // slither-disable-next-line reentrancy-events
      emit InterestUBIMinted(exchangeId, amountMinted);
    }
  }

  /// @inheritdoc IGoodDollarExpansionController
  function mintUBIFromExpansion(bytes32 exchangeId) external returns (uint256 amountMinted) {
    IBancorExchangeProvider.PoolExchange memory exchange = IBancorExchangeProvider(address(goodDollarExchangeProvider))
      .getPoolExchange(exchangeId);
    ExchangeExpansionConfig memory config = getExpansionConfig(exchangeId);

    bool shouldExpand = block.timestamp >= config.lastExpansion + config.expansionFrequency;
    if (shouldExpand || config.lastExpansion == 0) {
      uint256 reserveRatioScalar = _getReserveRatioScalar(exchangeId);

      amountMinted = goodDollarExchangeProvider.mintFromExpansion(exchangeId, reserveRatioScalar);

      IGoodDollar(exchange.tokenAddress).mint(address(distributionHelper), amountMinted);
      distributionHelper.onDistribution(amountMinted);

      // Ignored, because contracts only interacts with trusted contracts and tokens
      // slither-disable-next-line reentrancy-events
      emit ExpansionUBIMinted(exchangeId, amountMinted);
    }
  }

  /// @inheritdoc IGoodDollarExpansionController
  function mintRewardFromReserveRatio(bytes32 exchangeId, address to, uint256 amount) external onlyAvatar {
    // Defaults to no slippage protection
    mintRewardFromReserveRatio(exchangeId, to, amount, BANCOR_MAX_WEIGHT);
  }

  /// @inheritdoc IGoodDollarExpansionController
  function mintRewardFromReserveRatio(
    bytes32 exchangeId,
    address to,
    uint256 amount,
    uint256 maxSlippagePercentage
  ) public onlyAvatar {
    require(to != address(0), "Recipient address must be set");
    require(amount > 0, "Amount must be greater than 0");
    require(maxSlippagePercentage <= BANCOR_MAX_WEIGHT, "Max slippage percentage cannot be greater than 100%");
    IBancorExchangeProvider.PoolExchange memory exchange = IBancorExchangeProvider(address(goodDollarExchangeProvider))
      .getPoolExchange(exchangeId);

    goodDollarExchangeProvider.updateRatioForReward(exchangeId, amount, maxSlippagePercentage);
    IGoodDollar(exchange.tokenAddress).mint(to, amount);

    // Ignored, because contracts only interacts with trusted contracts and tokens
    // slither-disable-next-line reentrancy-events
    emit RewardMinted(exchangeId, to, amount);
  }

  /* =========================================================== */
  /* ==================== Private Functions ==================== */
  /* =========================================================== */

  /**
   * @notice Sets the distribution helper address.
   * @param _distributionHelper The address of the distribution helper contract.
   */
  function _setDistributionHelper(address _distributionHelper) internal {
    require(_distributionHelper != address(0), "Distribution helper address must be set");
    distributionHelper = IDistributionHelper(_distributionHelper);
    emit DistributionHelperUpdated(_distributionHelper);
  }

  /**
   * @notice Calculates the reserve ratio scalar for the given expansion config.
   * @param exchangeId The ID of the exchange.
   * @return reserveRatioScalar The reserve ratio scalar.
   */
  function _getReserveRatioScalar(bytes32 exchangeId) internal returns (uint256) {
    ExchangeExpansionConfig memory config = getExpansionConfig(exchangeId);
    uint256 numberOfExpansions;

    // If there was no previous expansion, we expand once.
    if (config.lastExpansion == 0) {
      numberOfExpansions = 1;
      exchangeExpansionConfigs[exchangeId].lastExpansion = uint32(block.timestamp);
    } else {
      numberOfExpansions = (block.timestamp - config.lastExpansion) / config.expansionFrequency;
      // slither-disable-next-line divide-before-multiply
      exchangeExpansionConfigs[exchangeId].lastExpansion = uint32(
        config.lastExpansion + numberOfExpansions * config.expansionFrequency
      );
    }

    uint256 stepReserveRatioScalar = EXPANSION_MAX_WEIGHT - config.expansionRate;
    return unwrap(powu(wrap(stepReserveRatioScalar), numberOfExpansions));
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
