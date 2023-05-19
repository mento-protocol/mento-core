// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.19;

import { ERC20PermitUpgradeable } from "./patched/ERC20PermitUpgradeable.sol";
import { ERC20Upgradeable } from "./patched/ERC20Upgradeable.sol";
import { IMentoERC20 } from "../interfaces/IMentoERC20.sol";

contract MentoERC20 is ERC20PermitUpgradeable, IMentoERC20 {
  address public validators;
  address public broker;
  address public exchange;

  event TransferComment(string comment);

  modifier onlyMinter {
    address sender = _msgSender();
    require(
      sender == broker || sender == validators || sender == exchange,
      "not allowed to mint"
    );
    _;
  }

  modifier onlyBurner {
    address sender = _msgSender();
    require(
      sender == broker || sender == exchange,
      "not allowed to burn"
    );
    _;
  }

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
    address _validators,
    address _exchange
  ) external reinitializer(2) onlyOwner {
    broker = _broker;
    validators = _validators;
    exchange = _exchange;
    __ERC20Permit_init(symbol());
  }

  function setBroker(address _broker) external onlyOwner {
    broker = _broker;
  }

  function setValidators(address _validators) external onlyOwner {
    validators = _validators;
  }

  function setExchange(address _exchange) external onlyOwner {
    exchange = _exchange;
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
  function mint(address to, uint256 value) external onlyMinter returns (bool) {
    _mint(to, value);
    return true;
  }

  /**
   * @notice Burns StableToken from the balance of msg.sender.
   * @param value The amount of StableToken to burn.
   */
  function burn(uint256 value) external onlyBurner returns (bool) {
    _burn(msg.sender, value);
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) public override(ERC20Upgradeable, IMentoERC20) returns (bool) {
    return ERC20Upgradeable.transferFrom(from, to, amount);
  }

  function transfer(address to, uint256 amount) public override(ERC20Upgradeable, IMentoERC20) returns (bool) {
    return ERC20Upgradeable.transfer(to, amount);
  }

  function balanceOf(address account) public view override(ERC20Upgradeable, IMentoERC20) returns (uint256) {
    return ERC20Upgradeable.balanceOf(account);
  }

  function approve(address spender, uint256 amount) public override(ERC20Upgradeable, IMentoERC20) returns (bool) {
    return ERC20Upgradeable.approve(spender, amount);
  }

  function allowance(address owner, address spender) public view override(ERC20Upgradeable, IMentoERC20) returns (uint256) {
    return ERC20Upgradeable.allowance(owner, spender);
  }

  function totalSupply() public view override(ERC20Upgradeable, IMentoERC20) returns (uint256) {
    return ERC20Upgradeable.totalSupply();
  }

  function permit(
    address owner,
    address spender,
    uint256 value,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public override(ERC20PermitUpgradeable, IMentoERC20) {
    ERC20PermitUpgradeable.permit(owner, spender, value, deadline, v, r, s);
  }
}
