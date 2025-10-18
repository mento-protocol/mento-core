// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { IStableTokenV3 } from "contracts/interfaces/IStableTokenV3.sol";
import { IERC20Metadata } from "bold/src/Interfaces/IBoldToken.sol";
import { IAddressesRegistry } from "bold/src/Interfaces/IAddressesRegistry.sol";
import { IActivePool } from "bold/src/Interfaces/IActivePool.sol";
import { IBorrowerOperations } from "bold/src/Interfaces/IBorrowerOperations.sol";
import { ICollSurplusPool } from "bold/src/Interfaces/ICollSurplusPool.sol";
import { IDefaultPool } from "bold/src/Interfaces/IDefaultPool.sol";
import { ISortedTroves } from "bold/src/Interfaces/ISortedTroves.sol";
import { IStabilityPool } from "bold/src/Interfaces/IStabilityPool.sol";
import { ITroveManager } from "bold/src/Interfaces/ITroveManager.sol";
import { IFPMM } from "contracts/interfaces/IFPMM.sol";
import { IFPMMFactory } from "contracts/interfaces/IFPMMFactory.sol";
import { IFactoryRegistry } from "contracts/interfaces/IFactoryRegistry.sol";
import { IOracleAdapter } from "contracts/interfaces/IOracleAdapter.sol";
import { ITroveNFT } from "bold/src/Interfaces/ITroveNFT.sol";
import { IPriceFeed } from "bold/src/Interfaces/IPriceFeed.sol";
import { IInterestRouter } from "bold/src/Interfaces/IInterestRouter.sol";
import { ISystemParams } from "bold/src/Interfaces/ISystemParams.sol";

import { console2 as console } from "forge-std/console2.sol";
import { IProxyAdmin } from "contracts/interfaces/IProxyAdmin.sol";

abstract contract TestStorage is Test {
  constructor() {
    $addresses.governance = makeAddr("governance");
    $addresses.sortedOracles = makeAddr("sortedOracles");
    $addresses.breakerBox = makeAddr("breakerBox");
    $addresses.marketHoursBreaker = makeAddr("marketHoursBreaker");
    $addresses.protocolFeeRecipient = makeAddr("protocolFeeRecipient");
    $addresses.referenceRateFeedID = makeAddr("referenceRateFeedID");
  }

  struct LiquityDeployments {
    bool deployed;
    IAddressesRegistry addressesRegistry;
    IBorrowerOperations borrowerOperations;
    ISortedTroves sortedTroves;
    IActivePool activePool;
    IStabilityPool stabilityPool;
    ITroveManager troveManager;
    ITroveNFT troveNFT;
    IPriceFeed priceFeed;
    IInterestRouter interestRouter;
    IERC20Metadata collToken;
    // LiquityContractsDevPools pools;
    ISystemParams systemParams;
  }

  struct TokenDeployments {
    bool deployed;
    IStableTokenV3 debtToken;
    IStableTokenV3 collateralToken;
    IERC20Metadata reserveCollateralToken;
  }

  struct FPMMDeployments {
    bool deployed;
    IOracleAdapter oracleAdapter;
    IFactoryRegistry factoryRegistry;
    IFPMMFactory fpmmFactory;
    IFPMM fpmm;
    IProxyAdmin proxyAdmin;
  }

  struct MockAddresses {
    address governance;
    address sortedOracles;
    address breakerBox;
    address marketHoursBreaker;
    address protocolFeeRecipient;
    address fpmmImplementation;
    address referenceRateFeedID;
  }

  LiquityDeployments public $liquity;
  TokenDeployments public $tokens;
  FPMMDeployments public $fpmm;
  MockAddresses public $addresses;

  /* ============================================================ */
  /* ======================== Helper functions ================== */
  /* ============================================================ */

  function printTokenAddresses() public view {
    console.log("===== Token Deployment addresses =====");
    console.log(
      "> ",
      IERC20Metadata(address($tokens.debtToken)).symbol(),
      IERC20Metadata(address($tokens.debtToken)).decimals(),
      address($tokens.debtToken)
    );
    console.log(
      "> ",
      IERC20Metadata(address($tokens.collateralToken)).symbol(),
      IERC20Metadata(address($tokens.collateralToken)).decimals(),
      address($tokens.collateralToken)
    );
    console.log();
  }

  function printLiquityAddresses() public view {
    console.log("===== Liquity Deployment addresses =====");
    console.log("> addressesRegistry:", address($liquity.addressesRegistry));
    console.log("> borrowerOperations:", address($liquity.borrowerOperations));
    console.log("> sortedTroves:", address($liquity.sortedTroves));
    console.log("> activePool:", address($liquity.activePool));
    console.log("> stabilityPool:", address($liquity.stabilityPool));
    console.log("> troveManager:", address($liquity.troveManager));
    console.log("> troveNFT:", address($liquity.troveNFT));
    console.log("> priceFeed:", address($liquity.priceFeed));
    console.log("> interestRouter:", address($liquity.interestRouter));
    console.log("> collToken:", address($liquity.collToken));
    console.log("> systemParams:", address($liquity.systemParams));
    console.log();
  }
}
