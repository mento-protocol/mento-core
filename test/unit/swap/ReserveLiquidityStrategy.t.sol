// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
// solhint-disable modifier-name-mixedcase,
pragma solidity ^0.8;
import { Test } from "mento-std/Test.sol";

import { UD60x18, ud } from "prb-math/UD60x18.sol";

import { ILiquidityStrategy } from "contracts/interfaces/ILiquidityStrategy.sol";
import { ReserveLiquidityStrategy } from "contracts/swap/ReserveLiquidityStrategy.sol";

import { MockERC20 } from "test/utils/mocks/MockERC20.sol";
import { MockReserve } from "test/utils/mocks/MockReserve.sol";
import { MockFPMMPool } from "test/utils/mocks/MockFPMMPool.sol";

contract ReserveLiquidityStrategyTest is Test {
  address public deployer = makeAddr("Deployer");
  address public alice = makeAddr("Alice");
  address public otherAddress = makeAddr("Other");

  ReserveLiquidityStrategy public strat;
  MockReserve public mockReserve;
  MockFPMMPool public mockPool;
  MockFPMMPool public mockPool6Dec;
  MockERC20 public stableToken;
  MockERC20 public collateralToken;
  MockERC20 public collateralToken6Dec;

  uint256 constant ONE_DAY = 1 days;
  uint256 constant DEFAULT_COOLDOWN = ONE_DAY;

  // Initial balances
  uint256 constant POOL_INITIAL_STABLE_BALANCE = 10000e18;
  uint256 constant POOL_INITIAL_COLLATERAL_BALANCE = 10000e18;
  uint256 constant RESERVE_INITIAL_COLLATERAL_BALANCE = 10000e18;

  // Events from LiquidityStrategy
  event FPMMPoolAdded(address indexed pool, uint256 cooldown);
  event FPMMPoolRemoved(address indexed pool);
  event RebalanceSkippedNotCool(address indexed pool);
  event RebalanceSkippedPriceInRange(address indexed pool);
  event RebalanceExecuted(address indexed pool, uint256 priceBefore, uint256 priceAfter);

  // Events from ReserveLiquidityStrategy
  event ReserveSet(address indexed reserve);
  event RebalanceInitiated(
    address indexed pool,
    uint256 stableOut,
    uint256 collateralOut,
    uint256 inputAmount,
    ILiquidityStrategy.PriceDirection direction
  );

  function setUp() public {
    vm.label(deployer, "Deployer");
    vm.label(alice, "Alice");
    vm.label(address(this), "TestContract");

    vm.startPrank(deployer);
    // Deploy mock tokens (token0 = stable, token1 = collateral)
    stableToken = new MockERC20("Mock Stable", "mSTB", 18);
    collateralToken = new MockERC20("Mock Collateral", "mCOL", 18);
    collateralToken6Dec = new MockERC20("Mock Collateral6", "mCOL6", 6);
    vm.label(address(stableToken), "StableToken (mSTB)");
    vm.label(address(collateralToken), "CollateralToken (mCOL)");
    vm.label(address(collateralToken6Dec), "CollateralToken6Dec (mCOL6)");

    mockReserve = new MockReserve();
    vm.label(address(mockReserve), "MockReserve");
    collateralToken.mint(address(mockReserve), RESERVE_INITIAL_COLLATERAL_BALANCE);
    collateralToken6Dec.mint(address(mockReserve), RESERVE_INITIAL_COLLATERAL_BALANCE);

    strat = new ReserveLiquidityStrategy(false);
    strat.initialize(address(mockReserve));
    vm.label(address(strat), "ReserveLiquidityStrategy");

    // Deploy mock pool with mock tokens
    mockPool = new MockFPMMPool(address(strat), address(stableToken), address(collateralToken));
    vm.label(address(mockPool), "MockFPMMPool");

    mockPool6Dec = new MockFPMMPool(address(strat), address(stableToken), address(collateralToken6Dec));
    vm.label(address(mockPool6Dec), "MockFPMMPool6Dec");

    // Fund MockFPMMPool with initial token balances
    stableToken.mint(address(mockPool), POOL_INITIAL_STABLE_BALANCE);
    stableToken.mint(address(mockPool6Dec), POOL_INITIAL_STABLE_BALANCE);
    collateralToken.mint(address(mockPool), POOL_INITIAL_COLLATERAL_BALANCE);
    collateralToken6Dec.mint(address(mockPool6Dec), POOL_INITIAL_COLLATERAL_BALANCE);

    // Add pools to strategy
    strat.addPool(address(mockPool), DEFAULT_COOLDOWN);
    strat.addPool(address(mockPool6Dec), DEFAULT_COOLDOWN);
    vm.stopPrank();
  }

  /* ---------- Admin Functions ---------- */

  function test_initialize_shouldSetOwnerAndReserve() public view {
    assertEq(strat.owner(), deployer);
    assertEq(address(strat.reserve()), address(mockReserve));
  }

  function test_setReserve_shouldSetReserve() public {
    vm.startPrank(deployer);
    MockReserve newMockReserve = new MockReserve();
    vm.label(address(newMockReserve), "NewMockReserve");

    vm.expectEmit(true, false, false, true);
    emit ReserveSet(address(newMockReserve));
    strat.setReserve(address(newMockReserve));

    assertEq(address(strat.reserve()), address(newMockReserve));
    vm.stopPrank();
  }

  function test_setReserve_revert_notOwner() public {
    vm.startPrank(alice);
    MockReserve newMockReserve = new MockReserve();
    vm.expectRevert("Ownable: caller is not the owner");
    strat.setReserve(address(newMockReserve));
    vm.stopPrank();
  }

  function test_setReserve_revert_zeroAddress() public {
    vm.startPrank(deployer);
    vm.expectRevert("RLS: ZERO_ADDRESS_RESERVE");
    strat.setReserve(address(0));
    vm.stopPrank();
  }

  /* ---------- Rebalance Revert Condition Tests ---------- */

  function test_rebalance_shouldRevert_whenTokenDecimalsGreaterThan18() public {
    // Create mock tokens with invalid decimals
    MockERC20 tokenWithInvalidDecimals = new MockERC20("Invalid Decimals", "INVD", 19);
    MockFPMMPool poolWithInvalidDecimals = new MockFPMMPool(
      address(strat), 
      address(tokenWithInvalidDecimals), 
      address(collateralToken)
    );
    
    vm.startPrank(deployer);
    strat.addPool(address(poolWithInvalidDecimals), DEFAULT_COOLDOWN);
    vm.stopPrank();
    
    // Mock metadata to return 19 decimals for token0
    vm.mockCall(
      address(poolWithInvalidDecimals),
      abi.encodeWithSelector(poolWithInvalidDecimals.metadata.selector),
      abi.encode(19, 18, 1000e18, 1000e18, address(tokenWithInvalidDecimals), address(collateralToken))
    );
    
    // Set up prices for rebalance
    poolWithInvalidDecimals.setPrices(1e18, 1.05e18);
    
    // Expect revert with RLS: TOKEN_DECIMALS_TOO_LARGE
    vm.expectRevert("RLS: TOKEN_DECIMALS_TOO_LARGE");
    strat.rebalance(address(poolWithInvalidDecimals));
  }

  function test_rebalance_shouldRevert_whenCooldownActive() public {
    // Initial rebalance to set timestamp
    mockPool.setPrices(1e18, 1.02e18); // poolPrice > Oracle + threshold
    mockPool.setReserves(1050e18, 1000e18); // S=1050, C=1000, P_oracle=1

    // Balances before first rebalance
    uint256 poolStableBefore = stableToken.balanceOf(address(mockPool));
    uint256 poolCollateralBefore = collateralToken.balanceOf(address(mockPool));
    uint256 reserveCollateralBefore = collateralToken.balanceOf(address(mockReserve));

    strat.rebalance(address(mockPool));

    // Pool balance changes: sends stable, receives collateral.
    // MockPool's internal reserve0/1 are set by setReserves, actual balances are what we check here.
    assertEq(stableToken.balanceOf(address(mockPool)), poolStableBefore - 25e18, "Pool stable balance incorrect");
    assertEq(
      collateralToken.balanceOf(address(mockPool)),
      poolCollateralBefore + 25e18,
      "Pool collateral balance incorrect"
    );

    // Reserve balance changes: sends collateral.
    assertEq(
      collateralToken.balanceOf(address(mockReserve)),
      reserveCollateralBefore - 25e18,
      "Reserve collateral balance unexpected"
    );

    // Attempt rebalance before cooldown
    vm.expectEmit(true, false, false, true);
    emit RebalanceSkippedNotCool(address(mockPool));
    strat.rebalance(address(mockPool)); // Should skip
  }

  function test_rebalance_shouldSkip_whenPriceInRange() public {
    mockPool.setPrices(1e18, 1.005e18); // 0.5% deviation, threshold 1%
    mockPool.setRebalanceThreshold(100); // 1%

    vm.expectEmit(true, false, false, true);
    emit RebalanceSkippedPriceInRange(address(mockPool));
    strat.rebalance(address(mockPool));
  }

  /* ---------- Rebalance Core Logic Tests ---------- */

  function test_rebalance_whenPoolPriceAboveOracle_shouldTriggerContraction() public {
    // --- Setup ---
    uint256 stableReserveInPool = 1050e18; // S
    uint256 collateralReserveInPool = 1000e18; // C
    uint256 oraclePrice = 1e18; // P_oracle
    uint256 currentPoolPrice = 1.02e18; // P_pool > P_oracle + threshold
    uint256 thresholdBps = 100; // 1%

    mockPool.setReserves(stableReserveInPool, collateralReserveInPool);
    mockPool.setPrices(oraclePrice, currentPoolPrice);
    mockPool.setRebalanceThreshold(thresholdBps);

    // --- Expected Calculations (Contraction) ---
    // Y = (S - P * C) / (2 * P) -> collateralToSell (inputAmount)
    // X = Y * P -> stablesToBuy (stableOut)

    UD60x18 stableR_ud = ud(stableReserveInPool);
    UD60x18 collateralR_ud = ud(collateralReserveInPool);
    UD60x18 oracleP_ud = ud(oraclePrice);

    UD60x18 numerator = stableR_ud.sub(oracleP_ud.mul(collateralR_ud)); // 50e18
    UD60x18 collateralToSell_ud = numerator.div(oracleP_ud.mul(ud(2e18))); // 25e18

    UD60x18 stablesToBuy_ud = collateralToSell_ud.mul(oracleP_ud); // 25e18
    uint256 expectedStableOut = stablesToBuy_ud.unwrap(); // 25e18

    uint256 expectedInputAmountCollateral = collateralToSell_ud.unwrap(); // 25e18
    uint256 expectedCollateralOut = 0;
    ILiquidityStrategy.PriceDirection expectedDirection = ILiquidityStrategy.PriceDirection.ABOVE_ORACLE;

    // --- Expect RebalanceInitiated Event---
    vm.expectEmit(true, true, true, true);
    emit RebalanceInitiated(
      address(mockPool),
      expectedStableOut,
      expectedCollateralOut,
      expectedInputAmountCollateral,
      expectedDirection
    );

    // --- Expect call to IFPMM.rebalance on mockPool ---
    bytes memory expectedCallbackData = abi.encode(address(mockPool), expectedInputAmountCollateral, expectedDirection);
    vm.expectCall(
      address(mockPool),
      abi.encodeWithSelector(
        mockPool.rebalance.selector,
        expectedStableOut,
        expectedCollateralOut,
        address(strat),
        expectedCallbackData
      ),
      1
    );

    // --- Expect calls from strat.hook (Contraction) ---

    // 1. Stable token burn
    vm.expectCall(address(stableToken), abi.encodeWithSelector(stableToken.burn.selector, expectedStableOut), 1);

    // 2. Reserve transfer collateral
    vm.expectCall(
      address(mockReserve),
      abi.encodeWithSelector(
        mockReserve.transferExchangeCollateralAsset.selector,
        address(collateralToken),
        payable(address(mockPool)),
        expectedInputAmountCollateral
      ),
      1
    );

    // --- Expect RebalanceExecuted Event ---
    // NOTE: The MockFPMMPool implementation does not simulate price updates after rebalancing.
    // This is intentional as price updates are not being tested here. The RebalanceExecuted event
    // will show the same price before and after since we're only verifying the event emission logic.
    vm.expectEmit(true, true, true, true);
    emit RebalanceExecuted(address(mockPool), currentPoolPrice, currentPoolPrice);

    // --- Execute ---
    (uint256 lastRebalanceBefore, ) = strat.fpmmPoolConfigs(address(mockPool));
    strat.rebalance(address(mockPool));

    // --- Assertions ---
    (uint256 lastRebalanceAfter, ) = strat.fpmmPoolConfigs(address(mockPool));
    assertTrue(lastRebalanceAfter > lastRebalanceBefore, "Last rebalance time not updated");
    assertTrue(lastRebalanceAfter <= block.timestamp, "Last rebalance time in future");
  }

  function test_rebalance_whenPoolPriceBelowOracle_shouldTriggerExpansion() public {
    // --- Setup ---

    uint256 stableReserveInPool = 1000e18; // S
    uint256 collateralReserveInPool = 1050e18; // C
    uint256 oraclePrice = 1e18; // P_oracle
    uint256 currentPoolPrice = 0.98e18; // P_pool < P_oracle - threshold
    uint256 thresholdBps = 100; // 1%

    mockPool.setReserves(stableReserveInPool, collateralReserveInPool);
    mockPool.setPrices(oraclePrice, currentPoolPrice);
    mockPool.setRebalanceThreshold(thresholdBps);

    // --- Expected Calculations (Expansion) ---
    // X = (C * P - S) / 2 -> stablesToSell (inputAmount)
    // Y = X / P -> collateralToBuy (collateralOut)

    UD60x18 stableR_ud = ud(stableReserveInPool);
    UD60x18 collateralR_ud = ud(collateralReserveInPool);
    UD60x18 oracleP_ud = ud(oraclePrice);

    // (1050 - 1000) / 2 = 25e18
    UD60x18 stablesToSell_ud = (collateralR_ud.mul(oracleP_ud).sub(stableR_ud)).div(ud(2e18));
    UD60x18 collateralToBuy_ud = stablesToSell_ud.div(oracleP_ud); // 25e18 / 1e18 = 25e18

    uint256 expectedCollateralOut = collateralToBuy_ud.unwrap(); // 25e18
    uint256 expectedInputAmountStable = stablesToSell_ud.unwrap(); // 25e18
    uint256 expectedStableOut = 0;
    ILiquidityStrategy.PriceDirection expectedDirection = ILiquidityStrategy.PriceDirection.BELOW_ORACLE;

    // --- Expect call to IFPMM.rebalance on mockPool ---
    bytes memory expectedCallbackData = abi.encode(address(mockPool), expectedInputAmountStable, expectedDirection);
    vm.expectCall(
      address(mockPool),
      abi.encodeWithSelector(
        mockPool.rebalance.selector,
        expectedStableOut,
        expectedCollateralOut,
        address(strat),
        expectedCallbackData
      ),
      1
    );

    // --- Expect RebalanceInitiated Event ---
    vm.expectEmit(true, true, true, true);
    emit RebalanceInitiated(
      address(mockPool),
      expectedStableOut,
      expectedCollateralOut,
      expectedInputAmountStable,
      expectedDirection
    );

    // --- Expect calls from strat.hook (Expansion) ---

    // 1. Stable token mint to pool
    vm.expectCall(
      address(stableToken),
      abi.encodeWithSelector(stableToken.mint.selector, address(mockPool), expectedInputAmountStable),
      1
    );

    // 2. Collateral token transfer to reserve
    vm.expectCall(
      address(collateralToken),
      abi.encodeWithSelector(collateralToken.transfer.selector, address(mockReserve), expectedCollateralOut),
      1
    );

    // --- Expect RebalanceExecuted Event ---
    // NOTE: The MockFPMMPool implementation does not simulate price updates after rebalancing.
    // This is intentional as price updates are not being tested here. The RebalanceExecuted event
    // will show the same price before and after since we're only verifying the event emission logic.
    vm.expectEmit(true, true, true, true);
    emit RebalanceExecuted(address(mockPool), currentPoolPrice, currentPoolPrice);

    // --- Execute ---
    (uint256 lastRebalanceBefore, ) = strat.fpmmPoolConfigs(address(mockPool));
    strat.rebalance(address(mockPool));

    // --- Assertions ---
    (uint256 lastRebalanceAfter, ) = strat.fpmmPoolConfigs(address(mockPool));
    assertTrue(lastRebalanceAfter > lastRebalanceBefore, "Last rebalance time not updated");
    assertTrue(lastRebalanceAfter <= block.timestamp, "Last rebalance time in future");
  }

  function test_rebalance_whenPoolPriceAboveOracle_shouldTriggerContraction_withDifferentDecimals() public {
    // --- Setup ---
    uint256 stableMultiplier = 1; // 10**(18-18)
    uint256 collateralMultiplier = 10 ** (18 - 6); // 1e12

    uint256 stableReserveInPool = 1050e18; // S (1050 with 18 decimals)
    uint256 collateralReserveInPool = 1000e6; // C (1000 with 6 decimals)
    uint256 oraclePrice = 1e18; // P_oracle
    uint256 currentPoolPrice = 1.02e18; // P_pool > P_oracle + threshold
    uint256 thresholdBps = 100; // 1%

    mockPool6Dec.setReserves(stableReserveInPool, collateralReserveInPool);
    mockPool6Dec.setPrices(oraclePrice, currentPoolPrice);
    mockPool6Dec.setRebalanceThreshold(thresholdBps);

    // --- Expected Calculations (Contraction) ---

    UD60x18 stableR_ud = ud(stableReserveInPool * stableMultiplier); // 1050e18 * 1 = 1050e18
    UD60x18 collateralR_ud = ud(collateralReserveInPool * collateralMultiplier); // 1000e6 * 1e12 = 1000e18
    UD60x18 oracleP_ud = ud(oraclePrice);

    UD60x18 numerator = stableR_ud.sub(oracleP_ud.mul(collateralR_ud)); // 1050e18 - 1e18 * 1000e18 = 50e18
    UD60x18 collateralToSell_ud = numerator.div(oracleP_ud.mul(ud(2e18))); // // 50e18 / (1e18 * 2e18) = 25e18

    uint256 expectedStableOut = collateralToSell_ud.mul(oracleP_ud).unwrap() / stableMultiplier;
    uint256 expectedInputAmountCollateral = collateralToSell_ud.unwrap() / collateralMultiplier;
    uint256 expectedCollateralOut = 0;
    ILiquidityStrategy.PriceDirection expectedDirection = ILiquidityStrategy.PriceDirection.ABOVE_ORACLE;

    vm.expectEmit(true, true, true, true);
    emit RebalanceInitiated(
      address(mockPool6Dec),
      expectedStableOut,
      expectedCollateralOut,
      expectedInputAmountCollateral,
      expectedDirection
    );

    vm.expectCall(address(stableToken), abi.encodeWithSelector(stableToken.burn.selector, expectedStableOut), 1);

    vm.expectCall(
      address(mockReserve),
      abi.encodeWithSelector(
        mockReserve.transferExchangeCollateralAsset.selector,
        address(collateralToken6Dec),
        payable(address(mockPool6Dec)),
        expectedInputAmountCollateral
      ),
      1
    );

    // --- Expect call to IFPMM.rebalance on poolDiffDec ---
    bytes memory expectedCallbackData = abi.encode(
      address(mockPool6Dec),
      expectedInputAmountCollateral,
      expectedDirection
    );

    vm.expectCall(
      address(mockPool6Dec),
      abi.encodeWithSelector(
        mockPool6Dec.rebalance.selector,
        expectedStableOut,
        expectedCollateralOut,
        address(strat),
        expectedCallbackData
      ),
      1
    );

    vm.expectEmit(true, true, true, true);
    emit RebalanceExecuted(address(mockPool6Dec), currentPoolPrice, currentPoolPrice);

    // --- Execute ---
    strat.rebalance(address(mockPool6Dec));
  }

  /* ---------- Hook Revert Condition Tests ---------- */

  function test_hook_whenCallerIsNotPool_shouldRevert() public {
    bytes memory dummyData = abi.encode(address(mockPool), 0, ILiquidityStrategy.PriceDirection.ABOVE_ORACLE);
    vm.prank(alice);
    vm.expectRevert("RLS: CALLER_NOT_POOL");
    strat.hook(address(mockPool), 0, 0, dummyData);
  }

  function test_hook_whenCallerIsNotPool_mismatchedPoolInData_shouldRevert() public {
    MockFPMMPool otherPool = new MockFPMMPool(address(strat), address(stableToken), address(collateralToken));
    bytes memory dataWithOtherPool = abi.encode(address(otherPool), 0, ILiquidityStrategy.PriceDirection.ABOVE_ORACLE);
    vm.prank(address(mockPool));
    vm.expectRevert("RLS: CALLER_NOT_POOL");
    strat.hook(address(mockPool), 0, 0, dataWithOtherPool);
  }

  function test_hook_whenPoolIsNotRegistered_shouldRevert() public {
    MockFPMMPool unregisteredPool = new MockFPMMPool(address(strat), address(stableToken), address(collateralToken));
    vm.label(address(unregisteredPool), "UnregisteredPoolForHookTest");

    bytes memory dataWithUnregisteredPool = abi.encode(
      address(unregisteredPool),
      0,
      ILiquidityStrategy.PriceDirection.ABOVE_ORACLE
    );
    vm.prank(address(unregisteredPool));
    vm.expectRevert("RLS: UNREGISTERED_POOL");
    strat.hook(address(unregisteredPool), 0, 0, dataWithUnregisteredPool);
  }
}
