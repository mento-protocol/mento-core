// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IGoodDollarExpansionController {
  /**
   * @notice Struct holding the configuration for the expansion of an exchange.
   * @param expansionRate The rate of expansion.
   * @param expansionfrequency The frequency of expansion.
   * @param lastExpansion The last time expansion was done.
   */
  struct ExchangeExpansionConfig {
    uint256 expansionRate;
    uint256 expansionfrequency;
    uint256 lastExpansion;
  }

  /* ------- Events ------- */

  /**
   * @notice Emitted when a reward is minted.
   * @param exchangeId The id of the exchange.
   * @param to The address of the recipient.
   * @param amount The amount of tokens minted.
   */
  event RewardMinted(bytes32 indexed exchangeId, address indexed to, uint256 amount);

  /**
   * @notice Emitted when UBI is minted.
   * @param exchangeId The id of the exchange.
   * @param amount Amount of tokens minted.
   */
  event UBIMinted(bytes32 indexed exchangeId, uint256 amount);

  /**
   * @notice Emitted when the distribution helper is updated.
   * @param distributionHelper The address of the new distribution helper.
   */
  event DistributionHelperUpdated(address indexed distributionHelper);

  /**
   * @notice Emitted when the GoodDollarExchangeProvider is updated.
   * @param exchangeProvider The address of the new GoodDollarExchangeProvider.
   */
  event GoodDollarExchangeProviderUpdated(address indexed exchangeProvider);

  /* ------- Functions ------- */

  /**
   * @notice Sets the GoodDollarExchangeProvider address.
   * @param _goodDollarExchangeProvider The address of the GoodDollarExchangeProvider contract.
   */
  function setGoodDollarExchangeProvider(address _goodDollarExchangeProvider) external;

  /**
   * @notice Sets the distribution helper address.
   * @param _distributionHelper The address of the distribution helper contract.
   */
  function setDistributionHelper(address _distributionHelper) external;

  /**
   * @notice Sets the reserve address.
   * @param _reserve The address of the reserve contract.
   */
  function setReserve(address _reserve) external;

  /**
   * @notice Sets the AVATAR address.
   * @param _avatar The address of the AVATAR contract.
   */
  function setAvatar(address _avatar) external;

  /**
   * @notice Sets the expansion config for the given exchange.
   * @param exchangeId The id of the exchange to set the expansion config for.
   * @param config The expansion config.
   */
  function setExpansionConfig(bytes32 exchangeId, ExchangeExpansionConfig memory config) external;

  /**
   * @notice Updates the expansion rate for the given exchange.
   * @param exchangeId The id of the exchange to set the expansion rate for.
   * @param expansionRate The expansion rate.
   */
  function setExpansionRate(bytes32 exchangeId, uint256 expansionRate) external;

  /**
   * @notice Mints UBI for the given exchange from collecting reserve interest.
   * @param exchangeId The id of the exchange to mint UBI for.
   * @param reserveInterest The amount of reserve tokens collected from interest.
   */
  function mintUBIFromInterest(bytes32 exchangeId, uint256 reserveInterest) external;

  /**
   * @notice Mints UBI for the given exchange by calculating the expansion rate.
   * @param exchangeId The id of the exchange to mint UBI for.
   * @return amountMinted The amount of UBI tokens minted.
   */
  function mintUBIFromExpansion(bytes32 exchangeId) external returns (uint256 amountMinted);

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
  ) external;
}
