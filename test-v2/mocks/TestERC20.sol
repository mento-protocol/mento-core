// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";

contract TestERC20 is ERC20Upgradeable {
  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }

  function init() external {
    __ERC20_init("TestERC20", "TE20");
  }
}
