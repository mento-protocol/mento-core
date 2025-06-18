pragma solidity ^0.8.24;

import { IERC20Metadata } from "openzeppelin-contracts-v4.9.5/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IBorrowerOperations } from "../contracts/v3/Interfaces/IBorrowerOperations.sol";
import { IBoldToken } from "../contracts/v3/Interfaces/IBoldToken.sol";
import { IAddressesRegistry } from "../contracts/v3/Interfaces/IAddressesRegistry.sol";
import { ITroveManager } from "../contracts/v3/Interfaces/ITroveManager.sol";
import { ICollateralRegistry } from "../contracts/v3/Interfaces/ICollateralRegistry.sol";
import { IStabilityPool } from "../contracts/v3/Interfaces/IStabilityPool.sol";
import { IActivePool } from "../contracts/v3/Interfaces/IActivePool.sol";

import { StdCheats } from "forge-std/StdCheats.sol";
import { Vm } from "forge-std/Vm.sol";
import { console2 } from "forge-std/console2.sol";
import { Script } from "forge-std/Script.sol";

interface IPriceFeed {
  function setPrice(uint256 _price) external;
  function getPrice() external view returns (uint256);
}

contract Demo is StdCheats, Script {
  // -------- Configuration --------
  address public registry = 0x6f10cc394F0FC8ef2A8B58e02E9cAF90C2f0922f;
  uint256 public troveId;

  //--------------------------------

  IBorrowerOperations public borrowerOperations;
  IBoldToken public boldToken;
  IERC20Metadata public cUSD;
  address public deployer;
  address public user;
  IAddressesRegistry public addressRegistry;
  IPriceFeed public priceFeed;
  ITroveManager public troveManager;
  ICollateralRegistry public collateralRegistry;
  IStabilityPool public stabilityPool;
  IActivePool public activePool;

  uint256 counter;

  function run() public {
    setup();

    uint256 privateKey1 = vm.envUint("DEPLOYER");
    deployer = vm.addr(privateKey1);
    uint256 privateKey2 = vm.envUint("USER");
    user = vm.addr(privateKey2);

    vm.startBroadcast(privateKey1);

    openTroveIfNeeded();
    sendBoldTokenIfNeeded();

    vm.stopBroadcast();

    vm.startBroadcast(privateKey2);
    redeemCollateral();
    vm.stopBroadcast();

    vm.startBroadcast(privateKey1);

    closeTroveIfExists();
    openTroveIfNeeded();

    vm.stopBroadcast();

    vm.startBroadcast(privateKey2);

    liquidateTroveIfPossible();
    updatePriceFeed(100e18);
    liquidateTroveIfPossible();
    updatePriceFeed(200e18);

    vm.stopBroadcast();
  }

  function setup() internal {
    addressRegistry = IAddressesRegistry(registry);
    borrowerOperations = IBorrowerOperations(addressRegistry.borrowerOperations());
    boldToken = IBoldToken(addressRegistry.boldToken());
    cUSD = IERC20Metadata(address(addressRegistry.collToken()));
    priceFeed = IPriceFeed(address(addressRegistry.priceFeed()));
    troveManager = ITroveManager(addressRegistry.troveManager());
    collateralRegistry = ICollateralRegistry(addressRegistry.collateralRegistry());
    stabilityPool = IStabilityPool(addressRegistry.stabilityPool());
    activePool = IActivePool(addressRegistry.activePool());
    console2.log("--------------------------------");
    console2.log("addressRegistry:", address(addressRegistry));
    console2.log("borrowerOperations:", address(borrowerOperations));
    console2.log("cEUR:", address(boldToken));
    console2.log("cUSD:", address(cUSD));
    console2.log("priceFeed:", address(priceFeed));
    console2.log("troveManager:", address(troveManager));
    console2.log("collateralRegistry:", address(collateralRegistry));
    console2.log("stabilityPool:", address(stabilityPool));
    console2.log("activePool:", address(activePool));
    console2.log("--------------------------------");
  }

  function approveIfNeeded(address token, address spender) internal {
    uint256 allowance = IERC20Metadata(token).allowance(address(deployer), spender);
    if (allowance != type(uint256).max) {
      IERC20Metadata(token).approve(spender, type(uint256).max);
    }
  }

  function openTroveIfNeeded() internal {
    if (troveId != 0) {
      return;
    }
    approveIfNeeded(address(cUSD), address(borrowerOperations));
    console2.log("--------------------------------");
    console2.log("Opening trove...");
    uint256 cUSDBalanceBefore = cUSD.balanceOf(deployer);
    uint256 boldTokenBalanceBefore = boldToken.balanceOf(deployer);
    console2.log("cUSD balance before opening trove:", cUSDBalanceBefore);
    console2.log("cKES balance before opening trove:", boldTokenBalanceBefore);
    // get timestamp
    uint256 timestamp = block.timestamp;
    troveId = borrowerOperations.openTrove(
      deployer,
      timestamp + counter, // use timestamp as ownerIndex
      150e18, // MCR 110%
      20000e18, // MIN_DEBT 2000e18
      0,
      0,
      1e17,
      type(uint256).max,
      address(0),
      address(0),
      address(0)
    );
    counter++;
    console2.log("Trove opened successfully");
    console2.log("troveId:", troveId);
    console2.log("cUSD balance after opening trove:", cUSD.balanceOf(deployer));
    console2.log("cKES balance after opening trove:", boldToken.balanceOf(deployer));
    (uint256 value, uint256 decimals) = formatWithTwoDecimals(cUSDBalanceBefore - cUSD.balanceOf(deployer));
    console2.log("cUSD deposit:", value, ".", decimals);
    (value, decimals) = formatWithTwoDecimals(boldToken.balanceOf(deployer) - boldTokenBalanceBefore);
    console2.log("cKES minted:", value, ".", decimals);
    console2.log("--------------------------------");
  }

  function sendBoldTokenIfNeeded() internal {
    if (boldToken.balanceOf(user) < 100e18) {
      boldToken.transfer(user, 100e18);
    }
  }

  function redeemCollateral() internal {
    approveIfNeeded(address(boldToken), address(collateralRegistry));
    uint256 boldTokenBalanceBefore = boldToken.balanceOf(user);
    uint256 cUSDBalanceBefore = cUSD.balanceOf(user);
    console2.log("--------------------------------");
    console2.log("Redeeming collateral...");
    console2.log("cKES balance before redeeming collateral:", boldTokenBalanceBefore);
    console2.log("cUSD balance before redeeming collateral:", cUSDBalanceBefore);

    collateralRegistry.redeemCollateral(100e18, 20, 1e18);

    console2.log("cKES balance after redeeming collateral:", boldToken.balanceOf(user));
    console2.log("cUSD balance after redeeming collateral:", cUSD.balanceOf(user));
    (uint256 value, uint256 decimals) = formatWithTwoDecimals(boldTokenBalanceBefore - boldToken.balanceOf(user));
    console2.log("cKES burned:", value, ".", decimals);
    (value, decimals) = formatWithTwoDecimals(cUSD.balanceOf(user) - cUSDBalanceBefore);
    console2.log("cUSD redeemed:", value, ".", decimals);
    console2.log("--------------------------------");
  }

  function closeTroveIfExists() internal {
    if (troveId == 0) {
      return;
    }
    approveIfNeeded(address(boldToken), address(borrowerOperations));
    console2.log("--------------------------------");
    console2.log("Closing trove...");
    uint256 cUSDBalanceBefore = cUSD.balanceOf(deployer);
    uint256 boldTokenBalanceBefore = boldToken.balanceOf(deployer);
    console2.log("cUSD balance before closing trove:", cUSDBalanceBefore);
    console2.log("cKES balance before closing trove:", boldTokenBalanceBefore);
    borrowerOperations.closeTrove(troveId);
    troveId = 0;
    console2.log("cUSD balance after closing trove:", cUSD.balanceOf(deployer));
    console2.log("cKES balance after closing trove:", boldToken.balanceOf(deployer));
    (uint256 value, uint256 decimals) = formatWithTwoDecimals(cUSD.balanceOf(deployer) - cUSDBalanceBefore);
    console2.log("cUSD regained:", value, ".", decimals);
    (value, decimals) = formatWithTwoDecimals(boldTokenBalanceBefore - boldToken.balanceOf(deployer));
    console2.log("cKES repaid:", value, ".", decimals);
    console2.log("--------------------------------");
  }

  function liquidateTroveIfPossible() internal {
    if (troveId == 0) {
      return;
    }
    console2.log("--------------------------------");
    console2.log("Liquidating trove...");
    uint256 currentPrice = priceFeed.getPrice();
    console2.log("Current price:", currentPrice);
    uint256 currentICR = troveManager.getCurrentICR(troveId, currentPrice);
    uint256 crPercent = (currentICR * 100) / 1e18;
    console2.log("Current CR: %s%%", crPercent);

    if (currentICR < 11e17) {
      console2.log("Current CR is less than MCR, liquidating trove...");

      uint256 cUSDBalanceBefore = cUSD.balanceOf(user);
      console2.log("cUSD balance before liquidation:", cUSDBalanceBefore);

      uint256[] memory troveIds = new uint256[](1);
      troveIds[0] = troveId;
      troveManager.batchLiquidateTroves(troveIds);
      console2.log("cUSD balance after liquidation:", cUSD.balanceOf(user));
      (uint256 value, uint256 decimals) = formatWithTwoDecimals(cUSD.balanceOf(user) - cUSDBalanceBefore);
      console2.log("cUSD reward for liquidation:", value, ".", decimals);

      if (troveManager.getTroveStatus(troveId) == ITroveManager.Status.closedByLiquidation) {
        console2.log("Trove is closed by liquidation");
      }
    } else {
      console2.log("Current CR is greater than MCR, can not liquidate trove");
    }
    console2.log("--------------------------------");
  }

  function updatePriceFeed(uint256 _price) internal {
    console2.log("--------------------------------");
    console2.log("Updating price feed...");
    priceFeed.setPrice(_price);
    uint256 currentPrice = priceFeed.getPrice();
    console2.log("Updated price:", currentPrice);
    console2.log("Price feed updated successfully");
    console2.log("--------------------------------");
  }

  function formatWithTwoDecimals(uint256 value) internal pure returns (uint256, uint256) {
    value = value / 1e16;
    uint256 decimals = value % 100;
    value = value / 100;
    return (value, decimals);
  }
}
