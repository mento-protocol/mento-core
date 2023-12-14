// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { ERC20Burnable, ERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/**
 * @title Mento Token
 * @author Mento Labs
 * @notice This contract represents the Mento Protocol Token which is a Burnable ERC20 token.
 */
contract MentoToken is ERC20Burnable {
  /// @notice The address of the emission contract that has the capability to emit new tokens.
  address public immutable emission;

  /// @notice The total amount of tokens that can be minted by the emission contract.
  uint256 public immutable emissionSupply;

  /// @notice The total amount of tokens that have been minted by the emission contract so far.
  uint256 public emittedAmount;

  // solhint-disable max-line-length
  /**
   * @dev Constructor for the MentoToken contract.
   * @notice It mints and allocates the initial token supply among several contracts.
   * @param mentoLabsMultiSig The address of the Mento Labs MultiSig where 8% of the total supply will be sent for vesting.
   * @param mentoLabsTreasuryTimelock The address of the timelocked Mento Labs treasury where 12% of the total supply will be sent.
   * @param airgrab The address of the airgrab contract where 5% of the total supply will be sent.
   * @param governanceTimelock The address of the treasury contract where 10% of the total supply will be sent.
   * @param emission_ The address of the emission contract where the rest of the supply will be emitted.
   */
  // solhint-enable max-line-length
  constructor(
    address mentoLabsMultiSig,
    address mentoLabsTreasuryTimelock,
    address airgrab,
    address governanceTimelock,
    address emission_
  ) ERC20("Mento Token", "MENTO") {
    uint256 supply = 1_000_000_000 * 10**decimals();

    uint256 mentoLabsMultiSigSupply = (supply * 8) / 100;
    uint256 mentoLabsTreasurySupply = (supply * 12) / 100;
    uint256 airgrabSupply = (supply * 5) / 100;
    uint256 governanceTimelockSupply = (supply * 10) / 100;
    uint256 emissionSupply_ = (supply * 65) / 100;

    _mint(mentoLabsMultiSig, mentoLabsMultiSigSupply);
    _mint(mentoLabsTreasuryTimelock, mentoLabsTreasurySupply);
    _mint(airgrab, airgrabSupply);
    _mint(governanceTimelock, governanceTimelockSupply);

    emission = emission_;
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
    require(msg.sender == emission, "MentoToken: only emission contract");
    require(emittedAmount + amount <= emissionSupply, "MentoToken: emission supply exceeded");

    emittedAmount += amount;
    _mint(target, amount);
  }
}
