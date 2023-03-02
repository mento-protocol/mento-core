// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.5.13;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Detailed.sol";

contract DummyERC20 is ERC20, ERC20Detailed {
  constructor(
    string memory name,
    string memory symbol,
    uint8 decimals
  ) public ERC20Detailed(name, symbol, decimals) {}
}
