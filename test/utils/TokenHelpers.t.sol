// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.5.13;

import "celo-foundry/Test.sol";

import "contracts/legacy/StableToken.sol";
import "contracts/common/GoldToken.sol";
import "contracts/common/interfaces/IRegistry.sol";
import "contracts/interfaces/IStableTokenV2.sol";

contract TokenHelpers is Test {
  address public constant REGISTRY_ADDRESS = 0x000000000000000000000000000000000000ce10;
  IRegistry public registry = IRegistry(REGISTRY_ADDRESS);

  function mint(
    address token,
    address to,
    uint256 amount
  ) public {
    if (token == registry.getAddressForString("GoldToken")) {
      mint(GoldToken(token), to, amount);
    } else if (token == registry.getAddressForStringOrDie("StableToken")) {
      mint(IStableTokenV2(token), to, amount);
    } else if (token == registry.getAddressForStringOrDie("StableTokenEUR")) {
      mint(IStableTokenV2(token), to, amount);
    } else if (token == registry.getAddressForStringOrDie("StableTokenBRL")) {
      mint(IStableTokenV2(token), to, amount);
    } else if (token == registry.getAddressForStringOrDie("StableTokenXOF")) {
      mint(IStableTokenV2(token), to, amount);
    } else {
      deal(token, to, amount);
    }
  }

  function mintCelo(address to, uint256 amount) public {
    mint(registry.getAddressForString("GoldToken"), to, amount);
  }

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

  // TODO: delete after the migration to StableTokenV2 is done on mainnet
  function mint(
    StableToken stableToken,
    address to,
    uint256 amount
  ) internal {
    address pranker = currentPrank;
    changePrank(stableToken.registry().getAddressForString("Broker"));
    stableToken.mint(to, amount);
    changePrank(pranker);
  }

  function mint(
    IStableTokenV2 stableToken,
    address to,
    uint256 amount
  ) internal {
    address pranker = currentPrank;
    changePrank(stableToken.broker());
    stableToken.mint(to, amount);
    changePrank(pranker);
  }
}
