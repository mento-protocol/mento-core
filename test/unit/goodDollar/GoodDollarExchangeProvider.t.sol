// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase

import { Test, console } from "forge-std/Test.sol";

import { GoodDollarExchangeProvider } from "contracts/goodDollar/GoodDollarExchangeProvider.sol";
import { ERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/ERC20.sol";

import { IReserve } from "contracts/interfaces/IReserve.sol";
import { IExchangeProvider } from "contracts/interfaces/IExchangeProvider.sol";
import { IBancorExchangeProvider } from "contracts/interfaces/IBancorExchangeProvider.sol";
import { UD60x18, unwrap, wrap } from "prb/math/UD60x18.sol";

contract GoodDollarExchangeProviderTest is Test {
  /* ------- Events from IGoodDollarExchangeProvider ------- */

  event ExpansionControllerUpdated(address indexed expansionController);

  event AvatarUpdated(address indexed AVATAR);

  event ReserveRatioUpdated(bytes32 indexed exchangeId, uint32 reserveRatio);

  event ExchangeCreated(bytes32 indexed exchangeId, address indexed reserveAsset, address indexed tokenAddress);

  event ExchangeDestroyed(bytes32 indexed exchangeId, address indexed reserveAsset, address indexed tokenAddress);

  event ExitContributionSet(bytes32 indexed exchangeId, uint256 exitContribution);

  /* ------------------------------------------- */

  ERC20 public reserveToken;
  ERC20 public token;
  ERC20 public token2;

  address public reserveAddress;
  address public brokerAddress;
  address public avatarAddress;
  address public expansionControllerAddress;

  IBancorExchangeProvider.PoolExchange public poolExchange1;
  IBancorExchangeProvider.PoolExchange public poolExchange2;
  IBancorExchangeProvider.PoolExchange public poolExchange;

  function setUp() public virtual {
    reserveToken = new ERC20("cUSD", "cUSD");
    token = new ERC20("Good$", "G$");
    token2 = new ERC20("Good2$", "G2$");

    reserveAddress = makeAddr("Reserve");
    brokerAddress = makeAddr("Broker");
    avatarAddress = makeAddr("Avatar");
    expansionControllerAddress = makeAddr("ExpansionController");

    poolExchange1 = IBancorExchangeProvider.PoolExchange({
      reserveAsset: address(reserveToken),
      tokenAddress: address(token),
      tokenSupply: 300_000 * 1e18,
      reserveBalance: 60_000 * 1e18,
      reserveRatio: 0.2 * 1e8,
      exitContribution: 0.01 * 1e8
    });

    poolExchange2 = IBancorExchangeProvider.PoolExchange({
      reserveAsset: address(reserveToken),
      tokenAddress: address(token2),
      tokenSupply: 300_000 * 1e18,
      reserveBalance: 60_000 * 1e18,
      reserveRatio: 1e8 * 0.2,
      exitContribution: 1e8 * 0.01
    });

    poolExchange = IBancorExchangeProvider.PoolExchange({
      reserveAsset: address(reserveToken),
      tokenAddress: address(token),
      tokenSupply: 7_000_000_000 * 1e18,
      reserveBalance: 200_000 * 1e18,
      reserveRatio: 1e8 * 0.28571428,
      exitContribution: 1e8 * 0.1
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
  }

  function initializeGoodDollarExchangeProvider() internal returns (GoodDollarExchangeProvider) {
    GoodDollarExchangeProvider exchangeProvider = new GoodDollarExchangeProvider(false);

    exchangeProvider.initialize(brokerAddress, reserveAddress, expansionControllerAddress, avatarAddress);
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

  function test_initializer() public view {
    assertEq(exchangeProvider.owner(), address(this));
    assertEq(exchangeProvider.broker(), brokerAddress);
    assertEq(address(exchangeProvider.reserve()), reserveAddress);
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

  /* ---------- setExitContribution ---------- */
  /* Focuses only on access control, implementation details are covered in BancorExchangeProvider tests */
  function test_setExitContribution_whenSenderIsOwner_shouldRevert() public {
    vm.expectRevert("Only Avatar can call this function");
    bytes32 exchangeId = "0xexchangeId";
    exchangeProvider.setExitContribution(exchangeId, 1e5);
  }

  function test_setExitContribution_whenSenderIsNotAvatar_shouldRevert() public {
    vm.startPrank(makeAddr("NotAvatarAndNotOwner"));
    vm.expectRevert("Only Avatar can call this function");
    bytes32 exchangeId = "0xexchangeId";
    exchangeProvider.setExitContribution(exchangeId, 1e5);
    vm.stopPrank();
  }

  function test_setExitContribution_whenSenderIsAvatar_shouldUpdateAndEmit() public {
    vm.startPrank(avatarAddress);
    bytes32 exchangeId = exchangeProvider.createExchange(poolExchange1);
    uint32 newExitContribution = 1e3;
    vm.expectEmit(true, true, true, true);
    emit ExitContributionSet(exchangeId, newExitContribution);
    exchangeProvider.setExitContribution(exchangeId, newExitContribution);

    IBancorExchangeProvider.PoolExchange memory poolExchange = exchangeProvider.getPoolExchange(exchangeId);
    assertEq(poolExchange.exitContribution, newExitContribution);
    vm.stopPrank();
  }
  /* ---------- setExitContribution end ---------- */
}

/**
 * @notice createExchange tests
 * @dev These tests focus only on access control. The implementation details
 *      are covered in the BancorExchangeProvider tests.
 */
contract GoodDollarExchangeProviderTest_createExchange is GoodDollarExchangeProviderTest {
  GoodDollarExchangeProvider exchangeProvider;

  function setUp() public override {
    super.setUp();
    exchangeProvider = initializeGoodDollarExchangeProvider();
  }

  function test_createExchange_whenSenderIsNotAvatar_shouldRevert() public {
    vm.prank(makeAddr("NotAvatar"));
    vm.expectRevert("Only Avatar can call this function");
    exchangeProvider.createExchange(poolExchange1);
  }

  function test_createExchange_whenSenderIsOwner_shouldRevert() public {
    vm.expectRevert("Only Avatar can call this function");
    exchangeProvider.createExchange(poolExchange1);
  }

  function test_createExchange_whenSenderIsAvatar_shouldCreateExchangeAndEmit() public {
    vm.startPrank(avatarAddress);
    vm.expectEmit(true, true, true, true);
    bytes32 expectedExchangeId = keccak256(abi.encodePacked(reserveToken.symbol(), token.symbol()));
    emit ExchangeCreated(expectedExchangeId, address(reserveToken), address(token));
    bytes32 exchangeId = exchangeProvider.createExchange(poolExchange1);
    assertEq(exchangeId, expectedExchangeId);

    IBancorExchangeProvider.PoolExchange memory poolExchange = exchangeProvider.getPoolExchange(exchangeId);
    assertEq(poolExchange.reserveAsset, poolExchange1.reserveAsset);
    assertEq(poolExchange.tokenAddress, poolExchange1.tokenAddress);
    assertEq(poolExchange.tokenSupply, poolExchange1.tokenSupply);
    assertEq(poolExchange.reserveBalance, poolExchange1.reserveBalance);
    assertEq(poolExchange.reserveRatio, poolExchange1.reserveRatio);
    assertEq(poolExchange.exitContribution, poolExchange1.exitContribution);

    IExchangeProvider.Exchange[] memory exchanges = exchangeProvider.getExchanges();
    assertEq(exchanges.length, 1);
    assertEq(exchanges[0].exchangeId, exchangeId);

    assertEq(exchangeProvider.tokenPrecisionMultipliers(address(reserveToken)), 1);
    assertEq(exchangeProvider.tokenPrecisionMultipliers(address(token)), 1);
    vm.stopPrank();
  }
}

/**
 * @notice destroyExchange tests
 * @dev These tests focus only on access control. The implementation details
 *      are covered in the BancorExchangeProvider tests.
 */
contract GoodDollarExchangeProviderTest_destroyExchange is GoodDollarExchangeProviderTest {
  GoodDollarExchangeProvider exchangeProvider;

  function setUp() public override {
    super.setUp();
    exchangeProvider = initializeGoodDollarExchangeProvider();
  }

  function test_destroyExchange_whenSenderIsOwner_shouldRevert() public {
    vm.startPrank(avatarAddress);
    bytes32 exchangeId = exchangeProvider.createExchange(poolExchange1);
    vm.stopPrank();
    vm.expectRevert("Only Avatar can call this function");
    exchangeProvider.destroyExchange(exchangeId, 0);
  }

  function test_destroyExchange_whenSenderIsNotAvatar_shouldRevert() public {
    vm.startPrank(avatarAddress);
    bytes32 exchangeId = exchangeProvider.createExchange(poolExchange1);
    vm.stopPrank();

    vm.startPrank(makeAddr("NotAvatar"));
    vm.expectRevert("Only Avatar can call this function");
    exchangeProvider.destroyExchange(exchangeId, 0);
    vm.stopPrank();
  }

  function test_destroyExchange_whenExchangeExists_shouldDestroyExchangeAndEmit() public {
    vm.startPrank(avatarAddress);
    bytes32 exchangeId = exchangeProvider.createExchange(poolExchange1);
    bytes32 exchangeId2 = exchangeProvider.createExchange(poolExchange2);
    vm.stopPrank();

    vm.startPrank(avatarAddress);
    vm.expectEmit(true, true, true, true);
    emit ExchangeDestroyed(exchangeId, poolExchange1.reserveAsset, poolExchange1.tokenAddress);
    exchangeProvider.destroyExchange(exchangeId, 0);

    bytes32[] memory exchangeIds = exchangeProvider.getExchangeIds();
    assertEq(exchangeIds.length, 1);

    IExchangeProvider.Exchange[] memory exchanges = exchangeProvider.getExchanges();
    assertEq(exchanges.length, 1);
    assertEq(exchanges[0].exchangeId, exchangeId2);
    vm.stopPrank();
  }
}

contract GoodDollarExchangeProviderTest_mintFromExpansion is GoodDollarExchangeProviderTest {
  GoodDollarExchangeProvider exchangeProvider;
  bytes32 exchangeId;
  uint256 expansionRate;
  uint256 dailyExpansionScaler;

  function setUp() public override {
    super.setUp();
    // based on a yearly expansion rate of 10% the daily rate is:
    // (1-x)^365 = 0.9 -> x = 1 - 0.9^(1/365) = 0.00028861728902231263...
    expansionRate = 288617289022312;
    dailyExpansionScaler = 1e18 - expansionRate;
    exchangeProvider = initializeGoodDollarExchangeProvider();
    vm.prank(avatarAddress);
    exchangeId = exchangeProvider.createExchange(poolExchange);
  }

  function calculateExpectedMintFromExpansion(
    uint256 tokenSupply,
    uint32 reserveRatio,
    uint256 expansionScaler
  ) public pure returns (uint256 expectedAmountToMint) {
    require(expansionScaler > 0, "Expansion rate must be greater than 0");

    // Convert to UD60x18 for precise calculations
    UD60x18 scaledRatio = wrap(uint256(reserveRatio) * 1e10);
    UD60x18 newRatio = scaledRatio.mul(wrap(expansionScaler));

    UD60x18 numerator = wrap(tokenSupply).mul(scaledRatio);
    numerator = numerator.sub(wrap(tokenSupply).mul(newRatio));

    expectedAmountToMint = unwrap(numerator.div(newRatio));
    return expectedAmountToMint;
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
    vm.expectRevert("Exchange does not exist");
    exchangeProvider.mintFromExpansion(bytes32(0), expansionRate);
  }

  function test_mintFromExpansion_whenExpansionRateIs100Percent_shouldReturn0() public {
    vm.prank(expansionControllerAddress);
    uint256 amountToMint = exchangeProvider.mintFromExpansion(exchangeId, 1e18);
    assertEq(amountToMint, 0);
  }

  function test_mintFromExpansion_whenValidExpansionRate_shouldReturnCorrectAmountAndEmit() public {
    // Formula: amountToMint = (tokenSupply * reserveRatio - tokenSupply * newRatio) / newRatio
    // amountToMint = (7_000_000_000 * 0.28571428 - 7_000_000_000 * 0.28571428 * (1-0.000288617289022312)) / 0.28571428 * (1-0.000288617289022312)
    // ≈ 2020904,291074047348860628
    uint256 expectedAmountToMint = 2020904291074047348860628;
    // Formula: newRatio = reserveRatio * (1 - expansionScaler)
    // newRatio = 0.28571428 * (1 - 0.000288617289022312) = 0.285631817919071438
    uint32 expectedReserveRatio = 28563181;

    vm.expectEmit(true, true, true, true);
    emit ReserveRatioUpdated(exchangeId, expectedReserveRatio);
    vm.prank(expansionControllerAddress);
    uint256 amountToMint = exchangeProvider.mintFromExpansion(exchangeId, dailyExpansionScaler);

    IBancorExchangeProvider.PoolExchange memory poolExchangeAfter = exchangeProvider.getPoolExchange(exchangeId);

    // 0.01% relative error tolerance because of precision loss when new reserve ratio is calculated
    assertApproxEqRel(amountToMint, expectedAmountToMint, 1e18 * 0.0001);
    assertApproxEqRel(poolExchangeAfter.tokenSupply, poolExchange.tokenSupply + amountToMint, 1e18 * 0.0001);
    assertEq(poolExchangeAfter.reserveRatio, expectedReserveRatio);
  }

  function testFuzz_mintFromExpansion(uint256 expansionScaler) public {
    expansionScaler = bound(expansionScaler, 100, 1e18);

    uint256 initialTokenSupply = poolExchange.tokenSupply;
    uint32 initialReserveRatio = poolExchange.reserveRatio;

    uint256 newRatio = (uint256(initialReserveRatio) * expansionScaler) / 1e18;
    uint32 expectedReserveRatio = uint32(newRatio);

    // Calculate expected values using the helper function
    uint256 expectedAmountToMint = calculateExpectedMintFromExpansion(
      initialTokenSupply,
      initialReserveRatio,
      expansionScaler
    );

    vm.expectEmit(true, true, true, true);
    emit ReserveRatioUpdated(exchangeId, expectedReserveRatio);

    vm.prank(expansionControllerAddress);
    uint256 amountToMint = exchangeProvider.mintFromExpansion(exchangeId, expansionScaler);

    assertEq(amountToMint, expectedAmountToMint, "Minted amount should match expected amount");

    IBancorExchangeProvider.PoolExchange memory poolExchangeAfter = exchangeProvider.getPoolExchange(exchangeId);
    assertEq(
      poolExchangeAfter.tokenSupply,
      initialTokenSupply + amountToMint,
      "Token supply should increase by minted amount"
    );

    assertEq(poolExchangeAfter.reserveRatio, expectedReserveRatio, "Reserve ratio should be updated correctly");
  }

  function testMintFromExpansion_RevertWhenNewRatioIsZero() public {
    uint256 verySmallExpansionScaler = 1;

    vm.expectRevert("New ratio must be greater than 0");

    vm.prank(expansionControllerAddress);
    exchangeProvider.mintFromExpansion(exchangeId, verySmallExpansionScaler);
  }

  function test_mintFromExpansion_whenValidExpansionRate_shouldNotChangePrice() public {
    uint256 priceBefore = exchangeProvider.currentPrice(exchangeId);

    vm.prank(expansionControllerAddress);
    exchangeProvider.mintFromExpansion(exchangeId, expansionRate);

    uint256 priceAfter = exchangeProvider.currentPrice(exchangeId);

    // 0.01% relative error tolerance because of precision loss when new reserve ratio is calculated
    assertApproxEqRel(priceBefore, priceAfter, 1e18 * 0.0001);
  }

  function test_mintFromExpansion_whenExpansionScalerIs100Percent_shouldReturn0() public {
    vm.prank(expansionControllerAddress);
    uint256 amountToMint = exchangeProvider.mintFromExpansion(exchangeId, 1e18);
    assertEq(amountToMint, 0);
  }

  function test_mintFromExpansion_withMultipleConsecutiveExpansions_shouldMintCorrectly() public {
    vm.startPrank(expansionControllerAddress);
    uint256 totalMinted = 0;
    uint256 initialTokenSupply = poolExchange.tokenSupply;
    uint32 initialReserveRatio = poolExchange.reserveRatio;
    uint256 initialReserveBalance = poolExchange.reserveBalance;
    uint256 initialPrice = exchangeProvider.currentPrice(exchangeId);

    for (uint256 i = 0; i < 5; i++) {
      uint256 amountToMint = exchangeProvider.mintFromExpansion(exchangeId, dailyExpansionScaler);
      totalMinted += amountToMint;

      // Check that amount minted is greater than 0
      assertGt(amountToMint, 0, "Amount minted should be greater than 0");
    }
    vm.stopPrank();

    IBancorExchangeProvider.PoolExchange memory poolExchangeAfter = exchangeProvider.getPoolExchange(exchangeId);

    // Check token supply
    assertEq(
      poolExchangeAfter.tokenSupply,
      initialTokenSupply + totalMinted,
      "Token supply should increase by total minted amount"
    );

    // Check reserve ratio has decreased
    assertLt(poolExchangeAfter.reserveRatio, initialReserveRatio, "Reserve ratio should decrease");

    // Check reserve balance remains unchanged
    assertEq(poolExchangeAfter.reserveBalance, initialReserveBalance, "Reserve balance should remain unchanged");

    // Calculate expected reserve ratio
    // daily Scaler is applied 5 times newRatio = initialReserveRatio * (dailyScaler ** 5)
    // newRatio = 0.28571428 * (0.999711382710977688 ** 5) ≈ 0.2853022075264986
    uint256 expectedReserveRatio = 28530220;
    assertApproxEqRel(
      poolExchangeAfter.reserveRatio,
      uint32(expectedReserveRatio),
      1e18 * 0.0001, // 0.01% relative error tolerance because of precision loss when new reserve ratio is calculated
      "Reserve ratio should be updated correctly within 0.01% tolerance"
    );

    // Check price remains approximately the same
    uint256 finalPrice = exchangeProvider.currentPrice(exchangeId);
    assertApproxEqRel(initialPrice, finalPrice, 1e18 * 0.0001, "Price should remain within 0.01% of initial price");
  }

  function test_mintFromExpansion_effectOnReserveRatio() public {
    uint32 initialReserveRatio = poolExchange.reserveRatio;

    vm.prank(expansionControllerAddress);
    exchangeProvider.mintFromExpansion(exchangeId, dailyExpansionScaler);
    IBancorExchangeProvider.PoolExchange memory poolExchangeAfter = exchangeProvider.getPoolExchange(exchangeId);
    assertLt(poolExchangeAfter.reserveRatio, initialReserveRatio);
  }

  function test_mintFromExpansion_withMaximumExpansion() public {
    uint256 maxExpansionScaler = 1e18 - 1; // Just below 100%

    vm.prank(expansionControllerAddress);
    uint256 amountToMint = exchangeProvider.mintFromExpansion(exchangeId, maxExpansionScaler);

    assertGt(amountToMint, 0);
    // Add more assertions to check the resulting state
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
    vm.prank(avatarAddress);
    exchangeId = exchangeProvider.createExchange(poolExchange);
  }

  function test_mintFromInterest_whenCallerIsNotExpansionController_shouldRevert() public {
    vm.prank(makeAddr("NotExpansionController"));
    vm.expectRevert("Only ExpansionController can call this function");
    exchangeProvider.mintFromInterest(exchangeId, reserveInterest);
  }

  function test_mintFromInterest_whenExchangeIdIsInvalid_shouldRevert() public {
    vm.prank(expansionControllerAddress);
    vm.expectRevert("Exchange does not exist");
    exchangeProvider.mintFromInterest(bytes32(0), reserveInterest);
  }

  function test_mintFromInterest_whenInterestIs0_shouldReturn0() public {
    vm.prank(expansionControllerAddress);
    uint256 amountToMint = exchangeProvider.mintFromInterest(exchangeId, 0);
    assertEq(amountToMint, 0);
  }

  function test_mintFromInterest_whenInterestLarger0_shouldReturnCorrectAmount() public {
    // formula: amountToMint = reserveInterest * tokenSupply / reserveBalance
    // amountToMint = 1_000 * 7_000_000_000 / 200_000 = 35_000_000
    uint256 expectedAmountToMint = 35_000_000 * 1e18;

    vm.prank(expansionControllerAddress);
    uint256 amountToMint = exchangeProvider.mintFromInterest(exchangeId, reserveInterest);
    assertEq(amountToMint, expectedAmountToMint);

    IBancorExchangeProvider.PoolExchange memory poolExchangeAfter = exchangeProvider.getPoolExchange(exchangeId);
    assertEq(poolExchangeAfter.tokenSupply, poolExchange.tokenSupply + amountToMint);
    assertEq(poolExchangeAfter.reserveBalance, poolExchange.reserveBalance + reserveInterest);
  }

  function test_mintFromInterest_whenInterestLarger0_shouldNotChangePrice() public {
    uint256 priceBefore = exchangeProvider.currentPrice(exchangeId);

    vm.prank(expansionControllerAddress);
    exchangeProvider.mintFromInterest(exchangeId, reserveInterest);

    uint256 priceAfter = exchangeProvider.currentPrice(exchangeId);

    assertEq(priceBefore, priceAfter);
  }

  function test_mintFromInterest_withMultipleConsecutiveInterests_shouldMintCorrectly() public {
    vm.startPrank(expansionControllerAddress);
    uint256 totalMinted = 0;
    for (uint256 i = 0; i < 5; i++) {
      uint256 amountToMint = exchangeProvider.mintFromInterest(exchangeId, reserveInterest);
      totalMinted += amountToMint;
    }
    vm.stopPrank();

    IBancorExchangeProvider.PoolExchange memory poolExchangeAfter = exchangeProvider.getPoolExchange(exchangeId);
    assertEq(poolExchangeAfter.tokenSupply, poolExchange.tokenSupply + totalMinted);
    assertEq(poolExchangeAfter.reserveBalance, poolExchange.reserveBalance + reserveInterest * 5);
  }

  function test_mintFromInterest_effectOnReserveBalance() public {
    uint256 initialReserveBalance = poolExchange.reserveBalance;

    vm.prank(expansionControllerAddress);
    exchangeProvider.mintFromInterest(exchangeId, reserveInterest);
    IBancorExchangeProvider.PoolExchange memory poolExchangeAfter = exchangeProvider.getPoolExchange(exchangeId);
    assertEq(poolExchangeAfter.reserveBalance, initialReserveBalance + reserveInterest);
  }

  function test_mintFromInterest_whenInterestIsLarge_shouldReturnCorrectAmount() public {
    // 1_000_000 reserve tokens 5 times current reserve balance
    uint256 interest = 1_000_000 * 1e18;

    uint256 priceBefore = exchangeProvider.currentPrice(exchangeId);

    // formula: amountToMint = reserveInterest * tokenSupply / reserveBalance
    // amountToMint = 1_000_000 * 7_000_000_000 / 200_000 = 35_000_000_000
    uint256 expectedAmountToMint = 35_000_000_000 * 1e18;

    vm.prank(expansionControllerAddress);
    uint256 amountToMint = exchangeProvider.mintFromInterest(exchangeId, interest);

    uint256 priceAfter = exchangeProvider.currentPrice(exchangeId);
    IBancorExchangeProvider.PoolExchange memory poolExchangeAfter = exchangeProvider.getPoolExchange(exchangeId);

    assertEq(amountToMint, expectedAmountToMint);
    assertEq(poolExchangeAfter.reserveBalance, poolExchange.reserveBalance + interest);
    assertEq(priceBefore, priceAfter);
  }

  function testFuzz_mintFromInterest(uint256 fuzzedInterest) public {
    fuzzedInterest = bound(fuzzedInterest, 1, type(uint256).max / poolExchange.tokenSupply);

    uint256 initialTokenSupply = poolExchange.tokenSupply;
    uint256 initialReserveBalance = poolExchange.reserveBalance;

    uint256 expectedAmountToMint = (fuzzedInterest * initialTokenSupply) / initialReserveBalance;
    uint256 priceBefore = exchangeProvider.currentPrice(exchangeId);

    vm.prank(expansionControllerAddress);
    uint256 amountToMint = exchangeProvider.mintFromInterest(exchangeId, fuzzedInterest);

    assertEq(amountToMint, expectedAmountToMint, "Minted amount should match expected amount");

    IBancorExchangeProvider.PoolExchange memory poolExchangeAfter = exchangeProvider.getPoolExchange(exchangeId);
    assertEq(
      poolExchangeAfter.tokenSupply,
      initialTokenSupply + amountToMint,
      "Token supply should increase by minted amount"
    );
    assertEq(
      poolExchangeAfter.reserveBalance,
      initialReserveBalance + fuzzedInterest,
      "Reserve balance should increase by interest amount"
    );

    uint256 priceAfter = exchangeProvider.currentPrice(exchangeId);
    assertEq(priceBefore, priceAfter, "Price should remain unchanged");
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
    vm.prank(avatarAddress);
    exchangeId = exchangeProvider.createExchange(poolExchange);
  }

  function test_updateRatioForReward_whenCallerIsNotExpansionController_shouldRevert() public {
    vm.prank(makeAddr("NotExpansionController"));
    vm.expectRevert("Only ExpansionController can call this function");
    exchangeProvider.updateRatioForReward(exchangeId, reward);
  }

  function test_updateRatioForReward_whenExchangeIdIsInvalid_shouldRevert() public {
    vm.prank(expansionControllerAddress);
    vm.expectRevert("Exchange does not exist");
    exchangeProvider.updateRatioForReward(bytes32(0), reward);
  }

  function test_updateRatioForReward_whenRewardIs0_shouldRevert() public {
    vm.prank(expansionControllerAddress);
    vm.expectRevert("Reward must be greater than 0");
    exchangeProvider.updateRatioForReward(exchangeId, 0);
  }

  function test_updateRatioForReward_whenRewardLarger0_shouldReturnCorrectRatioAndEmit() public {
    // formula: newRatio = reserveBalance / ((tokenSupply + reward) * currentPrice)
    // reserveRatio = 200_000 / ((7_000_000_000 + 1_000) * 0.000100000002) ≈ 0.28571423
    uint32 expectedReserveRatio = 28571423;

    vm.expectEmit(true, true, true, true);
    emit ReserveRatioUpdated(exchangeId, expectedReserveRatio);
    vm.prank(expansionControllerAddress);
    exchangeProvider.updateRatioForReward(exchangeId, reward);

    IBancorExchangeProvider.PoolExchange memory poolExchangeAfter = exchangeProvider.getPoolExchange(exchangeId);
    assertEq(poolExchangeAfter.reserveRatio, expectedReserveRatio);
    assertEq(poolExchangeAfter.tokenSupply, poolExchange.tokenSupply + reward);
  }

  function test_updateRatioForReward_shouldNotChangePrice() public {
    uint256 priceBefore = exchangeProvider.currentPrice(exchangeId);

    vm.prank(expansionControllerAddress);
    exchangeProvider.updateRatioForReward(exchangeId, reward);

    uint256 priceAfter = exchangeProvider.currentPrice(exchangeId);
    assertApproxEqRel(
      priceBefore,
      priceAfter,
      1e18 * 0.0001,
      "Price should remain unchanged, with a max relative error of 0.01%"
    );
  }

  function test_updateRatioForReward_withMultipleConsecutiveRewards() public {
    vm.startPrank(expansionControllerAddress);
    uint256 totalReward = 0;
    uint256 initialTokenSupply = poolExchange.tokenSupply;
    uint256 initialReserveBalance = poolExchange.reserveBalance;
    uint32 initialReserveRatio = poolExchange.reserveRatio;
    uint256 initialPrice = exchangeProvider.currentPrice(exchangeId);

    for (uint256 i = 0; i < 5; i++) {
      exchangeProvider.updateRatioForReward(exchangeId, reward);
      totalReward += reward;
    }
    vm.stopPrank();

    IBancorExchangeProvider.PoolExchange memory poolExchangeAfter = exchangeProvider.getPoolExchange(exchangeId);

    // Check token supply
    assertEq(
      poolExchangeAfter.tokenSupply,
      initialTokenSupply + totalReward,
      "Token supply should increase by total reward"
    );

    // Check reserve balance remains unchanged
    assertEq(poolExchangeAfter.reserveBalance, initialReserveBalance, "Reserve balance should remain unchanged");

    // Check reserve ratio has decreased
    assertLt(poolExchangeAfter.reserveRatio, initialReserveRatio, "Reserve ratio should decrease");

    // Calculate expected reserve ratio
    uint256 expectedReserveRatio = (uint256(initialReserveRatio) * initialTokenSupply) /
      (initialTokenSupply + totalReward);
    assertApproxEqRel(
      poolExchangeAfter.reserveRatio,
      uint32(expectedReserveRatio),
      1e15, // 0.1% relative error tolerance
      "Reserve ratio should be updated correctly within 0.1% tolerance"
    );

    // Check price remains approximately the same
    uint256 finalPrice = exchangeProvider.currentPrice(exchangeId);
    assertApproxEqRel(initialPrice, finalPrice, 1e16, "Price should remain within 1% of initial price");

    // Check that the exchange is still active
    IExchangeProvider.Exchange[] memory exchanges = exchangeProvider.getExchanges();
    bool exchangeFound = false;
    for (uint256 i = 0; i < exchanges.length; i++) {
      if (exchanges[i].exchangeId == exchangeId) {
        exchangeFound = true;
        break;
      }
    }
    assertTrue(exchangeFound, "Exchange should still be active after multiple rewards");
  }

  function test_updateRatioForReward_effectOnReserveRatio() public {
    uint32 initialReserveRatio = poolExchange.reserveRatio;

    vm.prank(expansionControllerAddress);
    exchangeProvider.updateRatioForReward(exchangeId, reward);
    IBancorExchangeProvider.PoolExchange memory poolExchangeAfter = exchangeProvider.getPoolExchange(exchangeId);
    assertLt(poolExchangeAfter.reserveRatio, initialReserveRatio);
  }

  function test_updateRatioForReward_withMaximumReward() public {
    uint256 maxReward = type(uint256).max - poolExchange.tokenSupply;

    vm.prank(expansionControllerAddress);
    exchangeProvider.updateRatioForReward(exchangeId, maxReward);

    IBancorExchangeProvider.PoolExchange memory poolExchangeAfter = exchangeProvider.getPoolExchange(exchangeId);
    assertGt(poolExchangeAfter.tokenSupply, poolExchange.tokenSupply);
    assertLt(poolExchangeAfter.reserveRatio, poolExchange.reserveRatio);
  }

  function testFuzz_updateRatioForReward(uint256 fuzzedReward) public {
    fuzzedReward = bound(fuzzedReward, 1, 1 * 1e28);

    uint256 initialTokenSupply = poolExchange.tokenSupply;
    uint256 initialReserveBalance = poolExchange.reserveBalance;
    uint32 initialReserveRatio = poolExchange.reserveRatio;

    uint256 priceBefore = exchangeProvider.currentPrice(exchangeId);

    vm.prank(expansionControllerAddress);
    exchangeProvider.updateRatioForReward(exchangeId, fuzzedReward);

    IBancorExchangeProvider.PoolExchange memory poolExchangeAfter = exchangeProvider.getPoolExchange(exchangeId);

    assertEq(
      poolExchangeAfter.tokenSupply,
      initialTokenSupply + fuzzedReward,
      "Token supply should increase by reward amount"
    );
    assertEq(poolExchangeAfter.reserveBalance, initialReserveBalance, "Reserve balance should remain unchanged");
    assertLe(poolExchangeAfter.reserveRatio, initialReserveRatio, "Reserve ratio should decrease");

    uint256 priceAfter = exchangeProvider.currentPrice(exchangeId);
    assertApproxEqRel(
      priceBefore,
      priceAfter,
      9 * 1e15,
      "Price should remain unchanged, with a max relative error of 0.9%"
    );
  }
}

contract GoodDollarExchangeProviderTest_pausable is GoodDollarExchangeProviderTest {
  GoodDollarExchangeProvider exchangeProvider;
  bytes32 exchangeId;

  function setUp() public override {
    super.setUp();
    exchangeProvider = initializeGoodDollarExchangeProvider();
    vm.prank(avatarAddress);
    exchangeId = exchangeProvider.createExchange(poolExchange1);
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
