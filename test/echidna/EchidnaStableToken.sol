pragma solidity ^0.5.13;

import { StableToken } from "contracts/legacy/StableToken.sol";
import { Registry } from "contracts/common/Registry.sol";

// solhint-disable-next-line max-line-length
//echidna ./test/echidna/EchidnaStableToken.sol --contract EchidnaStableToken --config ./echidna.yaml --test-mode assertion

contract EchidnaStableToken {
  StableToken public stableToken;
  Registry public registry;

  constructor() public {
    registry = new Registry(true);
    registry.initialize();
    registry.setAddressFor("GrandaMento", address(this));
    stableToken = new StableToken(true);
    stableToken.initialize(
      "Celo Dollar",
      "cUSD",
      18,
      address(registry),
      1e24,
      1 weeks,
      new address[](0),
      new uint256[](0),
      "Exchange"
    );
  }

  function zeroAlwaysEmptyERC20Properties() public view {
    assert(stableToken.balanceOf(address(0x0)) == 0);
  }

  function totalSupplyConsistantERC20Properties(
    uint120 user1Amount,
    uint120 user2Amount,
    uint120 user3Amount
  ) public {
    address user1 = address(0x1234);
    address user2 = address(0x5678);
    address user3 = address(0x9abc);
    assert(
      stableToken.balanceOf(user1) + stableToken.balanceOf(user2) + stableToken.balanceOf(user3) ==
        stableToken.totalSupply()
    );
    stableToken.mint(user1, user1Amount);
    stableToken.mint(user2, user2Amount);
    stableToken.mint(user3, user3Amount);
    assert(
      stableToken.balanceOf(user1) + stableToken.balanceOf(user2) + stableToken.balanceOf(user3) ==
        stableToken.totalSupply()
    );
  }

  function transferToOthersERC20PropertiesTransferable() public {
    address receiver = address(0x123456);
    uint256 amount = 100;
    stableToken.mint(msg.sender, amount);
    assert(stableToken.balanceOf(msg.sender) == amount);
    assert(stableToken.balanceOf(receiver) == 0);

    bool transfer = stableToken.transfer(receiver, amount);
    assert(stableToken.balanceOf(msg.sender) == 0);
    assert(stableToken.balanceOf(receiver) == amount);
    assert(transfer);
  }
}
