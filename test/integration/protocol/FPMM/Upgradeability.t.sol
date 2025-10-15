// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.8;

import { IFPMM } from "contracts/interfaces/IFPMM.sol";
import { FPMMBaseIntegration } from "./FPMMBaseIntegration.t.sol";
import { FPMMAlternativeImplementation } from "test/utils/mocks/FPMMAlternativeImplementation.sol";
import "openzeppelin-contracts-next/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract UpgradeabilityTest is FPMMBaseIntegration {
  address internal newFPMMimpl;
  address internal upgradedFPMM;

  function setUp() public override {
    super.setUp();
    newFPMMimpl = address(new FPMMAlternativeImplementation(true));

    upgradedFPMM = _deployFPMM(address(tokenA), address(tokenB));
  }

  function test_fpmmUpgradeability_upgrade() public {
    IFPMM fpmm = IFPMM(upgradedFPMM);
    vm.prank(governance);
    vm.expectRevert("FPMM: FEE_TOO_HIGH");
    fpmm.setLPFee(150);
    assertTrue(fpmm.lpFee() != 150);
    _upgrade(upgradedFPMM, newFPMMimpl);
    vm.prank(governance);
    fpmm.setLPFee(150);
    assertEq(fpmm.lpFee(), 150);
    vm.expectRevert("FPMM: FEE_TOO_HIGH");
    vm.prank(governance);
    fpmm.setLPFee(350);
  }

  function _upgrade(address fpmmProxy, address implementation) private {
    vm.prank(proxyAdminOwner);
    proxyAdmin.upgrade(ITransparentUpgradeableProxy(fpmmProxy), implementation);
  }
}
