// SPDX-License-Identifier: UNLICENSED
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.5.17;
pragma experimental ABIEncoderV2;

import { Test, console2 as console } from "celo-foundry/Test.sol";
import { TokenHelpers } from "../utils/TokenHelpers.sol";
import { StableToken } from "contracts/StableToken.sol";
import { StableTokenEUR } from "contracts/StableTokenEUR.sol";
import { GoldToken } from "contracts/common/GoldToken.sol";
import { IExchange } from "contracts/interfaces/IExchange.sol";

import { FixidityLib } from "contracts/common/FixidityLib.sol";

contract ExchangeGasTest is Test, TokenHelpers {
  address trader;
  uint256 celoMainnetFork;

  IExchange exchangeCUSD;
  IExchange exchangeCEUR;

  StableToken cUSDToken;
  StableTokenEUR cEURToken;
  GoldToken celoToken;

  function setUp() public {
    celoMainnetFork = vm.createFork("https://forno.celo.org");
    vm.selectFork(celoMainnetFork);

    // https://docs.mento.org/mento-protocol/core/deployment-addresses
    exchangeCUSD = IExchange(0x67316300f17f063085Ca8bCa4bd3f7a5a3C66275);
    exchangeCEUR = IExchange(0xE383394B913d7302c49F794C7d3243c429d53D1d);

    cUSDToken = StableToken(0x765DE816845861e75A25fCA122bb6898B8B1282a);
    cEURToken = StableTokenEUR(0xD8763CBa276a3738E6DE85b4b3bF5FDed6D6cA73);
    celoToken = GoldToken(0x471EcE3750Da237f93B8E339c536989b8978a438);

    trader = actor("trader");

    mint(cUSDToken, trader, 10**22);
    mint(cEURToken, trader, 10**22);

    console.log("trader CELO balance", celoToken.balanceOf(trader)); // 0, should be 10**22
    console.log(
      "governance proxy CELO balance after tansfer",
      celoToken.balanceOf(0xD533Ca259b330c7A88f74E000a3FaEa2d63B7972)
    );
    console.log("trader cUSD balance", cUSDToken.balanceOf(trader)); // 10**22
    console.log("trader cEUR balance", cEURToken.balanceOf(trader)); // 10**22
  }

  function test_gas_sell_CELO_for_cUSD() public {
    uint256 amountIn = 1000 * 10**18; // 1k
    uint256 minBuyAmount = 1 * 10**18; // 1
    bool sellGold = true;

    changePrank(0xD533Ca259b330c7A88f74E000a3FaEa2d63B7972); //governance proxy
    celoToken.approve(address(exchangeCUSD), amountIn);

    exchangeCUSD.sell(amountIn, minBuyAmount, sellGold);
  }

  function test_gas_sell_CELO_for_cEUR() public {
    uint256 amountIn = 1000 * 10**18; // 1k
    uint256 minBuyAmount = 1 * 10**18; // 1
    bool sellGold = true;

    changePrank(0xD533Ca259b330c7A88f74E000a3FaEa2d63B7972); //governance proxy
    celoToken.approve(address(exchangeCEUR), amountIn);

    exchangeCEUR.sell(amountIn, minBuyAmount, sellGold);
  }

  function test_gas_sell_cUSD_for_CELO() public {
    uint256 amountIn = 1000 * 10**18; // 1k
    uint256 minBuyAmount = 1 * 10**18; // 1
    bool sellGold = false;

    changePrank(trader);
    cUSDToken.approve(address(exchangeCUSD), amountIn);

    exchangeCUSD.sell(amountIn, minBuyAmount, sellGold);
  }

  function test_gas_sell_cEUR_for_CELO() public {
    uint256 amountIn = 1000 * 10**18; // 1k
    uint256 minBuyAmount = 1 * 10**18; // 1
    bool sellGold = false;

    changePrank(trader);
    cEURToken.approve(address(exchangeCEUR), amountIn);

    exchangeCEUR.sell(amountIn, minBuyAmount, sellGold);
  }
}
