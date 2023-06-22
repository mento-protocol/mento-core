// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";

import { BaseTest } from "../utils/BaseTest.t.sol";
import { TokenHelpers } from "../utils/TokenHelpers.t.sol";
import { DummyERC20 } from "../utils/DummyErc20.sol";
import { MockSortedOracles } from "../mocks/MockSortedOracles.sol";
import { MockStableToken } from "../mocks/MockStableToken.sol";

import { FixidityLib } from "contracts/common/FixidityLib.sol";
import { Reserve } from "contracts/swap/Reserve.sol";

contract ReserveTest is BaseTest, TokenHelpers {
  using SafeMath for uint256;
  using FixidityLib for FixidityLib.Fraction;

  event TobinTaxStalenessThresholdSet(uint256 value);
  event DailySpendingRatioSet(uint256 ratio);
  event TokenAdded(address indexed token);
  event TokenRemoved(address indexed token, uint256 index);
  event SpenderAdded(address indexed spender);
  event SpenderRemoved(address indexed spender);
  event OtherReserveAddressAdded(address indexed otherReserveAddress);
  event OtherReserveAddressRemoved(address indexed otherReserveAddress, uint256 index);
  event AssetAllocationSet(bytes32[] symbols, uint256[] weights);
  event ReserveGoldTransferred(address indexed spender, address indexed to, uint256 value);
  event TobinTaxSet(uint256 value);
  event TobinTaxReserveRatioSet(uint256 value);
  event ExchangeSpenderAdded(address indexed exchangeSpender);
  event ExchangeSpenderRemoved(address indexed exchangeSpender);
  event DailySpendingRatioForCollateralAssetSet(address collateralAsset, uint256 collateralAssetDailySpendingRatios);
  event CollateralAssetAdded(address collateralAsset);
  event CollateralAssetRemoved(address collateralAsset);

  address constant exchangeAddress = address(0xe7c45fa);
  uint256 constant tobinTaxStalenessThreshold = 600;
  uint256 constant dailySpendingRatio = 1000000000000000000000000;
  uint256 constant sortedOraclesDenominator = 1000000000000000000000000;
  uint256 tobinTax = FixidityLib.newFixedFraction(5, 1000).unwrap();
  uint256 tobinTaxReserveRatio = FixidityLib.newFixedFraction(2, 1).unwrap();

  address notDeployer;

  address broker;
  Reserve reserve;
  MockSortedOracles sortedOracles;
  DummyERC20 dummyToken1 = new DummyERC20("DummyToken1", "DT1", 18);
  DummyERC20 dummyToken2 = new DummyERC20("DummyToken2", "DT2", 18);
  DummyERC20 dummyToken3 = new DummyERC20("DummyToken3", "DT3", 18);

  function setUp() public {
    notDeployer = actor("notDeployer");
    vm.startPrank(deployer);
    reserve = new Reserve(true);
    sortedOracles = new MockSortedOracles();
    broker = actor("broker");

    registry.setAddressFor("SortedOracles", address(sortedOracles));
    registry.setAddressFor("Exchange", exchangeAddress);

    bytes32[] memory initialAssetAllocationSymbols = new bytes32[](1);
    initialAssetAllocationSymbols[0] = bytes32("cGLD");
    uint256[] memory initialAssetAllocationWeights = new uint256[](1);
    initialAssetAllocationWeights[0] = FixidityLib.newFixed(1).unwrap();

    address[] memory collateralAssets = new address[](2);
    uint256[] memory collateralAssetDailySpendingRatios = new uint256[](2);
    collateralAssets[0] = address(dummyToken1);
    collateralAssetDailySpendingRatios[0] = 100000000000000000000000;

    // Donate 10k DT3 to the reserve
    deal(address(dummyToken3), address(reserve), 10000 * 10**18);
    // Only 10% of reserve DT3 should be spendable per day
    collateralAssetDailySpendingRatios[1] = FixidityLib.newFixedFraction(1, 10).unwrap();
    collateralAssets[1] = address(dummyToken3);

    reserve.initialize(
      address(registry),
      tobinTaxStalenessThreshold,
      dailySpendingRatio,
      0,
      0,
      initialAssetAllocationSymbols,
      initialAssetAllocationWeights,
      tobinTax,
      tobinTaxReserveRatio,
      collateralAssets,
      collateralAssetDailySpendingRatios
    );
  }
}

contract ReserveTest_initAndSetters is ReserveTest {
  function test_init_setsParameters() public {
    assertEq(reserve.owner(), deployer);
    assertEq(address(reserve.registry()), address(registry));
    assertEq(reserve.tobinTaxStalenessThreshold(), tobinTaxStalenessThreshold);

    vm.expectRevert("contract already initialized");
    reserve.initialize(
      address(registry),
      0,
      0,
      0,
      0,
      new bytes32[](0),
      new uint256[](0),
      0,
      0,
      new address[](0),
      new uint256[](0)
    );
  }

  function test_tobinTax() public {
    uint256 newValue = 123;
    vm.expectEmit(true, true, true, true, address(reserve));
    emit TobinTaxSet(newValue);
    reserve.setTobinTax(newValue);
    assertEq(reserve.tobinTax(), newValue);

    vm.expectRevert("tobin tax cannot be larger than 1");
    reserve.setTobinTax(FixidityLib.newFixed(1).unwrap().add(1));

    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    reserve.setTobinTax(100);
  }

  function test_tobinTaxReserveRation() public {
    uint256 newValue = 123;
    vm.expectEmit(true, true, true, true, address(reserve));
    emit TobinTaxReserveRatioSet(newValue);
    reserve.setTobinTaxReserveRatio(newValue);
    assertEq(reserve.tobinTaxReserveRatio(), newValue);

    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    reserve.setTobinTaxReserveRatio(100);
  }

  function test_dailySpendingRatio() public {
    uint256 newValue = 123;
    vm.expectEmit(true, true, true, true, address(reserve));
    emit DailySpendingRatioSet(newValue);
    reserve.setDailySpendingRatio(newValue);
    assertEq(reserve.getDailySpendingRatio(), newValue);

    vm.expectRevert("spending ratio cannot be larger than 1");
    reserve.setDailySpendingRatio(FixidityLib.newFixed(1).unwrap().add(1));

    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    reserve.setDailySpendingRatio(100);
  }

  function test_setDailySpendingRatioForCollateralAssets_whenRatioIsSetWithCorrectParams_shouldEmitAndUpdate() public {
    address[] memory collateralAssets = new address[](1);
    uint256[] memory collateralAssetDailySpendingRatios = new uint256[](1);
    uint256 newValue = 123;
    collateralAssetDailySpendingRatios[0] = newValue;
    collateralAssets[0] = address(dummyToken1);

    vm.expectEmit(true, true, true, true, address(reserve));
    emit DailySpendingRatioForCollateralAssetSet(address(dummyToken1), newValue);
    reserve.setDailySpendingRatioForCollateralAssets(collateralAssets, collateralAssetDailySpendingRatios);
    assertEq(reserve.getDailySpendingRatioForCollateralAsset(address(dummyToken1)), newValue);
  }

  function test_setDailySpendingRatioForCollateralAssets_whenArraysAreDifferentLengths_shouldRevert() public {
    address[] memory collateralAssetsLocal = new address[](2);
    uint256[] memory collateralAssetDailySpendingRatiosLocal = new uint256[](1);
    collateralAssetsLocal[0] = address(dummyToken1);
    collateralAssetsLocal[1] = address(dummyToken2);
    collateralAssetDailySpendingRatiosLocal[0] = 1;

    vm.expectRevert("token addresses and spending ratio lengths have to be the same");
    reserve.setDailySpendingRatioForCollateralAssets(collateralAssetsLocal, collateralAssetDailySpendingRatiosLocal);
  }

  function test_setDailySpendingRatioForCollateralAssets_whenAddressIsNotCollateralAsset_shouldRevert() public {
    address[] memory collateralAssets = new address[](1);
    uint256[] memory collateralAssetDailySpendingRatios = new uint256[](1);
    collateralAssets[0] = address(dummyToken1);
    collateralAssetDailySpendingRatios[0] = 123;
    reserve.removeCollateralAsset(address(dummyToken1), 0);

    vm.expectRevert("the address specified is not a reserve collateral asset");
    reserve.setDailySpendingRatioForCollateralAssets(collateralAssets, collateralAssetDailySpendingRatios);
  }

  function test_setDailySpendingRatioForCollateralAssets_whenRatioIsLargerThanOne_shouldRevert() public {
    address[] memory collateralAssets = new address[](1);
    uint256[] memory collateralAssetDailySpendingRatios = new uint256[](1);
    collateralAssets[0] = address(dummyToken1);
    collateralAssetDailySpendingRatios[0] = FixidityLib.newFixed(1).unwrap().add(1);

    vm.expectRevert("spending ratio cannot be larger than 1");
    reserve.setDailySpendingRatioForCollateralAssets(collateralAssets, collateralAssetDailySpendingRatios);
  }

  function test_setDailySpendingRatioForCollateralAssets_whenSenderIsNotOwner_shouldRevert() public {
    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    reserve.setDailySpendingRatioForCollateralAssets(new address[](0), new uint256[](0));
  }

  function test_addCollateralAsset_whenAssetShouldBeAdded_shouldUpdateAndEmit() public {
    address token = address(0x1122);

    vm.expectEmit(true, true, true, true, address(reserve));
    emit CollateralAssetAdded(token);
    reserve.addCollateralAsset(token);
    assertEq(reserve.checkIsCollateralAsset(token), true);
  }

  function test_addCollateralAsset_whenAlreadyAdded_shouldRevert() public {
    vm.expectRevert("specified address is already added as a collateral asset");
    reserve.addCollateralAsset(address(dummyToken1));
  }

  function test_addCollateralAsset_withZeroAddress_shouldRevert() public {
    vm.expectRevert("can't be a zero address");
    reserve.addCollateralAsset(address(0));
  }

  function test_addCollateralAsset_whenNotOwner_shouldRevert() public {
    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    reserve.addCollateralAsset(address(0x1234));
  }

  function test_removeCollateralAsset_whenAssetShouldBeRemoved_shouldUpdateAndEmit() public {
    vm.expectEmit(true, true, true, true, address(reserve));
    emit CollateralAssetRemoved(address(dummyToken1));
    reserve.removeCollateralAsset(address(dummyToken1), 0);
    assertEq(reserve.checkIsCollateralAsset(address(dummyToken1)), false);
  }

  function test_removeCollateralAsset_whenNotCollateralAsset_shouldRevert() public {
    vm.expectRevert("specified address is not a collateral asset");
    reserve.removeCollateralAsset(address(0x1234), 1);
  }

  function test_removeCollateralAsset_whenIndexOutOfRange_shouldRevert() public {
    vm.expectRevert("index into collateralAssets list not mapped to token");
    reserve.removeCollateralAsset(address(dummyToken1), 3);
  }

  function test_removeCollateralAsset_whenNotOwner_shouldRevert() public {
    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    reserve.removeCollateralAsset(address(dummyToken1), 0);
  }

  function test_registry() public {
    address newValue = address(0x1234);
    reserve.setRegistry(newValue);
    assertEq(address(reserve.registry()), newValue);

    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    reserve.setRegistry(address(0x1234));
  }

  function test_addToken() public {
    address token = address(0x1234);
    sortedOracles.setMedianRate(token, sortedOraclesDenominator);
    vm.expectEmit(true, true, true, true, address(reserve));
    emit TokenAdded(token);
    reserve.addToken(token);
    assert(reserve.isToken(token));
    vm.expectRevert("token addr already registered");
    reserve.addToken(token);

    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    reserve.addToken(address(0x1234));
  }

  function test_removeToken() public {
    address token = address(0x1234);

    vm.expectRevert("token addr was never registered");
    reserve.removeToken(token, 0);

    sortedOracles.setMedianRate(token, sortedOraclesDenominator);
    reserve.addToken(token);

    vm.expectEmit(true, true, true, true, address(reserve));
    emit TokenRemoved(token, 0);
    reserve.removeToken(token, 0);

    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    reserve.removeToken(address(0x1234), 0);
  }

  function test_tobinTaxStalenessThreshold() public {
    uint256 newThreshold = 1;
    vm.expectEmit(true, true, true, true, address(reserve));
    emit TobinTaxStalenessThresholdSet(newThreshold);
    reserve.setTobinTaxStalenessThreshold(newThreshold);
    assertEq(reserve.tobinTaxStalenessThreshold(), newThreshold);

    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    reserve.setTobinTaxStalenessThreshold(newThreshold);
  }

  function test_addOtherReserveAddress() public {
    address[] memory otherReserveAddresses = new address[](2);
    otherReserveAddresses[0] = address(0x1111);
    otherReserveAddresses[1] = address(0x2222);

    vm.expectEmit(true, true, true, true, address(reserve));
    emit OtherReserveAddressAdded(otherReserveAddresses[0]);
    reserve.addOtherReserveAddress(otherReserveAddresses[0]);

    vm.expectRevert("reserve addr already added");
    reserve.addOtherReserveAddress(otherReserveAddresses[0]);

    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    reserve.addOtherReserveAddress(otherReserveAddresses[1]);
    changePrank(deployer);

    vm.expectEmit(true, true, true, true, address(reserve));
    emit OtherReserveAddressAdded(otherReserveAddresses[1]);
    reserve.addOtherReserveAddress(otherReserveAddresses[1]);

    address[] memory recordedAddresses = reserve.getOtherReserveAddresses();
    assertEq(recordedAddresses, otherReserveAddresses);

    deal(otherReserveAddresses[0], 100000);
    deal(otherReserveAddresses[1], 100000);
    deal(address(reserve), 100000);
    assertEq(reserve.getReserveGoldBalance(), uint256(300000));
  }

  function test_removeOtherReserveAddress() public {
    address[] memory otherReserveAddresses = new address[](3);
    otherReserveAddresses[0] = address(0x1111);
    otherReserveAddresses[1] = address(0x2222);

    vm.expectRevert("reserve addr was never added");
    reserve.removeOtherReserveAddress(otherReserveAddresses[0], 0);

    reserve.addOtherReserveAddress(otherReserveAddresses[0]);
    reserve.addOtherReserveAddress(otherReserveAddresses[1]);

    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    reserve.removeOtherReserveAddress(otherReserveAddresses[0], 0);
    changePrank(deployer);

    vm.expectEmit(true, true, true, true, address(reserve));
    emit OtherReserveAddressRemoved(otherReserveAddresses[0], 0);
    reserve.removeOtherReserveAddress(otherReserveAddresses[0], 0);
    address[] memory recordedAddresses = reserve.getOtherReserveAddresses();
    assertEq(recordedAddresses.length, 1);
    assertEq(recordedAddresses[0], otherReserveAddresses[1]);
  }

  function test_setAssetAllocations() public {
    bytes32[] memory assetAllocationSymbols = new bytes32[](3);
    assetAllocationSymbols[0] = bytes32("cGLD");
    assetAllocationSymbols[1] = bytes32("BTC");
    assetAllocationSymbols[2] = bytes32("ETH");
    uint256[] memory assetAllocationWeights = new uint256[](3);
    assetAllocationWeights[0] = FixidityLib.newFixedFraction(1, 3).unwrap();
    assetAllocationWeights[1] = FixidityLib.newFixedFraction(1, 3).unwrap();
    assetAllocationWeights[2] = FixidityLib.newFixedFraction(1, 3).unwrap().add(1);

    vm.expectEmit(true, true, true, true, address(reserve));
    emit AssetAllocationSet(assetAllocationSymbols, assetAllocationWeights);
    reserve.setAssetAllocations(assetAllocationSymbols, assetAllocationWeights);
    assertEq(reserve.getAssetAllocationSymbols(), assetAllocationSymbols);
    assertEq(reserve.getAssetAllocationWeights(), assetAllocationWeights);

    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    reserve.setAssetAllocations(assetAllocationSymbols, assetAllocationWeights);
    changePrank(deployer);

    assetAllocationWeights[2] = FixidityLib.newFixedFraction(1, 3).unwrap().add(100);
    vm.expectRevert("Sum of asset allocation must be 1");
    reserve.setAssetAllocations(assetAllocationSymbols, assetAllocationWeights);
    assetAllocationWeights[2] = FixidityLib.newFixedFraction(1, 3).unwrap().add(1);

    assetAllocationSymbols[2] = bytes32("BTC");
    vm.expectRevert("Cannot set weight twice");
    reserve.setAssetAllocations(assetAllocationSymbols, assetAllocationWeights);
    assetAllocationSymbols[2] = bytes32("ETH");

    assetAllocationSymbols[0] = bytes32("DAI");
    vm.expectRevert("Must set cGLD asset weight");
    reserve.setAssetAllocations(assetAllocationSymbols, assetAllocationWeights);
  }
}

contract ReserveTest_transfers is ReserveTest {
  uint256 constant reserveCeloBalance = 100000;
  uint256 constant reserveDummyToken1Balance = 10000000;
  uint256 constant reserveDummyToken2Balance = 20000000;
  address payable constant otherReserveAddress = address(0x1234);
  address payable constant trader = address(0x1245);
  address payable spender;

  function setUp() public {
    super.setUp();
    spender = address(uint160(actor("spender")));

    address[] memory collateralAssets = new address[](1);
    uint256[] memory collateralAssetDailySpendingRatios = new uint256[](1);
    collateralAssets[0] = address(dummyToken1);
    collateralAssetDailySpendingRatios[0] = FixidityLib.newFixedFraction(2, 10).unwrap();

    deal(address(reserve), reserveCeloBalance);
    deal(address(dummyToken1), address(reserve), reserveDummyToken1Balance);
    deal(address(dummyToken2), address(reserve), reserveDummyToken2Balance);
    reserve.addOtherReserveAddress(otherReserveAddress);
    reserve.addSpender(spender);
    reserve.setDailySpendingRatio(FixidityLib.newFixedFraction(2, 10).unwrap());
    reserve.setDailySpendingRatioForCollateralAssets(collateralAssets, collateralAssetDailySpendingRatios);
    vm.warp(100 * 24 * 3600 + 445);
  }

  /* ---------- Transfer Gold ---------- */

  function test_transferGold() public {
    changePrank(spender);
    uint256 amount = reserveCeloBalance.div(10);

    reserve.transferGold(otherReserveAddress, amount);
    assertEq(otherReserveAddress.balance, amount);
    assertEq(address(reserve).balance, reserveCeloBalance - amount);

    vm.expectRevert("Exceeding spending limit");
    reserve.transferGold(otherReserveAddress, amount.mul(2));

    vm.warp(block.timestamp + 24 * 3600);
    reserve.transferGold(otherReserveAddress, amount.mul(2));
    assertEq(otherReserveAddress.balance, 3 * amount);

    vm.expectRevert("can only transfer to other reserve address");
    reserve.transferGold(address(0x234), amount);

    changePrank(deployer);
    reserve.removeSpender(spender);
    changePrank(spender);
    vm.warp(block.timestamp + 24 * 3600);
    vm.expectRevert("sender not allowed to transfer Reserve funds");
    reserve.transferGold(otherReserveAddress, amount);
  }

  /* ---------- Transfer Collateral Asset ---------- */

  function test_transferCollateralAsset_whenParametersAreCorrect_shouldUpdate() public {
    changePrank(spender);
    uint256 amount = reserveDummyToken1Balance.div(10);
    reserve.transferCollateralAsset(address(dummyToken1), otherReserveAddress, amount);
    assertEq(dummyToken1.balanceOf(otherReserveAddress), amount);
    assertEq(dummyToken1.balanceOf(address(reserve)), reserveDummyToken1Balance - amount);
  }

  function test_transferCollateralAsset_whenItExceedsSpendingLimit_shouldRevert() public {
    changePrank(spender);
    vm.expectRevert("Exceeding spending limit");
    reserve.transferCollateralAsset(address(dummyToken1), otherReserveAddress, reserveDummyToken1Balance.add(2));

    vm.warp(block.timestamp + 24 * 3600);
  }

  function test_transferCollateralAsset_whenItTransfersToARandomAddress_shouldRevert() public {
    uint256 amount = reserveDummyToken1Balance.div(100);
    changePrank(spender);
    vm.expectRevert("can only transfer to other reserve address");
    reserve.transferCollateralAsset(address(dummyToken1), spender, amount);
  }

  function test_transferCollateralAsset_whenSpendingRatioWasNotSet_shouldRevert() public {
    changePrank(spender);
    vm.expectRevert("this asset has no spending ratio, therefore can't be transferred");
    reserve.transferCollateralAsset(address(dummyToken2), otherReserveAddress, reserveDummyToken2Balance);
  }

  function test_transferCollateralAsset_whenSpenderWasRemoved_shouldRevert() public {
    changePrank(deployer);
    reserve.removeSpender(spender);
    changePrank(spender);
    vm.warp(block.timestamp + 24 * 3600);
    vm.expectRevert("sender not allowed to transfer Reserve funds");
    reserve.transferCollateralAsset(address(dummyToken1), address(0x234), reserveDummyToken1Balance);
  }

  function test_transferCollateralAsset_whenMultipleTransfersDoNotHitDailySpend_shouldTransferCorrectAmounts() public {
    changePrank(spender);

    uint256 transfer1Amount = 500 * 10**18;
    uint256 transfer2Amount = 400 * 10**18;

    uint256 totalTransferAmount = transfer1Amount + transfer2Amount;
    uint256 reserveBalanceBefore = dummyToken3.balanceOf(address(reserve));

    // Spend 500 DT3 (50% of daily limit)
    reserve.transferCollateralAsset(address(dummyToken3), otherReserveAddress, transfer1Amount);
    // Spend 400 DT3 (LT remaining daily limit)
    reserve.transferCollateralAsset(address(dummyToken3), otherReserveAddress, transfer2Amount);

    uint256 traderBalanceAfter = dummyToken3.balanceOf(otherReserveAddress);
    uint256 reserveBalanceAfter = dummyToken3.balanceOf(address(reserve));

    assertEq(reserveBalanceAfter, (reserveBalanceBefore - totalTransferAmount));
    assertEq(traderBalanceAfter, totalTransferAmount);
  }

  function test_transferCollateralAsset_whenMultipleTransfersHitDailySpend_shouldRevert() public {
    changePrank(spender);

    // Spend 500 DT3 (50% of daily limit)
    reserve.transferCollateralAsset(address(dummyToken3), otherReserveAddress, 500 * 10**18);
    uint256 spendingLimitAfter = reserve.collateralAssetSpendingLimit(address(dummyToken3));

    // (collateralAssetDailySpendingRatio * reserve DT3 balance before transfer) - transfer amount
    assertEq(spendingLimitAfter, 500 * 10**18);

    vm.expectRevert("Exceeding spending limit");
    // Spend amount GT remaining daily limit
    reserve.transferCollateralAsset(address(dummyToken3), otherReserveAddress, spendingLimitAfter + 1);
  }

  function test_transferCollateralAsset_whenSpendingLimitIsHit_shoudResetNextDay() public {
    changePrank(spender);

    uint256 transfer1Amount = 500 * 10**18;
    uint256 transfer2Amount = 600 * 10**18;

    // Spend 500 DT3 (50% of daily limit)
    reserve.transferCollateralAsset(address(dummyToken3), otherReserveAddress, transfer1Amount);

    vm.expectRevert("Exceeding spending limit");
    // Spend 600 DT3 (GT remaining daily limit)
    reserve.transferCollateralAsset(address(dummyToken3), otherReserveAddress, transfer2Amount);

    uint256 traderBalanceAfterFirstDay = dummyToken3.balanceOf(otherReserveAddress);
    assertEq(traderBalanceAfterFirstDay, transfer1Amount);

    vm.warp(block.timestamp + 24 * 3600);

    // Spend 600 DT3 (LT remaining daily limit on new day)
    reserve.transferCollateralAsset(address(dummyToken3), otherReserveAddress, transfer2Amount);
    uint256 traderBalanceAfterSecondDay = dummyToken3.balanceOf(otherReserveAddress);

    assertEq(traderBalanceAfterSecondDay, transfer1Amount + transfer2Amount);
  }

  /* ---------- Transfer Exchange Collateral Asset ---------- */

  function test_transferExchangeCollateralAsset_whenSenderIsBroker_shouldTransfer() public {
    reserve.addExchangeSpender(broker);
    changePrank(broker);
    reserve.transferExchangeCollateralAsset(address(dummyToken1), otherReserveAddress, 1000);
    assertEq(dummyToken1.balanceOf(otherReserveAddress), 1000);
  }

  function test_transferExchangeCollateralAsset_notExchangeSender_shouldRevert() public {
    changePrank(notDeployer);
    vm.expectRevert("Address not allowed to spend");
    reserve.transferExchangeCollateralAsset(address(dummyToken1), otherReserveAddress, 1000);
  }

  function test_addExchangeSpender() public {
    address exchangeSpender0 = address(0x22222);
    address exchangeSpender1 = address(0x33333);

    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    reserve.addExchangeSpender(exchangeSpender0);

    changePrank(deployer);
    vm.expectEmit(true, true, true, true, address(reserve));
    emit ExchangeSpenderAdded(exchangeSpender0);
    reserve.addExchangeSpender(exchangeSpender0);

    vm.expectRevert("Spender can't be null");
    reserve.addExchangeSpender(address(0x0));

    reserve.addExchangeSpender(exchangeSpender1);
    address[] memory spenders = reserve.getExchangeSpenders();
    assertEq(spenders[0], exchangeSpender0);
    assertEq(spenders[1], exchangeSpender1);
  }

  function test_removeExchangeSpender() public {
    address exchangeSpender0 = address(0x22222);
    address exchangeSpender1 = address(0x33333);
    reserve.addExchangeSpender(exchangeSpender0);

    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    reserve.removeExchangeSpender(exchangeSpender0, 0);

    changePrank(deployer);
    vm.expectEmit(true, true, true, true, address(reserve));
    emit ExchangeSpenderRemoved(exchangeSpender0);
    reserve.removeExchangeSpender(exchangeSpender0, 0);

    vm.expectRevert("Index is invalid");
    reserve.removeExchangeSpender(exchangeSpender0, 0);

    reserve.addExchangeSpender(exchangeSpender0);
    reserve.addExchangeSpender(exchangeSpender1);

    vm.expectRevert("Index is invalid");
    reserve.removeExchangeSpender(exchangeSpender0, 3);
    vm.expectRevert("Index does not match spender");
    reserve.removeExchangeSpender(exchangeSpender1, 0);

    reserve.removeExchangeSpender(exchangeSpender0, 0);
    address[] memory spenders = reserve.getExchangeSpenders();
    assertEq(spenders[0], exchangeSpender1);
  }

  function test_addSpender() public {
    address _spender = address(0x4444);

    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    reserve.addSpender(_spender);

    changePrank(deployer);
    vm.expectEmit(true, true, true, true, address(reserve));
    emit SpenderAdded(_spender);
    reserve.addSpender(_spender);

    vm.expectRevert("Spender can't be null");
    reserve.addSpender(address(0x0));
  }

  function test_removeSpender_whenCallerIsOwner_shouldRemove() public {
    address _spender = actor("_spender");

    reserve.addSpender(_spender);
    vm.expectEmit(true, true, true, true, address(reserve));
    emit SpenderRemoved(_spender);
    reserve.removeSpender(_spender);
  }

  function test_removeSpender_whenCallerIsNotOwner_shouldRevert() public {
    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    reserve.removeSpender(spender);
  }

  function test_removeSpender_whenSpenderDoesNotExist_shouldRevert() public {
    vm.expectRevert("Spender hasn't been added");
    reserve.removeSpender(notDeployer);
  }

  function test_transferExchangeGold_asExchangeFromRegistry() public {
    transferExchangeGoldSpecs(exchangeAddress);
  }

  function test_transferExchangeGold_asRegisteredExchange() public {
    address additionalExchange = address(0x6666);
    reserve.addExchangeSpender(additionalExchange);
    transferExchangeGoldSpecs(exchangeAddress);

    changePrank(deployer);
    reserve.removeExchangeSpender(additionalExchange, 0);

    changePrank(additionalExchange);
    vm.expectRevert("Address not allowed to spend");
    reserve.transferExchangeGold(address(0x1111), 1000);
  }

  function transferExchangeGoldSpecs(address caller) public {
    changePrank(caller);
    address payable dest = address(0x1111);
    reserve.transferExchangeGold(dest, 1000);
    assertEq(dest.balance, 1000);

    changePrank(spender);
    vm.expectRevert("Address not allowed to spend");
    reserve.transferExchangeGold(dest, 1000);

    changePrank(notDeployer);
    vm.expectRevert("Address not allowed to spend");
    reserve.transferExchangeGold(dest, 1000);
  }

  function test_frozenGold() public {
    reserve.setDailySpendingRatio(FixidityLib.fixed1().unwrap());
    vm.expectRevert("Cannot freeze more than balance");
    reserve.setFrozenGold(reserveCeloBalance + 1, 1);
    uint256 dailyUnlock = reserveCeloBalance.div(3);

    reserve.setFrozenGold(reserveCeloBalance, 3);
    changePrank(spender);
    vm.expectRevert("Exceeding spending limit");
    reserve.transferGold(otherReserveAddress, 1);
    vm.warp(block.timestamp + 3600 * 24);
    assertEq(reserve.getUnfrozenBalance(), dailyUnlock);
    reserve.transferGold(otherReserveAddress, dailyUnlock);
    vm.warp(block.timestamp + 3600 * 24);
    assertEq(reserve.getUnfrozenBalance(), dailyUnlock);
    reserve.transferGold(otherReserveAddress, dailyUnlock);
    vm.warp(block.timestamp + 3600 * 24);
    assertEq(reserve.getUnfrozenBalance(), dailyUnlock + 1);
    reserve.transferGold(otherReserveAddress, dailyUnlock);
  }
}

contract ReserveTest_tobinTax is ReserveTest {
  MockStableToken stableToken0;
  MockStableToken stableToken1;

  function setUp() public {
    super.setUp();

    bytes32[] memory assetAllocationSymbols = new bytes32[](2);
    assetAllocationSymbols[0] = bytes32("cGLD");
    assetAllocationSymbols[1] = bytes32("BTC");
    uint256[] memory assetAllocationWeights = new uint256[](2);
    assetAllocationWeights[0] = FixidityLib.newFixedFraction(1, 2).unwrap();
    assetAllocationWeights[1] = FixidityLib.newFixedFraction(1, 2).unwrap();

    reserve.setAssetAllocations(assetAllocationSymbols, assetAllocationWeights);

    stableToken0 = new MockStableToken();
    sortedOracles.setMedianRate(address(stableToken0), sortedOraclesDenominator.mul(10));

    stableToken1 = new MockStableToken();
    sortedOracles.setMedianRate(address(stableToken1), sortedOraclesDenominator.mul(10));

    reserve.addToken(address(stableToken0));
    reserve.addToken(address(stableToken1));
  }

  function setValues(
    uint256 reserveBalance,
    uint256 stableToken0Supply,
    uint256 stableToken1Supply
  ) internal {
    deal(address(reserve), reserveBalance);
    stableToken0.setTotalSupply(stableToken0Supply);
    stableToken1.setTotalSupply(stableToken1Supply);
  }

  function getOrComputeTobinTaxFraction() internal returns (uint256) {
    (uint256 num, uint256 den) = reserve.getOrComputeTobinTax();
    return FixidityLib.newFixedFraction(num, den).unwrap();
  }

  function test_getReserveRatio() public {
    uint256 expected;

    setValues(1000000, 10000, 0);
    expected = FixidityLib.newFixed(2000000).divide(FixidityLib.newFixed(1000)).unwrap();
    assertEq(reserve.getReserveRatio(), expected);

    setValues(1000000, 10000, 30000);
    expected = FixidityLib.newFixed(2000000).divide(FixidityLib.newFixed(4000)).unwrap();
    assertEq(reserve.getReserveRatio(), expected);
  }

  function test_tobinTax() public {
    setValues(1000000, 400000, 500000);
    assertEq(getOrComputeTobinTaxFraction(), 0);
    setValues(1000000, 50000000, 50000000);
    // Is the same unless threshold passed
    assertEq(getOrComputeTobinTaxFraction(), 0);
    // Changes
    vm.warp(block.timestamp + tobinTaxStalenessThreshold);
    assertEq(getOrComputeTobinTaxFraction(), tobinTax);
  }
}
