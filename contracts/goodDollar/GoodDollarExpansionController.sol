// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { IGoodDollarExpansionController } from "contracts/interfaces/IGoodDollarExpansionController.sol";
import { IGoodDollarExchangeProvider } from "contracts/interfaces/IGoodDollarExchangeProvider.sol";
import { IBancorExchangeProvider } from "contracts/interfaces/IBancorExchangeProvider.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
import { IGoodDollar } from "contracts/goodDollar/interfaces/IGoodProtocol.sol";
import { IDistributionHelper } from "contracts/goodDollar/interfaces/IGoodProtocol.sol";

import { PausableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol";
import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { unwrap, wrap, powu } from "prb/math/UD60x18.sol";

/**
 * @title GoodDollarExpansionController
 * @notice Provides functionality to expand the supply of GoodDollars.
 */
contract GoodDollarExpansionController is IGoodDollarExpansionController, PausableUpgradeable, OwnableUpgradeable {
  /* ==================== State Variables ==================== */

  // MAX_WEIGHT is the max rate that can be assigned to an exchange
  uint256 public constant MAX_WEIGHT = 1e18;

  // Address of the distribution helper contract
  IDistributionHelper public distributionHelper;

  // Address of reserve contract holding the GoodDollar reserve
  address public reserve;

  // Address of the GoodDollar exchange provider
  IGoodDollarExchangeProvider public goodDollarExchangeProvider;

  // Maps exchangeId to exchangeExpansionConfig
  mapping(bytes32 => ExchangeExpansionConfig) public exchangeExpansionConfigs;

  // Address of the GoodDollar DAO contract.
  // solhint-disable-next-line var-name-mixedcase
  address public AVATAR;

  /* ==================== Constructor ==================== */

  /**
   * @dev Should be called with disable=true in deployments when
   * it's accessed through a Proxy.
   * Call this with disable=false during testing, when used
   * without a proxy.
   * @param disable Set to true to run `_disableInitializers()` inherited from
   * openzeppelin-contracts-upgradeable/Initializable.sol
   */
  constructor(bool disable) {
    if (disable) {
      _disableInitializers();
    }
  }

  /**
   * @notice Initializes the contract with the given parameters.
   * @param _goodDollarExchangeProvider The address of the GoodDollarExchangeProvider contract.
   * @param _distributionHelper The address of the distribution helper contract.
   * @param _reserve The address of the Reserve contract.
   * @param _avatar The address of the GoodDollar DAO contract.
   */
  function initialize(
    address _goodDollarExchangeProvider,
    address _distributionHelper,
    address _reserve,
    address _avatar
  ) public initializer {
    __Pausable_init();
    __Ownable_init();

    setGoodDollarExchangeProvider(_goodDollarExchangeProvider);
    _setDistributionHelper(_distributionHelper);
    setReserve(_reserve);
    setAvatar(_avatar);
  }

  /* ==================== Modifiers ==================== */

  modifier onlyAvatar() {
    require(msg.sender == AVATAR, "Only Avatar can call this function");
    _;
  }

  /* ==================== View Functions ==================== */

  /**
   * @notice Returns the expansion config for the given exchange.
   * @param exchangeId The id of the exchange to get the expansion config for.
   * @return config The expansion config.
   */
  function getExpansionConfig(bytes32 exchangeId) public view returns (ExchangeExpansionConfig memory) {
    require(exchangeExpansionConfigs[exchangeId].expansionRate > 0, "Expansion config not set");
    return exchangeExpansionConfigs[exchangeId];
  }

  /* ==================== Mutative Functions ==================== */

  /**
   * @notice Sets the GoodDollarExchangeProvider address.
   * @param _goodDollarExchangeProvider The address of the GoodDollarExchangeProvider contract.
   */
  function setGoodDollarExchangeProvider(address _goodDollarExchangeProvider) public onlyOwner {
    require(_goodDollarExchangeProvider != address(0), "GoodDollarExchangeProvider address must be set");
    goodDollarExchangeProvider = IGoodDollarExchangeProvider(_goodDollarExchangeProvider);
    emit GoodDollarExchangeProviderUpdated(_goodDollarExchangeProvider);
  }

  /**
   * @notice Sets the distribution helper address.
   * @param _distributionHelper The address of the distribution helper contract.
   */
  function setDistributionHelper(address _distributionHelper) public onlyAvatar {
    return _setDistributionHelper(_distributionHelper);
  }

  /**
   * @notice Sets the reserve address.
   * @param _reserve The address of the reserve contract.
   */
  function setReserve(address _reserve) public onlyOwner {
    require(_reserve != address(0), "Reserve address must be set");
    reserve = _reserve;
    emit ReserveUpdated(_reserve);
  }

  /**
   * @notice Sets the AVATAR address.
   * @param _avatar The address of the AVATAR contract.
   */
  function setAvatar(address _avatar) public onlyOwner {
    require(_avatar != address(0), "Avatar address must be set");
    AVATAR = _avatar;
    emit AvatarUpdated(_avatar);
  }

  /**
   * @notice Sets the expansion config for the given exchange.
   * @param exchangeId The id of the exchange to set the expansion config for.
   * @param expansionRate The rate of expansion.
   * @param expansionFrequency The frequency of expansion.
   */
  function setExpansionConfig(bytes32 exchangeId, uint64 expansionRate, uint32 expansionFrequency) external onlyAvatar {
    require(expansionRate < MAX_WEIGHT, "Expansion rate must be less than 100%");
    require(expansionRate > 0, "Expansion rate must be greater than 0");
    require(expansionFrequency > 0, "Expansion frequency must be greater than 0");

    exchangeExpansionConfigs[exchangeId].expansionRate = expansionRate;
    exchangeExpansionConfigs[exchangeId].expansionFrequency = expansionFrequency;

    emit ExpansionConfigSet(exchangeId, expansionRate, expansionFrequency);
  }

  /**
   * @notice Mints UBI for the given exchange from collecting reserve interest.
   * @param exchangeId The id of the exchange to mint UBI for.
   * @param reserveInterest The amount of reserve tokens collected from interest.
   */
  function mintUBIFromInterest(bytes32 exchangeId, uint256 reserveInterest) external {
    require(reserveInterest > 0, "reserveInterest must be greater than 0");
    IBancorExchangeProvider.PoolExchange memory exchange = IBancorExchangeProvider(address(goodDollarExchangeProvider))
      .getPoolExchange(exchangeId);

    uint256 amountToMint = goodDollarExchangeProvider.mintFromInterest(exchangeId, reserveInterest);

    require(IERC20(exchange.reserveAsset).transferFrom(msg.sender, reserve, reserveInterest), "Transfer failed");
    IGoodDollar(exchange.tokenAddress).mint(address(distributionHelper), amountToMint);

    // Ignored, because contracts only interacts with trusted contracts and tokens
    // slither-disable-next-line reentrancy-events
    emit InterestUBIMinted(exchangeId, amountToMint);
  }

  /**
   * @notice Mints UBI for the given exchange by comparing the reserve Balance of the contract to the virtual balance.
   * @param exchangeId The id of the exchange to mint UBI for.
   * @return amountMinted The amount of UBI tokens minted.
   */
  function mintUBIFromReserveBalance(bytes32 exchangeId) external returns (uint256 amountMinted) {
    IBancorExchangeProvider.PoolExchange memory exchange = IBancorExchangeProvider(address(goodDollarExchangeProvider))
      .getPoolExchange(exchangeId);

    uint256 contractReserveBalance = IERC20(exchange.reserveAsset).balanceOf(reserve);
    uint256 additionalReserveBalance = contractReserveBalance - exchange.reserveBalance;
    if (additionalReserveBalance > 0) {
      amountMinted = goodDollarExchangeProvider.mintFromInterest(exchangeId, additionalReserveBalance);
      IGoodDollar(exchange.tokenAddress).mint(address(distributionHelper), amountMinted);

      // Ignored, because contracts only interacts with trusted contracts and tokens
      // slither-disable-next-line reentrancy-events
      emit InterestUBIMinted(exchangeId, amountMinted);
    }
  }

  /**
   * @notice Mints UBI for the given exchange by calculating the expansion rate.
   * @param exchangeId The id of the exchange to mint UBI for.
   * @return amountMinted The amount of UBI tokens minted.
   */
  function mintUBIFromExpansion(bytes32 exchangeId) external returns (uint256 amountMinted) {
    ExchangeExpansionConfig memory config = getExpansionConfig(exchangeId);
    IBancorExchangeProvider.PoolExchange memory exchange = IBancorExchangeProvider(address(goodDollarExchangeProvider))
      .getPoolExchange(exchangeId);

    bool shouldExpand = block.timestamp > config.lastExpansion + config.expansionFrequency;
    if (shouldExpand || config.lastExpansion == 0) {
      uint256 numberOfExpansions;

      //special case for first expansion
      if (config.lastExpansion == 0) {
        numberOfExpansions = 1;
      } else {
        numberOfExpansions = (block.timestamp - config.lastExpansion) / config.expansionFrequency;
      }

      uint256 stepExpansionScaler = MAX_WEIGHT - config.expansionRate;
      uint256 expansionScaler = unwrap(powu(wrap(stepExpansionScaler), numberOfExpansions));

      exchangeExpansionConfigs[exchangeId].lastExpansion = uint32(block.timestamp);
      amountMinted = goodDollarExchangeProvider.mintFromExpansion(exchangeId, expansionScaler);

      IGoodDollar(exchange.tokenAddress).mint(address(distributionHelper), amountMinted);
      distributionHelper.onDistribution(amountMinted);

      // Ignored, because contracts only interacts with trusted contracts and tokens
      // slither-disable-next-line reentrancy-events
      emit ExpansionUBIMinted(exchangeId, amountMinted);
    }
  }

  /**
   * @notice Mints a reward of tokens for the given exchange.
   * @param exchangeId The id of the exchange to mint reward.
   * @param to The address of the recipient.
   * @param amount The amount of tokens to mint.
   */
  function mintRewardFromRR(bytes32 exchangeId, address to, uint256 amount) external onlyAvatar {
    require(to != address(0), "Invalid to address");
    require(amount > 0, "Amount must be greater than 0");
    IBancorExchangeProvider.PoolExchange memory exchange = IBancorExchangeProvider(address(goodDollarExchangeProvider))
      .getPoolExchange(exchangeId);

    goodDollarExchangeProvider.updateRatioForReward(exchangeId, amount);
    IGoodDollar(exchange.tokenAddress).mint(to, amount);

    // Ignored, because contracts only interacts with trusted contracts and tokens
    // slither-disable-next-line reentrancy-events
    emit RewardMinted(exchangeId, to, amount);
  }

  /* ==================== Private Functions ==================== */

  function _setDistributionHelper(address _distributionHelper) internal {
    require(_distributionHelper != address(0), "DistributionHelper address must be set");
    distributionHelper = IDistributionHelper(_distributionHelper);
    emit DistributionHelperUpdated(_distributionHelper);
  }
}
