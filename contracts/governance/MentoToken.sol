// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { ERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "openzeppelin-contracts-next/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/**
 * @title Mento Token
 * @author Mento Labs
 * @notice This contract represents the Mento Protocol Token which is a Burnable ERC20 token.
 */
contract MentoToken is ERC20, ERC20Burnable {
  /// @notice The address of the emission contract that has the capability to emit new tokens.
  address public immutable emissionContract;

  /// @notice The total amount of tokens that can be minted by the emission contract.
  uint256 public immutable emissionSupply;

  /// @notice The total amount of tokens that have been minted by the emission contract so far.
  uint256 public emittedAmount;

  /**
   * @dev Constructor for the MentoToken contract.
   * @notice It mints and allocates the initial token supply among several contracts.
   * @param vestingContract The address of the vesting contract where 20% of the total supply will be sent.
   * @param airgrabContract The address of the airgrab contract where 5% of the total supply will be sent.
   * @param treasuryContract The address of the treasury contract where 10% of the total supply will be sent.
   * @param emissionContract_ The address of the emission contract where the rest of the supply will be emitted.
   */
  constructor(
    address vestingContract,
    address airgrabContract,
    address treasuryContract,
    address emissionContract_
  )
    ERC20("Mento Token", "MENTO") // Initializes the ERC20 token with name and symbol
  {
    // Define the initial total supply as 1 billion tokens
    uint256 supply = 1_000_000_000 * 10**decimals();

    // Calculate the allocations for different purposes based on initial supply
    uint256 vestingSupply = (supply * 20) / 100; // 20%
    uint256 airgrabSupply = (supply * 5) / 100; // 5%
    uint256 treasurySupply = (supply * 10) / 100; // 10%
    uint256 emissionSupply_ = (supply * 65) / 100; // 65%

    // Mint the tokens to respective contracts
    _mint(vestingContract, vestingSupply);
    _mint(airgrabContract, airgrabSupply);
    _mint(treasuryContract, treasurySupply);

    // Set state variables
    emissionContract = emissionContract_;
    emissionSupply = emissionSupply_;
  }

  /**
   * @dev Allows the emission contract to mint new tokens up to the emission supply limit.
   * @notice This function can only be called by the emission contract and
   * only if the total emitted amount hasn't exceeded the emission supply.
   * @param target Address to which the newly minted tokens will be sent.
   * @param amount Amount of tokens to be minted.
   */
  function mint(address target, uint256 amount) external {
    // Only the emission contract can call this function
    require(msg.sender == emissionContract, "MentoToken: OnlyEmissionContract");
    // The total amount emitted doesn't exceed the emission supply
    require(emittedAmount + amount <= emissionSupply, "MentoToken: EmissionSupplyExceeded");

    emittedAmount += amount;
    _mint(target, amount);
  }
}
