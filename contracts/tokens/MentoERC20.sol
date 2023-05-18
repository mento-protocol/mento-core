// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.19;

import { ERC20PermitUpgradeable } from "./oz-overrides/ERC20PermitUpgradeable.sol";

contract MentoERC20 is ERC20PermitUpgradeable  {
  // bytes32 private constant VALIDATORS_REGISTRY_ID = keccak256(abi.encodePacked("Validators"));
  // bytes32 private constant BROKER_REGISTRY_ID = keccak256(abi.encodePacked("Broker"));

  address private validators;
  address private broker;

  event TransferComment(string comment);

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
  ) external initializer {
    __ERC20_init_unchained(_name, _symbol);
    __ERC20Permit_init(_symbol);
    _transferOwnership(msg.sender);

    require(initialBalanceAddresses.length == initialBalanceValues.length, "Array length mismatch");
    for (uint256 i = 0; i < initialBalanceAddresses.length; i += 1) {
      _mint(initialBalanceAddresses[i], initialBalanceValues[i]);
    }
  }

  function initializeV2(
    address _broker,
    address _validators
  ) external reinitializer(2) onlyOwner {
    broker = _broker;
    validators = _validators;
    __ERC20Permit_init(symbol());
  }

  function setBroker(address _broker) external onlyOwner {
    broker = _broker;
  }

  function setValidators(address _validators) external onlyOwner {
    validators = _validators;
  }

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
  ) external returns (bool) {
    emit TransferComment(comment);
    return transfer(to, value);
  }

  /**
   * @notice Mints new StableToken and gives it to 'to'.
   * @param to The account for which to mint tokens.
   * @param value The amount of StableToken to mint.
   */
  function mint(address to, uint256 value) external returns (bool) {
    require(
      msg.sender == broker || msg.sender == validators,
      "Sender not authorized to mint"
    );
    _mint(to, value);
    return true;
  }

  /**
   * @notice Burns StableToken from the balance of msg.sender.
   * @param value The amount of StableToken to burn.
   */
  function burn(uint256 value) external returns (bool) {
    require(
      msg.sender == broker,
      "Sender not authorized to burn"
    );
    _burn(msg.sender, value);
    return true;
  }
}
