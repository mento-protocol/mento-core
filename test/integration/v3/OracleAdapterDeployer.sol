// SPDX-License-Identifier: MIT
// solhint-disable max-line-length, function-max-lines

pragma solidity 0.8.24;
import { TestStorage } from "./TestStorage.sol";

import { IBoldToken, IERC20Metadata } from "bold/src/Interfaces/IBoldToken.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";
import { StableTokenV3 } from "contracts/tokens/StableTokenV3.sol";
import { FPMMFactory } from "contracts/swap/FPMMFactory.sol";
import { Router } from "contracts/swap/router/Router.sol";
import { FPMM } from "contracts/swap/FPMM.sol";
import { OneToOneFPMM } from "contracts/swap/OneToOneFPMM.sol";
import { FactoryRegistry } from "contracts/swap/FactoryRegistry.sol";
import { OracleAdapter } from "contracts/oracles/OracleAdapter.sol";
import { ProxyAdmin } from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import { IStableTokenV3 } from "contracts/interfaces/IStableTokenV3.sol";
import { IFPMMFactory } from "contracts/interfaces/IFPMMFactory.sol";
import { IFPMM } from "contracts/interfaces/IFPMM.sol";
import { IFactoryRegistry } from "contracts/interfaces/IFactoryRegistry.sol";
import { IRouter } from "contracts/swap/router/interfaces/IRouter.sol";
import { IOracleAdapter } from "contracts/interfaces/IOracleAdapter.sol";
import { IProxyAdmin } from "contracts/interfaces/IProxyAdmin.sol";

contract OracleAdapterDeployer is TestStorage {
  function _deployOracleAdapter() internal {
    $oracle.adapter = IOracleAdapter(new OracleAdapter(false));
    $oracle.adapter.initialize(
      $addresses.sortedOracles,
      $addresses.breakerBox,
      $addresses.marketHoursBreaker,
      $addresses.governance
    );

    _enableOneToOneFPMM();
    _setFxRate(2e18, 1e18);

    $oracle.deployed = true;
  }

  function _setFxRate(uint256 numerator, uint256 denominator) internal {
    vm.mockCall(
      address($oracle.adapter),
      abi.encodeWithSelector(IOracleAdapter.getFXRateIfValid.selector, $addresses.referenceRateFeedCDPFPMM),
      abi.encode(numerator, denominator)
    );
  }

  function _enableOneToOneFPMM() internal {
    vm.mockCall(
      address($oracle.adapter),
      abi.encodeWithSelector(IOracleAdapter.ensureRateValid.selector, $addresses.referenceRateFeedReserveFPMM),
      bytes("")
    );
  }
}
