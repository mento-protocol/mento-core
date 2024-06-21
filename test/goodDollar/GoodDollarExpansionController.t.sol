// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase

import { Test, console } from "forge-std-next/Test.sol";
import { ERC20Mock } from "openzeppelin-contracts-next/contracts/mocks/ERC20Mock.sol";
import { GoodDollarExpansionController } from "contracts/goodDollar/GoodDollarExpansionController.sol";

import { IGoodDollarExpansionController } from "contracts/goodDollar/interfaces/IGoodDollarExpansionController.sol";
import { IGoodDollarExchangeProvider } from "contracts/goodDollar/interfaces/IGoodDollarExchangeProvider.sol";
import { IBancorExchangeProvider } from "contracts/goodDollar/interfaces/IBancorExchangeProvider.sol";
import { IDistributionHelper } from "contracts/goodDollar/interfaces/IDistributionHelper.sol";

contract GoodDollarExpansionControllerTest is Test {
  /* ------- Events from IGoodDollarExpansionController ------- */

  event GoodDollarExchangeProviderUpdated(address indexed exchangeProvider);

  event DistributionHelperUpdated(address indexed distributionHelper);

  event ReserveUpdated(address indexed reserve);

  event AvatarUpdated(address indexed avatar);

  event ExpansionConfigSet(bytes32 indexed exchangeId, uint256 expansionRate, uint256 expansionfrequency);

  event RewardMinted(bytes32 indexed exchangeId, address indexed to, uint256 amount);

  event UBIMinted(bytes32 indexed exchangeId, uint256 amount);

  /* ------------------------------------------- */

  ERC20Mock public reserveToken;
  ERC20Mock public token;

  address public exchangeProvider;
  address public distributionHelper;
  address public reserveAddress;
  address public avatarAddress;

  bytes32 exchangeId = "ExchangeId";

  uint256 expansionRate = 1e18 * 0.01;
  uint256 expansionFrequency = 1 days;

  function setUp() public virtual {
    reserveToken = new ERC20Mock("cUSD", "cUSD", address(this), 1);
    token = new ERC20Mock("Good$", "G$", address(this), 1);

    exchangeProvider = makeAddr("ExchangeProvider");
    distributionHelper = makeAddr("DistributionHelper");
    reserveAddress = makeAddr("Reserve");
    avatarAddress = makeAddr("Avatar");
  }

  function initializeGoodDollarExpansionController() internal returns (GoodDollarExpansionController) {
    GoodDollarExpansionController expansionController = new GoodDollarExpansionController(false);

    expansionController.initialize(exchangeProvider, distributionHelper, reserveAddress, avatarAddress);

    return expansionController;
  }
}

contract GoodDollarExpansionControllerTest_initializerSettersGetters is GoodDollarExpansionControllerTest {
  GoodDollarExpansionController expansionController;

  function setUp() public override {
    super.setUp();
    expansionController = initializeGoodDollarExpansionController();
  }

  /* ---------- Initilizer ---------- */

  function test_initializer() public {
    assertEq(address(expansionController.distributionHelper()), distributionHelper);
    assertEq(expansionController.reserve(), reserveAddress);
    assertEq(address(expansionController.goodDollarExchangeProvider()), exchangeProvider);
    assertEq(expansionController.AVATAR(), avatarAddress);
  }

  /* ---------- Getters ---------- */

  function test_getExpansionConfig_whenConfigIsNotSet_shouldRevert() public {
    vm.expectRevert("Expansion config not set");
    expansionController.getExpansionConfig("NotSetExchangeId");
  }

  function test_getExpansionConfig_whenConfigIsSet_shouldReturnConfig() public {
    vm.prank(avatarAddress);
    expansionController.setExpansionConfig(exchangeId, expansionRate, expansionFrequency);

    IGoodDollarExpansionController.ExchangeExpansionConfig memory config = expansionController.getExpansionConfig(
      exchangeId
    );

    assertEq(config.expansionRate, expansionRate);
    assertEq(config.expansionFrequency, expansionFrequency);
    assertEq(config.lastExpansion, 0);
  }

  /* ---------- Setters ---------- */

  function test_setGoodDollarExchangeProvider_whenSenderIsNotOwner_shouldRevert() public {
    vm.prank(makeAddr("NotOwner"));
    vm.expectRevert("Ownable: caller is not the owner");
    expansionController.setGoodDollarExchangeProvider(makeAddr("NewExchangeProvider"));
  }

  function test_setGoodDollarExchangeProvider_whenAddressIsZero_shouldRevert() public {
    vm.expectRevert("GoodDollarExchangeProvider address must be set");
    expansionController.setGoodDollarExchangeProvider(address(0));
  }

  function test_setGoodDollarExchangeProvider_whenSenderIsOwner_shouldUpdateAndEmit() public {
    address newExchangeProvider = makeAddr("NewExchangeProvider");
    vm.expectEmit(true, true, true, true);
    emit GoodDollarExchangeProviderUpdated(newExchangeProvider);
    expansionController.setGoodDollarExchangeProvider(newExchangeProvider);

    assertEq(address(expansionController.goodDollarExchangeProvider()), newExchangeProvider);
  }

  function test_setDistributionHelper_whenSenderIsNotOwner_shouldRevert() public {
    vm.prank(makeAddr("NotOwner"));
    vm.expectRevert("Ownable: caller is not the owner");
    expansionController.setDistributionHelper(makeAddr("NewDistributionHelper"));
  }

  function test_setDistributiomHelper_whenAddressIsZero_shouldRevert() public {
    vm.expectRevert("DistributionHelper address must be set");
    expansionController.setDistributionHelper(address(0));
  }

  function test_setDistributionHelper_whenCallerIsOwner_shouldUpdateAndEmit() public {
    address newDistributionHelper = makeAddr("NewDistributionHelper");
    vm.expectEmit(true, true, true, true);
    emit DistributionHelperUpdated(newDistributionHelper);
    expansionController.setDistributionHelper(newDistributionHelper);

    assertEq(address(expansionController.distributionHelper()), newDistributionHelper);
  }

  function test_setReserve_whenSenderIsNotOwner_shouldRevert() public {
    vm.prank(makeAddr("NotOwner"));
    vm.expectRevert("Ownable: caller is not the owner");
    expansionController.setReserve(makeAddr("NewReserve"));
  }

  function test_setReserve_whenAddressIsZero_shouldRevert() public {
    vm.expectRevert("Reserve address must be set");
    expansionController.setReserve(address(0));
  }

  function test_setReserve_whenCallerIsOwner_shouldUpdateAndEmit() public {
    address newReserve = makeAddr("NewReserve");
    vm.expectEmit(true, true, true, true);
    emit ReserveUpdated(newReserve);
    expansionController.setReserve(newReserve);

    assertEq(expansionController.reserve(), newReserve);
  }

  function test_setAvatar_whenSenderIsNotOwner_shouldRevert() public {
    vm.prank(makeAddr("NotOwner"));
    vm.expectRevert("Ownable: caller is not the owner");
    expansionController.setAvatar(makeAddr("NewAvatar"));
  }

  function test_setAvatar_whenAddressIsZero_shouldRevert() public {
    vm.expectRevert("Avatar address must be set");
    expansionController.setAvatar(address(0));
  }

  function test_setAvatar_whenCallerIsOwner_shouldUpdateAndEmit() public {
    address newAvatar = makeAddr("NewAvatar");
    vm.expectEmit(true, true, true, true);
    emit AvatarUpdated(newAvatar);
    expansionController.setAvatar(newAvatar);

    assertEq(expansionController.AVATAR(), newAvatar);
  }

  function test_setExpansionConfig_whenSenderIsNotAvatar_shouldRevert() public {
    vm.prank(makeAddr("NotAvatar"));
    vm.expectRevert("Only Avatar can call this function");
    expansionController.setExpansionConfig(exchangeId, expansionRate, expansionFrequency);
  }

  function test_setExpansionConfig_whenExpansionRateIsLargerOrEqualToOne_shouldRevert() public {
    expansionRate = 1e18;

    vm.prank(avatarAddress);
    vm.expectRevert("Expansion rate must be less than 100%");
    expansionController.setExpansionConfig(exchangeId, expansionRate, expansionFrequency);
  }

  function test_setExpansionConfig_whenExpansionRateIsZero_shouldRevert() public {
    expansionRate = 0;

    vm.prank(avatarAddress);
    vm.expectRevert("Expansion rate must be greater than 0");
    expansionController.setExpansionConfig(exchangeId, expansionRate, expansionFrequency);
  }

  function test_setExpansionConfig_whenExpansionFrequencyIsZero_shouldRevert() public {
    expansionFrequency = 0;

    vm.prank(avatarAddress);
    vm.expectRevert("Expansion frequency must be greater than 0");
    expansionController.setExpansionConfig(exchangeId, expansionRate, expansionFrequency);
  }

  function test_setExpansionConfig_whenCallerIsAvatar_shouldUpdateAndEmit() public {
    vm.prank(avatarAddress);
    vm.expectEmit(true, true, true, true);
    emit ExpansionConfigSet(exchangeId, expansionRate, expansionFrequency);
    expansionController.setExpansionConfig(exchangeId, expansionRate, expansionFrequency);

    IGoodDollarExpansionController.ExchangeExpansionConfig memory config = expansionController.getExpansionConfig(
      exchangeId
    );

    assertEq(config.expansionRate, expansionRate);
    assertEq(config.expansionFrequency, expansionFrequency);
    assertEq(config.lastExpansion, 0);
  }
}

contract GoodDollarExpansionControllerTest_mintUBIFromInterest is GoodDollarExpansionControllerTest {
  GoodDollarExpansionController expansionController;

  function setUp() public override {
    super.setUp();
    expansionController = initializeGoodDollarExpansionController();
    vm.prank(avatarAddress);
    expansionController.setExpansionConfig(exchangeId, expansionRate, expansionFrequency);

    IBancorExchangeProvider.PoolExchange memory pool = IBancorExchangeProvider.PoolExchange({
      reserveAsset: address(reserveToken),
      tokenAddress: address(token),
      tokenSupply: 300_000 * 1e18,
      reserveBalance: 60_000 * 1e18,
      reserveRatio: 200000,
      exitConribution: 10000
    });

    vm.mockCall(
      exchangeProvider,
      abi.encodeWithSelector(IGoodDollarExchangeProvider(exchangeProvider).mintFromInterest.selector),
      abi.encode(1000e18)
    );

    vm.mockCall(
      exchangeProvider,
      abi.encodeWithSelector(IBancorExchangeProvider(exchangeProvider).getPoolExchange.selector),
      abi.encode(pool)
    );
  }

  function test_mintUBIFromInterest_whenReserveInterestIs0_shouldRevert() public {
    vm.expectRevert("reserveInterest must be greater than 0");
    expansionController.mintUBIFromInterest(exchangeId, 0);
  }

  function test_mintUBIFromInterest_whenAmountToMintIsLargerThan0_shouldMintTransferAndEmit() public {
    uint256 reserveInterest = 1000e18;
    uint256 amountToMint = 1000e18;
    address interestCollector = makeAddr("InterestCollector");

    deal(address(reserveToken), interestCollector, reserveInterest);
    assertEq(reserveToken.balanceOf(interestCollector), reserveInterest);

    uint256 interestCollectorBalanceBefore = reserveToken.balanceOf(interestCollector);
    uint256 reserveBalanceBefore = reserveToken.balanceOf(reserveAddress);
    uint256 distributionHelperBalanceBefore = token.balanceOf(distributionHelper);

    vm.startPrank(interestCollector);
    reserveToken.approve(address(expansionController), reserveInterest);

    vm.expectEmit(true, true, true, true);
    emit UBIMinted(exchangeId, amountToMint);
    expansionController.mintUBIFromInterest(exchangeId, reserveInterest);

    assertEq(reserveToken.balanceOf(reserveAddress), reserveBalanceBefore + reserveInterest);
    assertEq(token.balanceOf(distributionHelper), distributionHelperBalanceBefore + amountToMint);
    assertEq(reserveToken.balanceOf(interestCollector), interestCollectorBalanceBefore - reserveInterest);
  }
}

contract GoodDollarExpansionControllerTest_mintUBIFromReserveBalance is GoodDollarExpansionControllerTest {
  GoodDollarExpansionController expansionController;
  IBancorExchangeProvider.PoolExchange pool;

  function setUp() public override {
    super.setUp();
    expansionController = initializeGoodDollarExpansionController();
    vm.prank(avatarAddress);
    expansionController.setExpansionConfig(exchangeId, expansionRate, expansionFrequency);

    pool = IBancorExchangeProvider.PoolExchange({
      reserveAsset: address(reserveToken),
      tokenAddress: address(token),
      tokenSupply: 300_000 * 1e18,
      reserveBalance: 60_000 * 1e18,
      reserveRatio: 200000,
      exitConribution: 10000
    });

    vm.mockCall(
      exchangeProvider,
      abi.encodeWithSelector(IGoodDollarExchangeProvider(exchangeProvider).mintFromInterest.selector),
      abi.encode(1000e18)
    );

    vm.mockCall(
      exchangeProvider,
      abi.encodeWithSelector(IBancorExchangeProvider(exchangeProvider).getPoolExchange.selector),
      abi.encode(pool)
    );
  }

  function test_mintUBIFromReserveBalance_whenAdditionalReserveBalanceIs0_shouldReturn0() public {
    deal(address(reserveToken), reserveAddress, pool.reserveBalance);
    uint256 amountMinted = expansionController.mintUBIFromReserveBalance(exchangeId);
    assertEq(amountMinted, 0);
  }

  function test_mintUBIFromReserveBalance_whenAdditionalReserveBalanceIsLargerThan0_shouldMintAndEmit() public {
    uint256 amountToMint = 1000e18;
    uint256 additionalReserveBalance = 1000e18;

    deal(address(reserveToken), reserveAddress, pool.reserveBalance + additionalReserveBalance);

    uint256 distributionHelperBalanceBefore = token.balanceOf(distributionHelper);

    vm.expectEmit(true, true, true, true);
    emit UBIMinted(exchangeId, amountToMint);
    uint256 amountMinted = expansionController.mintUBIFromReserveBalance(exchangeId);

    assertEq(amountMinted, amountToMint);
    assertEq(token.balanceOf(distributionHelper), distributionHelperBalanceBefore + amountToMint);
  }
}

contract GoodDollarExpansionControllerTest_mintUBIFromExpansion is GoodDollarExpansionControllerTest {
  GoodDollarExpansionController expansionController;

  function setUp() public override {
    super.setUp();
    expansionController = initializeGoodDollarExpansionController();
    vm.prank(avatarAddress);
    expansionController.setExpansionConfig(exchangeId, expansionRate, expansionFrequency);

    IBancorExchangeProvider.PoolExchange memory pool = IBancorExchangeProvider.PoolExchange({
      reserveAsset: address(reserveToken),
      tokenAddress: address(token),
      tokenSupply: 300_000 * 1e18,
      reserveBalance: 60_000 * 1e18,
      reserveRatio: 200000,
      exitConribution: 10000
    });

    vm.mockCall(
      exchangeProvider,
      abi.encodeWithSelector(IGoodDollarExchangeProvider(exchangeProvider).mintFromExpansion.selector),
      abi.encode(1000e18)
    );

    vm.mockCall(
      exchangeProvider,
      abi.encodeWithSelector(IBancorExchangeProvider(exchangeProvider).getPoolExchange.selector),
      abi.encode(pool)
    );

    vm.mockCall(
      distributionHelper,
      abi.encodeWithSelector(IDistributionHelper(distributionHelper).onDistribution.selector),
      abi.encode(true)
    );
  }

  function test_mintUBIFromExpansion_whenExpansionConfigIsNotSet_shouldRevert() public {
    vm.expectRevert("Expansion config not set");
    expansionController.mintUBIFromExpansion("NotSetExchangeId");
  }

  function test_mintUBIFromExpansion_whenShouldNotExpand_shouldNotExpand() public {
    // doing one initial expansion to not be first expansion
    // since on first expansion the expansion is always applied once.
    expansionController.mintUBIFromExpansion(exchangeId);

    IGoodDollarExpansionController.ExchangeExpansionConfig memory config = expansionController.getExpansionConfig(
      exchangeId
    );
    uint256 lastExpansion = config.lastExpansion;
    skip(lastExpansion + config.expansionFrequency - 1);

    assertEq(expansionController.mintUBIFromExpansion(exchangeId), 0);
  }

  function test_mintUBIFromExpansion_whenFirstExpansionAndLessThanExpansionFrequencyPassed_shouldExpand1Time() public {
    // 1 day has passed since last expansion and expansion rate is 1% so the rate passed to the exchangeProvider
    // should be 0.99^1 = 0.99
    IGoodDollarExpansionController.ExchangeExpansionConfig memory config = expansionController.getExpansionConfig(
      exchangeId
    );
    assert(block.timestamp < config.lastExpansion + config.expansionFrequency);
    uint256 expansionScaler = 1e18 * 0.99;
    uint256 amountToMint = 1000e18;
    uint256 distributionHelperBalanceBefore = token.balanceOf(distributionHelper);

    vm.expectEmit(true, true, true, true);
    emit UBIMinted(exchangeId, amountToMint);

    vm.expectCall(
      exchangeProvider,
      abi.encodeWithSelector(
        IGoodDollarExchangeProvider(exchangeProvider).mintFromExpansion.selector,
        exchangeId,
        expansionScaler
      )
    );
    vm.expectCall(
      distributionHelper,
      abi.encodeWithSelector(IDistributionHelper(distributionHelper).onDistribution.selector, amountToMint)
    );

    uint256 amountMinted = expansionController.mintUBIFromExpansion(exchangeId);
    config = expansionController.getExpansionConfig(exchangeId);

    assertEq(amountMinted, amountToMint);
    assertEq(token.balanceOf(distributionHelper), distributionHelperBalanceBefore + amountToMint);
    assertEq(config.lastExpansion, block.timestamp);
  }

  function test_mintUBIFromExpansion_whenFirstExpansionAndMultipleExpansionFrequenciesPassed_shouldExpand1Time()
    public
  {
    // 1 day has passed since last expansion and expansion rate is 1% so the rate passed to the exchangeProvider
    // should be 0.99^1 = 0.99
    IGoodDollarExpansionController.ExchangeExpansionConfig memory config = expansionController.getExpansionConfig(
      exchangeId
    );
    skip(config.expansionFrequency * 3 + 1);
    assert(block.timestamp > config.lastExpansion + config.expansionFrequency * 3);
    uint256 expansionScaler = 1e18 * 0.99;
    uint256 amountToMint = 1000e18;
    uint256 distributionHelperBalanceBefore = token.balanceOf(distributionHelper);

    vm.expectEmit(true, true, true, true);
    emit UBIMinted(exchangeId, amountToMint);

    vm.expectCall(
      exchangeProvider,
      abi.encodeWithSelector(
        IGoodDollarExchangeProvider(exchangeProvider).mintFromExpansion.selector,
        exchangeId,
        expansionScaler
      )
    );
    vm.expectCall(
      distributionHelper,
      abi.encodeWithSelector(IDistributionHelper(distributionHelper).onDistribution.selector, amountToMint)
    );

    uint256 amountMinted = expansionController.mintUBIFromExpansion(exchangeId);
    config = expansionController.getExpansionConfig(exchangeId);

    assertEq(amountMinted, amountToMint);
    assertEq(token.balanceOf(distributionHelper), distributionHelperBalanceBefore + amountToMint);
    assertEq(config.lastExpansion, block.timestamp);
  }

  function test_mintUBIFromExpansion_when1DayPassed_shouldCalculateCorrectRateAndExpand() public {
    // doing one initial expansion to not be first expansion
    // since on first expansion the expansion is always applied once.
    expansionController.mintUBIFromExpansion(exchangeId);

    // 1 day has passed since last expansion and expansion rate is 1% so the rate passed to the exchangeProvider
    // should be 0.99^1 = 0.99
    uint256 expansionScaler = 1e18 * 0.99;
    skip(expansionFrequency + 1);

    uint256 amountToMint = 1000e18;
    uint256 distributionHelperBalanceBefore = token.balanceOf(distributionHelper);

    vm.expectEmit(true, true, true, true);
    emit UBIMinted(exchangeId, amountToMint);

    vm.expectCall(
      exchangeProvider,
      abi.encodeWithSelector(
        IGoodDollarExchangeProvider(exchangeProvider).mintFromExpansion.selector,
        exchangeId,
        expansionScaler
      )
    );
    vm.expectCall(
      distributionHelper,
      abi.encodeWithSelector(IDistributionHelper(distributionHelper).onDistribution.selector, amountToMint)
    );

    uint256 amountMinted = expansionController.mintUBIFromExpansion(exchangeId);
    IGoodDollarExpansionController.ExchangeExpansionConfig memory config = expansionController.getExpansionConfig(
      exchangeId
    );

    assertEq(amountMinted, amountToMint);
    assertEq(token.balanceOf(distributionHelper), distributionHelperBalanceBefore + amountToMint);
    assertEq(config.lastExpansion, block.timestamp);
  }

  function test_mintUBIFromExpansion_whenMultipleDaysPassed_shouldCalculateCorrectRateAndExpand() public {
    // doing one initial expansion to not be first expansion
    // since on first expansion the expansion is always applied once.
    expansionController.mintUBIFromExpansion(exchangeId);

    // 3 days have passed since last expansion and expansion rate is 1% so the rate passed to the exchangeProvider
    // should be 0.99^3 = 0.970299
    uint256 expansionScaler = 1e18 * 0.970299;

    skip(3 * expansionFrequency + 1);

    uint256 amountToMint = 1000e18;
    uint256 distributionHelperBalanceBefore = token.balanceOf(distributionHelper);

    vm.expectEmit(true, true, true, true);
    emit UBIMinted(exchangeId, amountToMint);

    vm.expectCall(
      exchangeProvider,
      abi.encodeWithSelector(
        IGoodDollarExchangeProvider(exchangeProvider).mintFromExpansion.selector,
        exchangeId,
        expansionScaler
      )
    );
    vm.expectCall(
      distributionHelper,
      abi.encodeWithSelector(IDistributionHelper(distributionHelper).onDistribution.selector, amountToMint)
    );

    uint256 amountMinted = expansionController.mintUBIFromExpansion(exchangeId);
    IGoodDollarExpansionController.ExchangeExpansionConfig memory config = expansionController.getExpansionConfig(
      exchangeId
    );

    assertEq(amountMinted, amountToMint);
    assertEq(token.balanceOf(distributionHelper), distributionHelperBalanceBefore + amountToMint);
    assertEq(config.lastExpansion, block.timestamp);
  }
}

contract GoodDollarExpansionControllerTest_mintRewardFromRR is GoodDollarExpansionControllerTest {
  GoodDollarExpansionController expansionController;

  function setUp() public override {
    super.setUp();
    expansionController = initializeGoodDollarExpansionController();
    vm.prank(avatarAddress);
    expansionController.setExpansionConfig(exchangeId, expansionRate, expansionFrequency);

    IBancorExchangeProvider.PoolExchange memory pool = IBancorExchangeProvider.PoolExchange({
      reserveAsset: address(reserveToken),
      tokenAddress: address(token),
      tokenSupply: 300_000 * 1e18,
      reserveBalance: 60_000 * 1e18,
      reserveRatio: 200000,
      exitConribution: 10000
    });

    vm.mockCall(
      exchangeProvider,
      abi.encodeWithSelector(IGoodDollarExchangeProvider(exchangeProvider).updateRatioForReward.selector),
      abi.encode(true)
    );

    vm.mockCall(
      exchangeProvider,
      abi.encodeWithSelector(IBancorExchangeProvider(exchangeProvider).getPoolExchange.selector),
      abi.encode(pool)
    );
  }

  function test_mintRewardFromRR_whenCallerIsNotAvatar_shouldRevert() public {
    vm.prank(makeAddr("NotAvatar"));
    vm.expectRevert("Only Avatar can call this function");
    expansionController.mintRewardFromRR(exchangeId, makeAddr("To"), 1000e18);
  }

  function test_mintRewardFromRR_whenToIsZero_shouldRevert() public {
    vm.prank(avatarAddress);
    vm.expectRevert("Invalid to address");
    expansionController.mintRewardFromRR(exchangeId, address(0), 1000e18);
  }

  function test_mintRewardFromRR_whenAmountIs0_shouldRevert() public {
    vm.prank(avatarAddress);
    vm.expectRevert("Amount must be greater than 0");
    expansionController.mintRewardFromRR(exchangeId, makeAddr("To"), 0);
  }

  function test_mintRewardFromRR_whenCallerIsAvatar_shouldMintAndEmit() public {
    uint256 amountToMint = 1000e18;
    address to = makeAddr("To");
    uint256 toBalanceBefore = token.balanceOf(to);

    vm.expectEmit(true, true, true, true);
    emit RewardMinted(exchangeId, to, amountToMint);

    vm.prank(avatarAddress);
    expansionController.mintRewardFromRR(exchangeId, to, amountToMint);

    assertEq(token.balanceOf(to), toBalanceBefore + amountToMint);
  }
}
