// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;

import { Script, console2 } from "forge-std/Script.sol";
import { ScriptHelper } from "../utils/ScriptHelper.sol";
import { IBroker } from "contracts/interfaces/IBroker.sol";
import { IExchangeProvider } from "contracts/interfaces/IExchangeProvider.sol";
import { IERC20Metadata } from "contracts/common/interfaces/IERC20Metadata.sol";
import { BiPoolManager } from "contracts/BiPoolManager.sol";

contract SwapTest is Script, ScriptHelper {
    function run() public {
        NetworkProxies memory proxies = getNetworkProxies();
        IBroker broker = IBroker(proxies.broker);
        address[] memory exchangeProviders = broker.getExchangeProviders();
        BiPoolManager bpm = BiPoolManager(exchangeProviders[0]);
        // bytes32[] memory exchanges = bpm.exchangeIds();
        bytes32 exchangeID = bpm.exchangeIds(0);
        address tokenIn = proxies.celoToken;
        address tokenOut = proxies.stableToken;

        uint256 amountOut = broker.getAmountOut(
            exchangeProviders[0],
            exchangeID,
            tokenIn,
            tokenOut,
            1e20
        );

        console2.log(amountOut);
        
        vm.startBroadcast();
        {


        }
        vm.stopBroadcast();
    }
}