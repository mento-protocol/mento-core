// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, state-visibility, max-states-count, var-name-mixedcase

import { Test, console } from "forge-std-next/Test.sol";

import { GoodDollarExchangeProvider } from "contracts/goodDollar/GoodDollarExchangeProvider.sol";
import { ERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/ERC20.sol";

import { IReserve } from "contracts/interfaces/IReserve.sol";
import { IExchangeProvider } from "contracts/interfaces/IExchangeProvider.sol";
import { IBancorExchangeProvider } from "contracts/goodDollar/interfaces/IBancorExchangeProvider.sol";
import { ISortedOracles } from "contracts/goodDollar/interfaces/ISortedOracles.sol";

contract GoodDollarExchangeProviderTest is Test {
  /* ------- Events from IGoodDollarExchangeProvider ------- */

  event ExchangeCreated(bytes32 indexed exchangeId, address indexed reserveAsset, address indexed tokenAddress);

  event SortedOraclesUpdated(address indexed sortedOracles);

  event ExpansionControllerUpdated(address indexed expansionController);

  event AvatarUpdated(address indexed AVATAR);

  event ReserveRatioUpdated(bytes32 indexed exchangeId, uint32 reserveRatio);

  /* ------------------------------------------- */

  ERC20 public reserveToken;
  ERC20 public token;
  ERC20 public token2;

  address public reserveAddress;
  address public sortedOraclesAddress;
  address public brokerAddress;
  address public avatarAddress;
  address public expansionControllerAddress;
  address public reserveTokenRateFeed;

  IBancorExchangeProvider.PoolExchange public poolExchange1;

  function setUp() public virtual {
    reserveToken = new ERC20("cUSD", "cUSD");
    token = new ERC20("Good$", "G$");
    token2 = new ERC20("Good2$", "G2$");

    reserveTokenRateFeed = makeAddr("ReserveTokenRateFeed");

    reserveAddress = makeAddr("Reserve");
    sortedOraclesAddress = makeAddr("SortedOracles");
    brokerAddress = makeAddr("Broker");
    avatarAddress = makeAddr("Avatar");
    expansionControllerAddress = makeAddr("ExpansionController");

    poolExchange1 = IBancorExchangeProvider.PoolExchange({
      reserveAsset: address(reserveToken),
      tokenAddress: address(token),
      tokenSupply: 300_000 * 1e18,
      reserveBalance: 60_000 * 1e18,
      reserveRatio: 200000,
      exitConribution: 10000
    });

    vm.mockCall(
      reserveAddress,
      abi.encodeWithSelector(IReserve(reserveAddress).isStableAsset.selector, address(token)),
      abi.encode(true)
    );
    vm.mockCall(
      reserveAddress,
      abi.encodeWithSelector(IReserve(reserveAddress).isStableAsset.selector, address(token2)),
      abi.encode(true)
    );
    vm.mockCall(
      reserveAddress,
      abi.encodeWithSelector(IReserve(reserveAddress).isCollateralAsset.selector, address(reserveToken)),
      abi.encode(true)
    );

    vm.mockCall(
      sortedOraclesAddress,
      abi.encodeWithSelector(ISortedOracles(sortedOraclesAddress).numRates.selector),
      abi.encode(10)
    );
  }

  function initializeGoodDollarExchangeProvider() internal returns (GoodDollarExchangeProvider) {
    GoodDollarExchangeProvider exchangeProvider = new GoodDollarExchangeProvider(false);

    exchangeProvider.initialize(
      brokerAddress,
      reserveAddress,
      sortedOraclesAddress,
      expansionControllerAddress,
      avatarAddress
    );
    return exchangeProvider;
  }
}

contract GoodDollarExchangeProviderTest_initializerSettersGetters is GoodDollarExchangeProviderTest {
  GoodDollarExchangeProvider exchangeProvider;

  function setUp() public override {
    super.setUp();
    exchangeProvider = initializeGoodDollarExchangeProvider();
  }

  /* ---------- Initilizer ---------- */

  function test_initializer() public {
    assertEq(exchangeProvider.owner(), address(this));
    assertEq(exchangeProvider.broker(), brokerAddress);
    assertEq(address(exchangeProvider.reserve()), reserveAddress);
    assertEq(address(exchangeProvider.sortedOracles()), sortedOraclesAddress);
    assertEq(address(exchangeProvider.expansionController()), expansionControllerAddress);
    assertEq(exchangeProvider.AVATAR(), avatarAddress);
  }

  /* ---------- Setters ---------- */

  function test_setAvatar_whenSenderIsNotOwner_shouldRevert() public {
    vm.prank(makeAddr("NotOwner"));
    vm.expectRevert("Ownable: caller is not the owner");
    exchangeProvider.setAvatar(makeAddr("NewAvatar"));
  }

  function test_setAvatar_whenAddressIsZero_shouldRevert() public {
    vm.expectRevert("Avatar address must be set");
    exchangeProvider.setAvatar(address(0));
  }

  function test_setAvatar_whenSenderIsOwner_shouldUpdateAndEmit() public {
    address newAvatar = makeAddr("NewAvatar");
    vm.expectEmit(true, true, true, true);
    emit AvatarUpdated(newAvatar);
    exchangeProvider.setAvatar(newAvatar);

    assertEq(exchangeProvider.AVATAR(), newAvatar);
  }

  function test_setExpansionController_whenSenderIsNotOwner_shouldRevert() public {
    vm.prank(makeAddr("NotOwner"));
    vm.expectRevert("Ownable: caller is not the owner");
    exchangeProvider.setExpansionController(makeAddr("NewExpansionController"));
  }

  function test_setExpansionController_whenAddressIsZero_shouldRevert() public {
    vm.expectRevert("ExpansionController address must be set");
    exchangeProvider.setExpansionController(address(0));
  }

  function test_setExpansionController_whenSenderIsOwner_shouldUpdateAndEmit() public {
    address newExpansionController = makeAddr("NewExpansionController");
    vm.expectEmit(true, true, true, true);
    emit ExpansionControllerUpdated(newExpansionController);
    exchangeProvider.setExpansionController(newExpansionController);

    assertEq(address(exchangeProvider.expansionController()), newExpansionController);
  }

  function test_setSortedOracles_whenSenderIsNotOwner_shouldRevert() public {
    vm.prank(makeAddr("NotOwner"));
    vm.expectRevert("Ownable: caller is not the owner");
    exchangeProvider.setSortedOracles(makeAddr("NewSortedOracles"));
  }

  function test_setSortedOracles_whenAddressIsZero_shouldRevert() public {
    vm.expectRevert("SortedOracles address must be set");
    exchangeProvider.setSortedOracles(address(0));
  }

  function test_setSortedOracles_whenSenderIsOwner_shouldUpdateAndEmit() public {
    address newSortedOracles = makeAddr("NewSortedOracles");
    vm.expectEmit(true, true, true, true);
    emit SortedOraclesUpdated(newSortedOracles);
    exchangeProvider.setSortedOracles(newSortedOracles);

    assertEq(address(exchangeProvider.sortedOracles()), newSortedOracles);
  }

  function test_setReserveAssetUSDRateFeed_whenSenderIsNotOwner_shouldRevert() public {
    vm.prank(makeAddr("NotOwner"));
    vm.expectRevert("Ownable: caller is not the owner");
    exchangeProvider.setReserveAssetUSDRateFeed(address(reserveToken), reserveTokenRateFeed);
  }

  function test_setReserveAssetUSDRateFeed_whenAssetAddressIsNotReserveAsset_shouldRevert() public {
    vm.mockCall(
      reserveAddress,
      abi.encodeWithSelector(IReserve(reserveAddress).isCollateralAsset.selector),
      abi.encode(false)
    );

    vm.expectRevert("Reserve asset must be a collateral asset");
    exchangeProvider.setReserveAssetUSDRateFeed(address(token), reserveTokenRateFeed);
  }

  function test_setReserveAssetUSDRateFeed_whenNoRates_shouldRevert() public {
    vm.mockCall(
      sortedOraclesAddress,
      abi.encodeWithSelector(ISortedOracles(sortedOraclesAddress).numRates.selector),
      abi.encode(0)
    );

    vm.expectRevert("USD rate feed must have rates");
    exchangeProvider.setReserveAssetUSDRateFeed(address(reserveToken), reserveTokenRateFeed);
  }

  function test_setReserveAssetUSDRateFeed_whenSenderIsOwner_shouldUpdate() public {
    address newReserveAssetUSDRateFeed = makeAddr("NewReserveAssetUSDRateFeed");
    exchangeProvider.setReserveAssetUSDRateFeed(address(reserveToken), newReserveAssetUSDRateFeed);

    assertEq(exchangeProvider.reserveAssetUSDRateFeed(address(reserveToken)), newReserveAssetUSDRateFeed);
  }
}

contract GoodDollarExchangeProviderTest_currentPriceUSD is GoodDollarExchangeProviderTest {
  GoodDollarExchangeProvider exchangeProvider;
  bytes32 exchangeId;

  function setUp() public override {
    super.setUp();
    vm.mockCall(
      sortedOraclesAddress,
      abi.encodeWithSelector(ISortedOracles(sortedOraclesAddress).medianRate.selector, reserveTokenRateFeed),
      abi.encode(1e24 * 0.5, 1e24) // mock 0.5 reserveAsset/USD rate
    );
    exchangeProvider = initializeGoodDollarExchangeProvider();
    exchangeId = exchangeProvider.createExchange(poolExchange1);
  }

  function test_currentPriceUSD_whenExchangeIdDoesNotExist_shouldRevert() public {
    vm.expectRevert("Exchange does not exist");
    exchangeProvider.currentPriceUSD(bytes32(0));
  }

  function test_currentPriceUSD_whenRateFeedNotSet_shouldRevert() public {
    vm.expectRevert("USD rate feed not set");
    exchangeProvider.currentPriceUSD(exchangeId);
  }

  function test_currentPriceUSD_whenRateFeedSet_shouldCalculatePrice() public {
    exchangeProvider.setReserveAssetUSDRateFeed(address(reserveToken), reserveTokenRateFeed);

    uint256 price = exchangeProvider.currentPriceUSD(exchangeId);
    assertEq(1e18 * 0.5, price);
  }
}

contract GoodDollarExchangeProviderTest_createExchange is GoodDollarExchangeProviderTest {
  GoodDollarExchangeProvider exchangeProvider;

  function setUp() public override {
    super.setUp();
    exchangeProvider = initializeGoodDollarExchangeProvider();
  }

  function test_createExchange_whenSenderIsNotOwner_shouldRevert() public {
    vm.prank(makeAddr("NotOwner"));
    vm.expectRevert("Ownable: caller is not the owner");
    exchangeProvider.createExchange(poolExchange1, reserveTokenRateFeed);
  }

  function test_createExchange_whenSenderIsOwner_shouldCreateExchangeAndEmit() public {
    vm.expectEmit(true, true, true, true);
    bytes32 expectedExchangeId = keccak256(abi.encodePacked(reserveToken.symbol(), token.symbol()));
    emit ExchangeCreated(expectedExchangeId, address(reserveToken), address(token));
    bytes32 exchangeId = exchangeProvider.createExchange(poolExchange1, reserveTokenRateFeed);

    IBancorExchangeProvider.PoolExchange memory poolExchange = exchangeProvider.getPoolExchange(exchangeId);

    assertEq(exchangeProvider.reserveAssetUSDRateFeed(address(reserveToken)), reserveTokenRateFeed);
    assertEq(poolExchange.reserveAsset, poolExchange1.reserveAsset);
    assertEq(poolExchange.tokenAddress, poolExchange1.tokenAddress);
    assertEq(poolExchange.tokenSupply, poolExchange1.tokenSupply);
    assertEq(poolExchange.reserveBalance, poolExchange1.reserveBalance);
    assertEq(poolExchange.reserveRatio, poolExchange1.reserveRatio);
    assertEq(poolExchange.exitConribution, poolExchange1.exitConribution);

    IExchangeProvider.Exchange[] memory exchanges = exchangeProvider.getExchanges();
    assertEq(exchanges.length, 1);
    assertEq(exchanges[0].exchangeId, exchangeId);

    assertEq(exchangeProvider.tokenPrecisionMultipliers(address(reserveToken)), 1);
    assertEq(exchangeProvider.tokenPrecisionMultipliers(address(token)), 1);
  }
}

contract GoodDollarExchangeProviderTest_mintFromExpansion is GoodDollarExchangeProviderTest {
  GoodDollarExchangeProvider exchangeProvider;
  bytes32 exchangeId;
  uint256 expansionRate;

  function setUp() public override {
    super.setUp();
    expansionRate = 1e18 * 0.99;
    exchangeProvider = initializeGoodDollarExchangeProvider();
    exchangeId = exchangeProvider.createExchange(poolExchange1, reserveTokenRateFeed);
  }

  function test_mintFromExpansion_whenCallerIsNotExpansionController_shouldRevert() public {
    vm.prank(makeAddr("NotExpansionController"));
    vm.expectRevert("Only ExpansionController can call this function");
    exchangeProvider.mintFromExpansion(exchangeId, expansionRate);
  }

  function test_mintFromExpansionRate_whenExpansionRateIs0_shouldRevert() public {
    vm.prank(expansionControllerAddress);
    vm.expectRevert("Expansion rate must be greater than 0");
    exchangeProvider.mintFromExpansion(exchangeId, 0);
  }

  function test_mintFromExpansion_whenExchangeIdIsInvalid_shouldRevert() public {
    vm.prank(expansionControllerAddress);
    vm.expectRevert("An exchange with the specified id does not exist");
    exchangeProvider.mintFromExpansion(bytes32(0), expansionRate);
  }

  function test_mintFromExpansion_whenExpansionRateIs100Percent_shouldReturn0() public {
    vm.prank(expansionControllerAddress);
    uint256 amountToMint = exchangeProvider.mintFromExpansion(exchangeId, 1e6);
    assertEq(amountToMint, 0);
  }

  function test_mintFromExpansion_whenValidExpansionRate_shouldReturnCorrectAmountAndEmit() public {
    // formula: amountToMint = (tokenSupply * reserveRatio - tokenSupply * newRatio) / newRatio
    // amountToMint = (300_000 * 0.2 - 300_000 * 0.2 * 0.99 ) / 0.2 * 0.99 ≈ 3030.303030303030303030
    uint256 expectedAmountToMint = 3030303030303030303030;
    uint32 expectedReserveRatio = 0.2 * 0.99 * 1e6;

    vm.expectEmit(true, true, true, true);
    emit ReserveRatioUpdated(exchangeId, expectedReserveRatio);
    vm.prank(expansionControllerAddress);
    uint256 amountToMint = exchangeProvider.mintFromExpansion(exchangeId, expansionRate);
    assertEq(amountToMint, expectedAmountToMint);

    IBancorExchangeProvider.PoolExchange memory poolExchangeAfter = exchangeProvider.getPoolExchange(exchangeId);
    assertEq(poolExchangeAfter.tokenSupply, poolExchange1.tokenSupply + amountToMint);
    assertEq(poolExchangeAfter.reserveRatio, expectedReserveRatio);
  }

  function test_mintFromExpansion_whenValidExpansionRate_shouldNotChangePrice() public {
    uint256 priceBefore = exchangeProvider.currentPrice(exchangeId);

    vm.prank(expansionControllerAddress);
    exchangeProvider.mintFromExpansion(exchangeId, expansionRate);

    uint256 priceAfter = exchangeProvider.currentPrice(exchangeId);

    assertEq(priceBefore, priceAfter);
  }
}

contract GoodDollarExchangeProviderTest_mintFromInterest is GoodDollarExchangeProviderTest {
  GoodDollarExchangeProvider exchangeProvider;
  bytes32 exchangeId;
  uint256 reserveInterest;

  function setUp() public override {
    super.setUp();
    reserveInterest = 1000 * 1e18;
    exchangeProvider = initializeGoodDollarExchangeProvider();
    exchangeId = exchangeProvider.createExchange(poolExchange1, reserveTokenRateFeed);
  }

  function test_mintFromInterest_whenCallerIsNotExpansionController_shouldRevert() public {
    vm.prank(makeAddr("NotExpansionController"));
    vm.expectRevert("Only ExpansionController can call this function");
    exchangeProvider.mintFromInterest(exchangeId, reserveInterest);
  }

  function test_mintFromInterest_whenExchangeIdIsInvalid_shouldRevert() public {
    vm.prank(expansionControllerAddress);
    vm.expectRevert("An exchange with the specified id does not exist");
    exchangeProvider.mintFromInterest(bytes32(0), reserveInterest);
  }

  function test_mintFromInterest_whenInterestIs0_shouldReturn0() public {
    vm.prank(expansionControllerAddress);
    uint256 amountToMint = exchangeProvider.mintFromInterest(exchangeId, 0);
    assertEq(amountToMint, 0);
  }

  function test_mintFromInterest_whenInterestLarger0_shouldReturnCorrectAmount() public {
    // formula: amountToMint = reserveInterest * tokenSupply / reserveBalance
    // amountToMint = 1000 * 300_000 / 60_000 = 5000
    uint256 expectedAmountToMint = 5000 * 1e18;

    vm.prank(expansionControllerAddress);
    uint256 amountToMint = exchangeProvider.mintFromInterest(exchangeId, reserveInterest);
    assertEq(amountToMint, expectedAmountToMint);

    IBancorExchangeProvider.PoolExchange memory poolExchangeAfter = exchangeProvider.getPoolExchange(exchangeId);
    assertEq(poolExchangeAfter.tokenSupply, poolExchange1.tokenSupply + amountToMint);
    assertEq(poolExchangeAfter.reserveBalance, poolExchange1.reserveBalance + reserveInterest);
  }

  function test_mintFromInterest_whenInterestLarger0_shouldNotChangePrice() public {
    uint256 priceBefore = exchangeProvider.currentPrice(exchangeId);

    vm.prank(expansionControllerAddress);
    exchangeProvider.mintFromInterest(exchangeId, reserveInterest);

    uint256 priceAfter = exchangeProvider.currentPrice(exchangeId);

    assertEq(priceBefore, priceAfter);
  }
}

contract GoodDollarExchangeProviderTest_updateRatioForReward is GoodDollarExchangeProviderTest {
  GoodDollarExchangeProvider exchangeProvider;
  bytes32 exchangeId;
  uint256 reward;

  function setUp() public override {
    super.setUp();
    reward = 1000 * 1e18;
    exchangeProvider = initializeGoodDollarExchangeProvider();
    exchangeId = exchangeProvider.createExchange(poolExchange1, reserveTokenRateFeed);
  }

  function test_updateRatioForReward_whenCallerIsNotExpansionController_shouldRevert() public {
    vm.prank(makeAddr("NotExpansionController"));
    vm.expectRevert("Only ExpansionController can call this function");
    exchangeProvider.updateRatioForReward(exchangeId, reward);
  }

  function test_updateRatioForReward_whenExchangeIdIsInvalid_shouldRevert() public {
    vm.prank(expansionControllerAddress);
    vm.expectRevert("An exchange with the specified id does not exist");
    exchangeProvider.updateRatioForReward(bytes32(0), reward);
  }

  function test_updateRatioForReward_whenRewardLarger0_shouldReturnCorrectRatioAndEmit() public {
    // formula: newRatio = reserveBalance / (tokenSupply + reward) * currentPrice
    // reserveRatio = 60_000 / (300_000 + 1000) * 1 ≈ 0.199335
    uint32 expectedReserveRatio = 199335;

    vm.expectEmit(true, true, true, true);
    emit ReserveRatioUpdated(exchangeId, expectedReserveRatio);
    vm.prank(expansionControllerAddress);
    exchangeProvider.updateRatioForReward(exchangeId, reward);

    IBancorExchangeProvider.PoolExchange memory poolExchangeAfter = exchangeProvider.getPoolExchange(exchangeId);
    assertEq(poolExchangeAfter.reserveRatio, expectedReserveRatio);
    assertEq(poolExchangeAfter.tokenSupply, poolExchange1.tokenSupply + reward);
  }
}

contract GoodDollarExchangeProviderTest_pausable is GoodDollarExchangeProviderTest {
  GoodDollarExchangeProvider exchangeProvider;
  bytes32 exchangeId;

  function setUp() public override {
    super.setUp();
    exchangeProvider = initializeGoodDollarExchangeProvider();
    exchangeId = exchangeProvider.createExchange(poolExchange1, reserveTokenRateFeed);
  }

  function test_pause_whenCallerIsNotAvatar_shouldRevert() public {
    vm.prank(makeAddr("NotAvatar"));
    vm.expectRevert("Only Avatar can call this function");
    exchangeProvider.pause();
  }

  function test_unpause_whenCallerIsNotAvatar_shouldRevert() public {
    vm.prank(makeAddr("NotAvatar"));
    vm.expectRevert("Only Avatar can call this function");
    exchangeProvider.unpause();
  }

  function test_pause_whenCallerIsAvatar_shouldPauseAndDisableExchange() public {
    vm.prank(avatarAddress);
    exchangeProvider.pause();

    assert(exchangeProvider.paused());

    vm.startPrank(brokerAddress);
    vm.expectRevert("Pausable: paused");
    exchangeProvider.swapIn(exchangeId, address(reserveToken), address(token), 1e18);

    vm.expectRevert("Pausable: paused");
    exchangeProvider.swapOut(exchangeId, address(reserveToken), address(token), 1e18);

    vm.startPrank(expansionControllerAddress);
    vm.expectRevert("Pausable: paused");
    exchangeProvider.mintFromExpansion(exchangeId, 1e18);

    vm.expectRevert("Pausable: paused");
    exchangeProvider.mintFromInterest(exchangeId, 1e18);

    vm.expectRevert("Pausable: paused");
    exchangeProvider.updateRatioForReward(exchangeId, 1e18);
  }

  function test_unpause_whenCallerIsAvatar_shouldUnpauseAndEnableExchange() public {
    vm.prank(avatarAddress);
    exchangeProvider.pause();

    vm.prank(avatarAddress);
    exchangeProvider.unpause();

    assert(exchangeProvider.paused() == false);

    vm.startPrank(brokerAddress);

    exchangeProvider.swapIn(exchangeId, address(reserveToken), address(token), 1e18);
    exchangeProvider.swapOut(exchangeId, address(reserveToken), address(token), 1e18);

    vm.startPrank(expansionControllerAddress);

    exchangeProvider.mintFromExpansion(exchangeId, 1e18);
    exchangeProvider.mintFromInterest(exchangeId, 1e18);
    exchangeProvider.updateRatioForReward(exchangeId, 1e18);
  }
}
