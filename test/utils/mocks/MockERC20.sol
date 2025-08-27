// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";

contract MockERC20 is IERC20 {
  string private _name;
  string private _symbol;
  uint256 private _decimals;

  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;
  uint256 public totalSupply;

  event MintCalled(address indexed caller, address indexed to, uint256 amount);
  event BurnCalled(address indexed caller, uint256 amount);
  event TransferCalled(address indexed caller, address indexed to, uint256 amount);

  constructor(string memory name_, string memory symbol_, uint256 decimals_) {
    _name = name_;
    _symbol = symbol_;
    _decimals = decimals_;
  }

  function name() public view returns (string memory) {
    return _name;
  }

  function symbol() public view returns (string memory) {
    return _symbol;
  }

  function decimals() public view returns (uint256) {
    return _decimals;
  }

  function transfer(address to, uint256 amount) external override returns (bool) {
    emit TransferCalled(msg.sender, to, amount);
    balanceOf[msg.sender] -= amount;
    balanceOf[to] += amount;
    emit Transfer(msg.sender, to, amount);
    return true;
  }

  function approve(address spender, uint256 amount) external override returns (bool) {
    allowance[msg.sender][spender] = amount;
    emit Approval(msg.sender, spender, amount);
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
    emit TransferCalled(msg.sender, to, amount);
    uint256 currentAllowance = allowance[from][msg.sender];
    require(currentAllowance >= amount, "MOCKERC20: transfer amount exceeds allowance");
    allowance[from][msg.sender] = currentAllowance - amount;

    balanceOf[from] -= amount;
    balanceOf[to] += amount;
    emit Transfer(from, to, amount);
    return true;
  }

  function mint(address to, uint256 amount) external {
    emit MintCalled(msg.sender, to, amount);
    balanceOf[to] += amount;
    totalSupply += amount;
    emit Transfer(address(0), to, amount);
  }

  function burn(uint256 amount) external {
    emit BurnCalled(msg.sender, amount);
    balanceOf[msg.sender] -= amount;
    totalSupply -= amount;
    emit Transfer(msg.sender, address(0), amount);
  }

  function setBalance(address account, uint256 amount) external {
    balanceOf[account] = amount;
  }

  function setTotalSupply(uint256 supply) external {
    totalSupply = supply;
  }
}
