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

contract GoodDollarExchangeProviderTest_getAmountOut is GoodDollarExchangeProviderTest {
  GoodDollarExchangeProvider exchangeProvider;

  function setUp() public override {
    super.setUp();
    exchangeProvider = initializeGoodDollarExchangeProvider();

    vm.mockCall(
      expansionControllerAddress,
      abi.encodeWithSelector(
        IGoodDollarExpansionController(expansionControllerAddress).getCurrentExpansionRate.selector
      ),
      abi.encode(0)
    );
  }

  function test_getAmountOut_whenTokenInIsReserveAsset_shouldReturnCorrectAmount() public {
    bytes32 exchangeId = exchangeProvider.createExchange(poolExchange1);
    // formula: amountOut = Supply * ( (1 + amountIn/reserveBalance)^collateralRatio - 1)
    // calculation: 300_000 * ( (1 + 1/60_000)^0.2 - 1) ≈ 0.999993333399999222
    uint256 expectedAmountIn = 999993333399999222;
    uint256 amountIn = exchangeProvider.getAmountOut(exchangeId, address(reserveToken), address(token), 1e18);
    assertEq(amountIn, expectedAmountIn);
  }

  function test_getAmountOut_whenTokenInIsToken_shouldReturnCorrectAmount() public {
    bytes32 exchangeId = exchangeProvider.createExchange(poolExchange1);
    // formula: amountOut = reserveBalance * ((1 + (amountIn * exitContribution)/tokenSupply)^(1/collateralRatio) -1)
    // calculation: 60_000 * ((1 + (1 * (1-0.01))/300_000)^(1/0.2) -1) ≈ 0.990006534021562235
    uint256 expectedAmountIn = 990006534021562235;
    uint256 amountIn = exchangeProvider.getAmountOut(exchangeId, address(token), address(reserveToken), 1e18);
    assertEq(amountIn, expectedAmountIn);
  }

  function test_getAmountOut_whenExpansionRateIsLargerZero_shouldReturnCorrectAmount() public {
    // expansion rate is 0.99 and two days have passed
    // expanded reserveRatio should be 0.2 * 0.99^2 = 0.19602
    // after expansion new tokenSupply should be 306_091.215182124273033363
    vm.mockCall(
      expansionControllerAddress,
      abi.encodeWithSelector(
        IGoodDollarExpansionController(expansionControllerAddress).getCurrentExpansionRate.selector
      ),
      abi.encode(980100)
    );

    bytes32 exchangeId = exchangeProvider.createExchange(poolExchange1);
    // formula: amountOut = Supply * ( (1 + amountIn/reserveBalance)^collateralRatio - 1)
    // calculation: 306_091.215182124273033363 * ( (1 + 1/60_000)^0.19602 - 1) ≈ 0.999993300233812356
    uint256 expectedAmountIn = 999993300233812356;
    uint256 amountIn = exchangeProvider.getAmountOut(exchangeId, address(reserveToken), address(token), 1e18);
    assertEq(amountIn, expectedAmountIn);
  }
}

contract GoodDollarExchangeProviderTest_getAmountIn is GoodDollarExchangeProviderTest {
  GoodDollarExchangeProvider exchangeProvider;

  function setUp() public override {
    super.setUp();
    exchangeProvider = initializeGoodDollarExchangeProvider();

    vm.mockCall(
      expansionControllerAddress,
      abi.encodeWithSelector(
        IGoodDollarExpansionController(expansionControllerAddress).getCurrentExpansionRate.selector
      ),
      abi.encode(0)
    );
  }

  function test_getAmountIn_whenTokenInIsReserveAsset_shouldReturnCorrectAmount() public {
    bytes32 exchangeId = exchangeProvider.createExchange(poolExchange1);
    // formula: amountIn = reserveBalance * (( scaledAmountOut / tokenSupply + 1)^ (1 / reserveRatio) -1)
    // calculation: 60_000 * ((1/300_000 + 1)^(1/0.2) - 1) ≈ 1.000006666688888925
    uint256 expectedAmountIn = 1000006666688888925;
    uint256 amountIn = exchangeProvider.getAmountIn(exchangeId, address(reserveToken), address(token), 1e18);
    assertEq(amountIn, expectedAmountIn);
  }

  function test_getAmountIn_whenTokenInIsToken_shouldReturnCorrectAmount() public {
    bytes32 exchangeId = exchangeProvider.createExchange(poolExchange1);
    // formula: amountIn = (S * ( ( r/R + 1 )^reserveRatio -1)) / (1-exitContribution)
    // calculation: (300_000 * ( ( 1/60_000 + 1) ^0.2 - 1)) / (1 - 0.01) ≈ 1.010094276161615375
    uint256 expectedAmountIn = 1010094276161615375;
    uint256 amountIn = exchangeProvider.getAmountIn(exchangeId, address(token), address(reserveToken), 1e18);
    assertEq(amountIn, expectedAmountIn);
  }

  function test_getAmountIn_whenExpansionRateIsLargerZero_shouldReturnCorrectAmount() public {
    // expansion rate is 0.99 and two days have passed
    // expanded reserveRatio should be 0.2 * 0.99^2 = 0.19602
    // after expansion new tokenSupply should be 306_091.215182124273033363
    vm.mockCall(
      expansionControllerAddress,
      abi.encodeWithSelector(
        IGoodDollarExpansionController(expansionControllerAddress).getCurrentExpansionRate.selector
      ),
      abi.encode(980100)
    );

    bytes32 exchangeId = exchangeProvider.createExchange(poolExchange1);
    // formula: amountIn = reserveBalance * (( scaledAmountOut / tokenSupply + 1)^ (1 / reserveRatio) -1)
    // calculation: 60_000 * ((1/306_091.215182124273033363 + 1)^(1/0.19602) - 1) ≈ 1.000006699855962431
    uint256 expectedAmountIn = 1000006699855962431;
    uint256 amountIn = exchangeProvider.getAmountIn(exchangeId, address(reserveToken), address(token), 1e18);
    assertEq(amountIn, expectedAmountIn);
  }
}
