// SPDX-License-Identifier: MIT
// solhint-disable max-line-length

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
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";
import { IBreakerBox } from "contracts/interfaces/IBreakerBox.sol";
import { IMedianDeltaBreaker } from "contracts/interfaces/IMedianDeltaBreaker.sol";
import { IMarketHoursBreaker } from "contracts/interfaces/IMarketHoursBreaker.sol";
import { IValueDeltaBreaker } from "contracts/interfaces/IValueDeltaBreaker.sol";

import { ITroveNFT } from "bold/src/Interfaces/ITroveNFT.sol";
import { IPriceFeed } from "bold/src/Interfaces/IPriceFeed.sol";
import { IInterestRouter } from "bold/src/Interfaces/IInterestRouter.sol";
import { ISystemParams } from "bold/src/Interfaces/ISystemParams.sol";
import { GasPool } from "bold/src/GasPool.sol";
import { ICollSurplusPool } from "bold/src/Interfaces/ICollSurplusPool.sol";
import { IDefaultPool } from "bold/src/Interfaces/IDefaultPool.sol";
import { console2 as console } from "forge-std/console2.sol";
import { IProxyAdmin } from "contracts/interfaces/IProxyAdmin.sol";

import { IReserveV2 } from "contracts/interfaces/IReserveV2.sol";
import { IReserveLiquidityStrategy } from "contracts/interfaces/IReserveLiquidityStrategy.sol";
import { ICDPLiquidityStrategy } from "contracts/interfaces/ICDPLiquidityStrategy.sol";
import { ICollateralRegistry } from "bold/src/Interfaces/ICollateralRegistry.sol";

abstract contract TestStorage is Test {
  constructor() {
    $addresses.governance = makeAddr("governance");
    $addresses.watchdog = makeAddr("watchdog");
    $addresses.whitelistedOracle = makeAddr("whitelistedOracle");
    $addresses.protocolFeeRecipient = makeAddr("protocolFeeRecipient");
    $addresses.referenceRateFeedCDPFPMM = makeAddr("referenceRateFeedCDPFPMM");
    $addresses.referenceRateFeedReserveFPMM = makeAddr("referenceRateFeedReserveFPMM");

    // Start all tests from a non-zero timestamp (2025-10-22 09:00:00)
    // This is required when setting up the circuit breaker, since otherwise it reverts when trying to configure
    // the market hours breaker because of the isFXMarketOpen() check.
    vm.warp(1761123600);
  }

  struct LiquityDeploymentPools {
    IDefaultPool defaultPool;
    ICollSurplusPool collSurplusPool;
    GasPool gasPool;
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
    ISystemParams systemParams;
    // ICollateralRegistry collateralRegistry; // adding this causes a stack too deep error
  }

  // @dev cdpColl == reserveDebt
  struct TokenDeployments {
    bool deployed;
    IStableTokenV3 cdpDebtToken;
    IStableTokenV3 cdpCollToken;
    IStableTokenV3 resDebtToken;
    IERC20Metadata resCollToken;
  }

  struct FPMMDeployments {
    bool deployed;
    IFactoryRegistry factoryRegistry;
    IFPMMFactory fpmmFactory;
    IFPMM fpmmCDP;
    IFPMM fpmmReserve;
    IProxyAdmin proxyAdmin;
    address fpmmImplementation;
    address oneToOneFPMMImplementation;
    bool isToken0DebtInCDPFPMM;
    bool isToken0DebtInResFPMM;
  }

  struct OracleDeployments {
    bool deployed;
    IOracleAdapter adapter;
    ISortedOracles sortedOracles;
    IBreakerBox breakerBox;
    IMarketHoursBreaker marketHoursBreaker;
    IMedianDeltaBreaker medianDeltaBreaker;
    IValueDeltaBreaker valueDeltaBreaker;
  }

  struct MockAddresses {
    address governance;
    address watchdog;
    address whitelistedOracle;
    address protocolFeeRecipient;
    address referenceRateFeedCDPFPMM;
    address referenceRateFeedReserveFPMM;
  }

  struct LiquidityStrategiesDeployments {
    bool deployed;
    ICDPLiquidityStrategy cdpLiquidityStrategy;
    IReserveLiquidityStrategy reserveLiquidityStrategy;
    IReserveV2 reserve;
  }

  LiquityDeployments public $liquity;
  LiquityDeploymentPools public $liquityInternalPools;
  TokenDeployments public $tokens;
  FPMMDeployments public $fpmm;
  OracleDeployments public $oracle;
  MockAddresses public $addresses;
  LiquidityStrategiesDeployments public $liquidityStrategies;
  ICollateralRegistry public $collateralRegistry; // adding it here instead of LiquityDeployment because of stack too deep error

  /* ============================================================ */
  /* ======================== Helper functions ================== */
  /* ============================================================ */

  function printTokenAddresses() public view {
    console.log("===== Token Deployment addresses =====");
    console.log(
      "> ",
      IERC20Metadata(address($tokens.cdpDebtToken)).symbol(),
      IERC20Metadata(address($tokens.cdpDebtToken)).decimals(),
      address($tokens.cdpDebtToken)
    );
    console.log(
      "> ",
      IERC20Metadata(address($tokens.resDebtToken)).symbol(),
      IERC20Metadata(address($tokens.resDebtToken)).decimals(),
      address($tokens.resDebtToken)
    );
    console.log(
      "> ",
      IERC20Metadata(address($tokens.resCollToken)).symbol(),
      IERC20Metadata(address($tokens.resCollToken)).decimals(),
      address($tokens.resCollToken)
    );
    console.log();
  }

  function printOracleAddresses() public view {
    console.log("===== Oracle Deployment addresses =====");
    console.log("> adapter:", address($oracle.adapter));
    console.log("> sortedOracles:", address($oracle.sortedOracles));
    console.log("> breakerBox:", address($oracle.breakerBox));
    console.log("> marketHoursBreaker:", address($oracle.marketHoursBreaker));
    console.log("> medianDeltaBreaker:", address($oracle.medianDeltaBreaker));
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
    console.log("> defaultPool:", address($liquityInternalPools.defaultPool));
    console.log("> collSurplusPool:", address($liquityInternalPools.collSurplusPool));
    console.log("> gasPool:", address($liquityInternalPools.gasPool));
    console.log();
  }

  function printFPMMAddresses() public view {
    console.log("===== FPMM Deployment addresses =====");
    console.log("> oracleAdapter:", address($oracle.adapter));
    console.log("> factoryRegistry:", address($fpmm.factoryRegistry));
    console.log("> fpmmFactory:", address($fpmm.fpmmFactory));
    console.log("> fpmmCDP:", address($fpmm.fpmmCDP));
    console.log("> fpmmReserve:", address($fpmm.fpmmReserve));
    console.log("> proxyAdmin:", address($fpmm.proxyAdmin));
  }

  function printLiquidityStrategiesAddresses() public view {
    console.log("===== Liquidity Strategies Deployment addresses =====");
    console.log("> cdpLiquidityStrategy:", address($liquidityStrategies.cdpLiquidityStrategy));
    console.log("> reserveLiquidityStrategy:", address($liquidityStrategies.reserveLiquidityStrategy));
    console.log("> reserve:", address($liquidityStrategies.reserve));
  }
}
