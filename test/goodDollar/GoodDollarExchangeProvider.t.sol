// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, state-visibility, max-states-count, var-name-mixedcase

import { Test, console } from "forge-std-next/Test.sol";

import { GoodDollarExchangeProvider } from "contracts/goodDollar/GoodDollarExchangeProvider.sol";
import { ERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/ERC20.sol";

import { IReserve } from "contracts/interfaces/IReserve.sol";
import { IExchangeProvider } from "contracts/interfaces/IExchangeProvider.sol";
import { IBancorExchangeProvider } from "contracts/goodDollar/interfaces/IBancorExchangeProvider.sol";
import { IGoodDollarExpansionController } from "contracts/goodDollar/interfaces/IGoodDollarExpansionController.sol";
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

  function test_setAvatr_whenSenderIsNotOwner_shouldRevert() public {
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

contract GoodDollarExchangeProviderTest_calculateExpansion is GoodDollarExchangeProviderTest {
  GoodDollarExchangeProvider exchangeProvider;
  bytes32 exchangeId;
  uint32 expansionRate;

  function setUp() public override {
    super.setUp();
    expansionRate = 990000;
    exchangeProvider = initializeGoodDollarExchangeProvider();
    exchangeId = exchangeProvider.createExchange(poolExchange1, reserveTokenRateFeed);
  }

  function test_calculateExpansion_whenCallerIsNotExpansionController_shouldRevert() public {
    vm.prank(makeAddr("NotExpansionController"));
    vm.expectRevert("Only ExpansionController can call this function");
    exchangeProvider.calculateExpansion(exchangeId, expansionRate);
  }

  function test_calculateExpansionRate_whenExpansionRateIs0_shouldRevert() public {
    vm.prank(expansionControllerAddress);
    vm.expectRevert("Expansion rate must be greater than 0");
    uint256 amountToMint = exchangeProvider.calculateExpansion(exchangeId, 0);
  }

  function test_calculateExpansion_whenExchangeIdIsInvalid_shouldRevert() public {
    vm.prank(expansionControllerAddress);
    vm.expectRevert("An exchange with the specified id does not exist");
    exchangeProvider.calculateExpansion(bytes32(0), expansionRate);
  }

  function test_calculateExpansion_whenExpansionRateIs100Percent_shouldReturn0() public {
    vm.prank(expansionControllerAddress);
    uint256 amountToMint = exchangeProvider.calculateExpansion(exchangeId, 1e6);
    assertEq(amountToMint, 0);
  }

  function test_calculateExpansion_whenValidExpansionRate_shouldReturnCorrectAmountAndEmit() public {
    // formula: amountToMint = (tokenSupply * reserveRatio - tokenSupply * newRatio) / newRatio
    // amountToMint = (300_000 * 0.2 - 300_000 * 0.2 * 0.99 ) / 0.2 * 0.99 ≈ 3030.303030303030303030
    uint256 expectedAmountToMint = 3030303030303030303030;
    uint32 expectedReserveRatio = 0.2 * 0.99 * 1e6;

    vm.expectEmit(true, true, true, true);
    emit ReserveRatioUpdated(exchangeId, expectedReserveRatio);
    vm.prank(expansionControllerAddress);
    uint256 amountToMint = exchangeProvider.calculateExpansion(exchangeId, expansionRate);
    assertEq(amountToMint, expectedAmountToMint);

    IBancorExchangeProvider.PoolExchange memory poolExchangeAfter = exchangeProvider.getPoolExchange(exchangeId);
    assertEq(poolExchangeAfter.tokenSupply, poolExchange1.tokenSupply + amountToMint);
    assertEq(poolExchangeAfter.reserveRatio, expectedReserveRatio);
  }

  function test_calculateExpansion_whenValidExpansionRate_shouldNotChangePrice() public {
    uint256 priceBefore = exchangeProvider.currentPrice(exchangeId);

    vm.prank(expansionControllerAddress);
    uint256 amountToMint = exchangeProvider.calculateExpansion(exchangeId, expansionRate);

    uint256 priceAfter = exchangeProvider.currentPrice(exchangeId);

    assertEq(priceBefore, priceAfter);
  }
}

contract GoodDollarExchangeProviderTest_calculateInterest is GoodDollarExchangeProviderTest {
  GoodDollarExchangeProvider exchangeProvider;
  bytes32 exchangeId;
  uint256 reserveInterest;

  function setUp() public override {
    super.setUp();
    reserveInterest = 1000 * 1e18;
    exchangeProvider = initializeGoodDollarExchangeProvider();
    exchangeId = exchangeProvider.createExchange(poolExchange1, reserveTokenRateFeed);
  }

  function test_calculateInterest_whenCallerIsNotExpansionController_shouldRevert() public {
    vm.prank(makeAddr("NotExpansionController"));
    vm.expectRevert("Only ExpansionController can call this function");
    exchangeProvider.calculateInterest(exchangeId, reserveInterest);
  }

  function test_calculateInterest_whenExchangeIdIsInvalid_shouldRevert() public {
    vm.prank(expansionControllerAddress);
    vm.expectRevert("An exchange with the specified id does not exist");
    exchangeProvider.calculateInterest(bytes32(0), reserveInterest);
  }

  function test_calculateInterest_whenInterestIs0_shouldReturn0() public {
    vm.prank(expansionControllerAddress);
    uint256 amountToMint = exchangeProvider.calculateInterest(exchangeId, 0);
    assertEq(amountToMint, 0);
  }

  function test_calculateInterest_whenInterestLarger0_shouldReturnCorrectAmount() public {
    // formula: amountToMint = reserveInterest * tokenSupply / reserveBalance
    // amountToMint = 1000 * 300_000 / 60_000 = 5000
    uint256 expectedAmountToMint = 5000 * 1e18;

    vm.prank(expansionControllerAddress);
    uint256 amountToMint = exchangeProvider.calculateInterest(exchangeId, reserveInterest);
    assertEq(amountToMint, expectedAmountToMint);

    IBancorExchangeProvider.PoolExchange memory poolExchangeAfter = exchangeProvider.getPoolExchange(exchangeId);
    assertEq(poolExchangeAfter.tokenSupply, poolExchange1.tokenSupply + amountToMint);
    assertEq(poolExchangeAfter.reserveBalance, poolExchange1.reserveBalance + reserveInterest);
  }

  function test_calculateInterest_whenInterestLarger0_shouldNotChangePrice() public {
    uint256 priceBefore = exchangeProvider.currentPrice(exchangeId);

    vm.prank(expansionControllerAddress);
    uint256 amountToMint = exchangeProvider.calculateInterest(exchangeId, reserveInterest);

    uint256 priceAfter = exchangeProvider.currentPrice(exchangeId);

    assertEq(priceBefore, priceAfter);
  }
}

contract GoodDollarExchangeProviderTest_calculateRatioForReward is GoodDollarExchangeProviderTest {
  GoodDollarExchangeProvider exchangeProvider;
  bytes32 exchangeId;
  uint256 reward;

  function setUp() public override {
    super.setUp();
    reward = 1000 * 1e18;
    exchangeProvider = initializeGoodDollarExchangeProvider();
    exchangeId = exchangeProvider.createExchange(poolExchange1, reserveTokenRateFeed);
  }

  function test_calculateRatioForReward_whenCallerIsNotExpansionController_shouldRevert() public {
    vm.prank(makeAddr("NotExpansionController"));
    vm.expectRevert("Only ExpansionController can call this function");
    exchangeProvider.calculateRatioForReward(exchangeId, reward);
  }

  function test_calculateRatioForReward_whenExchangeIdIsInvalid_shouldRevert() public {
    vm.prank(expansionControllerAddress);
    vm.expectRevert("An exchange with the specified id does not exist");
    exchangeProvider.calculateRatioForReward(bytes32(0), reward);
  }

  function test_calculateRatioForReward_whenRewardLarger0_shouldReturnCorrectRatioAndEmit() public {
    // formula: newRatio = reserveBalance / (tokenSupply + reward) * currentPrice
    // reserveRatio = 60_000 / (300_000 + 1000) * 1 ≈ 0.199335
    uint32 expectedReserveRatio = 199335;

    vm.expectEmit(true, true, true, true);
    emit ReserveRatioUpdated(exchangeId, expectedReserveRatio);
    vm.prank(expansionControllerAddress);
    exchangeProvider.calculateRatioForReward(exchangeId, reward);

    IBancorExchangeProvider.PoolExchange memory poolExchangeAfter = exchangeProvider.getPoolExchange(exchangeId);
    assertEq(poolExchangeAfter.reserveRatio, expectedReserveRatio);
    assertEq(poolExchangeAfter.tokenSupply, poolExchange1.tokenSupply + reward);
  }
}
