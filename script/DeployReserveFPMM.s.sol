// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { StableTokenV3 } from "contracts/v3/StableTokenV3.sol";
import { FPMMFactory } from "contracts/swap/FPMMFactory.sol";
import { FPMM } from "contracts/swap/FPMM.sol";
import { ProxyAdmin } from "openzeppelin-contracts-v4.9.5/contracts/proxy/transparent/ProxyAdmin.sol";
// import { ReserveLiquidityStrategy } from "contracts/swap/ReserveLiquidityStrategy.sol";

import { IReserve } from "contracts/interfaces/IReserve.sol";
import { IFPMM } from "contracts/interfaces/IFPMM.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

contract DeployReserveFPMM is Script {
  address public USDC = 0x87D61dA3d668797786D73BC674F053f87111570d;

  address public sortedOracles = 0xFdd8bD58115FfBf04e47411c1d228eCC45E93075;
  address public breakerBox = 0xC76BDf0AFb654888728003683cf748A8B1b4f5fD;
  ProxyAdmin public proxyAdmin;
  address public registry = 0x000000000000000000000000000000000000ce10;

  address public cUSDaxlUSDCFPMM;
  address public USDCUSDRateFeedID = 0xA1A8003936862E7a15092A91898D69fa8bCE290c;

  // ReserveLiquidityStrategy public liquidityStrategy;

  function run() public {
    address reserve;
    uint256 privateKey = vm.envUint("DEPLOYER");
    address deployer = vm.addr(privateKey);

    vm.startBroadcast(privateKey);

    // /// Deploy USD.m
    // StableTokenV3 USDm = new StableTokenV3(false);

    // address[] memory initialBalanceAddresses = new address[](1);
    // initialBalanceAddresses[0] = deployer;
    // uint256[] memory initialBalanceValues = new uint256[](1);
    // initialBalanceValues[0] = 10_000_000e18;

    // USDm.initialize("USD.m", "USD.m", initialBalanceAddresses, initialBalanceValues);
    // liquidityStrategy = new ReserveLiquidityStrategy(false);
    cUSDaxlUSDCFPMM = 0x7DBA083Db8303416D858cbF6282698F90f375Aec;

    // // // Deploy Reserve
    // // reserve = deployReserve();
    // reserve = 0x8ec4B539E7Cbf7c078A037c8Ac26fCD7B2DAd820;

    // // // Deploy FPMM implementation
    // // FPMM fpmmImplementation = new FPMM(true);

    // // // Deploy Proxy Admin
    // // proxyAdmin = new ProxyAdmin();

    // // // Deploy FPMM Factory
    // // FPMMFactory fpmmFactory = new FPMMFactory(false);
    // // fpmmFactory.initialize(sortedOracles, address(proxyAdmin), breakerBox, deployer, address(fpmmImplementation));

    // // // Deploy FPMM Proxy mUSD.m/USDC
    // // cUSDaxlUSDCFPMM = fpmmFactory.deployFPMM(address(fpmmImplementation), address(USDm), USDC, USDCUSDRateFeedID);

    // // Deploy Liquidity Strategy
    // liquidityStrategy.initialize(reserve);

    // // Add pool to liquidity strategy
    // // conservative rebalance incentive until we fixed the precision errors

    // // USDm.initializeV2(address(liquidityStrategy), address(deployer));

    // FPMM(cUSDaxlUSDCFPMM).setLiquidityStrategy(address(liquidityStrategy), true);
    // FPMM(cUSDaxlUSDCFPMM).setLiquidityStrategy(0x2EDFdC56DdF9e048f8BA9E337aa1dFFB0A1d03F8, false);

    // IReserve(reserve).removeExchangeSpender(0x2EDFdC56DdF9e048f8BA9E337aa1dFFB0A1d03F8, 0);
    // IReserve(reserve).addExchangeSpender(address(liquidityStrategy));

    // StableTokenV3(0x9E2d4412d0f434cC85500b79447d9323a7416f09).setBroker(address(liquidityStrategy));

    // liquidityStrategy.addPool(cUSDaxlUSDCFPMM, 600, 25);

    // IERC20(0x9E2d4412d0f434cC85500b79447d9323a7416f09).transfer(cUSDaxlUSDCFPMM, 10000e18); // 1_000_000 USDC to fpmm for mint call
    // uint256 amountOut = FPMM(cUSDaxlUSDCFPMM).getAmountOut(10000e18, 0x9E2d4412d0f434cC85500b79447d9323a7416f09);
    // FPMM(cUSDaxlUSDCFPMM).swap(0, 1, deployer, "");

    IERC20(USDC).transfer(cUSDaxlUSDCFPMM, 10000e6); // 1_000_000 USDC to fpmm for mint call
    uint256 amountOut = FPMM(cUSDaxlUSDCFPMM).getAmountOut(10000e6, USDC);
    FPMM(cUSDaxlUSDCFPMM).swap(amountOut, 0, deployer, "");

    //liquidityStrategy.rebalance(cUSDaxlUSDCFPMM);
    //USDm.transfer(cUSDaxlUSDCFPMM, 1e24); // 1_000_000 USD.m to fpmm for mint call

    //FPMM(cUSDaxlUSDCFPMM).mint(deployer);

    vm.stopBroadcast();
    // console.log("cUSDaxlUSDCFPMM", cUSDaxlUSDCFPMM);
    // console.log("reserve", reserve);
    // console.log("proxyAdmin", address(proxyAdmin));
    // console.log("fpmmFactory", address(fpmmFactory));
    // console.log("fpmmImplementation", address(fpmmImplementation));
    // console.log("liquidityStrategy", address(liquidityStrategy));
    // console.log("USDC", USDC);
    // console.log("USDm", address(USDm));
  }

  function deployReserve() public returns (address reserve) {
    // Deploy reserve through assembly create because of old solidity version
    string memory reservePath = string(abi.encodePacked("out/Reserve.sol/Reserve.json"));
    bytes memory reserveBytecode = abi.encodePacked(vm.getCode(reservePath), abi.encode(true));

    assembly {
      reserve := create(0, add(reserveBytecode, 0x20), mload(reserveBytecode))
    }

    bytes32[] memory initialAssetAllocationSymbols = new bytes32[](2);
    initialAssetAllocationSymbols[0] = bytes32("cGLD");
    initialAssetAllocationSymbols[1] = bytes32("USDC");

    uint256[] memory initialAssetAllocationWeights = new uint256[](2);
    initialAssetAllocationWeights[0] = 5e23;
    initialAssetAllocationWeights[1] = 5e23;

    address[] memory collateralAssets = new address[](1);
    collateralAssets[0] = USDC;

    uint256[] memory collateralAssetDailySpendingRatios = new uint256[](1);
    collateralAssetDailySpendingRatios[0] = 1e24;

    IReserve(reserve).initialize(
      registry,
      600, // deprecated
      1000000000000000000000000, // spending ratio celo not used
      0,
      0,
      initialAssetAllocationSymbols,
      initialAssetAllocationWeights,
      0,
      0,
      collateralAssets,
      collateralAssetDailySpendingRatios
    );

    IERC20(USDC).transfer(reserve, 1e13); // 10_000_000 USDC to reserve for reserve setup

    IReserve(reserve).addExchangeSpender(address(0));
  }
}
