// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.8;

import { IFPMM } from "contracts/interfaces/IFPMM.sol";
import { FPMMBaseIntegration } from "./FPMMBaseIntegration.t.sol";
import { FPMMAlternativeImplementation } from "test/utils/mocks/FPMMAlternativeImplementation.sol";
import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { IERC20Upgradeable } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import { ProxyAdmin } from "openzeppelin-contracts-next/contracts/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin-contracts-next/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract UpgradeabilityTest is FPMMBaseIntegration {
  // ========== Constants ==========
  string internal constant _REVERT_REASON = "FPMM: FEE_TOO_HIGH";
  uint256 internal constant _EXPECTED_FEE = 150;
  uint256 internal constant _ORIGINAL_LP_FEE = 30; // 0.3%
  uint256 internal constant _MAX_COMBINED_FEE_OLD = 100; // 1% in old implementation
  uint256 internal constant _MAX_COMBINED_FEE_NEW = 300; // 3% in new implementation

  address internal _newFPMMimpl;
  address internal _upgradedFPMM;
  IFPMM internal _fpmm;

  function setUp() public override {
    super.setUp();

    _newFPMMimpl = address(new FPMMAlternativeImplementation(true));
    _upgradedFPMM = _deployFPMM(address(tokenA), address(tokenB));
    _fpmm = IFPMM(_upgradedFPMM);
  }

  // ========== Core Upgrade Tests ==========
  function test_fpmmUpgradeability_upgradeAsProxyAdminOwner() public {
    _expectNotUpgraded(_fpmm, _EXPECTED_FEE, _REVERT_REASON);
    _upgrade(_upgradedFPMM, _newFPMMimpl, proxyAdminOwner);
    _expectUpgraded(_fpmm, _EXPECTED_FEE, _REVERT_REASON);
  }

  function test_fpmmUpgradeability_upgradeAsNotProxyAdminOwner() public {
    vm.expectRevert("Ownable: caller is not the owner");
    _upgrade(_upgradedFPMM, _newFPMMimpl, governance);
    _expectNotUpgraded(_fpmm, _EXPECTED_FEE, _REVERT_REASON);
  }

  // ========== UpgradeAndCall Tests ==========
  function test_fpmmUpgradeability_upgradeAndCallAsProxyAdminOwner() public {
    bytes memory data = abi.encodeWithSignature("lpFee()");

    _upgradeAndCall(_upgradedFPMM, _newFPMMimpl, data, proxyAdminOwner);
    assertEq(_fpmm.lpFee(), _ORIGINAL_LP_FEE, "lpFee changed unexpectedly");
    _expectUpgraded(_fpmm, _EXPECTED_FEE, _REVERT_REASON);
  }

  function test_fpmmUpgradeability_upgradeAndCallAsNotProxyAdminOwner() public {
    bytes memory data = abi.encodeWithSignature("lpFee()");

    vm.expectRevert("Ownable: caller is not the owner");
    _upgradeAndCall(_upgradedFPMM, _newFPMMimpl, data, governance);
    assertEq(_fpmm.lpFee(), _ORIGINAL_LP_FEE, "lpFee changed unexpectedly");
    _expectNotUpgraded(_fpmm, _EXPECTED_FEE, _REVERT_REASON);
  }

  // ========== Edge Case Tests ==========
  function test_fpmmUpgradeability_upgradeToZeroAddress() public {
    vm.prank(proxyAdminOwner);
    vm.expectRevert();
    proxyAdmin.upgrade(ITransparentUpgradeableProxy(_upgradedFPMM), address(0));
    _expectNotUpgraded(_fpmm, _EXPECTED_FEE, _REVERT_REASON);
  }

  function test_fpmmUpgradeability_upgradeToNonContract() public {
    address nonContract = address(0x1234);

    vm.prank(proxyAdminOwner);
    vm.expectRevert();
    proxyAdmin.upgrade(ITransparentUpgradeableProxy(_upgradedFPMM), nonContract);
    _expectNotUpgraded(_fpmm, _EXPECTED_FEE, _REVERT_REASON);
  }

  function test_fpmmUpgradeability_multipleSequentialUpgrades() public {
    // First upgrade
    _upgrade(_upgradedFPMM, _newFPMMimpl, proxyAdminOwner);
    _expectUpgraded(_fpmm, _EXPECTED_FEE, _REVERT_REASON);

    // Create another implementation
    address anotherImpl = address(new FPMMAlternativeImplementation(true));

    // Second upgrade
    _upgrade(_upgradedFPMM, anotherImpl, proxyAdminOwner);
    _expectUpgraded(_fpmm, _EXPECTED_FEE, _REVERT_REASON);

    // Verify implementation changed twice
    address finalImpl = proxyAdmin.getProxyImplementation(ITransparentUpgradeableProxy(_upgradedFPMM));
    assertEq(finalImpl, anotherImpl, "Final implementation should match second upgrade");
  }

  function test_fpmmUpgradeability_downgrade() public {
    address originalImpl = proxyAdmin.getProxyImplementation(ITransparentUpgradeableProxy(_upgradedFPMM));

    // Upgrade to new implementation and set fee to 150
    _upgrade(_upgradedFPMM, _newFPMMimpl, proxyAdminOwner);
    vm.prank(governance);
    _fpmm.setLPFee(_EXPECTED_FEE);
    assertEq(_fpmm.lpFee(), _EXPECTED_FEE, "Fee should be set to 150");

    // Downgrade back to original implementation
    _upgrade(_upgradedFPMM, originalImpl, proxyAdminOwner);

    // Storage is preserved, so fee is still 150, but old impl restricts changes
    assertEq(_fpmm.lpFee(), _EXPECTED_FEE, "Fee should remain 150 after downgrade");

    // Old implementation should reject fee >= 100, so setting to 50 should work
    vm.prank(governance);
    _fpmm.setLPFee(50);
    assertEq(_fpmm.lpFee(), 50, "Should be able to set fee to 50 with old impl");

    // Setting to 150 should fail with old implementation
    vm.prank(governance);
    vm.expectRevert(bytes(_REVERT_REASON));
    _fpmm.setLPFee(_EXPECTED_FEE);

    address currentImpl = proxyAdmin.getProxyImplementation(ITransparentUpgradeableProxy(_upgradedFPMM));
    assertEq(currentImpl, originalImpl, "Implementation should revert to original");
  }

  // ========== Implementation Verification Tests ==========
  function test_fpmmUpgradeability_verifyImplementationChange() public {
    address originalImpl = proxyAdmin.getProxyImplementation(ITransparentUpgradeableProxy(_upgradedFPMM));

    _upgrade(_upgradedFPMM, _newFPMMimpl, proxyAdminOwner);

    address newImpl = proxyAdmin.getProxyImplementation(ITransparentUpgradeableProxy(_upgradedFPMM));

    assertNotEq(originalImpl, newImpl, "Implementation should change");
    assertEq(newImpl, _newFPMMimpl, "Implementation should match new impl");
  }

  // ========== Proxy Admin Tests ==========
  function test_fpmmUpgradeability_getProxyAdmin() public {
    address admin = proxyAdmin.getProxyAdmin(ITransparentUpgradeableProxy(_upgradedFPMM));
    assertEq(admin, address(proxyAdmin), "Admin should match proxyAdmin");
  }

  // ========== State Preservation Tests ==========
  function test_fpmmUpgradeability_storageLayoutPreserved() public {
    _addInitialLiquidity(address(tokenA), address(tokenB), _upgradedFPMM);

    (uint256 reserve0Before, uint256 reserve1Before, ) = _fpmm.getReserves();
    uint256 lpFeeBefore = _fpmm.lpFee();
    uint256 totalSupplyBefore = IERC20Upgradeable(_upgradedFPMM).totalSupply();
    address ownerBefore = OwnableUpgradeable(_upgradedFPMM).owner();

    _upgrade(_upgradedFPMM, _newFPMMimpl, proxyAdminOwner);

    (uint256 reserve0After, uint256 reserve1After, ) = _fpmm.getReserves();
    assertEq(reserve0After, reserve0Before, "reserve0 changed");
    assertEq(reserve1After, reserve1Before, "reserve1 changed");
    assertEq(_fpmm.lpFee(), lpFeeBefore, "lpFee changed");
    assertEq(IERC20Upgradeable(_upgradedFPMM).totalSupply(), totalSupplyBefore, "totalSupply changed");
    assertEq(OwnableUpgradeable(_upgradedFPMM).owner(), ownerBefore, "owner changed");
  }

  function test_fpmmUpgradeability_viewFunctionsAfterUpgrade() public {
    address originalToken0 = _fpmm.token0();
    address originalToken1 = _fpmm.token1();
    uint256 originalDecimals0 = _fpmm.decimals0();
    uint256 originalDecimals1 = _fpmm.decimals1();
    address originalOwner = OwnableUpgradeable(_upgradedFPMM).owner();
    address originalOracleAdapter = address(_fpmm.oracleAdapter());

    _upgrade(_upgradedFPMM, _newFPMMimpl, proxyAdminOwner);
    
    assertEq(_fpmm.token0(), originalToken0, "token0 changed");
    assertEq(_fpmm.token1(), originalToken1, "token1 changed");
    assertEq(_fpmm.decimals0(), originalDecimals0, "decimals0 changed");
    assertEq(_fpmm.decimals1(), originalDecimals1, "decimals1 changed");
    assertEq(OwnableUpgradeable(_upgradedFPMM).owner(), originalOwner, "owner changed");
    assertEq(address(_fpmm.oracleAdapter()), originalOracleAdapter, "oracleAdapter changed");
  }

  // ========== Function Tests After Upgrade ==========
  function test_fpmmUpgradeability_mintAfterUpgrade() public {
    _addInitialLiquidity(address(tokenA), address(tokenB), _upgradedFPMM);
    uint256 liquidityBefore = IERC20Upgradeable(_upgradedFPMM).totalSupply();

    _upgrade(_upgradedFPMM, _newFPMMimpl, proxyAdminOwner);

    uint256 amount0 = 1000 * 10 ** tokenA.decimals();
    uint256 amount1 = 1000 * 10 ** tokenB.decimals();

    deal(address(tokenA), _upgradedFPMM, IERC20Upgradeable(address(tokenA)).balanceOf(_upgradedFPMM) + amount0);
    deal(address(tokenB), _upgradedFPMM, IERC20Upgradeable(address(tokenB)).balanceOf(_upgradedFPMM) + amount1);

    _fpmm.mint(address(this));

    uint256 liquidityAfter = IERC20Upgradeable(_upgradedFPMM).totalSupply();
    assertTrue(liquidityAfter > liquidityBefore, "Liquidity did not increase");
  }

  function test_fpmmUpgradeability_burnAfterUpgrade() public {
    _addInitialLiquidity(address(tokenA), address(tokenB), _upgradedFPMM);
    uint256 liquidity = IERC20Upgradeable(_upgradedFPMM).balanceOf(makeAddr("LP"));

    vm.prank(makeAddr("LP"));
    IERC20Upgradeable(_upgradedFPMM).transfer(address(this), liquidity / 2);
    uint256 liquidityToBurn = IERC20Upgradeable(_upgradedFPMM).balanceOf(address(this));

    _upgrade(_upgradedFPMM, _newFPMMimpl, proxyAdminOwner);

    IERC20Upgradeable(_upgradedFPMM).transfer(_upgradedFPMM, liquidityToBurn);
    (uint256 amount0Out, uint256 amount1Out) = _fpmm.burn(address(this));

    assertTrue(amount0Out > 0, "No token0 returned");
    assertTrue(amount1Out > 0, "No token1 returned");
  }

  function test_fpmmUpgradeability_swapAfterUpgrade() public {
    _addInitialLiquidity(address(tokenA), address(tokenB), _upgradedFPMM);

    _upgrade(_upgradedFPMM, _newFPMMimpl, proxyAdminOwner);

    uint256 swapAmount = 100 * 10 ** tokenA.decimals();
    uint256 expectedOut = _fpmm.getAmountOut(swapAmount, address(tokenA));
    assertTrue(expectedOut > 0, "getAmountOut should return non-zero after upgrade");

    (uint256 reserve0, uint256 reserve1, ) = _fpmm.getReserves();
    assertTrue(reserve0 > 0, "Reserve0 should be non-zero");
    assertTrue(reserve1 > 0, "Reserve1 should be non-zero");
  }

  function test_fpmmUpgradeability_getAmountOutConsistency() public {
    _addInitialLiquidity(address(tokenA), address(tokenB), _upgradedFPMM);

    uint256 amountIn = 100 * 10 ** tokenA.decimals();
    uint256 amountOutBefore = _fpmm.getAmountOut(amountIn, address(tokenA));
    assertTrue(amountOutBefore > 0, "getAmountOut returned 0 before upgrade");

    _upgrade(_upgradedFPMM, _newFPMMimpl, proxyAdminOwner);

    // Get quote after upgrade - should be the same
    uint256 amountOutAfter = _fpmm.getAmountOut(amountIn, address(tokenA));
    assertEq(amountOutAfter, amountOutBefore, "getAmountOut changed after upgrade");
  }

  function test_fpmmUpgradeability_ownerFunctionsAfterUpgrade() public {
    _upgrade(_upgradedFPMM, _newFPMMimpl, proxyAdminOwner);

    vm.startPrank(governance);

    _fpmm.setRebalanceIncentive(100);
    assertEq(_fpmm.rebalanceIncentive(), 100, "setRebalanceIncentive failed");

    _fpmm.setRebalanceThresholds(600, 600);
    assertEq(_fpmm.rebalanceThresholdAbove(), 600, "setRebalanceThresholdAbove failed");
    assertEq(_fpmm.rebalanceThresholdBelow(), 600, "setRebalanceThresholdBelow failed");

    vm.stopPrank();
  }

  function test_fpmmUpgradeability_eventsEmittedAfterUpgrade() public {
    _upgrade(_upgradedFPMM, _newFPMMimpl, proxyAdminOwner);

    vm.prank(governance);
    vm.expectEmit(true, true, false, true);
    emit LPFeeUpdated(_ORIGINAL_LP_FEE, 50);
    _fpmm.setLPFee(50);
  }

  function test_fpmmUpgradeability_accessControlAfterUpgrade() public {
    _upgrade(_upgradedFPMM, _newFPMMimpl, proxyAdminOwner);

    // Verify non-owner cannot call owner functions
    address notOwner = makeAddr("notOwner");

    vm.startPrank(notOwner);

    vm.expectRevert("Ownable: caller is not the owner");
    _fpmm.setLPFee(100);

    vm.expectRevert("Ownable: caller is not the owner");
    _fpmm.setRebalanceIncentive(100);

    vm.expectRevert("Ownable: caller is not the owner");
    _fpmm.setRebalanceThresholds(600, 600);

    vm.stopPrank();
  }

  // ========== Helper Functions ==========
  function _upgrade(address fpmmProxy, address implementation, address caller) private {
    vm.prank(caller);
    proxyAdmin.upgrade(ITransparentUpgradeableProxy(fpmmProxy), implementation);
  }

  function _upgradeAndCall(address fpmmProxy, address implementation, bytes memory data, address caller) private {
    vm.prank(caller);
    proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(fpmmProxy), implementation, data);
  }

  function _expectUpgraded(IFPMM fpmm, uint256 expectedFee, string memory revertReason) private {
    vm.prank(governance);
    fpmm.setLPFee(expectedFee);
    assertEq(fpmm.lpFee(), expectedFee);

    vm.prank(governance);
    vm.expectRevert(bytes(revertReason));
    fpmm.setLPFee(expectedFee + 300);
    assertEq(fpmm.lpFee(), expectedFee);
  }

  function _expectNotUpgraded(IFPMM fpmm, uint256 expectedFee, string memory revertReason) private {
    vm.prank(governance);
    vm.expectRevert(bytes(revertReason));
    fpmm.setLPFee(expectedFee);
    assertTrue(fpmm.lpFee() != expectedFee);
  }

  // Event declarations for expectEmit
  event LPFeeUpdated(uint256 oldFee, uint256 newFee);
}
