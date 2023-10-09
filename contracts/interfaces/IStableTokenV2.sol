// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.17 <0.8.19;

interface IStableTokenV2 {
  function totalSupply() external view returns (uint256);

  function balanceOf(address account) external view returns (uint256);

  function transfer(address recipient, uint256 amount) external returns (bool);

  function allowance(address owner, address spender) external view returns (uint256);

  function approve(address spender, uint256 amount) external returns (bool);

  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) external returns (bool);

  function mint(address, uint256) external returns (bool);

  function burn(uint256) external returns (bool);

  function permit(
    address owner,
    address spender,
    uint256 value,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external;

  /**
   * @notice Transfer token for a specified address
   * @param to The address to transfer to.
   * @param value The amount to be transferred.
   * @param comment The transfer comment.
   * @return True if the transaction succeeds.
   */
  function transferWithComment(
    address to,
    uint256 value,
    string calldata comment
  ) external returns (bool);

  /**
   * @notice Initializes a StableTokenV2.
   * It keeps the same signature as the original initialize() function
   * in legacy/StableToken.sol
   * @param _name The name of the stable token (English)
   * @param _symbol A short symbol identifying the token (e.g. "cUSD")
   * deprecated-param decimals Tokens are divisible to this many decimal places.
   * deprecated-param registryAddress Address of the Registry contract.
   * deprecated-param inflationRate Weekly inflation rate.
   * deprecated-param inflationFactorUpdatePeriod How often the inflation factor is updated, in seconds.
   * @param initialBalanceAddresses Array of addresses with an initial balance.
   * @param initialBalanceValues Array of balance values corresponding to initialBalanceAddresses.
   * deprecated-param exchangeIdentifier String identifier of exchange in registry (for specific fiat pairs)
   */
  function initialize(
    string calldata _name,
    string calldata _symbol,
    uint8, // deprecated: decimals
    address, // deprecated: registryAddress,
    uint256, // deprecated: inflationRate,
    uint256, // deprecated:  inflationFactorUpdatePeriod,
    address[] calldata initialBalanceAddresses,
    uint256[] calldata initialBalanceValues,
    string calldata // deprecated: exchangeIdentifier
  ) external;

  /**
   * @notice Initializes a StableTokenV2 contract
   * when upgrading from legacy/StableToken.sol.
   * It sets the addresses that were previously read from the Registry.
   * It runs the ERC20PermitUpgradeable initializer.
   * @dev This function is only callable once.
   * @param _broker The address of the Broker contract.
   * @param _validators The address of the Validators contract.
   * @param _exchange The address of the Exchange contract.
   */
  function initializeV2(
    address _broker,
    address _validators,
    address _exchange
  ) external;

  /**
   * @notice Gets the address of the Broker contract.
   */
  function broker() external returns (address);

  /**
   * @notice Gets the address of the Validators contract.
   */
  function validators() external returns (address);

  /**
   * @notice Gets the address of the Exchange contract.
   */
  function exchange() external returns (address);

  function debitGasFees(address from, uint256 value) external;

  function creditGasFees(
    address from,
    address feeRecipient,
    address gatewayFeeRecipient,
    address communityFund,
    uint256 refund,
    uint256 tipTxFee,
    uint256 gatewayFee,
    uint256 baseTxFee
  ) external;
}
