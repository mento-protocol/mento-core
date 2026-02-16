// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;
import {
  IERC20PermitUpgradeable
} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/draft-IERC20PermitUpgradeable.sol";

/**
 * @title IStableTokenSpoke
 * @notice Interface for the StableTokenSpoke contract.
 */
interface IStableTokenSpoke is IERC20PermitUpgradeable {
  /**
   * @notice Initializes a StableTokenSpoke.
   * @param _name The name of the stable token (English)
   * @param _symbol A short symbol identifying the token (e.g. "cUSD")
   * @param initialBalanceAddresses Array of addresses with an initial balance.
   * @param initialBalanceValues Array of balance values corresponding to initialBalanceAddresses.
   * @param _minters The addresses that are allowed to mint.
   * @param _burners The addresses that are allowed to burn.
   */
  function initialize(
    string calldata _name,
    string calldata _symbol,
    address[] calldata initialBalanceAddresses,
    uint256[] calldata initialBalanceValues,
    address[] calldata _minters,
    address[] calldata _burners
  ) external;
  /**
   * @notice Sets the minter role for an address.
   * @param _minter The address of the minter.
   * @param _isMinter The boolean value indicating if the address is a minter.
   */
  function setMinter(address _minter, bool _isMinter) external;

  /**
   * @notice Sets the burner role for an address.
   * @param _burner The address of the burner.
   * @param _isBurner The boolean value indicating if the address is a burner.
   */
  function setBurner(address _burner, bool _isBurner) external;

  /**
   * @notice Mints new StableToken and gives it to 'to'.
   * @param to The account for which to mint tokens.
   * @param value The amount of StableToken to mint.
   */
  function mint(address to, uint256 value) external returns (bool);

  /**
   * @notice Burns StableToken from the balance of msg.sender.
   * @param value The amount of StableToken to burn.
   */
  function burn(uint256 value) external returns (bool);
}
