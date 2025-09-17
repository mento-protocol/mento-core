// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import { TransparentUpgradeableProxy } from "openzeppelin-contracts-next/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "openzeppelin-contracts-next/contracts/proxy/transparent/ProxyAdmin.sol";
import { Ownable } from "openzeppelin-contracts-next/contracts/access/Ownable.sol";

import { GoodDollarExchangeProvider } from "contracts/goodDollar/GoodDollarExchangeProvider.sol";
import { GoodDollarExpansionController } from "contracts/goodDollar/GoodDollarExpansionController.sol";
import { Broker } from "contracts/swap/Broker.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";
import { ITradingLimits } from "contracts/interfaces/ITradingLimits.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
interface IRegistry {
    function initialize() external;
    function transferOwnership(address newOwner) external;
}
contract DeployMento is Script {
  // Deployment addresses to be populated
  ProxyAdmin public proxyAdmin;
  address public exchangeProvider = vm.envAddress("EXCHANGEPROVIDER_IMPL");
  address public expansionController = vm.envAddress("EXPANSIONCONTROLLER_IMPL");
  address public reserve = vm.envAddress("RESERVE_IMPL");
  address public broker = vm.envAddress("BROKER_IMPL");
  address public registry = vm.envAddress("REGISTRY_IMPL");
  address distHelper = vm.envAddress("DISTRIBUTION_HELPER");

  // Proxy addresses
  TransparentUpgradeableProxy public exchangeProviderProxy;
  TransparentUpgradeableProxy public expansionControllerProxy;
  TransparentUpgradeableProxy public registryProxy;
  TransparentUpgradeableProxy public reserveProxy;
  TransparentUpgradeableProxy public brokerProxy;

  uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
  address avatar = vm.envAddress("AVATAR");
  address cUSD = vm.envAddress("CUSD");
  address goodDollar = vm.envAddress("GOODDOLLAR");
  string env = vm.envString("ENV");
  address signer = vm.addr(deployerPrivateKey);
  address c2Deployer = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

  function run() public {
    vm.startBroadcast(deployerPrivateKey);

    // Deploy ProxyAdmin
    proxyAdmin = new ProxyAdmin();
    proxyAdmin.transferOwnership(avatar);

    registryProxy = new TransparentUpgradeableProxy{ salt: keccak256(abi.encodePacked("Registry", env)) }(
      address(registry),
      address(proxyAdmin),
      ""
    );
    reserveProxy = new TransparentUpgradeableProxy{ salt: keccak256(abi.encodePacked("MentoGDReserve", env)) }(
      address(reserve),
      address(proxyAdmin),
      ""
    );

    //Deploy BrokerProxy (using custom proxy pattern)
    brokerProxy = new TransparentUpgradeableProxy{ salt: keccak256(abi.encodePacked("MentoGDBroker", env)) }(
      address(broker),
      address(proxyAdmin),
      "" // No initialization data yet
    );

    // Deploy proxies
    exchangeProviderProxy = new TransparentUpgradeableProxy{
      salt: keccak256(abi.encodePacked("MentoGDExchangeProviderProxy", env))
    }(
      address(exchangeProvider),
      address(proxyAdmin),
      "" // No initialization data yet
    );

    expansionControllerProxy = new TransparentUpgradeableProxy{
      salt: keccak256(abi.encodePacked("MentoGDExpansionControllerProxy", env))
    }(
      address(expansionController),
      address(proxyAdmin),
      "" // No initialization data yet
    );

    // Get proxy-as-implementation contracts for initialization
    GoodDollarExchangeProvider exchangeProviderProxied = GoodDollarExchangeProvider(address(exchangeProviderProxy));
    GoodDollarExpansionController expansionControllerProxied = GoodDollarExpansionController(
      address(expansionControllerProxy)
    );
    Broker brokerProxied = Broker(address(brokerProxy));
    IReserve reserveProxied = IReserve(address(reserveProxy));
    IRegistry registryProxied = IRegistry(address(registryProxy));

    // Initialize contracts
    registryProxied.initialize();
    registryProxied.transferOwnership(avatar);

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

    console.log("initializing reserve...");
    reserveProxied.initialize(
      // 0x000000000000000000000000000000000000ce10, // registry address
      address(registryProxy), // registry address
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

    exchangeProviderProxied.initialize(
      address(brokerProxy),
      address(reserveProxy),
      address(expansionControllerProxy),
      avatar // avatar address
    );

    expansionControllerProxied.initialize(
      address(exchangeProviderProxy),
      address(distHelper), // distributionHelper address
      address(reserveProxy),
      avatar // avatar address
    );

    // Initialize broker with exchange providers and reserves
    address[] memory exchangeProviders = new address[](1);
    exchangeProviders[0] = address(exchangeProviderProxy);

    address[] memory reserves = new address[](1);
    reserves[0] = address(reserveProxy);

    console.log("initializing broker...");
    brokerProxied.initialize(exchangeProviders, reserves);

    // perform setup
    reserveProxied.addToken(goodDollar);
    reserveProxied.addExchangeSpender(address(brokerProxy));
    reserveProxied.addSpender(avatar);
    reserveProxied.addOtherReserveAddress(avatar);

    ITradingLimits.Config memory cusdLimits = ITradingLimits.Config({
      timestep0: 7 days, // Weekly timeframe
      timestep1: 30 days, // Monthly timeframe
      // limit0: 40000, // 40K weekly limit
      // limit1: 80000, // 80K monthly limit
      limit0In: 40000, // 40K weekly limit
      limit0Out: 40000, // 40K weekly limit
      limit1In: 80000, // 80K monthly limit
      limit1Out: 80000, // 80K monthly limit
      limitGlobal: 0, // No global limit
      flags: 0x03 // enable 1+2 binary 011
    });

    // ITradingLimits.Config memory gdLimits = ITradingLimits.Config({
    //   timestep0: 7 days, // Weekly timeframe
    //   timestep1: 30 days, // Monthly timeframe
    //   limit0: -2e9, // 200K weekly limit 200000/0.0001
    //   limit1: -4e9, // 400K monthly limit
    //   limitGlobal: 0, // No global limit
    //   flags: 0x03 // // enable 1+2 binary 011
    // });

    bytes32 exchangeId = keccak256(abi.encodePacked(IERC20(cUSD).symbol(), IERC20(goodDollar).symbol()));
    brokerProxied.configureTradingLimit(exchangeId, cUSD, cusdLimits);
    // brokerProxied.configureTradingLimit(exchangeId, goodDollar, gdLimits);

    brokerProxied.transferOwnership(avatar);
    reserveProxied.transferOwnership(avatar);
    exchangeProviderProxied.transferOwnership(avatar);
    expansionControllerProxied.transferOwnership(avatar);
    vm.stopBroadcast();

    // Log deployed addresses
    console.log("Deployer:", signer);
    console.log("ProxyAdmin deployed to:", address(proxyAdmin));
    console.log("GoodDollarExchangeProvider Proxy deployed to:", address(exchangeProviderProxy));
    console.log("GoodDollarExpansionController Proxy deployed to:", address(expansionControllerProxy));
    console.log("Registry Proxy deployed to:", address(registryProxy));
    console.log("Registry impl deployed to:", address(registry));
    console.log("Reserve Proxy deployed to:", address(reserveProxy));
    console.log("Reserve impl deployed to:", address(reserve));
    console.log("Broker Proxy deployed to:", address(brokerProxy));
  }
}
