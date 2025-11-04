// SPDX-License-Identifier: MIT
// solhint-disable max-line-length, function-max-lines

pragma solidity 0.8.24;
import { TestStorage } from "./TestStorage.sol";

import { VirtualPoolFactory } from "contracts/swap/virtual/VirtualPoolFactory.sol";
import { IVirtualPoolFactory } from "contracts/interfaces/IVirtualPoolFactory.sol";
import { IRPool } from "contracts/swap/router/interfaces/IRPool.sol";

contract VirtualPoolDeployer is TestStorage {
  function _deployVirtualPools() internal {
    require($tokens.deployed, "VIRTUAL_POOL_DEPLOYER: tokens not deployed");
    require($oracle.deployed, "VIRTUAL_POOL_DEPLOYER: oracle not deployed");
    require($fpmm.deployed, "VIRTUAL_POOL_DEPLOYER: FPMM not deployed");
    require($mentoV2.deployed, "VIRTUAL_POOL_DEPLOYER: MentoV2 not deployed");

    vm.startPrank($addresses.governance);
    $virtualPool.factory = IVirtualPoolFactory(address(new VirtualPoolFactory()));
    $virtualPool.exof_usdm_vp = IRPool(
      $virtualPool.factory.deployVirtualPool(address($mentoV2.biPoolManager), $mentoV2.pair_exof_usdm_id)
    );
    $virtualPool.exof_celo_vp = IRPool(
      $virtualPool.factory.deployVirtualPool(address($mentoV2.biPoolManager), $mentoV2.pair_exof_celo_id)
    );
    vm.label(address($virtualPool.exof_usdm_vp), "eXOF/USDm VirtualPool");
    vm.label(address($virtualPool.exof_celo_vp), "eXOF/Celo VirtualPool");
    $fpmm.factoryRegistry.approve(address($virtualPool.factory));
    vm.stopPrank();

    $virtualPool.deployed = true;
  }
}
