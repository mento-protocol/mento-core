// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
import { Test } from "forge-std/Test.sol";

import { GoodDollarExchangeProvider } from "contracts/goodDollar/GoodDollarExchangeProvider.sol";
import { ERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/ERC20.sol";

import { IReserve } from "contracts/interfaces/IReserve.sol";
import { IExchangeProvider } from "contracts/interfaces/IExchangeProvider.sol";
import { IBancorExchangeProvider } from "contracts/interfaces/IBancorExchangeProvider.sol";

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

  function setUp() public override {
    super.setUp();
    expansionRate = 1e18 * 0.99;
    exchangeProvider = initializeGoodDollarExchangeProvider();
    vm.prank(avatarAddress);
    exchangeId = exchangeProvider.createExchange(poolExchange1);
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
    uint256 amountToMint = exchangeProvider.mintFromExpansion(exchangeId, 1e18);
    assertEq(amountToMint, 0);
  }

  function test_mintFromExpansion_whenValidExpansionRate_shouldReturnCorrectAmountAndEmit() public {
    // formula: amountToMint = (tokenSupply * reserveRatio - tokenSupply * newRatio) / newRatio
    // amountToMint = (300_000 * 0.2 - 300_000 * 0.2 * 0.99 ) / 0.2 * 0.99 ≈ 3030.303030303030303030
    uint256 expectedAmountToMint = 3030303030303030303030;
    uint32 expectedReserveRatio = 0.2 * 0.99 * 1e8;

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
    vm.prank(avatarAddress);
    exchangeId = exchangeProvider.createExchange(poolExchange1);
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
    vm.prank(avatarAddress);
    exchangeId = exchangeProvider.createExchange(poolExchange1);
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
    // reserveRatio = 60_000 / (300_000 + 1000) * 1 ≈ 0.19933554
    uint32 expectedReserveRatio = 19933554;

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
