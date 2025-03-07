// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable gas-custom-errors
pragma solidity 0.8.18;

import { ERC20PermitUpgradeable } from "./patched/ERC20PermitUpgradeable.sol";
import { CalledByVm } from "celo/contracts/common/CalledByVm.sol";

/**
 * @title ERC20 token with minting and burning permissioned to a broker and validators.
 * @dev Extends StableTokenV2 functionality with the ability to update the token name.
 */
contract TempStableToken is ERC20PermitUpgradeable, CalledByVm {
  address public validators;
  address public broker;
  address public exchange;
  string private _name;

  event TransferComment(string comment);
  event BrokerUpdated(address broker);
  event ValidatorsUpdated(address validators);
  event ExchangeUpdated(address exchange);
  event NameUpdated(string oldName, string newName);

  /**
   * @dev Restricts a function so it can only be executed by an address that's allowed to mint.
   * Currently that's the broker, validators, or exchange.
   */
  modifier onlyMinter() {
    address sender = _msgSender();
    require(sender == broker || sender == validators || sender == exchange, "StableTokenV3: not allowed to mint");
    _;
  }

  /**
   * @dev Restricts a function so it can only be executed by an address that's allowed to burn.
   * Currently that's the broker or exchange.
   */
  modifier onlyBurner() {
    address sender = _msgSender();
    require(sender == broker || sender == exchange, "StableTokenV3: not allowed to burn");
    _;
  }

  /**
   * @notice The constructor for the StableTokenV3 contract.
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
   * @notice Updates the token name.
   * @dev This function is only callable by the owner.
   * @param newName The new name for the token.
   */
  function setName(string calldata newName) external onlyOwner {
    string memory oldName = name();
    _name = newName;
    emit NameUpdated(oldName, newName);
  }

  // Implementation of IStableTokenV2 functions that are not overridden

  function transferWithComment(address to, uint256 value, string calldata comment) external returns (bool) {
    emit TransferComment(comment);
    return transfer(to, value);
  }

  function mint(address to, uint256 value) external onlyMinter returns (bool) {
    _mint(to, value);
    return true;
  }

  function burn(uint256 value) external onlyBurner returns (bool) {
    _burn(msg.sender, value);
    return true;
  }

  function debitGasFees(address from, uint256 value) external onlyVm {
    _burn(from, value);
  }
}
