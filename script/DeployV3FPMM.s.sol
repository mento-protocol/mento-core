// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

// V3 contracts
import { FPMM } from "contracts/swap/FPMM.sol";
import { FPMMFactory } from "contracts/swap/FPMMFactory.sol";
import { FactoryRegistry } from "contracts/swap/FactoryRegistry.sol";
import { Router } from "contracts/swap/router/Router.sol";
import { OracleAdapter } from "contracts/oracles/OracleAdapter.sol";
import { ProxyAdmin } from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import { VirtualPoolFactory } from "contracts/swap/virtual/VirtualPoolFactory.sol";
import { OneToOneFPMM } from "contracts/swap/OneToOneFPMM.sol";

// Interfaces
import { IRouter } from "contracts/swap/router/interfaces/IRouter.sol";
import { IFPMM } from "contracts/interfaces/IFPMM.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";
import { IBreakerBox } from "contracts/interfaces/IBreakerBox.sol";
import { IMarketHoursBreaker } from "contracts/interfaces/IMarketHoursBreaker.sol";

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
contract DeployV3FPMM is Script, Test {
  // ============ Celo Mainnet Addresses ============//
  address constant SORTED_ORACLES = 0xefB84935239dAcdecF7c5bA76d8dE40b077B7b33;
  address constant BREAKER_BOX = 0x303ED1Bcb229CC7e9Fc998994aaD34B8FfE0D69b;
  address constant BIPOOL_MANAGER = 0x22d9db95E6Ae61c104A7B6F6C78D7993B94ec901;

  // Live tokens on Celo
  address constant cUSD = 0x765DE816845861e75A25fCA122bb6898B8B1282a;
  address constant cKES = 0x456a3D042C0DbD3db53D5489e98dFb038553B0d0;
  address constant USDC = 0xcebA9300f2b948710d2653dD7B07f33A8B32118C;
  address constant cEUR = 0xD8763CBa276a3738E6DE85b4b3bF5FDed6D6cA73;
  address constant cGHS = 0xfAeA5F3404bbA20D3cc2f8C4B0A888F55a3c7313;

  address constant DEPLOYER = 0x56fD3F2bEE130e9867942D0F463a16fBE49B8d81;

  // ============ Deployed Contracts ============
  OracleAdapter public oracleAdapter;
  FPMMFactory public fpmmFactory;
  FactoryRegistry public factoryRegistry;
  Router public router;
  IFPMM public fpmmPool;
  ProxyAdmin public proxyAdmin;
  address public virtualPool;

  // Rate feed ID for the pool
  address public rateFeedId = 0xA1A8003936862E7a15092A91898D69fa8bCE290c;

  function run() public {
    address deployer = msg.sender;
    console.log("=== V3 Deployment ===");
    console.log("Deployer:", deployer);
    console.log("Chain ID:", block.chainid);

    vm.startBroadcast();

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
      rebalanceIncentive: 50,
      rebalanceThresholdAbove: 500,
      rebalanceThresholdBelow: 500
    });

    fpmmFactory = new FPMMFactory(false);
    vm.label(address(fpmmFactory), "FPMMFactory");
    fpmmFactory.initialize(address(oracleAdapter), deployer, deployer, fpmmImpl, params);
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
    factoryRegistry.approve(address(virtualPoolFactory));

    // Deploy OneToOneFPMM & register it with the factory
    fpmmFactory.registerFPMMImplementation(oneToOneFpmmImpl);

    // Deploy FPMM pool
    fpmmPool = IFPMM(fpmmFactory.deployFPMM(fpmmImpl, cUSD, cKES, rateFeedId, false));
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
    bytes32 exchangeId = keccak256(abi.encodePacked(IERC20(cUSD).symbol(), IERC20(cGHS).symbol(), "ConstantSum"));
    virtualPool = virtualPoolFactory.deployVirtualPool(BIPOOL_MANAGER, exchangeId);

    _donate();

    vm.stopBroadcast();

    // Provide liquidity
    vm.startBroadcast();
    _provideLiquidity();
    vm.stopBroadcast();

    // Print summary
    _printSummary();
  }

  function _donate() internal {
    uint256 cusdAmount = 1_000_000e18;
    uint256 ckesAmount = 1_000_000e18;

    console.log("\n=== Donation ===");

    uint256 cusdBalanceBefore = IERC20(cUSD).balanceOf(msg.sender);
    uint256 ckesBalanceBefore = IERC20(cKES).balanceOf(msg.sender);
    console.log("cUSD Balance Before:", cusdBalanceBefore);
    console.log("cKES Balance Before:", ckesBalanceBefore);

    // Give 1 mil each to the deployer
    deal(cUSD, msg.sender, cusdAmount);
    deal(cKES, msg.sender, ckesAmount);

    uint256 cusdBalanceAfter = IERC20(cUSD).balanceOf(msg.sender);
    uint256 ckesBalanceAfter = IERC20(cKES).balanceOf(msg.sender);
    console.log("cUSD Balance After:", cusdBalanceAfter);
    console.log("cKES Balance After:", ckesBalanceAfter);

    // Approve the router to spend max tokens
    IERC20(cUSD).approve(address(router), type(uint256).max);
    IERC20(cKES).approve(address(router), type(uint256).max);
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
      governance
    );
    console.log("OracleAdapter:", address(oracleAdapter));
  }

  function _provideLiquidity() internal {

    console.log("\n=== Providing Liquidity ===");
    uint256 cusdAmount = 1_000_000e18;
    uint256 ckesAmount = 1_000_000e18;

    // Add liquidity
    (uint256 amount0, uint256 amount1, uint256 liquidity) = router.addLiquidity(
      cUSD,
      cKES,
      100000,
      100000,
      0, // amountAMin
      0, // amountBMin
      msg.sender,
      block.timestamp
    );

    console.log("Liquidity provided:");
    console.log("  cUSD:", cusdAmount / 1e18, "tokens");
    console.log("  cKES:", ckesAmount / 1e18, "tokens");
    console.log("  LP receiver:", msg.sender);
  }

  function _printSummary() internal view {
    console.log("\n========================================");
    console.log("=== V3 FPMM Deployment Complete ===");
    console.log("========================================");
    console.log("");
    console.log("Contracts:");
    console.log("  Router:          ", address(router));
    console.log("  FPMM Factory:         ", address(fpmmFactory));
    console.log("  FactoryRegistry: ", address(factoryRegistry));
    console.log("  OracleAdapter:   ", address(oracleAdapter));
    console.log("  ProxyAdmin:      ", address(proxyAdmin));
    console.log("");
    console.log("Pool:");
    console.log("  FPMM (cUSD/USDC):", address(fpmmPool));
    console.log("  VirtualPool (cUSD/cEUR):", virtualPool);
    console.log("  Token0 (cUSD):          ", cUSD);
    console.log("  Token1 (cEUR):          ", cEUR);
    console.log("  RateFeedId:             ", rateFeedId);
    console.log("");
  }
}

/**
 * @title DeployV3FPMMWithTokens
 * @notice Alternative deployment that also deploys mock tokens (for fully isolated testing)
 */
contract DeployV3FPMMWithMockTokens is Script {
  function run() public {
    // For cases where you want to deploy fresh mock tokens
    // instead of using live Celo tokens
    revert("Not implemented - use DeployV3FPMM for fork testing");
  }
}
