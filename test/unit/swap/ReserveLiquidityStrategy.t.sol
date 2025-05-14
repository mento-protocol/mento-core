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
  MockERC20 public stableToken;
  MockERC20 public collateralToken;

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
    vm.label(address(stableToken), "StableToken (mSTB)");
    vm.label(address(collateralToken), "CollateralToken (mCOL)");

    mockReserve = new MockReserve();
    vm.label(address(mockReserve), "MockReserve");
    collateralToken.mint(address(mockReserve), RESERVE_INITIAL_COLLATERAL_BALANCE);

    strat = new ReserveLiquidityStrategy(false);
    strat.initialize(address(mockReserve));
    vm.label(address(strat), "ReserveLiquidityStrategy");

    // Deploy mock pool with mock tokens
    mockPool = new MockFPMMPool(address(strat), address(stableToken), address(collateralToken));
    vm.label(address(mockPool), "MockFPMMPool");

    // Fund MockFPMMPool with initial token balances
    stableToken.mint(address(mockPool), POOL_INITIAL_STABLE_BALANCE);
    collateralToken.mint(address(mockPool), POOL_INITIAL_COLLATERAL_BALANCE);

    // Add pool to strategy
    strat.addPool(address(mockPool), DEFAULT_COOLDOWN);
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
    vm.expectRevert("Reserve cannot be the zero address");
    strat.setReserve(address(0));
    vm.stopPrank();
  }

  /* ---------- Rebalance Revert Condition Tests ---------- */

  function test_rebalance_shouldRevert_whenPoolNotRegistered() public {
    MockFPMMPool unregisteredPool = new MockFPMMPool(address(strat), address(stableToken), address(collateralToken));
    vm.expectRevert("Not added");
    strat.rebalance(address(unregisteredPool));
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

  function test_rebalance_shouldRevert_whenOraclePriceZero() public {
    mockPool.setPrices(0, 1e18);
    vm.expectRevert("Invalid prices");
    strat.rebalance(address(mockPool));
  }

  function test_rebalance_shouldRevert_whenPoolPriceZero() public {
    mockPool.setPrices(1e18, 0);
    vm.expectRevert("Invalid prices");
    strat.rebalance(address(mockPool));
  }

  function test_rebalance_shouldRevert_whenInvalidThresholdZero() public {
    mockPool.setRebalanceThreshold(0);
    mockPool.setPrices(1e18, 1.02e18);
    vm.expectRevert("Invalid pool threshold");
    strat.rebalance(address(mockPool));
  }

  function test_rebalance_shouldRevert_whenInvalidThresholdTooHigh() public {
    mockPool.setRebalanceThreshold(10001);
    mockPool.setPrices(1e18, 1.02e18);
    vm.expectRevert("Invalid pool threshold");
    strat.rebalance(address(mockPool));
  }

  function test_rebalance_shouldSkip_whenPriceInRange() public {
    mockPool.setPrices(1e18, 1.005e18); // 0.5% deviation, threshold 1%
    mockPool.setRebalanceThreshold(100); // 1%

    vm.expectEmit(true, false, false, true);
    emit RebalanceSkippedPriceInRange(address(mockPool));
    strat.rebalance(address(mockPool));
  }

  /* ==================== Rebalance Core Logic Tests ==================== */

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
    uint256 poolPriceAfterRebalanceMock = (currentPoolPrice * 99) / 100;
    vm.expectEmit(true, true, true, true);
    emit RebalanceExecuted(address(mockPool), currentPoolPrice, poolPriceAfterRebalanceMock);

    // --- Execute ---
    (uint256 lastRebalanceBefore, ) = strat.fpmmPoolConfigs(address(mockPool));
    strat.rebalance(address(mockPool));

    // --- Assertions ---
    (uint256 lastRebalanceAfter, ) = strat.fpmmPoolConfigs(address(mockPool));
    assertTrue(lastRebalanceAfter > lastRebalanceBefore, "Last rebalance time not updated");
    assertTrue(lastRebalanceAfter <= block.timestamp, "Last rebalance time in future");
  }
}
