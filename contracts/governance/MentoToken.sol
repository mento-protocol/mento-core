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
   * @param allocationRecipients_ The addresses of the initial token recipients.
   * @param allocationAmounts_ The percentage of tokens to be allocated to each recipient.
   * @param emission_ The address of the emission contract where the rest of the supply will be emitted.
   */
  // solhint-enable max-line-length
  constructor(
    address[] memory allocationRecipients_,
    uint256[] memory allocationAmounts_,
    address emission_
  ) ERC20("Mento Token", "MENTO") {
    require(emission_ != address(0), "MentoToken: emission is zero address");
    _verifyAllocation(allocationRecipients_, allocationAmounts_);
    uint256 supply = 1_000_000_000 * 10**decimals();

    uint256 emissionAllocation = 1000;
    for (uint256 i = 0; i < allocationRecipients_.length; i++) {
      _mint(allocationRecipients_[i], (supply * allocationAmounts_[i]) / 1000);
      emissionAllocation -= allocationAmounts_[i];
    }

    emission = emission_;
    emissionSupply = (supply * emissionAllocation) / 1000;
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

  /**
   * @dev verifies constructor parameters & ensures valid allocation.
   * @param allocationRecipients_ The addresses of the initial token recipients.
   * @param allocationAmounts_ The percentage of tokens to be allocated to each recipient.
   */
  function _verifyAllocation(address[] memory allocationRecipients_, uint256[] memory allocationAmounts_)
    internal
    pure
  {
    require(
      allocationRecipients_.length == allocationAmounts_.length,
      "MentoToken: recipients and amounts length mismatch"
    );

    uint256 totalAllocated = 0;

    for (uint256 i = 0; i < allocationRecipients_.length; i++) {
      require(allocationRecipients_[i] != address(0), "MentoToken: allocation recipient is zero address");
      totalAllocated += allocationAmounts_[i];
    }
    require(totalAllocated <= 1000, "MentoToken: total allocation exceeds 100%");
  }
}
