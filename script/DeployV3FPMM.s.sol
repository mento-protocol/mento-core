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
  address constant BREAKER_BOX = 0x303ED1Bcb229CC7e9Fc998994aaD34B8FfE0D69b;
  address constant BIPOOL_MANAGER = 0x22d9db95E6Ae61c104A7B6F6C78D7993B94ec901;

  // Live tokens on Celo
  address constant cUSD = 0x765DE816845861e75A25fCA122bb6898B8B1282a;
  address constant cKES = 0x456a3D042C0DbD3db53D5489e98dFb038553B0d0;
  address constant USDC = 0xcebA9300f2b948710d2653dD7B07f33A8B32118C;
  address constant cEUR = 0xD8763CBa276a3738E6DE85b4b3bF5FDed6D6cA73;
  address constant cGHS = 0xfAeA5F3404bbA20D3cc2f8C4B0A888F55a3c7313;

  // Mock tokens
  address usdmMock;
  address eurmMock;
  address kesmMock;

  address constant DEPLOYER = 0x56fD3F2bEE130e9867942D0F463a16fBE49B8d81;

  // ============ Deployed Contracts ============
  OracleAdapter public oracleAdapter;
  ProxyAdmin public proxyAdmin;
  FPMMFactory public fpmmFactory;
  FactoryRegistry public factoryRegistry;
  Router public router;
  IFPMM public fpmmPool;
  address public virtualPool;

  // Rate feed ID for the pool
  address public rateFeedId = 0xA1A8003936862E7a15092A91898D69fa8bCE290c;

  function run() public {
    address deployer = msg.sender;
    console.log("=== V3 Deployment ===");
    console.log("Deployer:", deployer);
    console.log("Chain ID:", block.chainid);
    vm.startBroadcast(DEPLOYER);

    // Deploy Mock tokens
    // usdmMock = address(new MockERC20("Mock USDm", "MOCK_USDm", 18));
    // eurmMock = address(new MockERC20("Mock EURm", "MOCK_EURm", 18));
    // kesmMock = address(new MockERC20("Mock KESm", "MOCK_KESm", 18));
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

    // Mint tokens by pranking as the broker (who has mint permission)
    // _mintCeloToken(cUSD, msg.sender, 1_000_000e18);
    // _mintCeloToken(cKES, msg.sender, 1_000_000e18);

    vm.stopBroadcast();

    _mintCeloToken(cUSD, DEPLOYER, 1_000_000e18);
    _mintCeloToken(cKES, DEPLOYER, 1_000_000e18);

    // Provide initial liquidity using direct transfer + mint pattern
    _provideLiquidity();

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
      governance
    );
    console.log("OracleAdapter:", address(oracleAdapter));
  }

  function _provideLiquidity() internal {
    console.log("\n=== Deployer Balance Before Transfer ===");
    console.log("cUSD Balance:", IERC20(cUSD).balanceOf(DEPLOYER) / 1e18);
    console.log("cKES Balance:", IERC20(cKES).balanceOf(DEPLOYER) / 1e18);
    console.log("=========================");

    console.log("\n=== Pool Balance Before Transfer ===");
    console.log("cUSD Before:", IERC20(cUSD).balanceOf(address(fpmmPool)) / 1e18);
    console.log("cKES Before:", IERC20(cKES).balanceOf(address(fpmmPool)) / 1e18);
    console.log("=========================");

    // Mint tokens directly to the pool
    vm.startBroadcast(DEPLOYER);
    IERC20(cUSD).transfer(address(fpmmPool), 200_000 ether);
    IERC20(cKES).transfer(address(fpmmPool), 200_000 ether);

    console.log("\n=== Deployer Balance After Transfer ===");
    console.log("cUSD Balance:", IERC20(cUSD).balanceOf(DEPLOYER) / 1e18);
    console.log("cKES Balance:", IERC20(cKES).balanceOf(DEPLOYER) / 1e18);
    console.log("=========================");

    console.log("\n=== Pool Balance After Transfer ===");
    console.log("cUSD After:", IERC20(cUSD).balanceOf(address(fpmmPool)) / 1e18);
    console.log("cKES After:", IERC20(cKES).balanceOf(address(fpmmPool)) / 1e18);
    console.log("\n=========================");

    console.log("\n=== Pool Reserves Before Mint ===");
    console.log("cUSD Before:", fpmmPool.reserve0() / 1e18);
    console.log("cKES Before:", fpmmPool.reserve1() / 1e18);
    console.log("\n=========================");

    // Mint LP tokens
    uint256 liquidity = fpmmPool.mint(DEPLOYER);
    vm.stopBroadcast();

    console.log("\n=== Deployer Balance After Mint ===");
    console.log("cUSD Balance:", IERC20(cUSD).balanceOf(DEPLOYER) / 1e18);
    console.log("cKES Balance:", IERC20(cKES).balanceOf(DEPLOYER) / 1e18);
    console.log("=========================");

    console.log("\n=== Pool Balance After Mint ===");
    console.log("cUSD After:", IERC20(cUSD).balanceOf(address(fpmmPool)) / 1e18);
    console.log("Liquidity provided:");
    console.log("  cUSD:", 200_000 ether / 1e18, "tokens");
    console.log("  cKES:", 200_000 ether / 1e18, "tokens");
    console.log("  LP tokens minted:", liquidity / 1e18);
    console.log("  LP receiver:", DEPLOYER);
  }

  /// @dev Mints Celo stablecoins by pranking as the broker
  function _mintCeloToken(address token, address to, uint256 amount) internal {
    address tokenBroker = IStableTokenV2(token).broker();

    vm.startPrank(tokenBroker);
    IStableTokenV2(token).mint(to, amount);
    vm.stopPrank();
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
    console.log("  RateFeedId: ", rateFeedId);
    console.log("");
  }

  function mintTest() public {
    vm.startBroadcast();
    console.log("=== Mint Test ===");

    uint256 cusdAmount = 1000e18;
    uint256 ckesAmount = 1000e18;

    console.log("\n=== Balances Before Mint ===");
    uint256 cusdBefore = IERC20(cUSD).balanceOf(msg.sender);
    uint256 ckesBefore = IERC20(cKES).balanceOf(msg.sender);

    console.log("cUSD Before:", cusdBefore / 1e18);
    console.log("cKES Before:", ckesBefore / 1e18);
    console.log("\n=========================");

    // Mint tokens by pranking as the broker
    _mintCeloToken(cUSD, msg.sender, cusdAmount);
    _mintCeloToken(cKES, msg.sender, ckesAmount);

    console.log("\n=== Balances After Mint ===");
    console.log("cUSD After:", IERC20(cUSD).balanceOf(msg.sender) / 1e18);
    console.log("cKES After:", IERC20(cKES).balanceOf(msg.sender) / 1e18);
    console.log("\n=========================");

    vm.stopBroadcast();
  }
}
