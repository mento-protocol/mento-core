// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { IStableTokenV3 } from "contracts/interfaces/IStableTokenV3.sol";
import { IBoldToken, IERC20Metadata } from "bold/src/Interfaces/IBoldToken.sol";
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

abstract contract TestStorage is Test {
  constructor() {
    $addresses.governance = makeAddr("governance");
    $addresses.sortedOracles = makeAddr("sortedOracles");
    $addresses.breakerBox = makeAddr("breakerBox");
    $addresses.marketHoursBreaker = makeAddr("marketHoursBreaker");
  }

  struct LiquityDeployments {
    IAddressesRegistry addressesRegistry;
    IActivePool activePool;
    IBorrowerOperations borrowerOperations;
    ICollSurplusPool collSurplusPool;
    IDefaultPool defaultPool;
    ISortedTroves sortedTroves;
    IStabilityPool stabilityPool;
    ITroveManager troveManager;
  }

  struct TokenDeployments {
    IBoldToken debtToken;
    IStableTokenV3 collateralToken;
    IERC20Metadata reserveCollateralToken;
  }

  struct FPMMDeployments {
    IOracleAdapter oracleAdapter;
    IFactoryRegistry factoryRegistry;
    IFPMMFactory fpmmFactory;
    IFPMM fpmm;
  }

  struct MockAddresses {
    address governance;
    address sortedOracles;
    address breakerBox;
    address marketHoursBreaker;
  }

  LiquityDeployments public $liquidity;
  TokenDeployments public $tokens;
  FPMMDeployments public $fpmm;
  MockAddresses public $addresses;
}
