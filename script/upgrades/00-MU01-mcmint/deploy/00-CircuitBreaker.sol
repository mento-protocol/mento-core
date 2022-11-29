// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;

import { Script, console2 } from "forge-std/Script.sol";
import { ScriptHelper } from "script/utils/ScriptHelper.sol";

import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";

import { MedianDeltaBreaker } from "contracts/MedianDeltaBreaker.sol";
import { BreakerBox } from "contracts/BreakerBox.sol";
import { BreakerBoxProxy } from "contracts/proxies/BreakerBoxProxy.sol";

/*
 Baklava: 
 forge script {file} --rpc-url $BAKLAVA_RPC_URL 
                     --broadcast --legacy --verify --verifier sourcify 
                     --private-key $BAKLAVA_DEPLOYER_PK
*/

contract DeployCircuitBreaker is Script, ScriptHelper {
  MedianDeltaBreaker private medianDeltaBreaker;
  BreakerBox private breakerBox;
  BreakerBoxProxy private breakerBoxProxy;

  function run() public {
    NetworkProxies memory proxies = getNetworkProxies();
    address[] memory rateFeedIDs = new address[](2);
    rateFeedIDs[0] = proxies.stableToken;
    rateFeedIDs[1] = proxies.stableTokenEUR;

    vm.startBroadcast();
    {
      medianDeltaBreaker = new MedianDeltaBreaker(0, 0, ISortedOracles(proxies.sortedOracles));
      medianDeltaBreaker.transferOwnership(proxies.celoGovernance);

      breakerBox = new BreakerBox(false);
      breakerBoxProxy = new BreakerBoxProxy();
      breakerBoxProxy._setAndInitializeImplementation(
        address(breakerBox),
        abi.encodeWithSelector(
          BreakerBox(address(breakerBoxProxy)).initialize.selector,
          rateFeedIDs,
          ISortedOracles(proxies.sortedOracles)
        )
      );
      breakerBoxProxy._transferOwnership(proxies.celoGovernance);
      BreakerBox(address(breakerBoxProxy)).transferOwnership(proxies.celoGovernance);
    }
    vm.stopBroadcast();

    console2.log("----------");
    console2.log("BreakerBox deployed at: ", address(breakerBox));
    console2.log("BreakerBoxProxy deployed at: ", address(breakerBoxProxy));
    console2.log("Transferred BreakerBox proxy & implementation ownereship to ", address(proxies.celoGovernance));
    console2.log("----------");
    console2.log("MedianDeltaBreaker deployed at", address(medianDeltaBreaker));
    console2.log("Transferred MedianDeltaBreaker ownership to ", address(proxies.celoGovernance));
    console2.log("----------");
  }
}
