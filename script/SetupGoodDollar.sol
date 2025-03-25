// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import { TransparentUpgradeableProxy } from "openzeppelin-contracts-next/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { GoodDollarExchangeProvider } from "contracts/goodDollar/GoodDollarExchangeProvider.sol";
import { GoodDollarExpansionController } from "contracts/goodDollar/GoodDollarExpansionController.sol";
import { Broker } from "contracts/swap/Broker.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";

// import { BrokerProxy } from "contracts/swap/BrokerProxy.sol";

contract SetupGoodDollar is Script {
  // Deployment addresses to be populated
  GoodDollarExchangeProvider public exchangeProvider;
  GoodDollarExpansionController public expansionController;
  IReserve public reserveProxied = IReserve(0x1cbDc8C2F57C3988cbE1B7bD2a323AaDb17379a7);
  address brokerProxy = 0xE60cf1cb6a56131CE135c604D0BD67e84B57CA3C;
  address avatar = vm.envAddress("AVATAR");
  address cUSD = vm.envAddress("CUSD");
  address goodDollar = vm.envAddress("GOODDOLLAR");

  function run() public {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

    vm.startBroadcast(deployerPrivateKey);
    bytes32[] memory assets = new bytes32[](2);
    assets[0] = "cUSD";
    assets[1] = "cGLD";
    address[] memory cAssets = new address[](1);
    cAssets[0] = cUSD;
    uint256[] memory aWeights = new uint256[](2);
    aWeights[0] = 1e24 - 1;
    aWeights[1] = 1;
    uint256[] memory sRatio = new uint256[](1);
    sRatio[0] = 1e24;

    reserveProxied.initialize(
      0x000000000000000000000000000000000000ce10, // registry address
      3153600000, // tobinTaxStalenessThreshold
      1e24, // spendingRatioForCelo (0.1 in fixidity)
      0, // frozenGold
      0, // frozenDays
      assets, // assetAllocationSymbols
      aWeights, // assetAllocationWeights
      0, // tobinTax
      0, // tobinTaxReserveRatio
      cAssets, // collateralAssets
      sRatio // collateralAssetDailySpendingRatios
    );

    reserveProxied.addToken(goodDollar);
    reserveProxied.addExchangeSpender(address(brokerProxy));
    reserveProxied.addSpender(avatar);
    reserveProxied.addOtherReserveAddress(avatar);
    reserveProxied.transferOwnership(avatar);

    vm.stopBroadcast();
  }
}
