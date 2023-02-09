// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;

import "celo-foundry/Test.sol";

import "contracts/StableToken.sol";
import "contracts/common/GoldToken.sol";
import "contracts/common/interfaces/IRegistry.sol";

contract TokenHelpers is Test {
  address public constant REGISTRY_ADDRESS = 0x000000000000000000000000000000000000ce10;
  IRegistry public registry = IRegistry(REGISTRY_ADDRESS);

  function mint(
    GoldToken celoToken,
    address to,
    uint256 amount
  ) internal {
    address pranker = currentPrank;
    changePrank(address(0));
    celoToken.mint(to, amount);
    changePrank(pranker);
  }

  function mint(
    StableToken stableToken,
    address to,
    uint256 amount
  ) internal {
    address pranker = currentPrank;
    changePrank(stableToken.registry().getAddressForString("GrandaMento"));
    stableToken.mint(to, amount);
    changePrank(pranker);
  }

  function mint(
    address token,
    address to,
    uint256 amount
  ) internal {
    if (token == registry.getAddressForString("GoldToken")) {
      mint(GoldToken(token), to, amount);
    } else if (token == registry.getAddressForStringOrDie("StableToken")) {
      mint(StableToken(token), to, amount);
    } else if (token == registry.getAddressForStringOrDie("StableTokenEUR")) {
      mint(StableToken(token), to, amount);
    } else if (token == registry.getAddressForStringOrDie("StableTokenBRL")) {
      mint(StableToken(token), to, amount);
    } else {
      deal(token, to, amount);
    }
  }
}
