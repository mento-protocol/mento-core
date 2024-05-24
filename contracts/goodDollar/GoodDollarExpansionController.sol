// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { IGoodDollarExpansionController } from "./interfaces/IGoodDollarExpansionController.sol";
import { IGoodDollarExchangeProvider } from "./interfaces/IGoodDollarExchangeProvider.sol";
import { IBancorExchangeProvider } from "./interfaces/IBancorExchangeProvider.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
import { IGoodDollar } from "./interfaces/IGoodDollar.sol";
import { IDistributionHelper } from "./interfaces/IDistributionHelper.sol";

import { PausableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol";
import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

/**
 * @title GoodDollarExpansionController
 * @notice Provides functionality to expand the supply of GoodDollars.
 */
contract GoodDollarExpansionController is IGoodDollarExpansionController, PausableUpgradeable, OwnableUpgradeable {
  /* ==================== State Variables ==================== */

  // MAX_WEIGHT is the max rate that can be assigned to an exchange
  uint256 private constant MAX_WEIGHT = 1e18;

  // Address of the distribution helper contract
  IDistributionHelper public distributionHelper;

  // Address of reserve contract holding the GoodDollar reserve
  address public reserve;

  // Address of the GoodDollar exchange provider
  IGoodDollarExchangeProvider public goodDollarExchangeProvider;

  // Maps exchangeId to exchangeExpansionConfig
  mapping(bytes32 => ExchangeExpansionConfig) public exchangeExpansionConfigs;

  // Address of the GoodDollar DAO contract.
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
   *
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
    setDistributionHelper(_distributionHelper);
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
    require(_goodDollarExchangeProvider != address(0), "Invalid exchangeProvider address");
    goodDollarExchangeProvider = IGoodDollarExchangeProvider(_goodDollarExchangeProvider);
  }

  /**
   * @notice Sets the distribution helper address.
   * @param _distributionHelper The address of the distribution helper contract.
   */
  function setDistributionHelper(address _distributionHelper) public onlyOwner {
    require(_distributionHelper != address(0), "Invalid distributionHelper address");
    distributionHelper = IDistributionHelper(_distributionHelper);
  }

  /**
   * @notice Sets the reserve address.
   * @param _reserve The address of the reserve contract.
   */
  function setReserve(address _reserve) public onlyOwner {
    require(_reserve != address(0), "Invalid reserve address");
    reserve = _reserve;
  }

  /**
   * @notice Sets the AVATAR address.
   * @param _avatar The address of the AVATAR contract.
   */
  function setAvatar(address _avatar) public onlyOwner {
    require(_avatar != address(0), "Invalid avatar address");
    AVATAR = _avatar;
  }

  /**
   * @notice Sets the expansion config for the given exchange.
   * @param exchangeId The id of the exchange to set the expansion config for.
   * @param config The expansion config.
   */
  function setExpansionConfig(bytes32 exchangeId, ExchangeExpansionConfig memory config) external onlyAvatar {
    require(config.expansionRate < MAX_WEIGHT, "Invalid expansion rate");
    require(config.expansionRate > 0, "Invalid expansion rate");
    require(config.expansionfrequency > 0, "Invalid expansion frequency");

    exchangeExpansionConfigs[exchangeId].expansionRate = config.expansionRate;
    exchangeExpansionConfigs[exchangeId].expansionfrequency = config.expansionfrequency;
    exchangeExpansionConfigs[exchangeId].lastExpansion = block.timestamp; // not sure how we want to initialize this
  }

  /**
   * @notice Updates the expansion rate for the given exchange.
   * @param exchangeId The id of the exchange to set the expansion rate for.
   * @param expansionRate The expansion rate.
   */
  function setExpansionRate(bytes32 exchangeId, uint256 expansionRate) external onlyAvatar {
    require(exchangeExpansionConfigs[exchangeId].expansionfrequency > 0, "Expansion config not set");
    require(expansionRate < MAX_WEIGHT, "Invalid expansion rate");
    require(expansionRate > 0, "Invalid expansion rate");
    exchangeExpansionConfigs[exchangeId].expansionRate = expansionRate;
  }

  /**
   * @notice Mints UBI for the given exchange from collecting reserve interest.
   * @param exchangeId The id of the exchange to mint UBI for.
   * @param reserveInterest The amount of reserve tokens collected from interest.
   */
  function mintUBIFromInterest(bytes32 exchangeId, uint256 reserveInterest) external {
    IBancorExchangeProvider.PoolExchange memory exchange = IBancorExchangeProvider(address(goodDollarExchangeProvider))
      .getPoolExchange(exchangeId);

    uint256 amountToMint = goodDollarExchangeProvider.mintFromInterest(exchangeId, reserveInterest);

    require(IERC20(exchange.reserveAsset).transferFrom(msg.sender, reserve, reserveInterest));
    require(IGoodDollar(exchange.tokenAddress).mint(address(distributionHelper), amountToMint));
    emit UBIMinted(exchangeId, amountToMint);
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

    bool shouldExpand = block.timestamp >= config.lastExpansion + config.expansionfrequency;
    if (shouldExpand) {
      uint256 numberOfExpansions = (block.timestamp - config.lastExpansion) / config.expansionfrequency;
      uint256 expansionRate = config.expansionRate;
      for (uint256 i = 0; i < numberOfExpansions; i++) {
        expansionRate = (expansionRate * expansionRate) / MAX_WEIGHT;
      }
      amountMinted = goodDollarExchangeProvider.mintFromExpansion(exchangeId, expansionRate);
      exchangeExpansionConfigs[exchangeId].lastExpansion = block.timestamp;

      require(IGoodDollar(exchange.tokenAddress).mint(address(distributionHelper), amountMinted));
      emit UBIMinted(exchangeId, amountMinted);
      distributionHelper.onDistribution(amountMinted);
    }
  }

  /**
   * @notice Mints a reward of tokens for the given exchange.
   * @param exchangeId The id of the exchange to mint reward.
   * @param to The address of the recipient.
   * @param amount The amount of tokens to mint.
   */
  function mintRewardFromRR(
    bytes32 exchangeId,
    address to,
    uint256 amount
  ) external onlyAvatar {
    require(to != address(0), "Invalid address");
    require(amount > 0, "Invalid amount");
    IBancorExchangeProvider.PoolExchange memory exchange = IBancorExchangeProvider(address(goodDollarExchangeProvider))
      .getPoolExchange(exchangeId);

    goodDollarExchangeProvider.updateRatioForReward(exchangeId, amount);
    require(IGoodDollar(exchange.tokenAddress).mint(to, amount));
    emit RewardMinted(exchangeId, to, amount);
  }
}
