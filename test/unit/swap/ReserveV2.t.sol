// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable-next-line max-line-length
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { ReserveV2 } from "contracts/swap/ReserveV2.sol";
import { IReserveV2 } from "contracts/interfaces/IReserveV2.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";
// solhint-disable-next-line max-line-length
import { TransparentUpgradeableProxy, ITransparentUpgradeableProxy } from "openzeppelin-contracts-next/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "openzeppelin-contracts-next/contracts/proxy/transparent/ProxyAdmin.sol";

contract ReserveV2Test is Test {
  ReserveV2 public reserve;
  ReserveV2 public reserveImplementation;
  ProxyAdmin public proxyAdmin;
  TransparentUpgradeableProxy public proxy;

  MockERC20 public collateralAsset;
  MockERC20 public collateralAsset2;
  MockERC20 public stableAsset;
  MockERC20 public stableAsset2;

  address public owner;
  address public notOwner;
  address public reserveManagerSpender;
  address public liquidityStrategySpender;
  address public otherReserveAddress;

  /* ---------------- Events from ReserveV2 --------------- */

  event StableAssetRegistered(address indexed stableAsset);
  event StableAssetUnregistered(address indexed stableAsset);
  event CollateralAssetRegistered(address indexed collateralAsset);
  event CollateralAssetUnregistered(address indexed collateralAsset);
  event OtherReserveAddressRegistered(address indexed otherReserveAddress);
  event OtherReserveAddressUnregistered(address indexed otherReserveAddress);
  event LiquidityStrategySpenderRegistered(address indexed liquidityStrategySpender);
  event LiquidityStrategySpenderUnregistered(address indexed liquidityStrategySpender);
  event ReserveManagerSpenderRegistered(address indexed reserveManagerSpender);
  event ReserveManagerSpenderUnregistered(address indexed reserveManagerSpender);
  event CollateralAssetTransferredReserveManagerSpender(
    address indexed reserveManagerSpender,
    address indexed collateralAsset,
    address indexed otherReserveAddress,
    uint256 value
  );
  event CollateralAssetTransferredLiquidityStrategySpender(
    address indexed liquidityStrategySpender,
    address indexed collateralAsset,
    address indexed to,
    uint256 value
  );

  /* ----------------------------------------------------- */

  function setUp() public {
    owner = makeAddr("owner");
    notOwner = makeAddr("notOwner");
    reserveManagerSpender = makeAddr("reserveManagerSpender");
    liquidityStrategySpender = makeAddr("liquidityStrategySpender");
    otherReserveAddress = makeAddr("otherReserveAddress");

    collateralAsset = new MockERC20("Collateral Asset", "CA", 18);
    collateralAsset2 = new MockERC20("Collateral Asset 2", "CA2", 18);
    stableAsset = new MockERC20("Stable Asset", "SA", 18);
    stableAsset2 = new MockERC20("Stable Asset 2", "SA2", 18);

    reserveImplementation = new ReserveV2(true);
    reserve = new ReserveV2(false);

    address[] memory stableAssets = new address[](1);
    stableAssets[0] = address(stableAsset);

    address[] memory collateralAssets = new address[](1);
    collateralAssets[0] = address(collateralAsset);

    address[] memory otherReserveAddresses = new address[](1);
    otherReserveAddresses[0] = otherReserveAddress;

    address[] memory liquidityStrategySpenders = new address[](1);
    liquidityStrategySpenders[0] = liquidityStrategySpender;

    address[] memory reserveManagerSpenders = new address[](0);

    reserve.initialize(
      stableAssets,
      collateralAssets,
      otherReserveAddresses,
      liquidityStrategySpenders,
      reserveManagerSpenders,
      owner
    );
  }

  /* ============================================================ */
  /* ==================== Constructor Tests ===================== */
  /* ============================================================ */

  function test_constructor_whenDisabledIsFalse_shouldNotDisableInitializers() public {
    ReserveV2 newReserve = new ReserveV2(false);
    address[] memory empty = new address[](0);
    // Should be able to initialize
    newReserve.initialize(empty, empty, empty, empty, empty, owner);
  }

  function test_constructor_whenDisabledIsTrue_shouldDisableInitializers() public {
    ReserveV2 newReserve = new ReserveV2(true);
    address[] memory empty = new address[](0);
    // Should not be able to initialize
    vm.expectRevert();
    newReserve.initialize(empty, empty, empty, empty, empty, owner);
  }

  /* ============================================================ */
  /* =================== Initialize Tests ======================= */
  /* ============================================================ */

  function test_initialize_shouldSetOwnerAndAddAllParameters() public {
    ReserveV2 newReserve = new ReserveV2(false);

    address[] memory stableAssets = new address[](2);
    stableAssets[0] = address(stableAsset);
    stableAssets[1] = address(stableAsset2);

    address[] memory collateralAssets = new address[](2);
    collateralAssets[0] = address(collateralAsset);
    collateralAssets[1] = address(collateralAsset2);

    address otherReserve2 = makeAddr("otherReserve2");
    address[] memory otherReserves = new address[](2);
    otherReserves[0] = otherReserveAddress;
    otherReserves[1] = otherReserve2;

    address liquidityStrategySpender2 = makeAddr("liquidityStrategySpender2");
    address[] memory liquidityStrategySpenders = new address[](2);
    liquidityStrategySpenders[0] = liquidityStrategySpender;
    liquidityStrategySpenders[1] = liquidityStrategySpender2;

    address reserveManagerSpender2 = makeAddr("reserveManagerSpender2");
    address[] memory reserveManagerSpenders = new address[](2);
    reserveManagerSpenders[0] = reserveManagerSpender;
    reserveManagerSpenders[1] = reserveManagerSpender2;

    // Expect all events
    vm.expectEmit(true, true, true, true);
    emit StableAssetRegistered(address(stableAsset));
    vm.expectEmit(true, true, true, true);
    emit StableAssetRegistered(address(stableAsset2));
    vm.expectEmit(true, true, true, true);
    emit CollateralAssetRegistered(address(collateralAsset));
    vm.expectEmit(true, true, true, true);
    emit CollateralAssetRegistered(address(collateralAsset2));
    vm.expectEmit(true, true, true, true);
    emit OtherReserveAddressRegistered(otherReserveAddress);
    vm.expectEmit(true, true, true, true);
    emit OtherReserveAddressRegistered(otherReserve2);
    vm.expectEmit(true, true, true, true);
    emit LiquidityStrategySpenderRegistered(liquidityStrategySpender);
    vm.expectEmit(true, true, true, true);
    emit LiquidityStrategySpenderRegistered(liquidityStrategySpender2);
    vm.expectEmit(true, true, true, true);
    emit ReserveManagerSpenderRegistered(reserveManagerSpender);
    vm.expectEmit(true, true, true, true);
    emit ReserveManagerSpenderRegistered(reserveManagerSpender2);

    newReserve.initialize(
      stableAssets,
      collateralAssets,
      otherReserves,
      liquidityStrategySpenders,
      reserveManagerSpenders,
      owner
    );

    // Verify owner
    assertEq(newReserve.owner(), owner);

    // Verify mappings
    assertTrue(newReserve.isStableAsset(address(stableAsset)));
    assertTrue(newReserve.isStableAsset(address(stableAsset2)));
    assertTrue(newReserve.isCollateralAsset(address(collateralAsset)));
    assertTrue(newReserve.isCollateralAsset(address(collateralAsset2)));
    assertTrue(newReserve.isOtherReserveAddress(otherReserveAddress));
    assertTrue(newReserve.isOtherReserveAddress(otherReserve2));
    assertTrue(newReserve.isLiquidityStrategySpender(liquidityStrategySpender));
    assertTrue(newReserve.isLiquidityStrategySpender(liquidityStrategySpender2));
    assertTrue(newReserve.isReserveManagerSpender(reserveManagerSpender));
    assertTrue(newReserve.isReserveManagerSpender(reserveManagerSpender2));

    // Verify arrays (via public getters)
    address[] memory stableAssetsContents = newReserve.getStableAssets();
    assertEq(stableAssetsContents.length, 2);
    assertEq(stableAssetsContents[0], address(stableAsset));
    assertEq(stableAssetsContents[1], address(stableAsset2));
    address[] memory collateralAssetsContents = newReserve.getCollateralAssets();
    assertEq(collateralAssetsContents.length, 2);
    assertEq(collateralAssetsContents[0], address(collateralAsset));
    assertEq(collateralAssetsContents[1], address(collateralAsset2));
    address[] memory otherReserveAddressesContents = newReserve.getOtherReserveAddresses();
    assertEq(otherReserveAddressesContents.length, 2);
    assertEq(otherReserveAddressesContents[0], otherReserveAddress);
    assertEq(otherReserveAddressesContents[1], otherReserve2);
    address[] memory liquidityStrategySpendersContents = newReserve.getLiquidityStrategySpenders();
    assertEq(liquidityStrategySpendersContents.length, 2);
    assertEq(liquidityStrategySpendersContents[0], liquidityStrategySpender);
    assertEq(liquidityStrategySpendersContents[1], liquidityStrategySpender2);
    address[] memory reserveManagerSpendersContents = newReserve.getReserveManagerSpenders();
    assertEq(reserveManagerSpendersContents.length, 2);
    assertEq(reserveManagerSpendersContents[0], reserveManagerSpender);
    assertEq(reserveManagerSpendersContents[1], reserveManagerSpender2);
  }

  function test_initialize_whenCalledTwice_shouldRevert() public {
    address[] memory empty = new address[](0);
    vm.expectRevert();
    reserve.initialize(empty, empty, empty, empty, empty, owner);
  }

  /* ============================================================ */
  /* ============== Stable Asset Management Tests =============== */
  /* ============================================================ */

  function test_registerStableAsset_shouldUpdateStorageEmitEventAndUpdateArray() public {
    vm.expectEmit(true, true, true, true);
    emit StableAssetRegistered(address(stableAsset2));

    vm.prank(owner);
    reserve.registerStableAsset(address(stableAsset2));

    // Verify mapping
    assertTrue(reserve.isStableAsset(address(stableAsset2)));

    // Verify array
    address[] memory assets = reserve.getStableAssets();
    assertEq(assets.length, 2);
    assertEq(assets[0], address(stableAsset));
    assertEq(assets[1], address(stableAsset2));
  }

  function test_registerStableAsset_whenCallerIsNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert();
    reserve.registerStableAsset(address(stableAsset2));
  }

  function test_registerStableAsset_whenAssetIsZeroAddress_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(IReserveV2.StableAssetZeroAddress.selector);
    reserve.registerStableAsset(address(0));
  }

  function test_registerStableAsset_whenAssetAlreadyRegistered_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(IReserveV2.StableAssetAlreadyRegistered.selector);
    reserve.registerStableAsset(address(stableAsset));
  }

  function test_unregisterStableAsset_shouldUpdateStorageEmitEventAndUpdateArray() public {
    // Add second asset first
    vm.prank(owner);
    reserve.registerStableAsset(address(stableAsset2));

    vm.expectEmit(true, true, true, true);
    emit StableAssetUnregistered(address(stableAsset));

    vm.prank(owner);
    reserve.unregisterStableAsset(address(stableAsset));

    // Verify mapping
    assertFalse(reserve.isStableAsset(address(stableAsset)));
    assertTrue(reserve.isStableAsset(address(stableAsset2)));

    // Verify array
    address[] memory assets = reserve.getStableAssets();
    assertEq(assets.length, 1);
    assertEq(assets[0], address(stableAsset2));
  }

  function test_unregisterStableAsset_whenCallerIsNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert();
    reserve.unregisterStableAsset(address(stableAsset));
  }

  function test_unregisterStableAsset_whenAssetNotRegistered_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(IReserveV2.StableAssetNotRegistered.selector);
    reserve.unregisterStableAsset(address(stableAsset2));
  }

  /* ============================================================ */
  /* ============ Collateral Asset Management Tests ============= */
  /* ============================================================ */

  function test_registerCollateralAsset_shouldUpdateStorageEmitEventAndUpdateArray() public {
    vm.expectEmit(true, true, true, true);
    emit CollateralAssetRegistered(address(collateralAsset2));

    vm.prank(owner);
    reserve.registerCollateralAsset(address(collateralAsset2));

    // Verify mapping
    assertTrue(reserve.isCollateralAsset(address(collateralAsset2)));

    // Verify array
    address[] memory assets = reserve.getCollateralAssets();
    assertEq(assets.length, 2);
    assertEq(assets[0], address(collateralAsset));
    assertEq(assets[1], address(collateralAsset2));
  }

  function test_registerCollateralAsset_whenCallerIsNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert();
    reserve.registerCollateralAsset(address(collateralAsset2));
  }

  function test_registerCollateralAsset_whenAssetIsZeroAddress_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(IReserveV2.CollateralAssetZeroAddress.selector);
    reserve.registerCollateralAsset(address(0));
  }

  function test_registerCollateralAsset_whenAssetAlreadyRegistered_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(IReserveV2.CollateralAssetAlreadyRegistered.selector);
    reserve.registerCollateralAsset(address(collateralAsset));
  }

  function test_unregisterCollateralAsset_shouldUpdateStorageEmitEventAndUpdateArray() public {
    // Add second asset first
    vm.prank(owner);
    reserve.registerCollateralAsset(address(collateralAsset2));

    vm.expectEmit(true, true, true, true);
    emit CollateralAssetUnregistered(address(collateralAsset));

    vm.prank(owner);
    reserve.unregisterCollateralAsset(address(collateralAsset));

    // Verify mapping
    assertFalse(reserve.isCollateralAsset(address(collateralAsset)));
    assertTrue(reserve.isCollateralAsset(address(collateralAsset2)));

    // Verify array
    address[] memory assets = reserve.getCollateralAssets();
    assertEq(assets.length, 1);
    assertEq(assets[0], address(collateralAsset2));
  }

  function test_unregisterCollateralAsset_whenCallerIsNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert();
    reserve.unregisterCollateralAsset(address(collateralAsset));
  }

  function test_unregisterCollateralAsset_whenAssetNotRegistered_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(IReserveV2.CollateralAssetNotRegistered.selector);
    reserve.unregisterCollateralAsset(address(collateralAsset2));
  }

  /* ============================================================ */
  /* ========== Other Reserve Address Management Tests ========== */
  /* ============================================================ */

  function test_registerOtherReserveAddress_shouldUpdateStorageEmitEventAndUpdateArray() public {
    address newReserveAddress = makeAddr("newReserveAddress");

    vm.expectEmit(true, true, true, true);
    emit OtherReserveAddressRegistered(newReserveAddress);

    vm.prank(owner);
    reserve.registerOtherReserveAddress(newReserveAddress);

    // Verify mapping
    assertTrue(reserve.isOtherReserveAddress(newReserveAddress));

    // Verify array
    address[] memory addresses = reserve.getOtherReserveAddresses();
    assertEq(addresses.length, 2);
    assertEq(addresses[0], otherReserveAddress);
    assertEq(addresses[1], newReserveAddress);
  }

  function test_registerOtherReserveAddress_whenCallerIsNotOwner_shouldRevert() public {
    address newReserveAddress = makeAddr("newReserveAddress");
    vm.prank(notOwner);
    vm.expectRevert();
    reserve.registerOtherReserveAddress(newReserveAddress);
  }

  function test_registerOtherReserveAddress_whenAddressIsZero_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(IReserveV2.OtherReserveAddressZeroAddress.selector);
    reserve.registerOtherReserveAddress(address(0));
  }

  function test_registerOtherReserveAddress_whenAddressAlreadyRegistered_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(IReserveV2.OtherReserveAddressAlreadyRegistered.selector);
    reserve.registerOtherReserveAddress(otherReserveAddress);
  }

  function test_unregisterOtherReserveAddress_shouldUpdateStorageEmitEventAndUpdateArray() public {
    address newReserveAddress = makeAddr("newReserveAddress");
    vm.prank(owner);
    reserve.registerOtherReserveAddress(newReserveAddress);

    vm.expectEmit(true, true, true, true);
    emit OtherReserveAddressUnregistered(otherReserveAddress);

    vm.prank(owner);
    reserve.unregisterOtherReserveAddress(otherReserveAddress);

    // Verify mapping
    assertFalse(reserve.isOtherReserveAddress(otherReserveAddress));
    assertTrue(reserve.isOtherReserveAddress(newReserveAddress));

    // Verify array
    address[] memory addresses = reserve.getOtherReserveAddresses();
    assertEq(addresses.length, 1);
    assertEq(addresses[0], newReserveAddress);
  }

  function test_unregisterOtherReserveAddress_whenCallerIsNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert();
    reserve.unregisterOtherReserveAddress(otherReserveAddress);
  }

  function test_unregisterOtherReserveAddress_whenAddressNotRegistered_shouldRevert() public {
    address newAddress = makeAddr("newAddress");
    vm.prank(owner);
    vm.expectRevert(IReserveV2.OtherReserveAddressNotRegistered.selector);
    reserve.unregisterOtherReserveAddress(newAddress);
  }

  /* ============================================================ */
  /* ======== Liquidity Strategy Spender Management Tests ======= */
  /* ============================================================ */

  function test_registerLiquidityStrategySpender_shouldUpdateStorageEmitEventAndUpdateArray() public {
    address newLiquidityStrategySpender = makeAddr("newLiquidityStrategySpender");

    vm.expectEmit(true, true, true, true);
    emit LiquidityStrategySpenderRegistered(newLiquidityStrategySpender);

    vm.prank(owner);
    reserve.registerLiquidityStrategySpender(newLiquidityStrategySpender);

    // Verify mapping
    assertTrue(reserve.isLiquidityStrategySpender(newLiquidityStrategySpender));

    // Verify array
    address[] memory spenders = reserve.getLiquidityStrategySpenders();
    assertEq(spenders.length, 2);
    assertEq(spenders[0], liquidityStrategySpender);
    assertEq(spenders[1], newLiquidityStrategySpender);
  }

  function test_registerLiquidityStrategySpender_whenCallerIsNotOwner_shouldRevert() public {
    address newLiquidityStrategySpender = makeAddr("newLiquidityStrategySpender");
    vm.prank(notOwner);
    vm.expectRevert();
    reserve.registerLiquidityStrategySpender(newLiquidityStrategySpender);
  }

  function test_registerLiquidityStrategySpender_whenAddressIsZero_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(IReserveV2.LiquidityStrategySpenderZeroAddress.selector);
    reserve.registerLiquidityStrategySpender(address(0));
  }

  function test_registerLiquidityStrategySpender_whenSpenderAlreadyRegistered_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(IReserveV2.LiquidityStrategySpenderAlreadyRegistered.selector);
    reserve.registerLiquidityStrategySpender(liquidityStrategySpender);
  }

  function test_unregisterLiquidityStrategySpender_shouldUpdateStorageEmitEventAndUpdateArray() public {
    address newLiquidityStrategySpender = makeAddr("newLiquidityStrategySpender");
    vm.prank(owner);
    reserve.registerLiquidityStrategySpender(newLiquidityStrategySpender);

    vm.expectEmit(true, true, true, true);
    emit LiquidityStrategySpenderUnregistered(liquidityStrategySpender);

    vm.prank(owner);
    reserve.unregisterLiquidityStrategySpender(liquidityStrategySpender);

    // Verify mapping
    assertFalse(reserve.isLiquidityStrategySpender(liquidityStrategySpender));
    assertTrue(reserve.isLiquidityStrategySpender(newLiquidityStrategySpender));

    // Verify array
    address[] memory spenders = reserve.getLiquidityStrategySpenders();
    assertEq(spenders.length, 1);
    assertEq(spenders[0], newLiquidityStrategySpender);
  }

  function test_unregisterLiquidityStrategySpender_whenCallerIsNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert();
    reserve.unregisterLiquidityStrategySpender(liquidityStrategySpender);
  }

  function test_unregisterLiquidityStrategySpender_whenSpenderNotRegistered_shouldRevert() public {
    address newSpender = makeAddr("newSpender");
    vm.prank(owner);
    vm.expectRevert(IReserveV2.LiquidityStrategySpenderNotRegistered.selector);
    reserve.unregisterLiquidityStrategySpender(newSpender);
  }

  /* ============================================================ */
  /* ======== Reserve Manager Spender Management Tests ========== */
  /* ============================================================ */

  function test_registerReserveManagerSpender_shouldUpdateStorageEmitEventAndUpdateArray() public {
    vm.expectEmit(true, true, true, true);
    emit ReserveManagerSpenderRegistered(reserveManagerSpender);

    vm.prank(owner);
    reserve.registerReserveManagerSpender(reserveManagerSpender);

    // Verify mapping
    assertTrue(reserve.isReserveManagerSpender(reserveManagerSpender));

    // Verify array
    address[] memory spenders = reserve.getReserveManagerSpenders();
    assertEq(spenders.length, 1);
    assertEq(spenders[0], reserveManagerSpender);
  }

  function test_registerReserveManagerSpender_whenCallerIsNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert();
    reserve.registerReserveManagerSpender(reserveManagerSpender);
  }

  function test_registerReserveManagerSpender_whenAddressIsZero_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(IReserveV2.ReserveManagerSpenderZeroAddress.selector);
    reserve.registerReserveManagerSpender(address(0));
  }

  function test_registerReserveManagerSpender_whenSpenderAlreadyRegistered_shouldRevert() public {
    vm.prank(owner);
    reserve.registerReserveManagerSpender(reserveManagerSpender);

    vm.prank(owner);
    vm.expectRevert(IReserveV2.ReserveManagerSpenderAlreadyRegistered.selector);
    reserve.registerReserveManagerSpender(reserveManagerSpender);
  }

  function test_unregisterReserveManagerSpender_shouldUpdateStorageEmitEventAndUpdateArray() public {
    address reserveManagerSpender2 = makeAddr("reserveManagerSpender2");
    vm.startPrank(owner);
    reserve.registerReserveManagerSpender(reserveManagerSpender);
    reserve.registerReserveManagerSpender(reserveManagerSpender2);
    vm.stopPrank();

    vm.expectEmit(true, true, true, true);
    emit ReserveManagerSpenderUnregistered(reserveManagerSpender);

    vm.prank(owner);
    reserve.unregisterReserveManagerSpender(reserveManagerSpender);

    // Verify mapping
    assertFalse(reserve.isReserveManagerSpender(reserveManagerSpender));
    assertTrue(reserve.isReserveManagerSpender(reserveManagerSpender2));

    // Verify array
    address[] memory spenders = reserve.getReserveManagerSpenders();
    assertEq(spenders.length, 1);
    assertEq(spenders[0], reserveManagerSpender2);
  }

  function test_unregisterReserveManagerSpender_whenCallerIsNotOwner_shouldRevert() public {
    vm.prank(owner);
    reserve.registerReserveManagerSpender(reserveManagerSpender);

    vm.prank(notOwner);
    vm.expectRevert();
    reserve.unregisterReserveManagerSpender(reserveManagerSpender);
  }

  function test_unregisterReserveManagerSpender_whenSpenderNotRegistered_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(IReserveV2.ReserveManagerSpenderNotRegistered.selector);
    reserve.unregisterReserveManagerSpender(reserveManagerSpender);
  }

  /* ============================================================ */
  /* =================== Transfer Tests ========================= */
  /* ============================================================ */

  function test_transferCollateralAssetToOtherReserve_shouldUpdateBalancesAndEmitEvent() public {
    vm.prank(owner);
    reserve.registerReserveManagerSpender(reserveManagerSpender);

    uint256 amount = 1000e18;
    collateralAsset.mint(address(reserve), amount);

    uint256 initialReserveBalance = collateralAsset.balanceOf(address(reserve));
    uint256 initialRecipientBalance = collateralAsset.balanceOf(otherReserveAddress);

    vm.expectEmit(true, true, true, true);
    emit CollateralAssetTransferredReserveManagerSpender(
      reserveManagerSpender,
      address(collateralAsset),
      otherReserveAddress,
      amount
    );

    vm.prank(reserveManagerSpender);
    bool success = reserve.transferCollateralAssetToOtherReserve(address(collateralAsset), otherReserveAddress, amount);

    // Verify return value
    assertTrue(success);

    // Verify balances
    assertEq(collateralAsset.balanceOf(address(reserve)), initialReserveBalance - amount);
    assertEq(collateralAsset.balanceOf(otherReserveAddress), initialRecipientBalance + amount);
  }

  function test_transferCollateralAssetToOtherReserve_whenCallerIsNotReserveManagerSpender_shouldRevert() public {
    uint256 amount = 1000e18;
    collateralAsset.mint(address(reserve), amount);

    vm.prank(notOwner);
    vm.expectRevert(IReserveV2.ReserveManagerSpenderNotRegistered.selector);
    reserve.transferCollateralAssetToOtherReserve(address(collateralAsset), otherReserveAddress, amount);
  }

  function test_transferCollateralAssetToOtherReserve_whenToIsNotOtherReserveAddress_shouldRevert() public {
    vm.prank(owner);
    reserve.registerReserveManagerSpender(reserveManagerSpender);

    uint256 amount = 1000e18;
    collateralAsset.mint(address(reserve), amount);

    address randomAddress = makeAddr("randomAddress");

    vm.prank(reserveManagerSpender);
    vm.expectRevert(IReserveV2.OtherReserveAddressNotRegistered.selector);
    reserve.transferCollateralAssetToOtherReserve(address(collateralAsset), randomAddress, amount);
  }

  function test_transferCollateralAssetToOtherReserve_whenCollateralAssetNotRegistered_shouldRevert() public {
    vm.prank(owner);
    reserve.registerReserveManagerSpender(reserveManagerSpender);

    MockERC20 unregisteredAsset = new MockERC20("Unregistered", "UNR", 18);
    uint256 amount = 1000e18;
    unregisteredAsset.mint(address(reserve), amount);

    vm.prank(reserveManagerSpender);
    vm.expectRevert(IReserveV2.CollateralAssetNotRegistered.selector);
    reserve.transferCollateralAssetToOtherReserve(address(unregisteredAsset), otherReserveAddress, amount);
  }

  function test_transferCollateralAssetToOtherReserve_whenInsufficientBalance_shouldRevert() public {
    vm.prank(owner);
    reserve.registerReserveManagerSpender(reserveManagerSpender);

    uint256 amount = 1000e18;

    vm.prank(reserveManagerSpender);
    vm.expectRevert(IReserveV2.InsufficientReserveBalance.selector);
    reserve.transferCollateralAssetToOtherReserve(address(collateralAsset), otherReserveAddress, amount);
  }

  function test_transferCollateralAsset_shouldUpdateBalancesAndEmitEvent() public {
    uint256 amount = 1000e18;
    collateralAsset.mint(address(reserve), amount);

    address recipient = makeAddr("recipient");
    uint256 initialReserveBalance = collateralAsset.balanceOf(address(reserve));
    uint256 initialRecipientBalance = collateralAsset.balanceOf(recipient);

    vm.expectEmit(true, true, true, true);
    emit CollateralAssetTransferredLiquidityStrategySpender(
      liquidityStrategySpender,
      address(collateralAsset),
      recipient,
      amount
    );

    vm.prank(liquidityStrategySpender);
    bool success = reserve.transferCollateralAsset(address(collateralAsset), recipient, amount);

    // Verify return value
    assertTrue(success);

    // Verify balances
    assertEq(collateralAsset.balanceOf(address(reserve)), initialReserveBalance - amount);
    assertEq(collateralAsset.balanceOf(recipient), initialRecipientBalance + amount);
  }

  function test_transferCollateralAsset_whenCallerIsNotLiquidityStrategySpender_shouldRevert() public {
    uint256 amount = 1000e18;
    collateralAsset.mint(address(reserve), amount);

    address recipient = makeAddr("recipient");

    vm.prank(notOwner);
    vm.expectRevert(IReserveV2.LiquidityStrategySpenderNotRegistered.selector);
    reserve.transferCollateralAsset(address(collateralAsset), recipient, amount);
  }

  function test_transferCollateralAsset_whenCollateralAssetNotRegistered_shouldRevert() public {
    MockERC20 unregisteredAsset = new MockERC20("Unregistered", "UNR", 18);
    uint256 amount = 1000e18;
    unregisteredAsset.mint(address(reserve), amount);

    address recipient = makeAddr("recipient");

    vm.prank(liquidityStrategySpender);
    vm.expectRevert(IReserveV2.CollateralAssetNotRegistered.selector);
    reserve.transferCollateralAsset(address(unregisteredAsset), recipient, amount);
  }

  function test_transferCollateralAsset_whenInsufficientBalance_shouldRevert() public {
    uint256 amount = 1000e18;
    address recipient = makeAddr("recipient");

    vm.prank(liquidityStrategySpender);
    vm.expectRevert(IReserveV2.InsufficientReserveBalance.selector);
    reserve.transferCollateralAsset(address(collateralAsset), recipient, amount);
  }

  /* ============================================================ */
  /* ============= TransparentUpgradeableProxy Tests ============ */
  /* ============================================================ */

  function test_proxy_shouldInitializeCorrectly() public {
    // Deploy proxy admin
    proxyAdmin = new ProxyAdmin();
    vm.prank(proxyAdmin.owner());
    proxyAdmin.transferOwnership(owner);

    // Prepare initialization data
    address[] memory stableAssets = new address[](1);
    stableAssets[0] = address(stableAsset);

    address[] memory collateralAssets = new address[](1);
    collateralAssets[0] = address(collateralAsset);

    address[] memory otherReserves = new address[](1);
    otherReserves[0] = otherReserveAddress;

    address[] memory liquidityStrategySpenders = new address[](1);
    liquidityStrategySpenders[0] = liquidityStrategySpender;

    address[] memory reserveManagerSpenders = new address[](0);

    bytes memory initData = abi.encodeWithSelector(
      ReserveV2.initialize.selector,
      stableAssets,
      collateralAssets,
      otherReserves,
      liquidityStrategySpenders,
      reserveManagerSpenders,
      owner
    );

    // Deploy proxy
    proxy = new TransparentUpgradeableProxy(address(reserveImplementation), address(proxyAdmin), initData);

    ReserveV2 proxyReserve = ReserveV2(payable(address(proxy)));

    // Verify initialization
    assertEq(proxyReserve.owner(), owner);
    assertTrue(proxyReserve.isStableAsset(address(stableAsset)));
    assertTrue(proxyReserve.isCollateralAsset(address(collateralAsset)));
    assertTrue(proxyReserve.isOtherReserveAddress(otherReserveAddress));
    assertTrue(proxyReserve.isLiquidityStrategySpender(liquidityStrategySpender));
  }

  function test_proxy_shouldAllowUpgrade() public {
    // Deploy proxy admin with owner
    proxyAdmin = new ProxyAdmin();
    vm.prank(proxyAdmin.owner());
    proxyAdmin.transferOwnership(owner);

    // Prepare initialization data
    address[] memory empty = new address[](0);

    bytes memory initData = abi.encodeWithSelector(
      ReserveV2.initialize.selector,
      empty,
      empty,
      empty,
      empty,
      empty,
      owner
    );

    // Deploy proxy
    proxy = new TransparentUpgradeableProxy(address(reserveImplementation), address(proxyAdmin), initData);

    ReserveV2 proxyReserve = ReserveV2(payable(address(proxy)));

    // Add an asset
    vm.prank(owner);
    proxyReserve.registerStableAsset(address(stableAsset));

    // Verify asset was added
    assertTrue(proxyReserve.isStableAsset(address(stableAsset)));

    // Deploy new implementation
    ReserveV2 newImplementation = new ReserveV2(true);

    // Upgrade proxy
    vm.prank(owner);
    proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(proxy)), address(newImplementation));

    // Verify state is preserved after upgrade
    assertTrue(proxyReserve.isStableAsset(address(stableAsset)));
  }

  function test_proxy_shouldWorkWithAllFunctions() public {
    // Deploy proxy admin
    proxyAdmin = new ProxyAdmin();
    vm.prank(proxyAdmin.owner());
    proxyAdmin.transferOwnership(owner);

    // Prepare initialization data
    address[] memory stableAssets = new address[](1);
    stableAssets[0] = address(stableAsset);

    address[] memory collateralAssets = new address[](1);
    collateralAssets[0] = address(collateralAsset);

    address[] memory otherReserves = new address[](1);
    otherReserves[0] = otherReserveAddress;

    address[] memory liquidityStrategySpenders = new address[](1);
    liquidityStrategySpenders[0] = liquidityStrategySpender;

    address[] memory reserveManagerSpenders = new address[](0);

    bytes memory initData = abi.encodeWithSelector(
      ReserveV2.initialize.selector,
      stableAssets,
      collateralAssets,
      otherReserves,
      liquidityStrategySpenders,
      reserveManagerSpenders,
      owner
    );

    // Deploy proxy
    proxy = new TransparentUpgradeableProxy(address(reserveImplementation), address(proxyAdmin), initData);

    ReserveV2 proxyReserve = ReserveV2(payable(address(proxy)));

    // Test register/unregister stable asset
    vm.startPrank(owner);
    proxyReserve.registerStableAsset(address(stableAsset2));
    assertTrue(proxyReserve.isStableAsset(address(stableAsset2)));

    proxyReserve.unregisterStableAsset(address(stableAsset2));
    assertFalse(proxyReserve.isStableAsset(address(stableAsset2)));

    // Test register/unregister collateral asset
    proxyReserve.registerCollateralAsset(address(collateralAsset2));
    assertTrue(proxyReserve.isCollateralAsset(address(collateralAsset2)));

    proxyReserve.unregisterCollateralAsset(address(collateralAsset2));
    assertFalse(proxyReserve.isCollateralAsset(address(collateralAsset2)));

    // Test register/unregister reserve manager spender
    proxyReserve.registerReserveManagerSpender(reserveManagerSpender);
    assertTrue(proxyReserve.isReserveManagerSpender(reserveManagerSpender));

    vm.stopPrank();

    // Test transfer with proxy
    uint256 amount = 1000e18;
    collateralAsset.mint(address(proxyReserve), amount);

    vm.prank(reserveManagerSpender);
    bool success = proxyReserve.transferCollateralAssetToOtherReserve(
      address(collateralAsset),
      otherReserveAddress,
      amount
    );

    assertTrue(success);
    assertEq(collateralAsset.balanceOf(otherReserveAddress), amount);
  }

  function test_proxy_implementationShouldNotBeInitializable() public {
    // The implementation contract was deployed with disable=true
    address[] memory empty = new address[](0);

    vm.expectRevert();
    reserveImplementation.initialize(empty, empty, empty, empty, empty, owner);
  }
}
