// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import { TransparentUpgradeableProxy } from "openzeppelin-contracts-next/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "openzeppelin-contracts-next/contracts/proxy/transparent/ProxyAdmin.sol";

import { GoodDollarExchangeProvider } from "contracts/goodDollar/GoodDollarExchangeProvider.sol";
import { GoodDollarExpansionController } from "contracts/goodDollar/GoodDollarExpansionController.sol";
// import { Reserve } from "contracts/swap/Reserve.sol";
import { Broker } from "contracts/swap/Broker.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";
import { ITradingLimits } from "contracts/interfaces/ITradingLimits.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

// import { BrokerProxy } from "contracts/swap/BrokerProxy.sol";

contract DeployGoodDollarImplementations is Script {
  // Deployment addresses to be populated
  GoodDollarExchangeProvider public exchangeProvider;
  GoodDollarExpansionController public expansionController;
  address public reserve;
  Broker public broker;

  uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
  address avatar = vm.envAddress("AVATAR");
  address signer = vm.addr(deployerPrivateKey);
  address c2Deployer = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

  function run() public {
    vm.startBroadcast(deployerPrivateKey);

    // Deploy implementation contracts
    exchangeProvider = new GoodDollarExchangeProvider{
      salt: keccak256(abi.encodePacked("ExchangeProviderImplV1", ""))
    }(true);
    expansionController = new GoodDollarExpansionController{
      salt: keccak256(abi.encodePacked("ExpansionControllerImplV1", ""))
    }(true);

    bytes memory reserveCode = vm.getCode("Reserve.sol");
    bytes memory c2Code = abi.encodePacked(
      keccak256(abi.encodePacked("MentoReserveImplV1", "")),
      abi.encodePacked(reserveCode, abi.encode(true))
    );

    (, bytes memory result) = c2Deployer.call{ value: 0 }(c2Code);
    reserve = address(bytes20(result));
    // reserve = 0xf78C12e6d3971cfC325A3B150fA4BB5AB8660c3F; //deployCode("Reserve.sol", abi.encode(true)); //because of solidity version conflict
    broker = new Broker{ salt: keccak256(abi.encodePacked("MentoBrokerImplV1", "")) }(true);

    vm.stopBroadcast();

    // Log deployed addresses
    console.log("Deployer:", signer);
    console.log("GoodDollarExchangeProvider deployed to:", address(exchangeProvider));
    console.log("GoodDollarExpansionController  deployed to:", address(expansionController));
    console.log("Reserve impl deployed to:", address(reserve));
    console.log("Broker deployed to:", address(broker));
  }
}
