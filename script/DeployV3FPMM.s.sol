// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

// V3 contracts
import { FPMM } from "contracts/swap/FPMM.sol";
import { FPMMFactory } from "contracts/swap/FPMMFactory.sol";
import { FactoryRegistry } from "contracts/swap/FactoryRegistry.sol";
import { Router } from "contracts/swap/router/Router.sol";
import { OracleAdapter } from "contracts/oracles/OracleAdapter.sol";
import { VirtualPoolFactory } from "contracts/swap/virtual/VirtualPoolFactory.sol";
import { OneToOneFPMM } from "contracts/swap/OneToOneFPMM.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";

// Interfaces
import { IFPMM } from "contracts/interfaces/IFPMM.sol";
import { IStableTokenV2 } from "contracts/interfaces/IStableTokenV2.sol";

// OpenZeppelin
import { ProxyAdmin } from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

// Breakers
import { MarketHoursBreaker } from "contracts/oracles/breakers/MarketHoursBreaker.sol";

/**
 * Usage:
 *   # Start Anvil fork
 *   anvil --fork-url $CELO_RPC_URL --chain-id 42220
 *
 *   # Run deployment
 *   forge script script/DeployV3FPMM.s.sol:DeployV3FPMM \
 *     --rpc-url http://localhost:8545 \
 *     --broadcast
 */
contract DeployV3FPMM is Script {
  // ============ Celo Mainnet Addresses ============//
  address constant SORTED_ORACLES = 0xefB84935239dAcdecF7c5bA76d8dE40b077B7b33;
  address constant BREAKER_BOX = 0x303ED1df62Fa067659B586EbEe8De0EcE824Ab39;
  address constant BIPOOL_MANAGER = 0x22d9db95E6Ae61c104A7B6F6C78D7993B94ec901;
  address constant L2_UPTIME_FEED = 0x4CD491Dc27C8B0BbD10D516A502856B786939d18;

  // Live tokens on Celo
  address constant cUSD = 0x765DE816845861e75A25fCA122bb6898B8B1282a;
  address constant cKES = 0x456a3D042C0DbD3db53D5489e98dFb038553B0d0;
  address constant USDC = 0xcebA9300f2b948710d2653dD7B07f33A8B32118C;
  address constant cEUR = 0xD8763CBa276a3738E6DE85b4b3bF5FDed6D6cA73;
  address constant cGHS = 0xfAeA5F3404bbA20D3cc2f8C4B0A888F55a3c7313;

  address constant CELO = 0x471EcE3750Da237f93B8E339c536989b8978a438;

  // Mock tokens
  address usdmMock;
  address eurmMock;
  address kesmMock;

  address constant DEPLOYER = 0x287810F677516f10993ff63a520aAD5509F35796;

  // ============ Deployed Contracts ============
  OracleAdapter public oracleAdapter;
  ProxyAdmin public proxyAdmin;
  FPMMFactory public fpmmFactory;
  FactoryRegistry public factoryRegistry;
  Router public router;
  IFPMM public fpmmPool;
  address public virtualPool;

  // Rate feed ID for the KESm/USDm FPMM Pool
  address public kesUsdRateFeedId = 0xbAcEE37d31b9f022Ef5d232B9fD53F05a531c169;

  function run() public {
    address deployer = msg.sender;
    console.log("=== V3 Deployment ===");
    console.log("Deployer:", deployer);
    console.log("Chain ID:", block.chainid);
    vm.startBroadcast(DEPLOYER);

    // Label tokens
    vm.label(cUSD, "cUSD");
    vm.label(cKES, "cKES");
    vm.label(USDC, "USDC");
    vm.label(cEUR, "cEUR");
    vm.label(cGHS, "cGHS");

    // Deploy OracleAdapter
    _deployOracleAdapter(deployer);

    // Deploy FPMM
    address fpmmImpl = address(new FPMM(true));
    vm.label(address(fpmmImpl), "FPMM Implementation");
    console.log("FPMM Implementation:", fpmmImpl);

    address oneToOneFpmmImpl = address(new OneToOneFPMM(true));
    vm.label(address(oneToOneFpmmImpl), "OneToOneFPMM Implementation");
    console.log("OneToOneFPMM Implementation:", oneToOneFpmmImpl);

    IFPMM.FPMMParams memory params = IFPMM.FPMMParams({
      lpFee: 30,
      protocolFee: 0,
      protocolFeeRecipient: deployer,
      feeSetter: address(0),
      rebalanceIncentive: 50,
      rebalanceThresholdAbove: 500,
      rebalanceThresholdBelow: 500
    });

    // Deploy ProxyAdmin
    proxyAdmin = new ProxyAdmin();
    proxyAdmin.transferOwnership(deployer);
    vm.label(address(proxyAdmin), "ProxyAdmin");
    console.log("ProxyAdmin:", address(proxyAdmin));

    fpmmFactory = new FPMMFactory(false);
    vm.label(address(fpmmFactory), "FPMMFactory");
    fpmmFactory.initialize(address(oracleAdapter), address(proxyAdmin), deployer, fpmmImpl, params);
    console.log("FPMMFactory:", address(fpmmFactory));

    // Deploy VirtualPoolFactory
    VirtualPoolFactory virtualPoolFactory = new VirtualPoolFactory(deployer);
    vm.label(address(virtualPoolFactory), "VirtualPoolFactory");
    console.log("VirtualPoolFactory:", address(virtualPoolFactory));

    // Deploy FactoryRegistry
    factoryRegistry = new FactoryRegistry(false);
    vm.label(address(factoryRegistry), "Factory Registry");
    factoryRegistry.initialize(address(fpmmFactory), deployer);
    console.log("FactoryRegistry:", address(factoryRegistry));

    // Approve the virtual pool factory with the factory registry
    vm.stopBroadcast();
    vm.startBroadcast(msg.sender);
    factoryRegistry.approve(address(virtualPoolFactory));
    vm.stopBroadcast();
    vm.startBroadcast(deployer);

    // Deploy OneToOneFPMM & register it with the factory
    fpmmFactory.registerFPMMImplementation(oneToOneFpmmImpl);

    // Deploy FPMM pool
    fpmmPool = IFPMM(fpmmFactory.deployFPMM(fpmmImpl, cUSD, cKES, kesUsdRateFeedId, false));
    vm.label(address(fpmmPool), "FPMM Pool");
    console.log("FPMM Pool:", address(fpmmPool));

    // Deploy Router
    router = new Router(address(0), address(factoryRegistry), address(fpmmFactory));
    vm.label(address(router), "Router");
    console.log("Router:", address(router));

    // Deploy VirtualPool with connected route cUSD/cGHS
    address precomputedAddress = virtualPoolFactory.getOrPrecomputeProxyAddress(cUSD, cGHS);
    vm.label(precomputedAddress, "VirtualPool");
    console.log("VirtualPool:", precomputedAddress);
    bytes32 exchangeId = 0x3562f9d29eba092b857480a82b03375839c752346b9ebe93a57ab82410328187;
    virtualPool = virtualPoolFactory.deployVirtualPool(BIPOOL_MANAGER, exchangeId);

    vm.stopBroadcast();

    _printSummary();
  }

  function _deployOracleAdapter(address governance) internal {
    // Deploy MarketHoursBreaker (needed for OracleAdapter)
    MarketHoursBreaker marketHoursBreaker = new MarketHoursBreaker();
    console.log("MarketHoursBreaker:", address(marketHoursBreaker));

    // Deploy OracleAdapter using existing Celo SortedOracles and BreakerBox
    oracleAdapter = new OracleAdapter(false);
    oracleAdapter.initialize(
      SORTED_ORACLES, // Use existing Celo SortedOracles
      BREAKER_BOX, // Use existing Celo BreakerBox
      address(marketHoursBreaker),
      governance,
      L2_UPTIME_FEED
    );
    console.log("OracleAdapter:", address(oracleAdapter));
  }

  function _printSummary() internal view {
    console.log("\n========================================");
    console.log("=== V3 FPMM Deployment Complete ===");
    console.log("========================================");
    console.log("");
    console.log("Contracts:");
    console.log("  Router:          ", address(router));
    console.log("  FPMM Factory:    ", address(fpmmFactory));
    console.log("  FactoryRegistry: ", address(factoryRegistry));
    console.log("  OracleAdapter:   ", address(oracleAdapter));
    console.log("  ProxyAdmin:      ", address(proxyAdmin));
    console.log("");
    console.log("Pools:");
    console.log("  FPMM (cUSD/cKES):       ", address(fpmmPool));
    console.log("  VirtualPool (cUSD/cGHS):", virtualPool);
    console.log("");
    console.log("FPMM Pool Details:");
    console.log("  Token0:     ", fpmmPool.token0());
    console.log("  Token1:     ", fpmmPool.token1());
    console.log("  RateFeedId: ", kesUsdRateFeedId);
    console.log("");
  }
}
