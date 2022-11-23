
pragma solidity ^0.5.13;

import { Script, console2 } from "forge-std/Script.sol";
import { ScriptHelper } from "../utils/ScriptHelper.sol";

import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";

import { MedianDeltaBreaker } from "contracts/MedianDeltaBreaker.sol";
import { BreakerBox } from "contracts/BreakerBox.sol";
import { BreakerBoxProxy } from "contracts/proxies/BreakerBoxProxy.sol";

// ANVIL - forge script script/deploy/01-CircuitBreaker.sol --fork-url http://localhost:8545 --broadcast --legacy --private-key
// Baklava - forge script script/deploy/01-CircuitBreaker.sol --rpc-url https://baklava-forno.celo-testnet.org --broadcast --legacy --verify --verifier sourcify --private-key

contract DeployCircuitBreaker is Script, ScriptHelper {
  MedianDeltaBreaker medianDeltaBreaker;
  BreakerBox breakerBox;
  BreakerBoxProxy breakerBoxProxy;

  function run() public {
    NetworkProxies memory proxies = getNetworkProxies();
    address[] memory rateFeedIDs = new address[](2);
    rateFeedIDs[0] = proxies.stableToken;
    rateFeedIDs[1] = proxies.stableTokenEUR;

    vm.startBroadcast();
    {
      // Deploy new implementations
      breakerBox = new BreakerBox(true);

      medianDeltaBreaker = new MedianDeltaBreaker(0, 0, ISortedOracles(proxies.sortedOracles));
      medianDeltaBreaker.transferOwnership(proxies.celoGovernance);

      breakerBoxProxy = new BreakerBoxProxy();
      breakerBoxProxy._setImplementation(address(breakerBox));
      BreakerBox(address(breakerBoxProxy)).initialize(
        rateFeedIDs,
        ISortedOracles(proxies.sortedOracles)
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
