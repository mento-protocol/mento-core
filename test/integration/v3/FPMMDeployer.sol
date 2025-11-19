// SPDX-License-Identifier: MIT
// solhint-disable max-line-length, function-max-lines

pragma solidity 0.8.24;
import { TestStorage } from "./TestStorage.sol";
import { CreateXHelper } from "test/utils/CreateXHelper.sol";

import { IERC20Metadata } from "bold/src/Interfaces/IBoldToken.sol";
import { FPMMFactory } from "contracts/swap/FPMMFactory.sol";
import { FPMM } from "contracts/swap/FPMM.sol";
import { OneToOneFPMM } from "contracts/swap/OneToOneFPMM.sol";
import { FactoryRegistry } from "contracts/swap/FactoryRegistry.sol";
import { ProxyAdmin } from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import { IFPMMFactory } from "contracts/interfaces/IFPMMFactory.sol";
import { IFPMM } from "contracts/interfaces/IFPMM.sol";
import { IFactoryRegistry } from "contracts/interfaces/IFactoryRegistry.sol";
import { IProxyAdmin } from "contracts/interfaces/IProxyAdmin.sol";
import { ITradingLimitsV2 } from "contracts/interfaces/ITradingLimitsV2.sol";

contract FPMMDeployer is TestStorage, CreateXHelper {
  constructor() {
    deployCreateX();
  }

  function _deployFPMM(bool invertCDPFPMMRate, bool invertReserveFPMMRate) internal {
    require($tokens.deployed, "FPMM_DEPLOYER: tokens not deployed");
    require($oracle.deployed, "FPMM_DEPLOYER: oracle not deployed");
    require($liquidityStrategies.deployed, "FPMM_DEPLOYER: liquidity strategies not deployed");

    $fpmm.fpmmImplementation = address(new FPMM(true));
    $fpmm.oneToOneFPMMImplementation = address(new OneToOneFPMM(true));

    $fpmm.proxyAdmin = IProxyAdmin(address(new ProxyAdmin()));
    vm.label(address($fpmm.proxyAdmin), "FPMM:ProxyAdmin");
    $fpmm.proxyAdmin.transferOwnership($addresses.governance);

    IFPMM.FPMMParams memory fpmmParams = IFPMM.FPMMParams({
      lpFee: 30,
      protocolFee: 0,
      protocolFeeRecipient: $addresses.protocolFeeRecipient,
      rebalanceIncentive: 50,
      rebalanceThresholdAbove: 500,
      rebalanceThresholdBelow: 500
    });

    $fpmm.fpmmFactory = IFPMMFactory(new FPMMFactory(false));
    vm.label(address($fpmm.fpmmFactory), "FPMMFactory");
    $fpmm.fpmmFactory.initialize(
      address($oracle.adapter),
      address($fpmm.proxyAdmin),
      $addresses.governance,
      $fpmm.fpmmImplementation,
      fpmmParams
    );

    $fpmm.factoryRegistry = IFactoryRegistry(new FactoryRegistry(false));
    vm.label(address($fpmm.factoryRegistry), "FactoryRegistry");
    $fpmm.factoryRegistry.initialize(address($fpmm.fpmmFactory), $addresses.governance);

    vm.startPrank($addresses.governance);
    $fpmm.fpmmCDP = IFPMM(
      $fpmm.fpmmFactory.deployFPMM(
        $fpmm.fpmmImplementation,
        address($tokens.cdpCollToken),
        address($tokens.cdpDebtToken),
        $addresses.referenceRateFeedCDPFPMM,
        invertCDPFPMMRate
      )
    );
    $fpmm.fpmmCDP.setLiquidityStrategy(address($liquidityStrategies.cdpLiquidityStrategy), true);
    vm.label(address($fpmm.fpmmCDP), "FPMMCDP");

    vm.startPrank($addresses.governance);
    $fpmm.fpmmFactory.registerFPMMImplementation(address($fpmm.oneToOneFPMMImplementation));
    $fpmm.fpmmReserve = IFPMM(
      $fpmm.fpmmFactory.deployFPMM(
        $fpmm.oneToOneFPMMImplementation,
        address($tokens.resDebtToken),
        address($tokens.resCollToken),
        $addresses.referenceRateFeedReserveFPMM,
        invertReserveFPMMRate
      )
    );
    $fpmm.fpmmReserve.setLiquidityStrategy(address($liquidityStrategies.reserveLiquidityStrategy), true);
    vm.stopPrank();
    vm.label(address($fpmm.fpmmReserve), "FPMMReserve");

    $fpmm.isToken0DebtInCDPFPMM = $fpmm.fpmmCDP.token0() == address($tokens.cdpDebtToken);
    $fpmm.isToken0DebtInResFPMM = $fpmm.fpmmReserve.token0() == address($tokens.resDebtToken);

    $fpmm.deployed = true;
  }

  function _fpmmTokens(IFPMM fpmm) internal view returns (address debtToken, address collToken) {
    if (address(fpmm) == address($fpmm.fpmmReserve)) {
      return (address($tokens.resDebtToken), address($tokens.resCollToken));
    } else if (address(fpmm) == address($fpmm.fpmmCDP)) {
      return (address($tokens.cdpDebtToken), address($tokens.cdpCollToken));
    }
  }

  function _fpmmReserves(IFPMM fpmm) internal view returns (uint256 debtAmount, uint256 collAmount) {
    (address debtToken, ) = _fpmmTokens(fpmm);
    if (debtToken == fpmm.token0()) {
      return (fpmm.reserve0(), fpmm.reserve1());
    } else {
      return (fpmm.reserve1(), fpmm.reserve0());
    }
  }

  function _provideLiquidityToFPMM(IFPMM fpmm, address provider, uint256 debtAmount, uint256 collAmount) internal {
    vm.startPrank(provider);

    (address debtToken, address collToken) = _fpmmTokens(fpmm);

    if (debtAmount > 0) {
      IERC20Metadata(debtToken).transfer(address(fpmm), debtAmount);
    }

    if (collAmount > 0) {
      IERC20Metadata(collToken).transfer(address(fpmm), collAmount);
    }

    uint256 lpTokensBefore = IERC20Metadata(address(fpmm)).balanceOf(provider);
    fpmm.mint(provider);
    uint256 lpTokensAfter = IERC20Metadata(address(fpmm)).balanceOf(provider);

    require(lpTokensAfter > lpTokensBefore, "FPMM_DEPLOYER: provide liquidity failed");

    vm.stopPrank();
  }

  struct FPMMPrices {
    uint256 oraclePriceNumerator;
    uint256 oraclePriceDenominator;
    uint256 reservePriceNumerator;
    uint256 reservePriceDenominator;
    uint256 priceDifference;
    bool reservePriceAboveOraclePrice;
  }

  function _snapshotPrices(IFPMM fpmm) internal view returns (FPMMPrices memory prices) {
    (
      prices.oraclePriceNumerator,
      prices.oraclePriceDenominator,
      prices.reservePriceNumerator,
      prices.reservePriceDenominator,
      prices.priceDifference,
      prices.reservePriceAboveOraclePrice
    ) = fpmm.getPrices();
  }

  function _configureTradingLimits(IFPMM fpmm, address token, ITradingLimitsV2.Config memory config) internal {
    require($fpmm.deployed, "FPMM_DEPLOYER: FPMM not deployed");

    vm.startPrank($addresses.governance);
    fpmm.configureTradingLimit(token, config);
    vm.stopPrank();
  }
}
