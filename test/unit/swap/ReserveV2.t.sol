// SPDX-License-Identifier: GPL-3.0-or-later
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

  MockERC20 public collateralToken;
  MockERC20 public collateralToken2;
  MockERC20 public stableToken;
  MockERC20 public stableToken2;

  address public owner;
  address public notOwner;
  address public spender;
  address public exchangeSpender;
  address public otherReserveAddress;

  /* ---------------- Events from ReserveV2 --------------- */

  event StableTokenAdded(address indexed token);
  event StableTokenRemoved(address indexed token);
  event CollateralTokenAdded(address indexed token);
  event CollateralTokenRemoved(address indexed token);
  event OtherReserveAddressAdded(address indexed otherReserveAddress);
  event OtherReserveAddressRemoved(address indexed otherReserveAddress);
  event ExchangeSpenderAdded(address indexed exchangeSpender);
  event ExchangeSpenderRemoved(address indexed exchangeSpender);
  event SpenderAdded(address indexed spender);
  event SpenderRemoved(address indexed spender);
  event CollateralAssetTransferredSpender(
    address indexed spender,
    address indexed collateralAsset,
    address indexed to,
    uint256 value
  );
  event CollateralAssetTransferredExchangeSpender(
    address indexed exchangeSpender,
    address indexed collateralAsset,
    address indexed to,
    uint256 value
  );

  /* ----------------------------------------------------- */

  function setUp() public {
    owner = makeAddr("owner");
    notOwner = makeAddr("notOwner");
    spender = makeAddr("spender");
    exchangeSpender = makeAddr("exchangeSpender");
    otherReserveAddress = makeAddr("otherReserveAddress");

    collateralToken = new MockERC20("Collateral Token", "CT", 18);
    collateralToken2 = new MockERC20("Collateral Token 2", "CT2", 18);
    stableToken = new MockERC20("Stable Token", "ST", 18);
    stableToken2 = new MockERC20("Stable Token 2", "ST2", 18);

    reserveImplementation = new ReserveV2(true);
    reserve = new ReserveV2(false);

    address[] memory stableTokens = new address[](1);
    stableTokens[0] = address(stableToken);

    address[] memory collateralTokens = new address[](1);
    collateralTokens[0] = address(collateralToken);

    address[] memory otherReserveAddresses = new address[](1);
    otherReserveAddresses[0] = otherReserveAddress;

    address[] memory exchangeSpenders = new address[](1);
    exchangeSpenders[0] = exchangeSpender;

    address[] memory spenders = new address[](0);

    reserve.initialize(stableTokens, collateralTokens, otherReserveAddresses, exchangeSpenders, spenders, owner);
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

    address[] memory stableTokens = new address[](2);
    stableTokens[0] = address(stableToken);
    stableTokens[1] = address(stableToken2);

    address[] memory collateralTokens = new address[](2);
    collateralTokens[0] = address(collateralToken);
    collateralTokens[1] = address(collateralToken2);

    address otherReserve2 = makeAddr("otherReserve2");
    address[] memory otherReserves = new address[](2);
    otherReserves[0] = otherReserveAddress;
    otherReserves[1] = otherReserve2;

    address exchangeSpender2 = makeAddr("exchangeSpender2");
    address[] memory exchangeSpenders = new address[](2);
    exchangeSpenders[0] = exchangeSpender;
    exchangeSpenders[1] = exchangeSpender2;

    address spender2 = makeAddr("spender2");
    address[] memory spenders = new address[](2);
    spenders[0] = spender;
    spenders[1] = spender2;

    // Expect all events
    vm.expectEmit(true, true, true, true);
    emit StableTokenAdded(address(stableToken));
    vm.expectEmit(true, true, true, true);
    emit StableTokenAdded(address(stableToken2));
    vm.expectEmit(true, true, true, true);
    emit CollateralTokenAdded(address(collateralToken));
    vm.expectEmit(true, true, true, true);
    emit CollateralTokenAdded(address(collateralToken2));
    vm.expectEmit(true, true, true, true);
    emit OtherReserveAddressAdded(otherReserveAddress);
    vm.expectEmit(true, true, true, true);
    emit OtherReserveAddressAdded(otherReserve2);
    vm.expectEmit(true, true, true, true);
    emit ExchangeSpenderAdded(exchangeSpender);
    vm.expectEmit(true, true, true, true);
    emit ExchangeSpenderAdded(exchangeSpender2);
    vm.expectEmit(true, true, true, true);
    emit SpenderAdded(spender);
    vm.expectEmit(true, true, true, true);
    emit SpenderAdded(spender2);

    newReserve.initialize(stableTokens, collateralTokens, otherReserves, exchangeSpenders, spenders, owner);

    // Verify owner
    assertEq(newReserve.owner(), owner);

    // Verify mappings
    assertTrue(newReserve.isStableToken(address(stableToken)));
    assertTrue(newReserve.isStableToken(address(stableToken2)));
    assertTrue(newReserve.isCollateralToken(address(collateralToken)));
    assertTrue(newReserve.isCollateralToken(address(collateralToken2)));
    assertTrue(newReserve.isOtherReserveAddress(otherReserveAddress));
    assertTrue(newReserve.isOtherReserveAddress(otherReserve2));
    assertTrue(newReserve.isExchangeSpender(exchangeSpender));
    assertTrue(newReserve.isExchangeSpender(exchangeSpender2));
    assertTrue(newReserve.isSpender(spender));
    assertTrue(newReserve.isSpender(spender2));

    // Verify arrays (via public getters)
    assertEq(newReserve.stableTokens(0), address(stableToken));
    assertEq(newReserve.stableTokens(1), address(stableToken2));
    assertEq(newReserve.collateralTokens(0), address(collateralToken));
    assertEq(newReserve.collateralTokens(1), address(collateralToken2));
    assertEq(newReserve.otherReserveAddresses(0), otherReserveAddress);
    assertEq(newReserve.otherReserveAddresses(1), otherReserve2);
    assertEq(newReserve.exchangeSpenders(0), exchangeSpender);
    assertEq(newReserve.exchangeSpenders(1), exchangeSpender2);
    assertEq(newReserve.spenders(0), spender);
    assertEq(newReserve.spenders(1), spender2);
  }

  function test_initialize_whenCalledTwice_shouldRevert() public {
    address[] memory empty = new address[](0);
    vm.expectRevert();
    reserve.initialize(empty, empty, empty, empty, empty, owner);
  }

  /* ============================================================ */
  /* ============== Stable Token Management Tests =============== */
  /* ============================================================ */

  function test_addStableToken_shouldUpdateStorageEmitEventAndUpdateArray() public {
    vm.expectEmit(true, true, true, true);
    emit StableTokenAdded(address(stableToken2));

    vm.prank(owner);
    reserve.addStableToken(address(stableToken2));

    // Verify mapping
    assertTrue(reserve.isStableToken(address(stableToken2)));

    // Verify array
    address[] memory tokens = reserve.getStableTokens();
    assertEq(tokens[0], address(stableToken));
    assertEq(tokens[1], address(stableToken2));
  }

  function test_addStableToken_whenCallerIsNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert();
    reserve.addStableToken(address(stableToken2));
  }

  function test_addStableToken_whenTokenIsZeroAddress_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(IReserveV2.StableTokenZeroAddress.selector);
    reserve.addStableToken(address(0));
  }

  function test_addStableToken_whenTokenAlreadyAdded_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(IReserveV2.StableTokenAlreadyAdded.selector);
    reserve.addStableToken(address(stableToken));
  }

  function test_removeStableToken_shouldUpdateStorageEmitEventAndUpdateArray() public {
    // Add second token first
    vm.prank(owner);
    reserve.addStableToken(address(stableToken2));

    vm.expectEmit(true, true, true, true);
    emit StableTokenRemoved(address(stableToken));

    vm.prank(owner);
    reserve.removeStableToken(address(stableToken));

    // Verify mapping
    assertFalse(reserve.isStableToken(address(stableToken)));
    assertTrue(reserve.isStableToken(address(stableToken2)));

    // Verify array
    address[] memory tokens = reserve.getStableTokens();
    assertEq(tokens.length, 1);
    assertEq(tokens[0], address(stableToken2));
  }

  function test_removeStableToken_whenCallerIsNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert();
    reserve.removeStableToken(address(stableToken));
  }

  function test_removeStableToken_whenTokenNotAdded_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(IReserveV2.StableTokenNotAdded.selector);
    reserve.removeStableToken(address(stableToken2));
  }

  /* ============================================================ */
  /* ============ Collateral Token Management Tests ============= */
  /* ============================================================ */

  function test_addCollateralToken_shouldUpdateStorageEmitEventAndUpdateArray() public {
    vm.expectEmit(true, true, true, true);
    emit CollateralTokenAdded(address(collateralToken2));

    vm.prank(owner);
    reserve.addCollateralToken(address(collateralToken2));

    // Verify mapping
    assertTrue(reserve.isCollateralToken(address(collateralToken2)));

    // Verify array
    address[] memory tokens = reserve.getCollateralTokens();
    assertEq(tokens.length, 2);
    assertEq(tokens[0], address(collateralToken));
    assertEq(tokens[1], address(collateralToken2));
  }

  function test_addCollateralToken_whenCallerIsNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert();
    reserve.addCollateralToken(address(collateralToken2));
  }

  function test_addCollateralToken_whenTokenIsZeroAddress_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(IReserveV2.CollateralTokenZeroAddress.selector);
    reserve.addCollateralToken(address(0));
  }

  function test_addCollateralToken_whenTokenAlreadyAdded_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(IReserveV2.CollateralTokenAlreadyAdded.selector);
    reserve.addCollateralToken(address(collateralToken));
  }

  function test_removeCollateralToken_shouldUpdateStorageEmitEventAndUpdateArray() public {
    // Add second token first
    vm.prank(owner);
    reserve.addCollateralToken(address(collateralToken2));

    vm.expectEmit(true, true, true, true);
    emit CollateralTokenRemoved(address(collateralToken));

    vm.prank(owner);
    reserve.removeCollateralToken(address(collateralToken));

    // Verify mapping
    assertFalse(reserve.isCollateralToken(address(collateralToken)));
    assertTrue(reserve.isCollateralToken(address(collateralToken2)));

    // Verify array
    address[] memory tokens = reserve.getCollateralTokens();
    assertEq(tokens.length, 1);
    assertEq(tokens[0], address(collateralToken2));
  }

  function test_removeCollateralToken_whenCallerIsNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert();
    reserve.removeCollateralToken(address(collateralToken));
  }

  function test_removeCollateralToken_whenTokenNotAdded_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(IReserveV2.CollateralTokenNotRegistered.selector);
    reserve.removeCollateralToken(address(collateralToken2));
  }

  /* ============================================================ */
  /* ========== Other Reserve Address Management Tests ========== */
  /* ============================================================ */

  function test_addOtherReserveAddress_shouldUpdateStorageEmitEventAndUpdateArray() public {
    address newReserveAddress = makeAddr("newReserveAddress");

    vm.expectEmit(true, true, true, true);
    emit OtherReserveAddressAdded(newReserveAddress);

    vm.prank(owner);
    reserve.addOtherReserveAddress(newReserveAddress);

    // Verify mapping
    assertTrue(reserve.isOtherReserveAddress(newReserveAddress));

    // Verify array
    address[] memory addresses = reserve.getOtherReserveAddresses();
    assertEq(addresses.length, 2);
    assertEq(addresses[0], otherReserveAddress);
    assertEq(addresses[1], newReserveAddress);
  }

  function test_addOtherReserveAddress_whenCallerIsNotOwner_shouldRevert() public {
    address newReserveAddress = makeAddr("newReserveAddress");
    vm.prank(notOwner);
    vm.expectRevert();
    reserve.addOtherReserveAddress(newReserveAddress);
  }

  function test_addOtherReserveAddress_whenAddressIsZero_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(IReserveV2.OtherReserveAddressZeroAddress.selector);
    reserve.addOtherReserveAddress(address(0));
  }

  function test_addOtherReserveAddress_whenAddressAlreadyAdded_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(IReserveV2.OtherReserveAddressAlreadyAdded.selector);
    reserve.addOtherReserveAddress(otherReserveAddress);
  }

  function test_removeOtherReserveAddress_shouldUpdateStorageEmitEventAndUpdateArray() public {
    address newReserveAddress = makeAddr("newReserveAddress");
    vm.prank(owner);
    reserve.addOtherReserveAddress(newReserveAddress);

    vm.expectEmit(true, true, true, true);
    emit OtherReserveAddressRemoved(otherReserveAddress);

    vm.prank(owner);
    reserve.removeOtherReserveAddress(otherReserveAddress);

    // Verify mapping
    assertFalse(reserve.isOtherReserveAddress(otherReserveAddress));
    assertTrue(reserve.isOtherReserveAddress(newReserveAddress));

    // Verify array
    address[] memory addresses = reserve.getOtherReserveAddresses();
    assertEq(addresses.length, 1);
    assertEq(addresses[0], newReserveAddress);
  }

  function test_removeOtherReserveAddress_whenCallerIsNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert();
    reserve.removeOtherReserveAddress(otherReserveAddress);
  }

  function test_removeOtherReserveAddress_whenAddressNotAdded_shouldRevert() public {
    address newAddress = makeAddr("newAddress");
    vm.prank(owner);
    vm.expectRevert(IReserveV2.OtherReserveAddressNotRegistered.selector);
    reserve.removeOtherReserveAddress(newAddress);
  }

  /* ============================================================ */
  /* ============ Exchange Spender Management Tests ============= */
  /* ============================================================ */

  function test_addExchangeSpender_shouldUpdateStorageEmitEventAndUpdateArray() public {
    address newExchangeSpender = makeAddr("newExchangeSpender");

    vm.expectEmit(true, true, true, true);
    emit ExchangeSpenderAdded(newExchangeSpender);

    vm.prank(owner);
    reserve.addExchangeSpender(newExchangeSpender);

    // Verify mapping
    assertTrue(reserve.isExchangeSpender(newExchangeSpender));

    // Verify array
    address[] memory spenders = reserve.getExchangeSpenders();
    assertEq(spenders.length, 2);
    assertEq(spenders[0], exchangeSpender);
    assertEq(spenders[1], newExchangeSpender);
  }

  function test_addExchangeSpender_whenCallerIsNotOwner_shouldRevert() public {
    address newExchangeSpender = makeAddr("newExchangeSpender");
    vm.prank(notOwner);
    vm.expectRevert();
    reserve.addExchangeSpender(newExchangeSpender);
  }

  function test_addExchangeSpender_whenAddressIsZero_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(IReserveV2.ExchangeSpenderZeroAddress.selector);
    reserve.addExchangeSpender(address(0));
  }

  function test_addExchangeSpender_whenSpenderAlreadyAdded_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(IReserveV2.ExchangeSpenderAlreadyAdded.selector);
    reserve.addExchangeSpender(exchangeSpender);
  }

  function test_removeExchangeSpender_shouldUpdateStorageEmitEventAndUpdateArray() public {
    address newExchangeSpender = makeAddr("newExchangeSpender");
    vm.prank(owner);
    reserve.addExchangeSpender(newExchangeSpender);

    vm.expectEmit(true, true, true, true);
    emit ExchangeSpenderRemoved(exchangeSpender);

    vm.prank(owner);
    reserve.removeExchangeSpender(exchangeSpender);

    // Verify mapping
    assertFalse(reserve.isExchangeSpender(exchangeSpender));
    assertTrue(reserve.isExchangeSpender(newExchangeSpender));

    // Verify array
    address[] memory spenders = reserve.getExchangeSpenders();
    assertEq(spenders.length, 1);
    assertEq(spenders[0], newExchangeSpender);
  }

  function test_removeExchangeSpender_whenCallerIsNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert();
    reserve.removeExchangeSpender(exchangeSpender);
  }

  function test_removeExchangeSpender_whenSpenderNotAdded_shouldRevert() public {
    address newSpender = makeAddr("newSpender");
    vm.prank(owner);
    vm.expectRevert(IReserveV2.ExchangeSpenderNotRegistered.selector);
    reserve.removeExchangeSpender(newSpender);
  }

  /* ============================================================ */
  /* ================ Spender Management Tests ================== */
  /* ============================================================ */

  function test_addSpender_shouldUpdateStorageEmitEventAndUpdateArray() public {
    vm.expectEmit(true, true, true, true);
    emit SpenderAdded(spender);

    vm.prank(owner);
    reserve.addSpender(spender);

    // Verify mapping
    assertTrue(reserve.isSpender(spender));

    // Verify array
    address[] memory spenders = reserve.getSpenders();
    assertEq(spenders.length, 1);
    assertEq(spenders[0], spender);
  }

  function test_addSpender_whenCallerIsNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert();
    reserve.addSpender(spender);
  }

  function test_addSpender_whenAddressIsZero_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(IReserveV2.SpenderZeroAddress.selector);
    reserve.addSpender(address(0));
  }

  function test_addSpender_whenSpenderAlreadyAdded_shouldRevert() public {
    vm.prank(owner);
    reserve.addSpender(spender);

    vm.prank(owner);
    vm.expectRevert(IReserveV2.SpenderAlreadyAdded.selector);
    reserve.addSpender(spender);
  }

  function test_removeSpender_shouldUpdateStorageEmitEventAndUpdateArray() public {
    address spender2 = makeAddr("spender2");
    vm.startPrank(owner);
    reserve.addSpender(spender);
    reserve.addSpender(spender2);
    vm.stopPrank();

    vm.expectEmit(true, true, true, true);
    emit SpenderRemoved(spender);

    vm.prank(owner);
    reserve.removeSpender(spender);

    // Verify mapping
    assertFalse(reserve.isSpender(spender));
    assertTrue(reserve.isSpender(spender2));

    // Verify array
    address[] memory spenders = reserve.getSpenders();
    assertEq(spenders.length, 1);
    assertEq(spenders[0], spender2);
  }

  function test_removeSpender_whenCallerIsNotOwner_shouldRevert() public {
    vm.prank(owner);
    reserve.addSpender(spender);

    vm.prank(notOwner);
    vm.expectRevert();
    reserve.removeSpender(spender);
  }

  function test_removeSpender_whenSpenderNotAdded_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(IReserveV2.SpenderNotRegistered.selector);
    reserve.removeSpender(spender);
  }

  /* ============================================================ */
  /* =================== Transfer Tests ========================= */
  /* ============================================================ */

  function test_transferCollateralAsset_shouldUpdateBalancesAndEmitEvent() public {
    vm.prank(owner);
    reserve.addSpender(spender);

    uint256 amount = 1000e18;
    collateralToken.mint(address(reserve), amount);

    uint256 initialReserveBalance = collateralToken.balanceOf(address(reserve));
    uint256 initialRecipientBalance = collateralToken.balanceOf(otherReserveAddress);

    vm.expectEmit(true, true, true, true);
    emit CollateralAssetTransferredSpender(spender, address(collateralToken), otherReserveAddress, amount);

    vm.prank(spender);
    bool success = reserve.transferCollateralAsset(otherReserveAddress, address(collateralToken), amount);

    // Verify return value
    assertTrue(success);

    // Verify balances
    assertEq(collateralToken.balanceOf(address(reserve)), initialReserveBalance - amount);
    assertEq(collateralToken.balanceOf(otherReserveAddress), initialRecipientBalance + amount);
  }

  function test_transferCollateralAsset_whenCallerIsNotSpender_shouldRevert() public {
    uint256 amount = 1000e18;
    collateralToken.mint(address(reserve), amount);

    vm.prank(notOwner);
    vm.expectRevert(IReserveV2.SpenderNotRegistered.selector);
    reserve.transferCollateralAsset(otherReserveAddress, address(collateralToken), amount);
  }

  function test_transferCollateralAsset_whenToIsNotOtherReserveAddress_shouldRevert() public {
    vm.prank(owner);
    reserve.addSpender(spender);

    uint256 amount = 1000e18;
    collateralToken.mint(address(reserve), amount);

    address randomAddress = makeAddr("randomAddress");

    vm.prank(spender);
    vm.expectRevert(IReserveV2.OtherReserveAddressNotRegistered.selector);
    reserve.transferCollateralAsset(randomAddress, address(collateralToken), amount);
  }

  function test_transferCollateralAsset_whenCollateralTokenNotRegistered_shouldRevert() public {
    vm.prank(owner);
    reserve.addSpender(spender);

    MockERC20 unregisteredToken = new MockERC20("Unregistered", "UNR", 18);
    uint256 amount = 1000e18;
    unregisteredToken.mint(address(reserve), amount);

    vm.prank(spender);
    vm.expectRevert(IReserveV2.CollateralTokenNotRegistered.selector);
    reserve.transferCollateralAsset(otherReserveAddress, address(unregisteredToken), amount);
  }

  function test_transferCollateralAsset_whenInsufficientBalance_shouldRevert() public {
    vm.prank(owner);
    reserve.addSpender(spender);

    uint256 amount = 1000e18;

    vm.prank(spender);
    vm.expectRevert(IReserveV2.InsufficientReserveBalance.selector);
    reserve.transferCollateralAsset(otherReserveAddress, address(collateralToken), amount);
  }

  function test_transferExchangeCollateralAsset_shouldUpdateBalancesAndEmitEvent() public {
    uint256 amount = 1000e18;
    collateralToken.mint(address(reserve), amount);

    address recipient = makeAddr("recipient");
    uint256 initialReserveBalance = collateralToken.balanceOf(address(reserve));
    uint256 initialRecipientBalance = collateralToken.balanceOf(recipient);

    vm.expectEmit(true, true, true, true);
    emit CollateralAssetTransferredExchangeSpender(exchangeSpender, address(collateralToken), recipient, amount);

    vm.prank(exchangeSpender);
    bool success = reserve.transferExchangeCollateralAsset(address(collateralToken), recipient, amount);

    // Verify return value
    assertTrue(success);

    // Verify balances
    assertEq(collateralToken.balanceOf(address(reserve)), initialReserveBalance - amount);
    assertEq(collateralToken.balanceOf(recipient), initialRecipientBalance + amount);
  }

  function test_transferExchangeCollateralAsset_whenCallerIsNotExchangeSpender_shouldRevert() public {
    uint256 amount = 1000e18;
    collateralToken.mint(address(reserve), amount);

    address recipient = makeAddr("recipient");

    vm.prank(notOwner);
    vm.expectRevert(IReserveV2.ExchangeSpenderNotRegistered.selector);
    reserve.transferExchangeCollateralAsset(address(collateralToken), recipient, amount);
  }

  function test_transferExchangeCollateralAsset_whenCollateralTokenNotRegistered_shouldRevert() public {
    MockERC20 unregisteredToken = new MockERC20("Unregistered", "UNR", 18);
    uint256 amount = 1000e18;
    unregisteredToken.mint(address(reserve), amount);

    address recipient = makeAddr("recipient");

    vm.prank(exchangeSpender);
    vm.expectRevert(IReserveV2.CollateralTokenNotRegistered.selector);
    reserve.transferExchangeCollateralAsset(address(unregisteredToken), recipient, amount);
  }

  function test_transferExchangeCollateralAsset_whenInsufficientBalance_shouldRevert() public {
    uint256 amount = 1000e18;
    address recipient = makeAddr("recipient");

    vm.prank(exchangeSpender);
    vm.expectRevert(IReserveV2.InsufficientReserveBalance.selector);
    reserve.transferExchangeCollateralAsset(address(collateralToken), recipient, amount);
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
    address[] memory stableTokens = new address[](1);
    stableTokens[0] = address(stableToken);

    address[] memory collateralTokens = new address[](1);
    collateralTokens[0] = address(collateralToken);

    address[] memory otherReserves = new address[](1);
    otherReserves[0] = otherReserveAddress;

    address[] memory exchangeSpenders = new address[](1);
    exchangeSpenders[0] = exchangeSpender;

    address[] memory spenders = new address[](0);

    bytes memory initData = abi.encodeWithSelector(
      ReserveV2.initialize.selector,
      stableTokens,
      collateralTokens,
      otherReserves,
      exchangeSpenders,
      spenders,
      owner
    );

    // Deploy proxy
    proxy = new TransparentUpgradeableProxy(address(reserveImplementation), address(proxyAdmin), initData);

    ReserveV2 proxyReserve = ReserveV2(payable(address(proxy)));

    // Verify initialization
    assertEq(proxyReserve.owner(), owner);
    assertTrue(proxyReserve.isStableToken(address(stableToken)));
    assertTrue(proxyReserve.isCollateralToken(address(collateralToken)));
    assertTrue(proxyReserve.isOtherReserveAddress(otherReserveAddress));
    assertTrue(proxyReserve.isExchangeSpender(exchangeSpender));
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

    // Add a token
    vm.prank(owner);
    proxyReserve.addStableToken(address(stableToken));

    // Verify token was added
    assertTrue(proxyReserve.isStableToken(address(stableToken)));

    // Deploy new implementation
    ReserveV2 newImplementation = new ReserveV2(true);

    // Upgrade proxy
    vm.prank(owner);
    proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(proxy)), address(newImplementation));

    // Verify state is preserved after upgrade
    assertTrue(proxyReserve.isStableToken(address(stableToken)));
  }

  function test_proxy_shouldWorkWithAllFunctions() public {
    // Deploy proxy admin
    proxyAdmin = new ProxyAdmin();
    vm.prank(proxyAdmin.owner());
    proxyAdmin.transferOwnership(owner);

    // Prepare initialization data
    address[] memory stableTokens = new address[](1);
    stableTokens[0] = address(stableToken);

    address[] memory collateralTokens = new address[](1);
    collateralTokens[0] = address(collateralToken);

    address[] memory otherReserves = new address[](1);
    otherReserves[0] = otherReserveAddress;

    address[] memory exchangeSpenders = new address[](1);
    exchangeSpenders[0] = exchangeSpender;

    address[] memory spenders = new address[](0);

    bytes memory initData = abi.encodeWithSelector(
      ReserveV2.initialize.selector,
      stableTokens,
      collateralTokens,
      otherReserves,
      exchangeSpenders,
      spenders,
      owner
    );

    // Deploy proxy
    proxy = new TransparentUpgradeableProxy(address(reserveImplementation), address(proxyAdmin), initData);

    ReserveV2 proxyReserve = ReserveV2(payable(address(proxy)));

    // Test add/remove stable token
    vm.startPrank(owner);
    proxyReserve.addStableToken(address(stableToken2));
    assertTrue(proxyReserve.isStableToken(address(stableToken2)));

    proxyReserve.removeStableToken(address(stableToken2));
    assertFalse(proxyReserve.isStableToken(address(stableToken2)));

    // Test add/remove collateral token
    proxyReserve.addCollateralToken(address(collateralToken2));
    assertTrue(proxyReserve.isCollateralToken(address(collateralToken2)));

    proxyReserve.removeCollateralToken(address(collateralToken2));
    assertFalse(proxyReserve.isCollateralToken(address(collateralToken2)));

    // Test add/remove spender
    proxyReserve.addSpender(spender);
    assertTrue(proxyReserve.isSpender(spender));

    vm.stopPrank();

    // Test transfer with proxy
    uint256 amount = 1000e18;
    collateralToken.mint(address(proxyReserve), amount);

    vm.prank(spender);
    bool success = proxyReserve.transferCollateralAsset(otherReserveAddress, address(collateralToken), amount);

    assertTrue(success);
    assertEq(collateralToken.balanceOf(otherReserveAddress), amount);
  }

  function test_proxy_implementationShouldNotBeInitializable() public {
    // The implementation contract was deployed with disable=true
    address[] memory empty = new address[](0);

    vm.expectRevert();
    reserveImplementation.initialize(empty, empty, empty, empty, empty, owner);
  }
}
