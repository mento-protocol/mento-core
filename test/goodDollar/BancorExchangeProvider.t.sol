// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, state-visibility, max-states-count, var-name-mixedcase

import { Test, console } from "forge-std-next/Test.sol";
import { ERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/ERC20.sol";
import { BancorExchangeProvider } from "contracts/goodDollar/BancorExchangeProvider.sol";
import { IExchangeProvider } from "contracts/interfaces/IExchangeProvider.sol";
import { IBancorExchangeProvider } from "contracts/goodDollar/interfaces/IBancorExchangeProvider.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";

contract BancorExchangeProviderTest is Test {
  /* ------- Events from IBancorExchangeProvider ------- */

  event BrokerUpdated(address indexed newBroker);

  event ReserveUpdated(address indexed newReserve);

  event PowerUpdated(address indexed newPower);

  event ExchangeCreated(bytes32 indexed exchangeId, address indexed reserveAsset, address indexed tokenAddress);

  event ExchangeDestroyed(bytes32 indexed exchangeId, address indexed reserveAsset, address indexed tokenAddress);

  event ExitContributionSet(bytes32 indexed exchangeId, uint256 exitContribution);

  /* ------------------------------------------- */

  ERC20 public reserveToken;
  ERC20 public token;
  ERC20 public token2;

  address public reserveAddress;
  address public brokerAddress;
  IBancorExchangeProvider.PoolExchange public poolExchange1;
  IBancorExchangeProvider.PoolExchange public poolExchange2;

  function setUp() public virtual {
    reserveToken = new ERC20("cUSD", "cUSD");
    token = new ERC20("Good$", "G$");
    token2 = new ERC20("Good2$", "G2$");

    brokerAddress = makeAddr("Broker");
    reserveAddress = makeAddr("Reserve");

    poolExchange1 = IBancorExchangeProvider.PoolExchange({
      reserveAsset: address(reserveToken),
      tokenAddress: address(token),
      tokenSupply: 300_000 * 1e18,
      reserveBalance: 60_000 * 1e18,
      reserveRatio: 1e8 * 0.2,
      exitConribution: 1e8 * 0.01
    });

    poolExchange2 = IBancorExchangeProvider.PoolExchange({
      reserveAsset: address(reserveToken),
      tokenAddress: address(token2),
      tokenSupply: 300_000 * 1e18,
      reserveBalance: 60_000 * 1e18,
      reserveRatio: 1e8 * 0.2,
      exitConribution: 1e8 * 0.01
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

  function initializeBancorExchangeProvider() internal returns (BancorExchangeProvider) {
    BancorExchangeProvider bancorExchangeProvider = new BancorExchangeProvider(false);

    bancorExchangeProvider.initialize(brokerAddress, reserveAddress);
    return bancorExchangeProvider;
  }
}

contract BancorExchangeProviderTest_initilizerSettersGetters is BancorExchangeProviderTest {
  BancorExchangeProvider bancorExchangeProvider;

  function setUp() public override {
    super.setUp();
    bancorExchangeProvider = initializeBancorExchangeProvider();
  }

  /* ---------- Initilizer ---------- */
  function test_initialize_shouldSetOwner() public {
    assertEq(bancorExchangeProvider.owner(), address(this));
  }

  function test_initilize_shouldSetBroker() public {
    assertEq(bancorExchangeProvider.broker(), brokerAddress);
  }

  function test_initilize_shouldSetReserve() public {
    assertEq(address(bancorExchangeProvider.reserve()), reserveAddress);
  }

  /* ---------- Setters ---------- */

  function test_setBroker_whenSenderIsNotOwner_shouldRevert() public {
    vm.prank(makeAddr("NotOwner"));
    vm.expectRevert("Ownable: caller is not the owner");
    bancorExchangeProvider.setBroker(makeAddr("NewBroker"));
  }

  function test_setBroker_whenAddressIsZero_shouldRevert() public {
    vm.expectRevert("Broker address must be set");
    bancorExchangeProvider.setBroker(address(0));
  }

  function test_setBroker_whenSenderIsOwner_shouldUpdateAndEmit() public {
    address newBroker = makeAddr("NewBroker");

    vm.expectEmit(true, true, true, true);
    emit BrokerUpdated(newBroker);
    bancorExchangeProvider.setBroker(newBroker);

    assertEq(bancorExchangeProvider.broker(), newBroker);
  }

  function test_setReserve_whenSenderIsNotOwner_shouldRevert() public {
    vm.prank(makeAddr("NotOwner"));
    vm.expectRevert("Ownable: caller is not the owner");
    bancorExchangeProvider.setReserve(makeAddr("NewReserve"));
  }

  function test_setReserve_whenAddressIsZero_shouldRevert() public {
    vm.expectRevert("Reserve address must be set");
    bancorExchangeProvider.setReserve(address(0));
  }

  function test_setReserve_whenSenderIsOwner_shouldUpdateAndEmit() public {
    address newReserve = makeAddr("NewReserve");

    vm.expectEmit(true, true, true, true);
    emit ReserveUpdated(newReserve);
    bancorExchangeProvider.setReserve(newReserve);

    assertEq(address(bancorExchangeProvider.reserve()), newReserve);
  }

  function test_setExitContribution_whenSenderIsNotOwner_shouldRevert() public {
    vm.prank(makeAddr("NotOwner"));
    vm.expectRevert("Ownable: caller is not the owner");
    bytes32 exchangeId = "0xexchangeId";
    bancorExchangeProvider.setExitContribution(exchangeId, 1e5);
  }

  function test_setExitContribution_whenExchangeDoesNotExist_shouldRevert() public {
    bytes32 exchangeId = "0xexchangeId";
    vm.expectRevert("Exchange does not exist");
    bancorExchangeProvider.setExitContribution(exchangeId, 1e5);
  }

  function test_setExitContribution_whenExitContributionAbove100Percent_shouldRevert() public {
    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);

    uint32 maxWeight = bancorExchangeProvider.MAX_WEIGHT();
    vm.expectRevert("Invalid exit contribution");
    bancorExchangeProvider.setExitContribution(exchangeId, maxWeight + 1);
  }

  function test_setExitContribution_whenSenderIsOwner_shouldUpdateAndEmit() public {
    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);

    uint32 newExitContribution = 1e3;
    vm.expectEmit(true, true, true, true);
    emit ExitContributionSet(exchangeId, newExitContribution);
    bancorExchangeProvider.setExitContribution(exchangeId, newExitContribution);

    IBancorExchangeProvider.PoolExchange memory poolExchange = bancorExchangeProvider.getPoolExchange(exchangeId);
    assertEq(poolExchange.exitConribution, newExitContribution);
  }

  /* ---------- Getters ---------- */

  function test_getPoolExchange_whenExchangeDoesNotExist_shouldRevert() public {
    bytes32 exchangeId = "0xexchangeId";
    vm.expectRevert("An exchange with the specified id does not exist");
    bancorExchangeProvider.getPoolExchange(exchangeId);
  }

  function test_getPoolExchange_whenPoolExists_shouldReturnPool() public {
    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);

    IBancorExchangeProvider.PoolExchange memory poolExchange = bancorExchangeProvider.getPoolExchange(exchangeId);
    assertEq(poolExchange.reserveAsset, poolExchange1.reserveAsset);
    assertEq(poolExchange.tokenAddress, poolExchange1.tokenAddress);
    assertEq(poolExchange.tokenSupply, poolExchange1.tokenSupply);
    assertEq(poolExchange.reserveBalance, poolExchange1.reserveBalance);
    assertEq(poolExchange.reserveRatio, poolExchange1.reserveRatio);
    assertEq(poolExchange.exitConribution, poolExchange1.exitConribution);
  }

  function test_getExchangeIds_whenNoExchanges_shouldReturnEmptyArray() public {
    bytes32[] memory exchangeIds = bancorExchangeProvider.getExchangeIds();
    assertEq(exchangeIds.length, 0);
  }

  function test_getExchangeIds_whenExchangesExist_shouldReturnExchangeIds() public {
    bytes32 exchangeId1 = bancorExchangeProvider.createExchange(poolExchange1);

    bytes32[] memory exchangeIds = bancorExchangeProvider.getExchangeIds();
    assertEq(exchangeIds.length, 1);
    assertEq(exchangeIds[0], exchangeId1);
  }

  function test_getExchanges_whenNoExchanges_shouldReturnEmptyArray() public {
    IExchangeProvider.Exchange[] memory exchanges = bancorExchangeProvider.getExchanges();
    assertEq(exchanges.length, 0);
  }

  function test_getExchanges_whenExchangesExist_shouldReturnExchange() public {
    bytes32 exchangeId1 = bancorExchangeProvider.createExchange(poolExchange1);

    IExchangeProvider.Exchange[] memory exchanges = bancorExchangeProvider.getExchanges();
    assertEq(exchanges.length, 1);
    assertEq(exchanges[0].exchangeId, exchangeId1);
    assertEq(exchanges[0].assets[0], poolExchange1.reserveAsset);
    assertEq(exchanges[0].assets[1], poolExchange1.tokenAddress);
  }
}

contract BancorExchangeProviderTest_createExchange is BancorExchangeProviderTest {
  BancorExchangeProvider bancorExchangeProvider;

  function setUp() public override {
    super.setUp();
    bancorExchangeProvider = initializeBancorExchangeProvider();
  }

  function test_createExchange_whenSenderIsNotOwner_shouldRevert() public {
    vm.prank(makeAddr("NotOwner"));
    vm.expectRevert("Ownable: caller is not the owner");
    bancorExchangeProvider.createExchange(poolExchange1);
  }

  function test_createExchange_whenReserveAssetIsZero_shouldRevert() public {
    poolExchange1.reserveAsset = address(0);
    vm.expectRevert("Invalid reserve asset");
    bancorExchangeProvider.createExchange(poolExchange1);
  }

  function test_createExchange_whenReserveAssetIsNotCollateral_shouldRevert() public {
    vm.mockCall(
      reserveAddress,
      abi.encodeWithSelector(IReserve(reserveAddress).isCollateralAsset.selector, address(reserveToken)),
      abi.encode(false)
    );
    vm.expectRevert("reserve asset must be a collateral registered with the reserve");
    bancorExchangeProvider.createExchange(poolExchange1);
  }

  function test_createExchange_whenTokenAddressIsZero_shouldRevert() public {
    poolExchange1.tokenAddress = address(0);
    vm.expectRevert("Invalid token address");
    bancorExchangeProvider.createExchange(poolExchange1);
  }

  function test_createExchange_whenTokenAddressIsNotStable_shouldRevert() public {
    vm.mockCall(
      reserveAddress,
      abi.encodeWithSelector(IReserve(reserveAddress).isStableAsset.selector, address(token)),
      abi.encode(false)
    );
    vm.expectRevert("token must be a stable registered with the reserve");
    bancorExchangeProvider.createExchange(poolExchange1);
  }

  function test_createExchange_whenReserveRatioIsSmaller2_shouldRevert() public {
    poolExchange1.reserveRatio = 0;
    vm.expectRevert("Invalid reserve ratio");
    bancorExchangeProvider.createExchange(poolExchange1);
    poolExchange1.reserveRatio = 1;
    vm.expectRevert("Invalid reserve ratio");
    bancorExchangeProvider.createExchange(poolExchange1);
  }

  function test_createExchange_whenReserveRatioAbove100Percent_shouldRevert() public {
    poolExchange1.reserveRatio = bancorExchangeProvider.MAX_WEIGHT() + 1;
    vm.expectRevert("Invalid reserve ratio");
    bancorExchangeProvider.createExchange(poolExchange1);
  }

  function test_createExchange_whenExitContributionAbove100Percent_shouldRevert() public {
    poolExchange1.exitConribution = bancorExchangeProvider.MAX_WEIGHT() + 1;
    vm.expectRevert("Invalid exit contribution");
    bancorExchangeProvider.createExchange(poolExchange1);
  }

  function test_createExchange_whenExchangeAlreadyExists_shouldRevert() public {
    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    vm.expectRevert("Exchange already exists");
    bancorExchangeProvider.createExchange(poolExchange1);
  }

  function test_createExchanges_whenReserveTokenHasMoreDecimalsThan18_shouldRevert() public {
    vm.mockCall(address(reserveToken), abi.encodeWithSelector(reserveToken.decimals.selector), abi.encode(19));
    vm.expectRevert("reserve token decimals must be <= 18");
    bancorExchangeProvider.createExchange(poolExchange1);
  }

  function test_createExchange_whenTokenHasMoreDecimalsThan18_shouldRevert() public {
    vm.mockCall(address(token), abi.encodeWithSelector(token.decimals.selector), abi.encode(19));
    vm.expectRevert("token decimals must be <= 18");
    bancorExchangeProvider.createExchange(poolExchange1);
  }

  function test_createExchange_whenExchangeDoesNotExist_shouldCreateExchangeAndEmit() public {
    vm.expectEmit(true, true, true, true);
    bytes32 expectedExchangeId = keccak256(abi.encodePacked(reserveToken.symbol(), token.symbol()));
    emit ExchangeCreated(expectedExchangeId, address(reserveToken), address(token));
    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    assertEq(exchangeId, expectedExchangeId);

    IBancorExchangeProvider.PoolExchange memory poolExchange = bancorExchangeProvider.getPoolExchange(exchangeId);
    assertEq(poolExchange.reserveAsset, poolExchange1.reserveAsset);
    assertEq(poolExchange.tokenAddress, poolExchange1.tokenAddress);
    assertEq(poolExchange.tokenSupply, poolExchange1.tokenSupply);
    assertEq(poolExchange.reserveBalance, poolExchange1.reserveBalance);
    assertEq(poolExchange.reserveRatio, poolExchange1.reserveRatio);
    assertEq(poolExchange.exitConribution, poolExchange1.exitConribution);

    IExchangeProvider.Exchange[] memory exchanges = bancorExchangeProvider.getExchanges();
    assertEq(exchanges.length, 1);
    assertEq(exchanges[0].exchangeId, exchangeId);

    assertEq(bancorExchangeProvider.tokenPrecisionMultipliers(address(reserveToken)), 1);
    assertEq(bancorExchangeProvider.tokenPrecisionMultipliers(address(token)), 1);
  }
}

contract BancorExchangeProviderTest_destroyExchange is BancorExchangeProviderTest {
  BancorExchangeProvider bancorExchangeProvider;

  function setUp() public override {
    super.setUp();
    bancorExchangeProvider = initializeBancorExchangeProvider();
  }

  function test_destroyExchange_whenSenderIsNotOwner_shouldRevert() public {
    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    vm.prank(makeAddr("NotOwner"));
    vm.expectRevert("Ownable: caller is not the owner");
    bancorExchangeProvider.destroyExchange(exchangeId, 0);
  }

  function test_destroyExchange_whenIndexOutOfRange_shouldRevert() public {
    bytes32 exchangeId = "0xexchangeId";
    vm.expectRevert("exchangeIdIndex not in range");
    bancorExchangeProvider.destroyExchange(exchangeId, 10);
  }

  function test_destroyExchange_whenExchangeIdAndIndexDontMatch_shouldRevert() public {
    bytes32 exchangeId = "0xexchangeId";
    bancorExchangeProvider.createExchange(poolExchange1);
    vm.expectRevert("exchangeId at index doesn't match");
    bancorExchangeProvider.destroyExchange(exchangeId, 0);
  }

  function test_destroyExchange_whenExchangeExists_shouldDestroyExchangeAndEmit() public {
    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    bytes32 exchangeId2 = bancorExchangeProvider.createExchange(poolExchange2);

    vm.expectEmit(true, true, true, true);
    emit ExchangeDestroyed(exchangeId, poolExchange1.reserveAsset, poolExchange1.tokenAddress);
    bancorExchangeProvider.destroyExchange(exchangeId, 0);

    bytes32[] memory exchangeIds = bancorExchangeProvider.getExchangeIds();
    assertEq(exchangeIds.length, 1);

    IExchangeProvider.Exchange[] memory exchanges = bancorExchangeProvider.getExchanges();
    assertEq(exchanges.length, 1);
    assertEq(exchanges[0].exchangeId, exchangeId2);
  }
}

contract BancorExchangeProviderTest_getAmountIn is BancorExchangeProviderTest {
  BancorExchangeProvider bancorExchangeProvider;

  function setUp() public override {
    super.setUp();
    bancorExchangeProvider = initializeBancorExchangeProvider();
  }

  function test_getAmountIn_whenExchangeDoesNotExist_shouldRevert() public {
    bytes32 exchangeId = "0xexchangeId";
    vm.expectRevert("An exchange with the specified id does not exist");
    bancorExchangeProvider.getAmountIn(exchangeId, address(reserveToken), address(token), 1e18);
  }

  function test_getAmountIn_whenTokenInNotInExchange_shouldRevert() public {
    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    vm.expectRevert("tokenIn and tokenOut must match exchange");
    bancorExchangeProvider.getAmountOut(exchangeId, address(token2), address(token), 1e18);
  }

  function test_getAmountIn_whenTokenOutNotInExchange_shouldRevert() public {
    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    vm.expectRevert("tokenIn and tokenOut must match exchange");
    bancorExchangeProvider.getAmountOut(exchangeId, address(token), address(token2), 1e18);
  }

  function test_getAmountIn_whenTokenInEqualsTokenOut_itReverts() public {
    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    vm.expectRevert("tokenIn and tokenOut must match exchange");
    bancorExchangeProvider.getAmountOut(exchangeId, address(token), address(token), 1e18);
  }

  function test_getAmountIn_whenTokenInIsReserveAsset_shouldReturnCorrectAmount() public {
    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    // formula: amountIn = reserveBalance * (( (tokenSupply + amountOut) / tokenSupply) ^ (1/reserveRatio) - 1)
    // calculation: 60_000 * ((300_001/300_000)^(1/0.2) - 1) ≈ 1.000006666688888926
    uint256 expectedAmountIn = 1000006666688888926;
    uint256 amountIn = bancorExchangeProvider.getAmountIn(exchangeId, address(reserveToken), address(token), 1e18);
    assertEq(amountIn, expectedAmountIn);
  }

  function test_getAmountIn_whenTokenInIsToken_shouldReturnCorrectAmount() public {
    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    // formula: amountIn = (tokenSupply * (( (amountOut + reserveBalance)  / reserveBalance) ^ (reserveRatio) - 1)) \ exitContribution
    // calculation: (300_000 * ( (60_001/60_000) ^0.2 - 1)) / (0.99) ≈ 1.010094276161615375
    uint256 expectedAmountIn = 1010094276161615375;
    uint256 amountIn = bancorExchangeProvider.getAmountIn(exchangeId, address(token), address(reserveToken), 1e18);
    assertEq(amountIn, expectedAmountIn);
  }
}

contract BancorExchangeProviderTest_getAmountOut is BancorExchangeProviderTest {
  BancorExchangeProvider bancorExchangeProvider;

  function setUp() public override {
    super.setUp();
    bancorExchangeProvider = initializeBancorExchangeProvider();
  }

  function test_getAmountOut_whenExchangeDoesNotExist_shouldRevert() public {
    bytes32 exchangeId = "0xexchangeId";
    vm.expectRevert("An exchange with the specified id does not exist");
    bancorExchangeProvider.getAmountOut(exchangeId, address(reserveToken), address(token), 1e18);
  }

  function test_getAmountOut_whenTokenInNotInExchange_shouldRevert() public {
    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    vm.expectRevert("tokenIn and tokenOut must match exchange");
    bancorExchangeProvider.getAmountOut(exchangeId, address(token2), address(token), 1e18);
  }

  function test_getAmountOut_whenTokenOutNotInExchange_shouldRevert() public {
    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    vm.expectRevert("tokenIn and tokenOut must match exchange");
    bancorExchangeProvider.getAmountOut(exchangeId, address(token), address(token2), 1e18);
  }

  function test_getAmountOut_whenTokenInEqualsTokenOut_itReverts() public {
    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    vm.expectRevert("tokenIn and tokenOut must match exchange");
    bancorExchangeProvider.getAmountOut(exchangeId, address(token), address(token), 1e18);
  }

  function test_getAmountOut_whenTokenInIsReserveAsset_shouldReturnCorrectAmount() public {
    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    // formula: amountOut = Supply * ( (1 + amountIn/reserveBalance)^collateralRatio - 1)
    // calculation: 300_000 * ( (1 + 1/60_000)^0.2 - 1) ≈ 0.999993333399999222
    uint256 expectedAmountIn = 999993333399999222;
    uint256 amountIn = bancorExchangeProvider.getAmountOut(exchangeId, address(reserveToken), address(token), 1e18);
    assertEq(amountIn, expectedAmountIn);
  }

  function test_getAmountOut_whenTokenInIsToken_shouldReturnCorrectAmount() public {
    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    // formula: amountOut = reserveBalance * ((1 + (amountIn * exitContribution)/tokenSupply)^(1/collateralRatio) -1)
    // calculation: 60_000 * ((1 + (1 * (1-0.01))/300_000)^(1/0.2) -1) ≈ 0.990006534021562235
    uint256 expectedAmountIn = 989993466021562164;
    uint256 amountIn = bancorExchangeProvider.getAmountOut(exchangeId, address(token), address(reserveToken), 1e18);
    assertEq(amountIn, expectedAmountIn);
  }
}

contract BancorExchangeProviderTest_currentPrice is BancorExchangeProviderTest {
  BancorExchangeProvider bancorExchangeProvider;

  function setUp() public override {
    super.setUp();
    bancorExchangeProvider = initializeBancorExchangeProvider();
  }

  function test_currentPrice_whenExchangeDoesNotExist_shouldRevert() public {
    bytes32 exchangeId = "0xexchangeId";
    vm.expectRevert("Exchange does not exist");
    bancorExchangeProvider.currentPrice(exchangeId);
  }

  function test_currentPrice_whenExchangeExists_shouldReturnCorrectPrice() public {
    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    // formula: price = reserveBalance / tokenSupply * reserveRatio
    // calculation: 60_000 / 300_000 * 0.2 = 1
    uint256 expectedPrice = 1e18;
    uint256 price = bancorExchangeProvider.currentPrice(exchangeId);
    assertEq(price, expectedPrice);
  }
}

contract BancorExchangeProviderTest_swapIn is BancorExchangeProviderTest {
  function test_swapIn_whenCallerIsNotBroker_shouldRevert() public {
    BancorExchangeProvider bancorExchangeProvider = initializeBancorExchangeProvider();
    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    vm.prank(makeAddr("NotBroker"));
    vm.expectRevert("Caller is not the Broker");
    bancorExchangeProvider.swapIn(exchangeId, address(reserveToken), address(token), 1e18);
  }

  function test_swapIn_whenExchangeDoesNotExist_shouldRevert() public {
    BancorExchangeProvider bancorExchangeProvider = initializeBancorExchangeProvider();
    vm.prank(brokerAddress);
    vm.expectRevert("An exchange with the specified id does not exist");
    bancorExchangeProvider.swapIn("0xexchangeId", address(reserveToken), address(token), 1e18);
  }

  function test_swapIn_whenTokenInNotInexchange_shouldRevert() public {
    BancorExchangeProvider bancorExchangeProvider = initializeBancorExchangeProvider();
    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    vm.prank(brokerAddress);
    vm.expectRevert("tokenIn and tokenOut must match exchange");
    bancorExchangeProvider.swapIn(exchangeId, address(token2), address(token), 1e18);
  }

  function test_swapIn_whenTokenOutNotInexchange_shouldRevert() public {
    BancorExchangeProvider bancorExchangeProvider = initializeBancorExchangeProvider();
    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    vm.prank(brokerAddress);
    vm.expectRevert("tokenIn and tokenOut must match exchange");
    bancorExchangeProvider.swapIn(exchangeId, address(token), address(token2), 1e18);
  }

  function test_swapIn_whenTokenInEqualsTokenOut_itReverts() public {
    BancorExchangeProvider bancorExchangeProvider = initializeBancorExchangeProvider();
    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    vm.prank(brokerAddress);
    vm.expectRevert("tokenIn and tokenOut must match exchange");
    bancorExchangeProvider.swapIn(exchangeId, address(token), address(token), 1e18);
  }

  function test_swapIn_whenTokenInIsReserveAsset_shouldSwapIn() public {
    BancorExchangeProvider bancorExchangeProvider = initializeBancorExchangeProvider();
    uint256 amountIn = 1e18;

    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    uint256 reserveBalanceBefore = poolExchange1.reserveBalance;
    uint256 tokenSupplyBefore = poolExchange1.tokenSupply;

    uint256 expectedAmountOut = bancorExchangeProvider.getAmountOut(
      exchangeId,
      address(reserveToken),
      address(token),
      amountIn
    );
    vm.prank(brokerAddress);
    uint256 amountOut = bancorExchangeProvider.swapIn(exchangeId, address(reserveToken), address(token), amountIn);
    assertEq(amountOut, expectedAmountOut);

    (, , uint256 tokenSupplyAfter, uint256 reserveBalanceAfter, , ) = bancorExchangeProvider.exchanges(exchangeId);

    assertEq(reserveBalanceAfter, reserveBalanceBefore + amountIn);
    assertEq(tokenSupplyAfter, tokenSupplyBefore + amountOut);
  }

  function test_swapIn_whenTokenInIsToken_shouldSwapIn() public {
    BancorExchangeProvider bancorExchangeProvider = initializeBancorExchangeProvider();
    uint256 amountIn = 1e18;

    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    uint256 reserveBalanceBefore = poolExchange1.reserveBalance;
    uint256 tokenSupplyBefore = poolExchange1.tokenSupply;

    uint256 expectedAmountOut = bancorExchangeProvider.getAmountOut(
      exchangeId,
      address(token),
      address(reserveToken),
      amountIn
    );
    vm.prank(brokerAddress);
    uint256 amountOut = bancorExchangeProvider.swapIn(exchangeId, address(token), address(reserveToken), amountIn);
    assertEq(amountOut, expectedAmountOut);

    (, , uint256 tokenSupplyAfter, uint256 reserveBalanceAfter, , ) = bancorExchangeProvider.exchanges(exchangeId);

    assertEq(reserveBalanceAfter, reserveBalanceBefore - amountOut);
    assertEq(tokenSupplyAfter, tokenSupplyBefore - amountIn);
  }
}

contract BancorExchangeProviderTest_swapOut is BancorExchangeProviderTest {
  function test_swapOut_whenCallerIsNotBroker_shouldRevert() public {
    BancorExchangeProvider bancorExchangeProvider = initializeBancorExchangeProvider();
    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    vm.prank(makeAddr("NotBroker"));
    vm.expectRevert("Caller is not the Broker");
    bancorExchangeProvider.swapOut(exchangeId, address(reserveToken), address(token), 1e18);
  }

  function test_swapOut_whenExchangeDoesNotExist_shouldRevert() public {
    BancorExchangeProvider bancorExchangeProvider = initializeBancorExchangeProvider();
    vm.prank(brokerAddress);
    vm.expectRevert("An exchange with the specified id does not exist");
    bancorExchangeProvider.swapOut("0xexchangeId", address(reserveToken), address(token), 1e18);
  }

  function test_swapOut_whenTokenInNotInexchange_shouldRevert() public {
    BancorExchangeProvider bancorExchangeProvider = initializeBancorExchangeProvider();
    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    vm.prank(brokerAddress);
    vm.expectRevert("tokenIn and tokenOut must match exchange");
    bancorExchangeProvider.swapOut(exchangeId, address(token2), address(token), 1e18);
  }

  function test_swapOut_whenTokenOutNotInexchange_shouldRevert() public {
    BancorExchangeProvider bancorExchangeProvider = initializeBancorExchangeProvider();
    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    vm.prank(brokerAddress);
    vm.expectRevert("tokenIn and tokenOut must match exchange");
    bancorExchangeProvider.swapOut(exchangeId, address(token), address(token2), 1e18);
  }

  function test_swapOut_whenTokenInEqualsTokenOut_shouldRevert() public {
    BancorExchangeProvider bancorExchangeProvider = initializeBancorExchangeProvider();
    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    vm.prank(brokerAddress);
    vm.expectRevert("tokenIn and tokenOut must match exchange");
    bancorExchangeProvider.swapOut(exchangeId, address(token), address(token), 1e18);
  }

  function test_swapOut_whenTokenInIsReserveAsset_shouldSwapOut() public {
    BancorExchangeProvider bancorExchangeProvider = initializeBancorExchangeProvider();
    uint256 amountOut = 1e18;

    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    uint256 reserveBalanceBefore = poolExchange1.reserveBalance;
    uint256 tokenSupplyBefore = poolExchange1.tokenSupply;

    uint256 expectedAmountIn = bancorExchangeProvider.getAmountIn(
      exchangeId,
      address(reserveToken),
      address(token),
      amountOut
    );
    vm.prank(brokerAddress);
    uint256 amountIn = bancorExchangeProvider.swapOut(exchangeId, address(reserveToken), address(token), amountOut);
    assertEq(amountIn, expectedAmountIn);

    (, , uint256 tokenSupplyAfter, uint256 reserveBalanceAfter, , ) = bancorExchangeProvider.exchanges(exchangeId);

    assertEq(reserveBalanceAfter, reserveBalanceBefore + amountIn);
    assertEq(tokenSupplyAfter, tokenSupplyBefore + amountOut);
  }

  function test_swapOut_whenTokenInIsToken_shouldSwapOut() public {
    BancorExchangeProvider bancorExchangeProvider = initializeBancorExchangeProvider();
    uint256 amountOut = 1e18;

    bytes32 exchangeId = bancorExchangeProvider.createExchange(poolExchange1);
    uint256 reserveBalanceBefore = poolExchange1.reserveBalance;
    uint256 tokenSupplyBefore = poolExchange1.tokenSupply;

    uint256 expectedAmountIn = bancorExchangeProvider.getAmountIn(
      exchangeId,
      address(token),
      address(reserveToken),
      amountOut
    );
    vm.prank(brokerAddress);
    uint256 amountIn = bancorExchangeProvider.swapOut(exchangeId, address(token), address(reserveToken), amountOut);
    assertEq(amountIn, expectedAmountIn);

    (, , uint256 tokenSupplyAfter, uint256 reserveBalanceAfter, , ) = bancorExchangeProvider.exchanges(exchangeId);

    assertEq(reserveBalanceAfter, reserveBalanceBefore - amountOut);
    assertEq(tokenSupplyAfter, tokenSupplyBefore - amountIn);
  }
}
