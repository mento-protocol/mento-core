// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
// solhint-disable max-line-length
pragma solidity ^0.8;

import { CDPLiquidityStrategy_BaseTest } from "./CDPLiquidityStrategy_BaseTest.sol";
import { ICDPLiquidityStrategy } from "contracts/interfaces/ICDPLiquidityStrategy.sol";
import { ILiquidityStrategy } from "contracts/interfaces/ILiquidityStrategy.sol";
import { MockStabilityPool } from "test/utils/mocks/MockStabilityPool.sol";
import { MockCollateralRegistry } from "test/utils/mocks/MockCollateralRegistry.sol";

contract CDPLiquidityStrategy_AdminTest is CDPLiquidityStrategy_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  /* ============================================================ */
  /* ==================== addPool Tests ========================= */
  /* ============================================================ */

  function test_addPool_whenCalledByOwner_shouldAddPoolSuccessfully() public fpmmToken0Debt(18, 18) {
    // Deploy mocks
    mockCollateralRegistry = new MockCollateralRegistry(debtToken, collToken);
    mockStabilityPool = new MockStabilityPool(debtToken, collToken, mockSystemParams);

    ILiquidityStrategy.AddPoolParams memory params = _buildAddPoolParams(
      address(fpmm),
      debtToken,
      0,
      25,
      25,
      25,
      25,
      protocolFeeRecipient
    );
    ICDPLiquidityStrategy.CDPConfig memory config = ICDPLiquidityStrategy.CDPConfig({
      stabilityPool: address(mockStabilityPool),
      collateralRegistry: address(mockCollateralRegistry),
      stabilityPoolPercentage: 9000,
      maxIterations: 100
    });

    vm.expectEmit(true, true, false, true);
    emit PoolAdded(address(fpmm), params);

    vm.prank(owner);
    strategy.addPool(params, config);

    // Verify pool is registered
    assertTrue(strategy.isPoolRegistered(address(fpmm)), "Pool should be registered");

    // Verify CDP config
    ICDPLiquidityStrategy.CDPConfig memory storedConfig = strategy.getCDPConfig(address(fpmm));
    assertEq(storedConfig.stabilityPool, address(mockStabilityPool), "Stability pool should match");
    assertEq(storedConfig.collateralRegistry, address(mockCollateralRegistry), "Collateral registry should match");
    assertEq(storedConfig.stabilityPoolPercentage, 9000, "Stability pool percentage should match");
    assertEq(storedConfig.maxIterations, 100, "Max iterations should match");
  }

  function test_addPool_whenCalledByNonOwner_shouldRevert() public fpmmToken0Debt(18, 18) {
    mockCollateralRegistry = new MockCollateralRegistry(debtToken, collToken);
    mockStabilityPool = new MockStabilityPool(debtToken, collToken, mockSystemParams);

    ILiquidityStrategy.AddPoolParams memory params = _buildAddPoolParams(
      address(fpmm),
      debtToken,
      0,
      25,
      25,
      25,
      25,
      protocolFeeRecipient
    );
    ICDPLiquidityStrategy.CDPConfig memory config = ICDPLiquidityStrategy.CDPConfig({
      stabilityPool: address(mockStabilityPool),
      collateralRegistry: address(mockCollateralRegistry),
      stabilityPoolPercentage: 9000,
      maxIterations: 100
    });

    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(notOwner);
    strategy.addPool(params, config);
  }

  function test_addPool_whenStabilityPoolPercentageIsZero_shouldRevert() public fpmmToken0Debt(18, 18) {
    mockCollateralRegistry = new MockCollateralRegistry(debtToken, collToken);
    mockStabilityPool = new MockStabilityPool(debtToken, collToken, mockSystemParams);

    ILiquidityStrategy.AddPoolParams memory params = _buildAddPoolParams(
      address(fpmm),
      debtToken,
      0,
      25,
      25,
      25,
      25,
      protocolFeeRecipient
    );
    ICDPLiquidityStrategy.CDPConfig memory config = ICDPLiquidityStrategy.CDPConfig({
      stabilityPool: address(mockStabilityPool),
      collateralRegistry: address(mockCollateralRegistry),
      stabilityPoolPercentage: 0,
      maxIterations: 100
    });

    vm.expectRevert(ICDPLiquidityStrategy.CDPLS_INVALID_STABILITY_POOL_PERCENTAGE.selector);
    vm.prank(owner);
    strategy.addPool(params, config);
  }

  function test_addPool_whenStabilityPoolPercentageIs10000_shouldRevert() public fpmmToken0Debt(18, 18) {
    mockCollateralRegistry = new MockCollateralRegistry(debtToken, collToken);
    mockStabilityPool = new MockStabilityPool(debtToken, collToken, mockSystemParams);

    vm.expectRevert(ICDPLiquidityStrategy.CDPLS_INVALID_STABILITY_POOL_PERCENTAGE.selector);
    ILiquidityStrategy.AddPoolParams memory params = _buildAddPoolParams(
      address(fpmm),
      debtToken,
      0,
      25,
      25,
      25,
      25,
      protocolFeeRecipient
    );
    ICDPLiquidityStrategy.CDPConfig memory config = ICDPLiquidityStrategy.CDPConfig({
      stabilityPool: address(mockStabilityPool),
      collateralRegistry: address(mockCollateralRegistry),
      stabilityPoolPercentage: 10000,
      maxIterations: 100
    });
    vm.prank(owner);
    strategy.addPool(params, config);
  }

  function test_addPool_whenCollateralRegistryIsZero_shouldRevert() public fpmmToken0Debt(18, 18) {
    mockStabilityPool = new MockStabilityPool(debtToken, collToken, mockSystemParams);
    ILiquidityStrategy.AddPoolParams memory params = _buildAddPoolParams(
      address(fpmm),
      debtToken,
      0,
      25,
      25,
      25,
      25,
      protocolFeeRecipient
    );
    ICDPLiquidityStrategy.CDPConfig memory config = ICDPLiquidityStrategy.CDPConfig({
      stabilityPool: address(mockStabilityPool),
      collateralRegistry: address(0),
      stabilityPoolPercentage: 9000,
      maxIterations: 100
    });

    vm.expectRevert(ICDPLiquidityStrategy.CDPLS_COLLATERAL_REGISTRY_IS_ZERO.selector);
    vm.prank(owner);
    strategy.addPool(params, config);
  }

  function test_addPool_whenStabilityPoolIsZero_shouldRevert() public fpmmToken0Debt(18, 18) {
    mockCollateralRegistry = new MockCollateralRegistry(debtToken, collToken);

    ILiquidityStrategy.AddPoolParams memory params = _buildAddPoolParams(
      address(fpmm),
      debtToken,
      0,
      25,
      25,
      25,
      25,
      protocolFeeRecipient
    );
    ICDPLiquidityStrategy.CDPConfig memory config = ICDPLiquidityStrategy.CDPConfig({
      stabilityPool: address(0),
      collateralRegistry: address(mockCollateralRegistry),
      stabilityPoolPercentage: 9000,
      maxIterations: 100
    });

    vm.expectRevert(ICDPLiquidityStrategy.CDPLS_STABILITY_POOL_IS_ZERO.selector);
    vm.prank(owner);
    strategy.addPool(params, config);
  }

  /* ============================================================ */
  /* =================== removePool Tests ======================= */
  /* ============================================================ */

  function test_removePool_whenCalledByOwner_shouldRemovePoolSuccessfully()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 9000, 100, 25, 25, 25, 25)
  {
    assertTrue(strategy.isPoolRegistered(address(fpmm)), "Pool should be registered initially");

    vm.expectEmit(true, false, false, false);
    emit PoolRemoved(address(fpmm));

    vm.prank(owner);
    strategy.removePool(address(fpmm));

    assertFalse(strategy.isPoolRegistered(address(fpmm)), "Pool should no longer be registered");
  }

  function test_removePool_whenCalledByNonOwner_shouldRevert()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 9000, 100, 25, 25, 25, 25)
  {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(notOwner);
    strategy.removePool(address(fpmm));
  }

  function test_removePool_whenPoolNotRegistered_shouldRevert() public fpmmToken0Debt(18, 18) {
    vm.expectRevert("LS_POOL_NOT_FOUND()");
    vm.prank(owner);
    strategy.removePool(address(fpmm));
  }

  /* ============================================================ */
  /* =================== setCDPConfig Tests ===================== */
  /* ============================================================ */

  function test_setCDPConfig_whenCalledByOwner_shouldUpdateConfigSuccessfully()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 9000, 100, 25, 25, 25, 25)
  {
    // Create new mocks
    MockStabilityPool newStabilityPool = new MockStabilityPool(debtToken, collToken, mockSystemParams);
    MockCollateralRegistry newCollateralRegistry = new MockCollateralRegistry(debtToken, collToken);

    ICDPLiquidityStrategy.CDPConfig memory newConfig = ICDPLiquidityStrategy.CDPConfig({
      stabilityPool: address(newStabilityPool),
      collateralRegistry: address(newCollateralRegistry),
      stabilityPoolPercentage: 8000, // 80%
      maxIterations: 100
    });

    vm.prank(owner);
    strategy.setCDPConfig(address(fpmm), newConfig);

    // Verify updated config
    ICDPLiquidityStrategy.CDPConfig memory config = strategy.getCDPConfig(address(fpmm));
    assertEq(config.stabilityPool, address(newStabilityPool), "Stability pool should be updated");
    assertEq(config.collateralRegistry, address(newCollateralRegistry), "Collateral registry should be updated");
    assertEq(config.stabilityPoolPercentage, 8000, "Stability pool percentage should be updated");
    assertEq(config.maxIterations, 100, "Max iterations should be updated");
  }

  function test_setCDPConfig_whenCalledByNonOwner_shouldRevert()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 9000, 100, 25, 25, 25, 25)
  {
    ICDPLiquidityStrategy.CDPConfig memory newConfig = ICDPLiquidityStrategy.CDPConfig({
      stabilityPool: address(mockStabilityPool),
      collateralRegistry: address(mockCollateralRegistry),
      stabilityPoolPercentage: 8000,
      maxIterations: 100
    });

    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(notOwner);
    strategy.setCDPConfig(address(fpmm), newConfig);
  }

  function test_setCDPConfig_whenPoolNotRegistered_shouldRevert() public fpmmToken0Debt(18, 18) {
    ICDPLiquidityStrategy.CDPConfig memory newConfig = ICDPLiquidityStrategy.CDPConfig({
      stabilityPool: address(mockStabilityPool),
      collateralRegistry: address(mockCollateralRegistry),
      stabilityPoolPercentage: 8000,
      maxIterations: 100
    });

    vm.expectRevert("LS_POOL_NOT_FOUND()");
    vm.prank(owner);
    strategy.setCDPConfig(address(fpmm), newConfig);
  }

  /* ============================================================ */
  /* =================== getCDPConfig Tests ===================== */
  /* ============================================================ */

  function test_getCDPConfig_whenPoolRegistered_shouldReturnConfig()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 9000, 100, 25, 25, 25, 25)
  {
    ICDPLiquidityStrategy.CDPConfig memory config = strategy.getCDPConfig(address(fpmm));

    assertEq(config.stabilityPool, address(mockStabilityPool), "Stability pool should match");
    assertEq(config.collateralRegistry, address(mockCollateralRegistry), "Collateral registry should match");
    assertEq(config.stabilityPoolPercentage, 9000, "Stability pool percentage should match");
    assertEq(config.maxIterations, 100, "Max iterations should match");
  }

  function test_getCDPConfig_whenPoolNotRegistered_shouldRevert() public fpmmToken0Debt(18, 18) {
    vm.expectRevert("LS_POOL_NOT_FOUND()");
    strategy.getCDPConfig(address(fpmm));
  }

  function test_initialize_whenCalledTwice_shouldReverts() public {
    vm.expectRevert("Initializable: contract is already initialized");
    strategy.initialize(owner);
  }
}
