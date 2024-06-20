// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity 0.8.18;
pragma experimental ABIEncoderV2;

import { Test, console } from "forge-std-next/Test.sol";

import { StableTokenV2 } from "contracts/tokens/StableTokenV2.sol";
import { MockExchangeProvider } from "../mocks/MockExchangeProvider.sol";
import { MockReserve } from "../mocks/MockReserveNext.sol";
import { TestERC20 } from "../utils/TestERC20.sol";
import { Arrays } from "../utils/Arrays.sol";

import { FixidityLib } from "../utils/FixidityLibNext.sol";
import { IStableTokenV2 } from "contracts/interfaces/IStableTokenV2.sol";
import { IExchangeProvider } from "contracts/interfaces/IExchangeProvider.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";

import { ITradingLimits } from "contracts/libraries/ITradingLimits.sol";
import { Broker } from "contracts/swap/Broker.sol";

// forge test --match-contract Broker -vvv
contract BrokerTest is Test {
  using FixidityLib for FixidityLib.Fraction;

  event Swap(
    address exchangeProvider,
    bytes32 indexed exchangeId,
    address indexed trader,
    address indexed tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOut
  );
  event ExchangeProviderAdded(address indexed exchangeProvider);
  event ExchangeProviderRemoved(address indexed exchangeProvider);
  event ReserveSet(address indexed newAddress, address indexed prevAddress);
  event TradingLimitConfigured(bytes32 exchangeId, address token, ITradingLimits.Config config);

  address deployer = makeAddr("deployer");
  address notDeployer = makeAddr("notDeployer");
  address trader = makeAddr("trader");
  address randomExchangeProvider = makeAddr("randomExchangeProvider");
  address randomAsset = makeAddr("randomAsset");

  MockReserve reserve;
  StableTokenV2 stableAsset;
  TestERC20 collateralAsset;

  Broker broker;

  MockExchangeProvider exchangeProvider;
  address exchangeProvider1 = makeAddr("exchangeProvider1");
  address exchangeProvider2 = makeAddr("exchangeProvider2");

  address[] public exchangeProviders;
  address[] public reserves;

  function setUp() public virtual {
    /* Dependencies and actors */
    reserve = new MockReserve();
    collateralAsset = new TestERC20();
    stableAsset = new StableTokenV2(false);
    broker = new Broker(true);
    stableAsset.initialize(
      "cUSD",
      "cUSD",
      0, // deprecated
      address(0), // deprecated
      0, // deprecated
      0, // deprecated
      new address[](0),
      new uint256[](0),
      "" // deprecated
    );
    stableAsset.initializeV2(address(broker), address(0), address(0));
    randomAsset = makeAddr("randomAsset");
    exchangeProvider = new MockExchangeProvider();

    reserve.addToken(address(stableAsset));
    reserve.addCollateralAsset(address(collateralAsset));

    vm.startPrank(deployer);
    exchangeProviders.push(exchangeProvider1);
    exchangeProviders.push(exchangeProvider2);
    exchangeProviders.push((address(exchangeProvider)));
    reserves.push(address(reserve));
    reserves.push(address(reserve));
    reserves.push(address(reserve));
    broker.initialize(exchangeProviders, reserves);
    changePrank(trader);
  }
}

contract BrokerTest_initilizerAndSetters is BrokerTest {
  /* ---------- Initilizer ---------- */

  function test_initilize_shouldSetOwner() public {
    assertEq(broker.owner(), deployer);
  }

  function test_initilize_shouldSetExchangeProviderAddresseses() public {
    assertEq(broker.getExchangeProviders(), exchangeProviders);
  }

  function test_initilize_shouldSetReserves() public {
    assertEq(address(broker.exchangeReserve(exchangeProvider1)), address(reserve));
    assertEq(address(broker.exchangeReserve(exchangeProvider2)), address(reserve));
  }

  /* ---------- Setters ---------- */

  function test_addExchangeProvider_whenSenderIsNotOwner_shouldRevert() public {
    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    broker.addExchangeProvider(address(0), address(0));
  }

  function test_addExchangeProvider_wheExchangeProviderAddressIsZero_shouldRevert() public {
    changePrank(deployer);
    vm.expectRevert("ExchangeProvider address can't be 0");
    broker.addExchangeProvider(address(0), address(reserve));
  }

  function test_addExchangeProvider_whenReserveAddressIsZero_shouldRevert() public {
    changePrank(deployer);
    vm.expectRevert("Reserve address can't be 0");
    broker.addExchangeProvider(makeAddr("newExchangeProvider"), address(0));
  }

  function test_addExchangeProvider_whenSenderIsOwner_shouldUpdateAndEmit() public {
    changePrank(deployer);
    address newExchangeProvider = makeAddr("newExchangeProvider");
    vm.expectEmit(true, false, false, false);
    emit ExchangeProviderAdded(newExchangeProvider);
    broker.addExchangeProvider(newExchangeProvider, address(reserve));
    address[] memory updatedExchangeProviders = broker.getExchangeProviders();
    assertEq(updatedExchangeProviders[updatedExchangeProviders.length - 1], newExchangeProvider);
    assertEq(broker.isExchangeProvider(newExchangeProvider), true);
  }

  function test_addExchangeProvider_whenAlreadyAdded_shouldRevert() public {
    changePrank(deployer);
    vm.expectRevert("ExchangeProvider already exists in the list");
    broker.addExchangeProvider(address(exchangeProvider), address(reserve));
  }

  function test_removeExchangeProvider_whenSenderIsOwner_shouldUpdateAndEmit() public {
    changePrank(deployer);
    vm.expectEmit(true, true, true, true);
    emit ExchangeProviderRemoved(exchangeProvider1);
    broker.removeExchangeProvider(exchangeProvider1, 0);
    assert(broker.getExchangeProviders()[0] != exchangeProvider1);
  }

  function test_removeExchangeProvider_whenAddressDoesNotExist_shouldRevert() public {
    changePrank(deployer);
    vm.expectRevert("index doesn't match provider");
    broker.removeExchangeProvider(notDeployer, 1);
  }

  function test_removeExchangeProvider_whenIndexOutOfRange_shouldRevert() public {
    changePrank(deployer);
    vm.expectRevert("index doesn't match provider");
    broker.removeExchangeProvider(exchangeProvider1, 1);
  }

  function test_removeExchangeProvider_whenNotOwner_shouldRevert() public {
    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    broker.removeExchangeProvider(exchangeProvider1, 0);
  }

  function test_setReserves_whenSenderIsNotOwner_shouldRevert() public {
    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    broker.setReserves(new address[](0), new address[](0));
  }

  function test_setReserves_whenExchangeProviderIsNotAdded_shouldRevert() public {
    address[] memory exchangeProviders = new address[](1);
    exchangeProviders[0] = makeAddr("newExchangeProvider");
    address[] memory reserves = new address[](1);
    reserves[0] = makeAddr("newReserve");
    changePrank(deployer);
    vm.expectRevert("ExchangeProvider does not exist");
    broker.setReserves(exchangeProviders, reserves);
  }

  function test_setReserves_whenReserveAddressIsZero_shouldRevert() public {
    address[] memory exchangeProviders = new address[](1);
    exchangeProviders[0] = exchangeProvider1;
    address[] memory reserves = new address[](1);
    reserves[0] = address(0);
    changePrank(deployer);
    vm.expectRevert("Reserve address can't be 0");
    broker.setReserves(exchangeProviders, reserves);
  }

  function test_setReserves_whenSenderIsOwner_shouldUpdateAndEmit() public {
    address[] memory exchangeProviders = new address[](1);
    exchangeProviders[0] = exchangeProvider1;
    address[] memory reserves = new address[](1);
    reserves[0] = makeAddr("newReserve");
    changePrank(deployer);
    //vm.expectEmit(true, false, false, false);
    //emit ReserveSet(newReserve, address(reserve));

    broker.setReserves(exchangeProviders, reserves);
    assertEq(address(broker.exchangeReserve(address(exchangeProvider1))), reserves[0]);
  }
}

contract BrokerTest_getAmounts is BrokerTest {
  bytes32 exchangeId = keccak256(abi.encode("exhcangeId"));

  function setUp() public override {
    super.setUp();
    exchangeProvider.setRate(
      exchangeId,
      address(stableAsset),
      address(collateralAsset),
      FixidityLib.unwrap(FixidityLib.newFixedFraction(25, 10))
    );
  }

  function test_getAmountIn_whenExchangeProviderWasNotSet_shouldRevert() public {
    vm.expectRevert("ExchangeProvider does not exist");
    broker.getAmountIn(randomExchangeProvider, exchangeId, address(stableAsset), address(collateralAsset), 1e24);
  }

  function test_getAmountIn_whenExchangeProviderIsSet_shouldReceiveCall() public {
    uint256 amountIn = broker.getAmountIn(
      address(exchangeProvider),
      exchangeId,
      address(stableAsset),
      address(collateralAsset),
      1e18
    );

    assertEq(amountIn, 25e17);
  }

  function test_getAmountOut_whenExchangeProviderWasNotSet_shouldRevert() public {
    vm.expectRevert("ExchangeProvider does not exist");
    broker.getAmountOut(randomExchangeProvider, exchangeId, randomAsset, randomAsset, 1e24);
  }

  function test_getAmountOut_whenExchangeProviderIsSet_shouldReceiveCall() public {
    vm.expectCall(
      address(exchangeProvider),
      abi.encodeWithSelector(
        exchangeProvider.getAmountOut.selector,
        exchangeId,
        address(stableAsset),
        address(collateralAsset),
        1e18
      )
    );

    uint256 amountOut = broker.getAmountOut(
      address(exchangeProvider),
      exchangeId,
      address(stableAsset),
      address(collateralAsset),
      1e18
    );
    assertEq(amountOut, 4e17);
  }
}

contract BrokerTest_BurnStableTokens is BrokerTest {
  uint256 burnAmount = 1;

  function test_burnStableTokens_whenTokenIsAReserveStable_shouldBurnAndEmit() public {
    changePrank(address(broker));
    stableAsset.mint(notDeployer, 2);

    changePrank(notDeployer);
    stableAsset.approve(address(broker), burnAmount);

    vm.expectCall(
      address(IStableTokenV2(address(stableAsset))),
      abi.encodeWithSelector(
        IStableTokenV2(address(stableAsset)).transferFrom.selector,
        address(notDeployer),
        address(broker),
        burnAmount
      )
    );

    vm.expectCall(
      address(IStableTokenV2(address(stableAsset))),
      abi.encodeWithSelector(IStableTokenV2(address(stableAsset)).burn.selector, burnAmount)
    );

    bool result = broker.burnStableTokens(address(stableAsset), 1);

    assertEq(result, true);
    assertEq(stableAsset.balanceOf(notDeployer), 1);
    assertEq(stableAsset.balanceOf(address(broker)), 0);
  }
}

contract BrokerTest_swap is BrokerTest {
  struct AccountBalanceSnapshot {
    uint256 stable;
    uint256 collateral;
  }

  struct BalanceSnapshot {
    AccountBalanceSnapshot trader;
    AccountBalanceSnapshot reserve;
    AccountBalanceSnapshot broker;
  }

  bytes32 exchangeId = keccak256(abi.encode("exhcangeId"));

  function setUp() public override {
    super.setUp();
    exchangeProvider.setRate(
      exchangeId,
      address(stableAsset),
      address(collateralAsset),
      FixidityLib.unwrap(FixidityLib.newFixedFraction(25, 10))
    );

    deal(address(collateralAsset), address(reserve), 1e24);
    deal(address(collateralAsset), trader, 1e24);
    changePrank(address(broker));
    stableAsset.mint(trader, 1e22);
  }

  function makeBalanceSnapshot() internal view returns (BalanceSnapshot memory bs) {
    bs.trader.stable = stableAsset.balanceOf(trader);
    bs.trader.collateral = collateralAsset.balanceOf(trader);
    bs.reserve.stable = stableAsset.balanceOf(address(reserve));
    bs.reserve.collateral = collateralAsset.balanceOf(address(reserve));
    bs.broker.stable = stableAsset.balanceOf(address(broker));
    bs.broker.collateral = collateralAsset.balanceOf(address(broker));
  }

  function test_swapIn_whenAmountOutMinNotMet_shouldRevert() public {
    vm.expectRevert("amountOutMin not met");
    broker.swapIn(address(exchangeProvider), exchangeId, address(stableAsset), address(collateralAsset), 1e16, 1e20);
  }

  function test_swapOut_whenAmountInMaxExceeded_shouldRevert() public {
    vm.expectRevert("amountInMax exceeded");
    broker.swapOut(address(exchangeProvider), exchangeId, address(stableAsset), address(collateralAsset), 1e16, 1e15);
  }

  function test_swapIn_whenTokenInStableAsset_shouldUpdateAndEmit() public {
    changePrank(trader);
    uint256 amountIn = 1e16;
    stableAsset.approve(address(broker), amountIn);
    uint256 expectedAmountOut = exchangeProvider.getAmountOut(
      exchangeId,
      address(stableAsset),
      address(collateralAsset),
      amountIn
    );

    BalanceSnapshot memory balBefore = makeBalanceSnapshot();

    vm.expectEmit(true, true, true, true);
    emit Swap(
      address(exchangeProvider),
      exchangeId,
      trader,
      address(stableAsset),
      address(collateralAsset),
      amountIn,
      expectedAmountOut
    );
    uint256 amountOut = broker.swapIn(
      address(exchangeProvider),
      exchangeId,
      address(stableAsset),
      address(collateralAsset),
      amountIn,
      expectedAmountOut
    );

    BalanceSnapshot memory balAfter = makeBalanceSnapshot();
    assertEq(amountOut, expectedAmountOut);
    assertEq(balAfter.trader.stable, balBefore.trader.stable - amountIn);
    assertEq(balAfter.trader.collateral, balBefore.trader.collateral + expectedAmountOut);
    assertEq(balAfter.reserve.collateral, balBefore.reserve.collateral - expectedAmountOut);
    assertEq(balAfter.reserve.stable, 0);
    assertEq(balAfter.broker.stable, 0);
    assertEq(balAfter.broker.collateral, 0);
  }

  function test_swapIn_whenTokenInCollateralAsset_shouldUpdateAndEmit() public {
    changePrank(trader);
    uint256 amountIn = 1e16;
    uint256 expectedAmountOut = exchangeProvider.getAmountOut(
      exchangeId,
      address(collateralAsset),
      address(stableAsset),
      amountIn
    );

    collateralAsset.approve(address(broker), amountIn);
    BalanceSnapshot memory balBefore = makeBalanceSnapshot();

    vm.expectEmit(true, true, true, true);
    emit Swap(
      address(exchangeProvider),
      exchangeId,
      trader,
      address(collateralAsset),
      address(stableAsset),
      amountIn,
      expectedAmountOut
    );
    uint256 amountOut = broker.swapIn(
      address(exchangeProvider),
      exchangeId,
      address(collateralAsset),
      address(stableAsset),
      amountIn,
      expectedAmountOut
    );

    BalanceSnapshot memory balAfter = makeBalanceSnapshot();
    assertEq(amountOut, expectedAmountOut);
    assertEq(balAfter.trader.collateral, balBefore.trader.collateral - amountIn);
    assertEq(balAfter.reserve.collateral, balBefore.reserve.collateral + amountIn);
    assertEq(balAfter.trader.stable, balBefore.trader.stable + expectedAmountOut);
    assertEq(balAfter.reserve.stable, 0);
    assertEq(balAfter.broker.stable, 0);
    assertEq(balAfter.broker.collateral, 0);
  }

  function test_swapOut_whenTokenInStableAsset_shoulUpdateAndEmit() public {
    changePrank(trader);
    uint256 amountOut = 1e16;
    uint256 expectedAmountIn = exchangeProvider.getAmountIn(
      exchangeId,
      address(stableAsset),
      address(collateralAsset),
      amountOut
    );
    stableAsset.approve(address(broker), expectedAmountIn);

    BalanceSnapshot memory balBefore = makeBalanceSnapshot();
    vm.expectEmit(true, true, true, true);
    emit Swap(
      address(exchangeProvider),
      exchangeId,
      trader,
      address(stableAsset),
      address(collateralAsset),
      expectedAmountIn,
      amountOut
    );

    uint256 amountIn = broker.swapOut(
      address(exchangeProvider),
      exchangeId,
      address(stableAsset),
      address(collateralAsset),
      amountOut,
      expectedAmountIn
    );

    BalanceSnapshot memory balAfter = makeBalanceSnapshot();
    assertEq(amountIn, expectedAmountIn);
    assertEq(balAfter.trader.collateral, balBefore.trader.collateral + amountOut);
    assertEq(balAfter.reserve.collateral, balBefore.reserve.collateral - amountOut);
    assertEq(balAfter.trader.stable, balBefore.trader.stable - expectedAmountIn);
    assertEq(balAfter.reserve.stable, 0);
    assertEq(balAfter.broker.stable, 0);
    assertEq(balAfter.broker.collateral, 0);
  }

  function test_swapOut_whenTokenInCollateralAsset_shouldUpdateAndEmit() public {
    changePrank(trader);
    uint256 amountOut = 1e16;
    uint256 expectedAmountIn = exchangeProvider.getAmountIn(
      exchangeId,
      address(collateralAsset),
      address(stableAsset),
      amountOut
    );

    collateralAsset.approve(address(broker), expectedAmountIn);
    BalanceSnapshot memory balBefore = makeBalanceSnapshot();

    vm.expectEmit(true, true, true, true);
    emit Swap(
      address(exchangeProvider),
      exchangeId,
      trader,
      address(collateralAsset),
      address(stableAsset),
      expectedAmountIn,
      amountOut
    );
    uint256 amountIn = broker.swapOut(
      address(exchangeProvider),
      exchangeId,
      address(collateralAsset),
      address(stableAsset),
      amountOut,
      expectedAmountIn
    );

    BalanceSnapshot memory balAfter = makeBalanceSnapshot();
    assertEq(amountIn, expectedAmountIn);
    assertEq(balAfter.trader.collateral, balBefore.trader.collateral - expectedAmountIn);
    assertEq(balAfter.reserve.collateral, balBefore.reserve.collateral + expectedAmountIn);
    assertEq(balAfter.trader.stable, balBefore.trader.stable + amountOut);
    assertEq(balAfter.reserve.stable, 0);
    assertEq(balAfter.broker.stable, 0);
    assertEq(balAfter.broker.collateral, 0);
  }

  function test_swapOut_whenExchangeManagerWasNotSet_shouldRevert() public {
    vm.expectRevert("ExchangeProvider does not exist");
    broker.swapOut(randomExchangeProvider, exchangeId, randomAsset, randomAsset, 2e24, 1e24);
  }

  function test_swapIn_whenTradingLimitWasNotMet_shouldSwap() public {
    ITradingLimits.Config memory config;
    config.flags = 1;
    config.timestep0 = 10000;
    config.limit0 = 1000;
    changePrank(deployer);
    vm.expectEmit(true, true, true, true);
    emit TradingLimitConfigured(exchangeId, address(stableAsset), config);
    broker.configureTradingLimit(exchangeId, address(stableAsset), config);
    changePrank(trader);

    collateralAsset.approve(address(broker), 1e21);
    broker.swapIn(address(exchangeProvider), exchangeId, address(collateralAsset), address(stableAsset), 1e20, 1e16);
  }

  function test_swapIn_whenTradingLimitWasMet_shouldNotSwap() public {
    ITradingLimits.Config memory config;
    config.flags = 1;
    config.timestep0 = 10000;
    config.limit0 = 100;
    changePrank(deployer);
    vm.expectEmit(true, true, true, true);
    emit TradingLimitConfigured(exchangeId, address(stableAsset), config);
    broker.configureTradingLimit(exchangeId, address(stableAsset), config);
    changePrank(trader);

    vm.expectRevert(bytes("L0 Exceeded"));
    broker.swapIn(address(exchangeProvider), exchangeId, address(stableAsset), address(collateralAsset), 5e20, 0);
  }
}
