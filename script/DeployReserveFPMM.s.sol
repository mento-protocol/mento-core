// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { StableTokenV3 } from "contracts/v3/StableTokenV3.sol";
import { FPMMFactory } from "contracts/swap/FPMMFactory.sol";
import { FPMM } from "contracts/swap/FPMM.sol";
import { ProxyAdmin } from "openzeppelin-contracts-v4.9.5/contracts/proxy/transparent/ProxyAdmin.sol";

import { IReserve } from "contracts/interfaces/IReserve.sol";
import { IFPMM } from "contracts/interfaces/IFPMM.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

contract DeployReserveFPMM is Script {
  address public USDC = 0x87D61dA3d668797786D73BC674F053f87111570d;

  address public sortedOracles = 0xFdd8bD58115FfBf04e47411c1d228eCC45E93075;
  address public breakerBox = 0xC76BDf0AFb654888728003683cf748A8B1b4f5fD;
  address public proxyAdmin;
  address public registry = 0x000000000000000000000000000000000000ce10;

  address public cUSDaxlUSDCFPMM;
  address public USDCUSDRateFeedID = 0xA1A8003936862E7a15092A91898D69fa8bCE290c;

  //TODO: LiquidityStrategy
  address public liquidityStrategy = makeAddr("LiquidityStrategy");

  function run() public {
    address reserve;
    uint256 privateKey = vm.envUint("DEPLOYER");
    address deployer = vm.addr(privateKey);

    vm.startBroadcast(privateKey);

    /// Deploy USD.m
    StableTokenV3 USDm = new StableTokenV3(false);

    address[] memory initialBalanceAddresses = new address[](1);
    initialBalanceAddresses[0] = deployer;
    uint256[] memory initialBalanceValues = new uint256[](1);
    initialBalanceValues[0] = 10_000_000e18;

    USDm.initialize("USD.m", "USD.m", initialBalanceAddresses, initialBalanceValues);

    // Deploy Reserve
    reserve = deployReserve();

    // Deploy FPMM implementation
    FPMM fpmmImplementation = new FPMM(true);

    // Deploy Proxy Admin
    ProxyAdmin proxyAdmin = new ProxyAdmin();

    // Deploy FPMM Factory
    FPMMFactory fpmmFactory = new FPMMFactory(false);
    fpmmFactory.initialize(sortedOracles, address(proxyAdmin), breakerBox, deployer, address(fpmmImplementation));

    // Deploy FPMM Proxy mUSD.m/USDC
    address cUSDaxlUSDCFPMM = fpmmFactory.deployFPMM(
      address(fpmmImplementation),
      address(USDm),
      USDC,
      USDCUSDRateFeedID,
      false // revertRateFeed - set to false as default
    );

    //FPMM(cUSDaxlUSDCFPMM).setLiquidityStrategy(liquidityStrategy, true); //TODO: LiquidityStrategy`

    IERC20(USDC).transfer(cUSDaxlUSDCFPMM, 1e12); // 1_000_000 USDC to fpmm for mint call
    USDm.transfer(cUSDaxlUSDCFPMM, 1e24); // 1_000_000 USD.m to fpmm for mint call

    FPMM(cUSDaxlUSDCFPMM).mint(deployer);

    vm.stopBroadcast();
    console.log("cUSDaxlUSDCFPMM", cUSDaxlUSDCFPMM);
    console.log("reserve", reserve);
    console.log("proxyAdmin", address(proxyAdmin));
    console.log("fpmmFactory", address(fpmmFactory));
    console.log("fpmmImplementation", address(fpmmImplementation));
    console.log("liquidityStrategy", liquidityStrategy);
    console.log("USDC", USDC);
    console.log("USDm", address(USDm));
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

    //IReserve(reserve).addExchangeSpender(liquidityStrategy); //TODO: LiquidityStrategy
  }
}
