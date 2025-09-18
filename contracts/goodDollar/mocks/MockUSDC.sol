// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockUSDC is ERC20, Ownable {
  constructor() ERC20("G$ Test USDC", "USDC") Ownable() {}

  function issueToken() public {
    _mint(msg.sender, 10000 * 10 ** 18);
  }
  function decimals() public view virtual override returns (uint8) {
    return 6;
  }
  function mint(address to, uint256 amount) public onlyOwner {
    _mint(to, amount);
  }
}
