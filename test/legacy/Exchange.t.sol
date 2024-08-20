// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import "../utils/TokenHelpers.t.sol";
import "../utils/BaseTest.t.sol";

import "../mocks/MockReserve.sol";
import "../mocks/MockSortedOracles.sol";

import "contracts/legacy/Exchange.sol";
import "contracts/common/FixidityLib.sol";
import "contracts/common/Freezer.sol";
import "contracts/common/GoldToken.sol";
import "contracts/interfaces/IStableTokenV2.sol";

contract ExchangeTest is BaseTest, TokenHelpers {
  using SafeMath for uint256;
  using FixidityLib for FixidityLib.Fraction;

  // Declare exchange events for matching
  event Exchanged(address indexed exchanger, uint256 sellAmount, uint256 buyAmount, bool soldCelo);
  event UpdateFrequencySet(uint256 updateFrequency);
  event MinimumReportsSet(uint256 minimumReports);
  event StableTokenSet(address indexed stable);
  event SpreadSet(uint256 spread);
  event ReserveFractionSet(uint256 reserveFraction);
  event BucketsUpdated(uint256 celoBucket, uint256 stableBucket);
  event Approval(address indexed owner, address indexed spender, uint256 value);

  address deployer;
  address rando;

  Exchange exchange;
  Freezer freezer;
  IStableTokenV2 stableToken;
  GoldToken celoToken;
  MockReserve reserve;
  MockSortedOracles sortedOracles;

  uint256 constant referenceRateResetFrequency = 60 * 60;
  uint256 constant initialReserveBalance = 10000000000000000000000;
  FixidityLib.Fraction reserveFraction = FixidityLib.newFixedFraction(5, 100);
  uint256 initialCeloBucket = FixidityLib.newFixed(initialReserveBalance).multiply(reserveFraction).fromFixed();
  uint256 constant celoAmountForRate = 1000000000000000000000000;
  uint256 constant stableAmountForRate = 2000000000000000000000000;
  uint256 initialStableBucket = initialCeloBucket * 2;
  FixidityLib.Fraction spread = FixidityLib.newFixedFraction(3, 1000);

  function setUp() public {
    deployer = address(factory);
    rando = actor("rando");
    // Go somwehre in the future
    vm.warp(60 * 60 * 24 * 7 * 100);
    vm.startPrank(deployer);
    currentPrank = deployer;
    freezer = new Freezer(true);
    celoToken = new GoldToken(true);
    reserve = new MockReserve();
    exchange = new Exchange(true);
    stableToken = IStableTokenV2(factory.createContract("StableTokenV2", abi.encode(false)));
    sortedOracles = new MockSortedOracles();

    registry.setAddressFor("Freezer", address(freezer));
    registry.setAddressFor("GoldToken", address(celoToken));
    registry.setAddressFor("Reserve", address(reserve));
    registry.setAddressFor("StableToken", address(stableToken));
    registry.setAddressFor("GrandaMento", address(0x1));
    registry.setAddressFor("Exchange", address(exchange));
    registry.setAddressFor("SortedOracles", address(sortedOracles));

    reserve.setGoldToken(address(celoToken));
    celoToken.initialize(address(registry));

    mint(celoToken, address(reserve), initialReserveBalance);

    address[] memory initialAddresses = new address[](0);
    uint256[] memory initialBalances = new uint256[](0);

    stableToken.initialize(
      "Celo Dollar",
      "cUSD",
      18,
      address(registry),
      FixidityLib.unwrap(FixidityLib.fixed1()),
      60 * 60 * 24 * 7,
      initialAddresses,
      initialBalances,
      "Exchange"
    );
    stableToken.initializeV2(address(0), address(0), address(exchange));

    sortedOracles.setMedianRate(address(stableToken), stableAmountForRate);
    sortedOracles.setMedianTimestampToNow(address(stableToken));
    sortedOracles.setNumRates(address(stableToken), 2);

    exchange.initialize(
      address(registry),
      "StableToken",
      FixidityLib.unwrap(spread),
      FixidityLib.unwrap(reserveFraction),
      referenceRateResetFrequency,
      2
    );
  }

  function getBuyTokenAmount(uint256 sellAmount, uint256 sellSupply, uint256 buySupply) public view returns (uint256) {
    return getBuyTokenAmount(sellAmount, sellSupply, buySupply, spread);
  }

  function getBuyTokenAmount(
    uint256 sellAmount,
    uint256 sellSupply,
    uint256 buySupply,
    FixidityLib.Fraction memory spread_
  ) public pure returns (uint256) {
    FixidityLib.Fraction memory reducedSellAmount = FixidityLib.newFixed(sellAmount).multiply(
      FixidityLib.fixed1().subtract(spread_)
    );
    FixidityLib.Fraction memory numerator = reducedSellAmount.multiply(FixidityLib.newFixed(buySupply));
    FixidityLib.Fraction memory denominator = FixidityLib.newFixed(sellSupply).add(reducedSellAmount);
    return numerator.unwrap().div(denominator.unwrap());
  }

  function getSellTokenAmount(uint256 buyAmount, uint256 sellSupply, uint256 buySupply) public view returns (uint256) {
    return getSellTokenAmount(buyAmount, sellSupply, buySupply, spread);
  }

  function getSellTokenAmount(
    uint256 buyAmount,
    uint256 sellSupply,
    uint256 buySupply,
    FixidityLib.Fraction memory spread_
  ) public pure returns (uint256) {
    FixidityLib.Fraction memory numerator = FixidityLib.newFixed(buyAmount.mul(sellSupply));
    FixidityLib.Fraction memory denominator = FixidityLib.newFixed(buySupply.sub(buyAmount)).multiply(
      FixidityLib.fixed1().subtract(spread_)
    );
    return numerator.unwrap().div(denominator.unwrap());
  }
}

contract Exchange_initializeAndSetters is ExchangeTest {
  function test_initialize_shouldHaveSetOwner() public view {
    assert(exchange.owner() == deployer);
  }

  function test_initialize_setsStableTokenIdentifier() public view {
    bytes32 identifier = exchange.stableTokenRegistryId();
    assert(identifier == keccak256("StableToken"));
  }

  function test_initialize_canOnlyBeCalledOnce() public {
    vm.expectRevert("contract already initialized");
    exchange.initialize(
      address(registry),
      "StableToken",
      FixidityLib.unwrap(FixidityLib.newFixedFraction(3, 1000)),
      FixidityLib.unwrap(FixidityLib.newFixedFraction(5, 100)),
      60 * 60,
      2
    );
  }

  function test_activateStable_setsTheStableStorageAddress() public {
    assert(exchange.stable() == address(0));
    vm.expectEmit(true, true, true, true, address(exchange));
    emit StableTokenSet(address(stableToken));
    exchange.activateStable();
    assert(exchange.stable() == address(stableToken));
  }

  function test_activateStable_canOnlyBeCalledByOwner() public {
    vm.expectRevert("Ownable: caller is not the owner");
    changePrank(rando);
    exchange.activateStable();
  }

  function test_activateStable_canOnlyBeCalledOnce() public {
    exchange.activateStable();
    vm.expectRevert("StableToken address already activated");
    exchange.activateStable();
  }

  function test_setUpdateFrequency_setsTheValueAndEmits() public {
    vm.expectEmit(true, true, true, true, address(exchange));
    emit UpdateFrequencySet(60 * 3);
    exchange.setUpdateFrequency(60 * 3);
    assert(exchange.updateFrequency() == 60 * 3);
  }

  function test_setUpdateFrequency_isOnlyCallableByOwner() public {
    changePrank(rando);
    vm.expectRevert("Ownable: caller is not the owner");
    exchange.setUpdateFrequency(60 * 4);
  }

  function test_setMinimumReports_setsTheValueAndEmits() public {
    vm.expectEmit(true, true, true, true, address(exchange));
    emit MinimumReportsSet(10);
    exchange.setMinimumReports(10);
    assert(exchange.minimumReports() == 10);
  }

  function test_setMinimumReports_isOnlyCallableByOwner() public {
    changePrank(rando);
    vm.expectRevert("Ownable: caller is not the owner");
    exchange.setMinimumReports(10);
  }

  function test_setStableToken_setsTheValueAndEmits() public {
    vm.expectEmit(true, true, true, true, address(exchange));
    emit StableTokenSet(address(11));
    exchange.setStableToken(address(11));
    assert(exchange.stable() == address(11));
  }

  function test_setStableToken_isOnlyCallableByOwner() public {
    changePrank(rando);
    vm.expectRevert("Ownable: caller is not the owner");
    exchange.setStableToken(address(11));
  }

  function test_setSpread_setsTheValueAndEmits() public {
    uint256 newSpread = FixidityLib.unwrap(FixidityLib.newFixedFraction(5, 100));
    vm.expectEmit(true, true, true, true, address(exchange));
    emit SpreadSet(newSpread);
    exchange.setSpread(newSpread);
    assert(exchange.spread() == newSpread);
  }

  function test_setSpread_isOnlyCallableByOwner() public {
    changePrank(rando);
    vm.expectRevert("Ownable: caller is not the owner");
    exchange.setSpread(0);
  }

  function test_setReserveFraction_setsTheValueAndEmits() public {
    uint256 newReserveFraction = FixidityLib.unwrap(FixidityLib.newFixedFraction(5, 100));
    vm.expectEmit(true, true, true, true, address(exchange));
    emit ReserveFractionSet(newReserveFraction);
    exchange.setReserveFraction(newReserveFraction);
    assert(exchange.reserveFraction() == newReserveFraction);
  }

  function test_setReserveFraction_cantBeOne() public {
    uint256 newReserveFraction = FixidityLib.unwrap(FixidityLib.fixed1());
    vm.expectRevert("reserve fraction must be smaller than 1");
    exchange.setReserveFraction(newReserveFraction);
  }

  function test_setReserveFraction_isOnlyCallableByOwner() public {
    changePrank(rando);
    vm.expectRevert("Ownable: caller is not the owner");
    exchange.setReserveFraction(0);
  }
}

contract ExchangeTest_stableActivated is ExchangeTest {
  function setUp() public {
    super.setUp();
    exchange.activateStable();
  }
}

contract ExchangeTest_buyAndSellValues is ExchangeTest_stableActivated {
  function test_getBuyAndSellBuckets_returnsTheCorrectAmountOfTokens() public view {
    (uint256 buyBucketSize, uint256 sellBucketSize) = exchange.getBuyAndSellBuckets(true);
    assert(buyBucketSize == initialStableBucket);
    assert(sellBucketSize == initialCeloBucket);
  }

  function test_getBuyAndSellBuckets_afterReserveChange_isTheSameIfNotStale() public {
    mint(celoToken, address(reserve), initialReserveBalance);

    (uint256 buyBucketSize, uint256 sellBucketSize) = exchange.getBuyAndSellBuckets(true);
    assert(buyBucketSize == initialStableBucket);
    assert(sellBucketSize == initialCeloBucket);
  }

  function test_getBuyAndSellBuckets_afterReserveChange_updatesIfTimeHasPassed() public {
    mint(celoToken, address(reserve), initialReserveBalance);
    vm.warp(block.timestamp + referenceRateResetFrequency);
    sortedOracles.setMedianTimestampToNow(address(stableToken));

    (uint256 buyBucketSize, uint256 sellBucketSize) = exchange.getBuyAndSellBuckets(true);
    assert(buyBucketSize == 2 * initialStableBucket);
    assert(sellBucketSize == 2 * initialCeloBucket);
  }

  function test_getBuyAndSellBuckets_afterOracelUpdate_isTheSameIfNotStale() public {
    sortedOracles.setMedianRate(address(stableToken), celoAmountForRate.mul(4));
    (uint256 buyBucketSize, uint256 sellBucketSize) = exchange.getBuyAndSellBuckets(true);
    assert(buyBucketSize == initialStableBucket);
    assert(sellBucketSize == initialCeloBucket);
  }

  function test_getBuyAndSellBuckets_afterOracelUpdate_updatesIfTimeHasPassed() public {
    sortedOracles.setMedianRate(address(stableToken), celoAmountForRate.mul(4));
    vm.warp(block.timestamp + referenceRateResetFrequency);
    sortedOracles.setMedianTimestampToNow(address(stableToken));

    (uint256 buyBucketSize, uint256 sellBucketSize) = exchange.getBuyAndSellBuckets(true);
    assert(buyBucketSize == initialStableBucket * 2);
    assert(sellBucketSize == initialCeloBucket);
  }

  function test_getBuyTokenAmount_returnsCorrectNumberOfTokens(uint256 amount) public {
    vm.assume(amount < initialCeloBucket);
    uint256 buyAmount = exchange.getBuyTokenAmount(amount, true);
    uint256 expectedBuyAmount = getBuyTokenAmount(amount, initialCeloBucket, initialStableBucket);
    assertEq(buyAmount, expectedBuyAmount);
  }

  function test_getSellTokenAmount_returnsCorrectNumberOfTokens(uint256 amount) public {
    vm.assume(amount < initialCeloBucket);
    uint256 sellAmount = exchange.getSellTokenAmount(amount, true);
    uint256 expectedSellAmount = getSellTokenAmount(amount, initialCeloBucket, initialStableBucket);
    assertEq(sellAmount, expectedSellAmount);
  }
}

contract ExchangeTest_sell is ExchangeTest_stableActivated {
  address seller;
  uint256 constant sellerCeloBalance = 100000000000000000000;
  uint256 constant sellerStableBalance = 100000000000000000000;

  function setUp() public {
    super.setUp();
    seller = vm.addr(2);
    vm.label(seller, "Seller");
    mint(celoToken, seller, sellerCeloBalance);
    mint(stableToken, seller, sellerStableBalance);
  }

  // This function will be overriden to test both `sell` and `exchange` functions
  function sell(uint256 amount, uint256 minBuyAmount, bool sellCelo) internal returns (uint256) {
    return exchange.sell(amount, minBuyAmount, sellCelo);
  }

  function approveExchange(uint256 amount, bool sellCelo) internal {
    changePrank(seller);
    if (sellCelo) {
      vm.expectEmit(true, true, true, true, address(celoToken));
      emit Approval(seller, address(exchange), amount);
      celoToken.approve(address(exchange), amount);
    } else {
      vm.expectEmit(true, true, true, true, address(stableToken));
      emit Approval(seller, address(exchange), amount);
      stableToken.approve(address(exchange), amount);
    }
  }

  function approveAndSell(uint256 amount, bool sellCelo) internal returns (uint256 expected, uint256 received) {
    approveExchange(amount, sellCelo);
    if (sellCelo) {
      expected = getBuyTokenAmount(amount, initialCeloBucket, initialStableBucket);
    } else {
      expected = getBuyTokenAmount(amount, initialStableBucket, initialCeloBucket);
    }
    vm.expectEmit(true, true, true, true, address(exchange));
    emit Exchanged(seller, amount, expected, sellCelo);
    received = sell(amount, expected, sellCelo);
  }

  function approveAndSell(
    uint256 amount,
    bool sellCelo,
    uint256 updatedCeloBucket,
    uint256 updatedStableBucket
  ) internal returns (uint256 expected, uint256 received) {
    approveExchange(amount, sellCelo);
    if (sellCelo) {
      expected = getBuyTokenAmount(amount, initialCeloBucket, initialStableBucket);
    } else {
      expected = getBuyTokenAmount(amount, initialStableBucket, initialCeloBucket);
    }
    vm.expectEmit(true, true, true, true, address(exchange));
    emit BucketsUpdated(updatedCeloBucket, updatedStableBucket);
    emit Exchanged(seller, expected, amount, sellCelo);
    received = sell(amount, expected, sellCelo);
  }

  function test_sellCelo_executesTrade(uint256 amount) public {
    vm.assume(amount <= sellerCeloBalance && amount > 10);
    uint256 stableSupply = stableToken.totalSupply();
    uint256 expected = getBuyTokenAmount(amount, initialCeloBucket, initialStableBucket);

    approveAndSell(amount, true);

    assertEq(stableToken.balanceOf(seller), sellerStableBalance + expected);
    assertEq(celoToken.balanceOf(seller), sellerCeloBalance - amount);
    assertEq(celoToken.allowance(seller, address(exchange)), 0);
    assertEq(celoToken.balanceOf(address(reserve)), initialReserveBalance + amount);
    assertEq(stableToken.totalSupply(), stableSupply + expected);
    (uint256 mintableStable, uint256 tradableCelo) = exchange.getBuyAndSellBuckets(true);
    assertEq(mintableStable, initialStableBucket - expected);
    assertEq(tradableCelo, initialCeloBucket + amount);
  }

  function test_sellCelo_revertsIfApprovalIsWrong(uint256 amount) public {
    vm.assume(amount < sellerCeloBalance);
    approveExchange(amount, true);
    uint256 expectedStableAmount = getBuyTokenAmount(amount, initialCeloBucket, initialStableBucket);
    vm.expectRevert("transfer value exceeded sender's allowance for recipient");
    sell(amount + 1, expectedStableAmount, true);
  }

  function test_sellCelo_revertsIfMinBuyAmountUnsatisfied(uint256 amount) public {
    vm.assume(amount <= sellerCeloBalance);
    approveExchange(amount, true);
    uint256 expectedStableAmount = getBuyTokenAmount(amount, initialCeloBucket, initialStableBucket);

    vm.expectRevert("Calculated buyAmount was less than specified minBuyAmount");
    sell(amount, expectedStableAmount + 1, true);
  }

  function test_sellCelo_whenBucketsStaleAndReportFresh_updatesBuckets() public {
    uint256 amount = 1000;
    mint(celoToken, address(reserve), initialReserveBalance);
    vm.warp(block.timestamp + referenceRateResetFrequency);
    sortedOracles.setMedianTimestampToNow(address(stableToken));

    uint256 updatedCeloBucket = initialCeloBucket.mul(2);
    uint256 updatedStableBucket = updatedCeloBucket.mul(stableAmountForRate).div(celoAmountForRate);
    (uint256 expected, ) = approveAndSell(amount, true, updatedCeloBucket, updatedStableBucket);

    assertEq(stableToken.balanceOf(seller), sellerStableBalance + expected);
    (uint256 mintableStable, uint256 tradableCelo) = exchange.getBuyAndSellBuckets(true);
    assertEq(mintableStable, updatedStableBucket - expected);
    assertEq(tradableCelo, updatedCeloBucket + amount);
  }

  function test_sellCelo_whenBucketsStaleAndReportStale_doesNotUpdateBuckets() public {
    uint256 amount = 1000;
    mint(celoToken, address(reserve), initialReserveBalance);
    vm.warp(block.timestamp + referenceRateResetFrequency);
    sortedOracles.setOldestReportExpired(address(stableToken));

    (uint256 expected, ) = approveAndSell(amount, true);
    assertEq(stableToken.balanceOf(seller), sellerStableBalance + expected);
    (uint256 mintableStable, uint256 tradableCelo) = exchange.getBuyAndSellBuckets(true);
    assertEq(mintableStable, initialStableBucket - expected);
    assertEq(tradableCelo, initialCeloBucket + amount);
  }

  function test_sellStable_executesTrade(uint256 amount) public {
    vm.assume(amount < sellerStableBalance && amount > 10);
    uint256 stableTokenSupplyBefore = stableToken.totalSupply();
    uint256 expected = getBuyTokenAmount(amount, initialStableBucket, initialCeloBucket);

    approveAndSell(amount, false);

    assertEq(stableToken.balanceOf(seller), sellerStableBalance - amount);
    assertEq(celoToken.balanceOf(seller), sellerCeloBalance + expected);
    assertEq(stableToken.allowance(seller, address(exchange)), 0);
    assertEq(celoToken.balanceOf(address(reserve)), initialReserveBalance - expected);
    assertEq(stableToken.totalSupply(), stableTokenSupplyBefore - amount);
    (uint256 mintableStable, uint256 tradableCelo) = exchange.getBuyAndSellBuckets(true);
    assertEq(mintableStable, initialStableBucket + amount);
    assertEq(tradableCelo, initialCeloBucket - expected);
  }

  function test_sellStable_revertWithoutApproval(uint256 amount) public {
    vm.assume(amount < sellerStableBalance);
    uint256 expectedCelo = getBuyTokenAmount(amount, initialStableBucket, initialCeloBucket);
    changePrank(seller);
    approveExchange(amount, false);
    vm.expectRevert("ERC20: insufficient allowance");
    sell(amount + 1, expectedCelo, false);
  }

  function test_sellStable_revertIfMinBuyAmountUnsatisfied(uint256 amount) public {
    vm.assume(amount < sellerStableBalance);
    uint256 expectedCelo = getBuyTokenAmount(amount, initialStableBucket, initialCeloBucket);
    changePrank(seller);
    approveExchange(amount, false);
    vm.expectRevert("Calculated buyAmount was less than specified minBuyAmount");
    sell(amount, expectedCelo + 1, false);
  }

  function test_sellStable_whenBucketsStaleAndReportFresh_updatesBuckets() public {
    uint256 amount = 1000;
    mint(celoToken, address(reserve), initialReserveBalance);
    vm.warp(block.timestamp + referenceRateResetFrequency);
    sortedOracles.setMedianTimestampToNow(address(stableToken));

    uint256 updatedCeloBucket = initialCeloBucket.mul(2);
    uint256 updatedStableBucket = updatedCeloBucket.mul(stableAmountForRate).div(celoAmountForRate);
    (uint256 expected, ) = approveAndSell(amount, false, updatedCeloBucket, updatedStableBucket);

    assertEq(celoToken.balanceOf(seller), sellerCeloBalance + expected);
    (uint256 mintableStable, uint256 tradableCelo) = exchange.getBuyAndSellBuckets(true);
    assertEq(mintableStable, updatedStableBucket + amount);
    assertEq(tradableCelo, updatedCeloBucket - expected);
  }

  function test_sellStable_whenBucketsStaleAndReportStale_doesNotUpdateBuckets() public {
    uint256 amount = 1000;
    mint(celoToken, address(reserve), initialReserveBalance);
    vm.warp(block.timestamp + referenceRateResetFrequency);
    sortedOracles.setOldestReportExpired(address(stableToken));

    (uint256 expected, ) = approveAndSell(amount, false);
    assertEq(celoToken.balanceOf(seller), sellerCeloBalance + expected);
    (uint256 mintableStable, uint256 tradableCelo) = exchange.getBuyAndSellBuckets(true);
    assertEq(mintableStable, initialStableBucket + amount);
    assertEq(tradableCelo, initialCeloBucket - expected);
  }

  function test_whenContractIsFrozen_reverts() public {
    freezer.freeze(address(exchange));
    vm.expectRevert("can't call when contract is frozen");
    sell(1000, 0, false);
  }
}

contract ExchangeTest_exchange is ExchangeTest_sell {
  function sell(uint256 amount, uint256 minBuyAmount, bool sellCelo) internal returns (uint256) {
    changePrank(seller);
    return exchange.exchange(amount, minBuyAmount, sellCelo);
  }
}

contract ExchangeTest_buy is ExchangeTest_stableActivated {
  address buyer;
  uint256 constant buyerCeloBalance = 100000000000000000000;
  uint256 constant buyerStableBalance = 100000000000000000000;

  function setUp() public {
    super.setUp();
    buyer = vm.addr(2);
    vm.label(buyer, "buyer");
    mint(celoToken, buyer, buyerCeloBalance);
    mint(stableToken, buyer, buyerStableBalance);
  }

  function approveExchange(uint256 amount, bool buyCelo) internal returns (uint256 expected) {
    changePrank(buyer);
    if (buyCelo) {
      expected = getSellTokenAmount(amount, initialStableBucket, initialCeloBucket);
      vm.expectEmit(true, true, true, true, address(stableToken));
      emit Approval(buyer, address(exchange), expected);
      stableToken.approve(address(exchange), expected);
    } else {
      expected = getSellTokenAmount(amount, initialCeloBucket, initialStableBucket);
      vm.expectEmit(true, true, true, true, address(celoToken));
      emit Approval(buyer, address(exchange), expected);
      celoToken.approve(address(exchange), expected);
    }
  }

  function approveAndBuy(uint256 amount, bool buyCelo) internal returns (uint256 expected, uint256 received) {
    expected = approveExchange(amount, buyCelo);
    vm.expectEmit(true, true, true, true, address(exchange));
    emit Exchanged(buyer, expected, amount, !buyCelo);
    received = exchange.buy(amount, expected, buyCelo);
  }

  function approveAndBuy(
    uint256 amount,
    bool buyCelo,
    uint256 updatedCeloBucket,
    uint256 updateStableBucket
  ) internal returns (uint256 expected, uint256 received) {
    expected = approveExchange(amount, buyCelo);
    vm.expectEmit(true, true, true, true, address(exchange));
    emit BucketsUpdated(updatedCeloBucket, updateStableBucket);
    emit Exchanged(buyer, expected, amount, !buyCelo);
    received = exchange.buy(amount, expected, buyCelo);
  }

  function test_buyCelo_executesTrade(uint256 amount) public {
    vm.assume(amount < buyerCeloBalance);
    uint256 expected = getSellTokenAmount(amount, initialStableBucket, initialCeloBucket);
    vm.assume(expected < buyerStableBalance);
    uint256 stableSupply = stableToken.totalSupply();

    approveAndBuy(amount, true);

    assertEq(stableToken.balanceOf(buyer), buyerStableBalance - expected);
    assertEq(celoToken.balanceOf(buyer), buyerCeloBalance + amount);
    assertEq(stableToken.allowance(buyer, address(exchange)), 0);
    assertEq(celoToken.balanceOf(address(reserve)), initialReserveBalance - amount);
    assertEq(stableToken.totalSupply(), stableSupply - expected);
    (uint256 mintableStable, uint256 tradableCelo) = exchange.getBuyAndSellBuckets(true);
    assertEq(mintableStable, initialStableBucket + expected);
    assertEq(tradableCelo, initialCeloBucket - amount);
  }

  function test_buyCelo_revertsIfApprovalIsWrong(uint256 amount) public {
    vm.assume(amount > 10 && amount < buyerCeloBalance);
    uint256 expected = getSellTokenAmount(amount, initialStableBucket, initialCeloBucket);
    vm.assume(expected < buyerStableBalance);
    approveExchange(amount - 10, true);
    vm.expectRevert("ERC20: insufficient allowance");
    exchange.buy(amount, expected, true);
  }

  function test_buyCelo_revertsIfMaxSellAmountUnsatisfied(uint256 amount) public {
    vm.assume(amount <= buyerCeloBalance);
    uint256 expected = approveExchange(amount, true);
    vm.expectRevert("Calculated sellAmount was greater than specified maxSellAmount");
    exchange.buy(amount + 1, expected, true);
  }

  function test_buyCelo_whenBucketsStaleAndReportFresh_updatesBuckets() public {
    uint256 amount = 1000;
    mint(celoToken, address(reserve), initialReserveBalance);
    vm.warp(block.timestamp + referenceRateResetFrequency);
    sortedOracles.setMedianTimestampToNow(address(stableToken));

    uint256 updatedCeloBucket = initialCeloBucket.mul(2);
    uint256 updatedStableBucket = updatedCeloBucket.mul(stableAmountForRate).div(celoAmountForRate);
    (uint256 expected, ) = approveAndBuy(amount, true, updatedCeloBucket, updatedStableBucket);

    assertEq(celoToken.balanceOf(buyer), buyerCeloBalance + amount);
    (uint256 mintableStable, uint256 tradableCelo) = exchange.getBuyAndSellBuckets(true);
    assertEq(mintableStable, updatedStableBucket + expected);
    assertEq(tradableCelo, updatedCeloBucket - amount);
  }

  function test_buyCelo_whenBucketsStaleAndReportStale_doesNotUpdateBuckets() public {
    uint256 amount = 1000;
    mint(celoToken, address(reserve), initialReserveBalance);
    vm.warp(block.timestamp + referenceRateResetFrequency);
    sortedOracles.setOldestReportExpired(address(stableToken));

    (uint256 expected, ) = approveAndBuy(amount, true);
    assertEq(celoToken.balanceOf(buyer), buyerCeloBalance + amount);
    (uint256 mintableStable, uint256 tradableCelo) = exchange.getBuyAndSellBuckets(true);
    assertEq(mintableStable, initialStableBucket + expected);
    assertEq(tradableCelo, initialCeloBucket - amount);
  }

  function test_buyStable_executesTrade(uint256 amount) public {
    vm.assume(amount < buyerStableBalance && amount > 0);
    uint256 stableTokenSupplyBefore = stableToken.totalSupply();
    uint256 expected = getSellTokenAmount(amount, initialCeloBucket, initialStableBucket);

    approveAndBuy(amount, false);

    assertEq(stableToken.balanceOf(buyer), buyerStableBalance + amount);
    assertEq(celoToken.balanceOf(buyer), buyerCeloBalance - expected);
    assertEq(celoToken.allowance(buyer, address(exchange)), 0);
    assertEq(celoToken.balanceOf(address(reserve)), initialReserveBalance + expected);
    assertEq(stableToken.totalSupply(), stableTokenSupplyBefore + amount);
    (uint256 mintableStable, uint256 tradableCelo) = exchange.getBuyAndSellBuckets(true);
    assertEq(mintableStable, initialStableBucket - amount);
    assertEq(tradableCelo, initialCeloBucket + expected);
  }

  function test_buyStable_revertWithoutApproval(uint256 amount) public {
    vm.assume(amount < buyerStableBalance && amount > 10);
    uint256 expected = getSellTokenAmount(amount, initialCeloBucket, initialStableBucket);
    vm.assume(expected < buyerCeloBalance);
    approveExchange(amount - 10, false);
    vm.expectRevert("transfer value exceeded sender's allowance for recipient");
    exchange.buy(amount, expected, false);
  }

  function test_buyStable_revertIfMinBuyAmountUnsatisfied(uint256 amount) public {
    vm.assume(amount < buyerStableBalance && amount > 0);
    uint256 expected = getSellTokenAmount(amount, initialCeloBucket, initialStableBucket);
    vm.assume(expected > 0);
    approveExchange(amount, false);
    vm.expectRevert("Calculated sellAmount was greater than specified maxSellAmount");
    exchange.buy(amount + 10, expected, false);
  }

  function test_buyStable_whenBucketsStaleAndReportFresh_updatesBuckets() public {
    uint256 amount = 1000;
    mint(celoToken, address(reserve), initialReserveBalance);
    vm.warp(block.timestamp + referenceRateResetFrequency);
    sortedOracles.setMedianTimestampToNow(address(stableToken));

    uint256 updatedCeloBucket = initialCeloBucket.mul(2);
    uint256 updatedStableBucket = updatedCeloBucket.mul(stableAmountForRate).div(celoAmountForRate);
    (uint256 expected, ) = approveAndBuy(amount, false, updatedCeloBucket, updatedStableBucket);

    assertEq(celoToken.balanceOf(buyer), buyerCeloBalance - expected);
    (uint256 mintableStable, uint256 tradableCelo) = exchange.getBuyAndSellBuckets(true);
    assertEq(mintableStable, updatedStableBucket - amount);
    assertEq(tradableCelo, updatedCeloBucket + expected);
  }

  function test_buyStable_whenBucketsStaleAndReportStale_doesNotUpdateBuckets() public {
    uint256 amount = 1000;
    mint(celoToken, address(reserve), initialReserveBalance);
    vm.warp(block.timestamp + referenceRateResetFrequency);
    sortedOracles.setOldestReportExpired(address(stableToken));

    (uint256 expected, ) = approveAndBuy(amount, false);
    assertEq(celoToken.balanceOf(buyer), buyerCeloBalance - expected);
    (uint256 mintableStable, uint256 tradableCelo) = exchange.getBuyAndSellBuckets(true);
    assertEq(mintableStable, initialStableBucket - amount);
    assertEq(tradableCelo, initialCeloBucket + expected);
  }

  function test_whenContractIsFrozen_reverts() public {
    freezer.freeze(address(exchange));
    vm.expectRevert("can't call when contract is frozen");
    exchange.buy(1000, 0, false);
  }
}
