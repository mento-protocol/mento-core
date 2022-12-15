// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;

import { Script } from "script/utils/Script.sol";
import { console2 } from "forge-std/Script.sol";
import { IBroker } from "contracts/interfaces/IBroker.sol";
import { IExchangeProvider } from "contracts/interfaces/IExchangeProvider.sol";
import { IERC20Metadata } from "contracts/common/interfaces/IERC20Metadata.sol";
import { BiPoolManager } from "contracts/BiPoolManager.sol";

contract SwapTest is Script {
  function run() public {
    IBroker broker = IBroker(contracts.celoRegistry("Broker"));
    address[] memory exchangeProviders = broker.getExchangeProviders();
    BiPoolManager bpm = BiPoolManager(exchangeProviders[0]);
    // bytes32[] memory exchanges = bpm.exchangeIds();
    bytes32 exchangeID = bpm.exchangeIds(0);
    address tokenIn = contracts.celoRegistry("GoldToken");
    address tokenOut = contracts.celoRegistry("StableToen");

    uint256 amountOut = broker.getAmountOut(exchangeProviders[0], exchangeID, tokenIn, tokenOut, 1e20);

    console2.log(amountOut);

    vm.startBroadcast();
    {
      IERC20Metadata(contracts.celoRegistry("GoldToken")).approve(address(broker), 1e20);
      broker.swapIn(exchangeProviders[0], exchangeID, tokenIn, tokenOut, 1e20, amountOut - 1e18);
    }
    vm.stopBroadcast();
  }
}
