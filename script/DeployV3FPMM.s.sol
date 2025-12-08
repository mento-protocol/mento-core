// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { StdCheats } from "forge-std/StdCheats.sol";

// V3 contracts
import { FPMM } from "contracts/swap/FPMM.sol";
import { OneToOneFPMM } from "contracts/swap/OneToOneFPMM.sol";
import { FPMMFactory } from "contracts/swap/FPMMFactory.sol";
import { FactoryRegistry } from "contracts/swap/FactoryRegistry.sol";
import { Router } from "contracts/swap/router/Router.sol";
import { OracleAdapter } from "contracts/oracles/OracleAdapter.sol";
import { ProxyAdmin } from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import { VirtualPoolFactory } from "contracts/swap/virtual/VirtualPoolFactory.sol";

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

    // Live tokens on Celo
    address constant cUSD = 0x765DE816845861e75A25fCA122bb6898B8B1282a;
    address constant USDC = 0xcebA9300f2b948710d2653dD7B07f33A8B32118C; // axlUSDC
    address constant cEUR = 0xD8763CBa276a3738E6DE85b4b3bF5FDed6D6cA73;

    // ============ Deployed Contracts ============
    OracleAdapter public oracleAdapter;
    FPMMFactory public factory;
    FactoryRegistry public factoryRegistry;
    Router public router;
    IFPMM public fpmmPool;
    ProxyAdmin public proxyAdmin;

    // Rate feed ID for the pool
    address public rateFeedId;

    function run() public {
        address deployer = msg.sender;
        console.log("=== V3 FPMM Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast();

        // 1. Deploy OracleAdapter
        _deployOracleAdapter(deployer);

        // 2. Deploy ProxyAdmin
        proxyAdmin = new ProxyAdmin();
        console.log("ProxyAdmin:", address(proxyAdmin));

        // 3. Deploy FPMM implementation (OneToOne for stablecoin pairs)
        address fpmmImpl = address(new OneToOneFPMM(true));
        console.log("FPMM Implementation (OneToOne):", fpmmImpl);

        // 4. Deploy Factory with default params
        IFPMM.FPMMParams memory params = IFPMM.FPMMParams({
            lpFee: 30, // 0.30%
            protocolFee: 0,
            protocolFeeRecipient: deployer,
            rebalanceIncentive: 50, // 0.50%
            rebalanceThresholdAbove: 500, // 5%
            rebalanceThresholdBelow: 500 // 5%
        });

        factory = new FPMMFactory(false);
        factory.initialize(address(oracleAdapter), address(proxyAdmin), deployer, fpmmImpl, params);
        console.log("FPMMFactory:", address(factory));

        // 5. Deploy FactoryRegistry
        factoryRegistry = new FactoryRegistry(false);
        factoryRegistry.initialize(address(factory), deployer);
        console.log("FactoryRegistry:", address(factoryRegistry));

        // 6. Deploy Router
        router = new Router(address(0), address(factoryRegistry), address(factory));
        console.log("Router:", address(router));

        // Deploy 

        // // 7. Deploy FPMM pool (cUSD/USDC - stablecoin pair)
        // rateFeedId = address(uint160(uint256(keccak256("cUSD/USDC"))));
        // fpmmPool = IFPMM(
        //     factory.deployFPMM(
        //         fpmmImpl,
        //         cUSD,
        //         USDC,
        //         rateFeedId,
        //         false // don't invert rate
        //     )
        // );
        console.log("FPMM Pool (cUSD/USDC):", address(fpmmPool));

        vm.stopBroadcast();

        // 8. Provide liquidity (uses cheatcodes - only works on fork)
        _provideLiquidity();

        // Print summary
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
        uint256 cusdAmount = 100_000e18; // 100k cUSD
        uint256 usdcAmount = 100_000e6; // 100k USDC

        console.log("\n=== Providing Liquidity ===");

        // Use deal() to mint tokens directly to the pool
        // This only works on Anvil fork with cheatcodes enabled
        deal(cUSD, address(fpmmPool), cusdAmount);
        deal(USDC, address(fpmmPool), usdcAmount);

        // Mint LP tokens to a test address
        address lpReceiver = makeAddr("lpReceiver");
        vm.prank(lpReceiver);
        fpmmPool.mint(lpReceiver);

        console.log("Liquidity provided:");
        console.log("  cUSD:", cusdAmount / 1e18, "tokens");
        console.log("  USDC:", usdcAmount / 1e6, "tokens");
        console.log("  LP receiver:", lpReceiver);
    }

    function _printSummary() internal view {
        console.log("\n========================================");
        console.log("=== V3 FPMM Deployment Complete ===");
        console.log("========================================");
        console.log("");
        console.log("Contracts:");
        console.log("  Router:          ", address(router));
        console.log("  Factory:         ", address(factory));
        console.log("  FactoryRegistry: ", address(factoryRegistry));
        console.log("  OracleAdapter:   ", address(oracleAdapter));
        console.log("  ProxyAdmin:      ", address(proxyAdmin));
        console.log("");
        console.log("Pool:");
        console.log("  FPMM (cUSD/USDC):", address(fpmmPool));
        console.log("  Token0 (cUSD):   ", cUSD);
        console.log("  Token1 (USDC):   ", USDC);
        console.log("  RateFeedId:      ", rateFeedId);
        console.log("");
        console.log("SDK Usage:");
        console.log("  router.getAmountsOut(amount, routes)");
        console.log("  router.swapExactTokensForTokens(...)");
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
