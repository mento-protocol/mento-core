// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { Test } from "mento-std/Test.sol";

import { MockStableToken } from "../mocks/MockStableToken.sol";
import { MockExchangeProvider } from "../mocks/MockExchangeProvider.sol";
import { MockReserve } from "../mocks/MockReserve.sol";
import { TestERC20 } from "../mocks/TestERC20.sol";

import { FixidityLib } from "celo/contracts/common/FixidityLib.sol";

import { IStableTokenV2 } from "contracts/interfaces/IStableTokenV2.sol";
import { IExchangeProvider } from "contracts/interfaces/IExchangeProvider.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";

import { ITradingLimitsHarness } from "../harnesses/ITradingLimitsHarness.sol";
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
  event TradingLimitConfigured(bytes32 exchangeId, address token, ITradingLimitsHarness.Config config);

  address deployer = actor("deployer");
  address notDeployer = actor("notDeployer");
  address trader = actor("trader");
  address randomExchangeProvider = actor("randomExchangeProvider");
  address randomAsset = actor("randomAsset");

  MockReserve reserve;
  MockStableToken stableAsset;
  DummyERC20 collateralAsset;

  Broker broker;

  MockExchangeProvider exchangeProvider;
  address exchangeProvider1 = actor("exchangeProvider1");
  address exchangeProvider2 = actor("exchangeProvider2");

  address[] public exchangeProviders;

  function setUp() public {
    /* Dependencies and actors */
    reserve = new MockReserve();
    collateralAsset = new DummyERC20("Collateral", "CL", 18);
    stableAsset = new MockStableToken();
    randomAsset = actor("randomAsset");
    broker = new Broker(true);
    exchangeProvider = new MockExchangeProvider();

    reserve.addToken(address(stableAsset));
    reserve.addCollateralAsset(address(collateralAsset));

    vm.startPrank(deployer);
    exchangeProviders.push(exchangeProvider1);
    exchangeProviders.push(exchangeProvider2);
    exchangeProviders.push((address(exchangeProvider)));
    broker.initialize(exchangeProviders, address(reserve));
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

  function test_initilize_shouldSetReserve() public {
    assertEq(address(broker.reserve()), address(reserve));
  }

  /* ---------- Setters ---------- */

  function test_addExchangeProvider_whenSenderIsNotOwner_shouldRevert() public {
    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    broker.addExchangeProvider(address(0));
  }

  function test_addExchangeProvider_whenAddressIsZero_shouldRevert() public {
    changePrank(deployer);
    vm.expectRevert("ExchangeProvider address can't be 0");
    broker.addExchangeProvider(address(0));
  }

  function test_addExchangeProvider_whenSenderIsOwner_shouldUpdateAndEmit() public {
    changePrank(deployer);
    address newExchangeProvider = actor("newExchangeProvider");
    vm.expectEmit(true, false, false, false);
    emit ExchangeProviderAdded(newExchangeProvider);
    broker.addExchangeProvider(newExchangeProvider);
    address[] memory updatedExchangeProviders = broker.getExchangeProviders();
    assertEq(updatedExchangeProviders[updatedExchangeProviders.length - 1], newExchangeProvider);
    assertEq(broker.isExchangeProvider(newExchangeProvider), true);
  }

  function test_addExchangeProvider_whenAlreadyAdded_shouldRevert() public {
    changePrank(deployer);
    vm.expectRevert("ExchangeProvider already exists in the list");
    broker.addExchangeProvider(address(exchangeProvider));
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

  function test_setReserve_whenSenderIsNotOwner_shouldRevert() public {
    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    broker.setReserve(address(0));
  }

  function test_setReserve_whenAddressIsZero_shouldRevert() public {
    changePrank(deployer);
    vm.expectRevert("Reserve address must be set");
    broker.setReserve(address(0));
  }

  function test_setReserve_whenSenderIsOwner_shouldUpdateAndEmit() public {
    changePrank(deployer);
    address newReserve = actor("newReserve");
    vm.expectEmit(true, false, false, false);
    emit ReserveSet(newReserve, address(reserve));

    broker.setReserve(newReserve);
    assertEq(address(broker.reserve()), newReserve);
  }
}

contract BrokerTest_getAmounts is BrokerTest {
  bytes32 exchangeId = keccak256(abi.encode("exhcangeId"));

  function setUp() public {
    super.setUp();
    exchangeProvider.setRate(
      exchangeId,
      address(stableAsset),
      address(collateralAsset),
      FixidityLib.newFixedFraction(25, 10).unwrap()
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

  function test_burnStableTokens_whenTokenIsNotReserveStable_shouldRevert() public {
    changePrank(notDeployer);
    vm.expectRevert("Token must be a reserve stable asset");
    broker.burnStableTokens(randomAsset, 2);
  }

  function test_burnStableTokens_whenTokenIsAReserveStable_shouldBurnAndEmit() public {
    stableAsset.mint(notDeployer, 2);

    changePrank(notDeployer);

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

  function setUp() public {
    super.setUp();
    exchangeProvider.setRate(
      exchangeId,
      address(stableAsset),
      address(collateralAsset),
      FixidityLib.newFixedFraction(25, 10).unwrap()
    );

    deal(address(collateralAsset), address(reserve), 1e24);
    deal(address(collateralAsset), trader, 1e24);
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
    ITradingLimitsHarness.Config memory config;
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
    TradingLimits.Config memory config;
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
