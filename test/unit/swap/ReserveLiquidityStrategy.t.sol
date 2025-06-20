// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
// solhint-disable modifier-name-mixedcase,
pragma solidity ^0.8;
import { Test } from "mento-std/Test.sol";

import { ILiquidityStrategy } from "contracts/interfaces/ILiquidityStrategy.sol";
import { ReserveLiquidityStrategy } from "contracts/swap/ReserveLiquidityStrategy.sol";
import { IERC20MintableBurnable } from "contracts/common/IERC20MintableBurnable.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

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
  uint256 constant DEFAULT_INCENTIVE = 100;

  // Initial balances
  uint256 constant POOL_INITIAL_STABLE_BALANCE = 10000e18;
  uint256 constant POOL_INITIAL_COLLATERAL_BALANCE = 10000e18;
  uint256 constant RESERVE_INITIAL_COLLATERAL_BALANCE = 100000e18;

  // Events from LiquidityStrategy
  event FPMMPoolAdded(address indexed pool, uint256 cooldown);
  event FPMMPoolRemoved(address indexed pool);
  event RebalanceExecuted(address indexed pool, uint256 priceBefore, uint256 priceAfter);

  // Events from ReserveLiquidityStrategy
  event ReserveSet(address indexed reserve);
  event RebalanceInitiated(
    address indexed pool,
    uint256 stableOut,
    uint256 collateralOut,
    uint256 inputAmount,
    uint256 incentiveAmount,
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
    strat.addPool(address(mockPool), DEFAULT_COOLDOWN, DEFAULT_INCENTIVE);
    strat.addPool(address(mockPool6Dec), DEFAULT_COOLDOWN, DEFAULT_INCENTIVE);
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

  function test_setReserve_whenCallerNotOwner_shouldRevert() public {
    vm.startPrank(alice);
    MockReserve newMockReserve = new MockReserve();
    vm.expectRevert("Ownable: caller is not the owner");
    strat.setReserve(address(newMockReserve));
    vm.stopPrank();
  }

  function test_setReserve_whenAddressIsZero_shouldRevert() public {
    vm.startPrank(deployer);
    vm.expectRevert("RLS: ZERO_ADDRESS_RESERVE");
    strat.setReserve(address(0));
    vm.stopPrank();
  }

  /* ---------- Rebalance Revert Condition Tests ---------- */

  function test_rebalance_whenTokenDecimalsGreaterThan18_shouldRevert() public {
    // Create mock tokens with invalid decimals
    MockERC20 tokenWithInvalidDecimals = new MockERC20("Invalid Decimals", "INVD", 19);
    MockFPMMPool poolWithInvalidDecimals = new MockFPMMPool(
      address(strat),
      address(tokenWithInvalidDecimals),
      address(collateralToken)
    );

    vm.startPrank(deployer);
    strat.addPool(address(poolWithInvalidDecimals), DEFAULT_COOLDOWN, DEFAULT_INCENTIVE);
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

  function test_rebalance_whenCooldownActive_shouldRevert() public {
    // Initial rebalance to set timestamp
    // Create a scenario that will trigger expansion (price above oracle)
    mockPool.setPrices(1e18, 2e18); // poolPrice > Oracle + threshold
    mockPool.setReserves(2e21, 4e21); // S=2000, C=4000, P_oracle=1

    // Mint tokens to support the test
    collateralToken.mint(address(mockPool), 50e18);
    collateralToken.mint(address(mockReserve), 50e18);

    // First rebalance to set the timestamp
    strat.rebalance(address(mockPool));

    // Attempt rebalance before cooldown ends - should revert
    vm.expectRevert("LS: COOLDOWN_ACTIVE");
    strat.rebalance(address(mockPool));
  }

  function test_rebalance_whenPriceInRange_shouldRevert() public {
    mockPool.setPrices(1e18, 1.005e18); // 0.5% deviation, threshold 1%
    mockPool.setRebalanceThreshold(100, 100); // 1%

    vm.expectRevert("LS: PRICE_IN_RANGE");
    strat.rebalance(address(mockPool));
  }

  /* ---------- Rebalance Core Logic Tests ---------- */

  function test_rebalance_whenPoolPriceAboveOracle_shouldTriggerExpansion() public {
    // --- Setup with oracle price < 1e18 to create expansion ---
    uint256 stableReserveInPool = 1000e18; // S
    uint256 collateralReserveInPool = 1000e18; // C
    uint256 oraclePrice = 0.9e18; // P_oracle < 1e18 will make stable * (1-P) > 0
    uint256 poolPrice = 1.02e18; // P_pool > P_oracle + threshold
    uint256 thresholdBps = 100; // 1%

    mockPool.setReserves(stableReserveInPool, collateralReserveInPool);
    mockPool.setPrices(oraclePrice, poolPrice);
    mockPool.setRebalanceThreshold(thresholdBps, thresholdBps);

    // Add sufficient tokens to the pool and reserve for the test
    collateralToken.mint(address(mockPool), 1000e18);

    // Pre-calculate expected amounts with these values
    // Using formula: numerator = C - P * S = 1000e18 - 1000e18*0.9 = 100e18
    // collateralOut = numerator / 2 = 50e18
    // stablesIn = (collateralOut * 1e18) / P = (50e18 * 1e18) / 0.9 = 55.555...e18
    uint256 expectedCollateralOut = 50e18;
    uint256 expectedStablesIn = 55555555555555555555; // 55.555...e18
    uint256 incentiveAmount = (expectedStablesIn * DEFAULT_INCENTIVE) / 10_000;

    // Record balances before rebalance
    uint256 poolStableBefore = stableToken.balanceOf(address(mockPool));
    uint256 poolCollateralBefore = collateralToken.balanceOf(address(mockPool));
    uint256 reserveCollateralBefore = collateralToken.balanceOf(address(mockReserve));

    // Expect RebalanceInitiated event with non-zero amounts
    vm.expectEmit(true, true, true, true);
    emit RebalanceInitiated(
      address(mockPool),
      0, // stableOut
      expectedCollateralOut,
      expectedStablesIn - incentiveAmount,
      incentiveAmount,
      ILiquidityStrategy.PriceDirection.ABOVE_ORACLE
    );

    // Expect call to FPMM pool with non-zero amounts
    bytes memory expectedCallbackData = abi.encode(
      expectedStablesIn,
      ILiquidityStrategy.PriceDirection.ABOVE_ORACLE,
      incentiveAmount
    );

    vm.expectCall(
      address(mockPool),
      abi.encodeWithSelector(
        mockPool.rebalance.selector,
        0, // stableOut
        expectedCollateralOut,
        expectedCallbackData
      )
    );

    // --- Execute ---
    strat.rebalance(address(mockPool));

    // --- Assertions ---
    // Verify balance changes
    assertEq(
      stableToken.balanceOf(address(mockPool)),
      poolStableBefore + expectedStablesIn - incentiveAmount,
      "Pool stable balance should increase during expansion"
    );

    assertEq(
      collateralToken.balanceOf(address(mockPool)),
      poolCollateralBefore - expectedCollateralOut,
      "Pool collateral balance should decrease during expansion"
    );

    assertEq(
      collateralToken.balanceOf(address(mockReserve)),
      reserveCollateralBefore + expectedCollateralOut,
      "Reserve collateral balance should increase during expansion"
    );
  }

  function test_rebalance_whenPoolPriceBelowOracle_shouldTriggerContraction() public {
    // --- Setup ---
    // Create a scenario where contraction should happen
    // Setting these values to ensure a positive numerator for the formula
    uint256 stableReserveInPool = 1000e18; // S
    uint256 collateralReserveInPool = 950e18; // C < P * S (1000e18)
    uint256 oraclePrice = 1e18; // P_oracle
    uint256 poolPrice = 0.98e18; // P_pool < P_oracle - threshold
    uint256 thresholdBps = 100; // 1%

    mockPool.setReserves(stableReserveInPool, collateralReserveInPool);
    mockPool.setPrices(oraclePrice, poolPrice);
    mockPool.setRebalanceThreshold(thresholdBps, thresholdBps);

    // Mint additional collateral to the reserve for the test
    collateralToken.mint(address(mockReserve), 1000e18);

    // Record balances before rebalance
    uint256 poolStableBefore = stableToken.balanceOf(address(mockPool));
    uint256 poolCollateralBefore = collateralToken.balanceOf(address(mockPool));
    uint256 reserveCollateralBefore = collateralToken.balanceOf(address(mockReserve));

    // Calculate expected amounts
    // Using formula: numerator = P * S - C = 1e18*1000e18 - 950e18 = 50e18
    // collateralIn = numerator / 2 = 25e18
    // stableOut = collateralIn * 1e18 / P = 25e18 / 1e18 = 25e18
    uint256 expectedCollateralIn = 25e18;
    uint256 expectedStableOut = 25e18;
    uint256 incentiveAmount = (expectedCollateralIn * DEFAULT_INCENTIVE) / 10_000;

    // Expect RebalanceInitiated event with calculated amounts
    vm.expectEmit(true, true, true, true);
    emit RebalanceInitiated(
      address(mockPool),
      expectedStableOut,
      0, // collateralOut
      expectedCollateralIn - incentiveAmount,
      incentiveAmount,
      ILiquidityStrategy.PriceDirection.BELOW_ORACLE
    );

    // Expect call to FPMM pool with calculated amounts
    bytes memory expectedCallbackData = abi.encode(
      expectedCollateralIn,
      ILiquidityStrategy.PriceDirection.BELOW_ORACLE,
      incentiveAmount
    );

    vm.expectCall(
      address(mockPool),
      abi.encodeWithSelector(
        mockPool.rebalance.selector,
        expectedStableOut,
        0, // collateralOut
        expectedCallbackData
      )
    );

    // --- Execute ---
    (uint256 lastRebalanceBefore, , ) = strat.fpmmPoolConfigs(address(mockPool));
    strat.rebalance(address(mockPool));

    // --- Assertions ---
    (uint256 lastRebalanceAfter, , ) = strat.fpmmPoolConfigs(address(mockPool));
    assertTrue(lastRebalanceAfter > lastRebalanceBefore, "Last rebalance time not updated");
    assertTrue(lastRebalanceAfter <= block.timestamp, "Last rebalance time in future");

    // Verify specific balance changes
    assertEq(
      stableToken.balanceOf(address(mockPool)),
      poolStableBefore - expectedStableOut,
      "Pool stable balance should decrease by the exact calculated amount"
    );

    assertEq(
      collateralToken.balanceOf(address(mockPool)),
      poolCollateralBefore + expectedCollateralIn - incentiveAmount,
      "Pool collateral balance should increase by the exact calculated amount"
    );

    assertEq(
      collateralToken.balanceOf(address(mockReserve)),
      reserveCollateralBefore - expectedCollateralIn,
      "Reserve collateral balance should decrease by the exact calculated amount"
    );
  }

  function test_rebalance_withDifferentDecimals() public {
    // --- Setup ---
    // stable has 18 decimals, collateral has 6 decimals
    uint256 stableReserveInPool = 1050e18; // S
    uint256 collateralReserveInPool = 1100e6; // C
    uint256 oraclePrice = 1e18; // P_oracle
    uint256 poolPrice = 1.02e18; // P_pool > P_oracle + threshold
    uint256 thresholdBps = 100; // 1%

    mockPool6Dec.setReserves(stableReserveInPool, collateralReserveInPool);
    mockPool6Dec.setPrices(oraclePrice, poolPrice);
    mockPool6Dec.setRebalanceThreshold(thresholdBps, thresholdBps);

    // --- Calculations ---
    uint256 collateralReserveInPool_scaled = collateralReserveInPool * 1e12;

    // numerator = C_scaled - (P_oracle * S / 1e18)
    uint256 numerator = collateralReserveInPool_scaled - (oraclePrice * stableReserveInPool) / 1e18;

    uint256 collateralOut_scaled = numerator / 2;
    uint256 expectedCollateralOut = collateralOut_scaled / 1e12;
    uint256 expectedStablesIn = (collateralOut_scaled * 1e18) / oraclePrice;
    uint256 incentiveAmount = (expectedStablesIn * DEFAULT_INCENTIVE) / 10_000;

    // --- Balances ---
    uint256 poolStableBefore = stableToken.balanceOf(address(mockPool6Dec));
    uint256 poolCollateralBefore = collateralToken6Dec.balanceOf(address(mockPool6Dec));
    uint256 reserveCollateralBefore = collateralToken6Dec.balanceOf(address(mockReserve));

    // --- Event and call expectations ---
    vm.expectEmit(true, true, true, true);
    emit RebalanceInitiated(
      address(mockPool6Dec),
      0, // stableOut
      expectedCollateralOut,
      expectedStablesIn - incentiveAmount,
      incentiveAmount,
      ILiquidityStrategy.PriceDirection.ABOVE_ORACLE
    );

    bytes memory expectedCallbackData = abi.encode(
      expectedStablesIn,
      ILiquidityStrategy.PriceDirection.ABOVE_ORACLE,
      incentiveAmount
    );

    vm.expectCall(
      address(mockPool6Dec),
      abi.encodeWithSelector(mockPool6Dec.rebalance.selector, 0, expectedCollateralOut, expectedCallbackData)
    );

    // --- Execute ---
    (uint256 lastRebalanceBefore, , ) = strat.fpmmPoolConfigs(address(mockPool6Dec));
    strat.rebalance(address(mockPool6Dec));

    // --- Assertions ---
    (uint256 lastRebalanceAfter, , ) = strat.fpmmPoolConfigs(address(mockPool6Dec));
    assertTrue(lastRebalanceAfter > lastRebalanceBefore, "Last rebalance time not updated");
    assertTrue(lastRebalanceAfter <= block.timestamp, "Last rebalance time in future");

    assertEq(
      stableToken.balanceOf(address(mockPool6Dec)),
      poolStableBefore + expectedStablesIn - incentiveAmount,
      "Pool stable balance should increase during expansion"
    );

    assertEq(
      collateralToken6Dec.balanceOf(address(mockPool6Dec)),
      poolCollateralBefore - expectedCollateralOut,
      "Pool collateral balance should decrease during expansion"
    );

    assertEq(
      collateralToken6Dec.balanceOf(address(mockReserve)),
      reserveCollateralBefore + expectedCollateralOut,
      "Reserve collateral balance should increase during expansion"
    );
  }

  /* ---------- Hook Tests ---------- */

  function test_hook_whenInitiatorIsNotStrategy_shouldRevert() public {
    bytes memory dummyData = abi.encode(0, ILiquidityStrategy.PriceDirection.ABOVE_ORACLE, 0);
    vm.prank(alice);
    vm.expectRevert("RLS: HOOK_SENDER_NOT_SELF");
    strat.hook(address(mockPool), 0, 0, dummyData);
  }

  function test_hook_whenPoolIsNotRegistered_shouldRevert() public {
    MockFPMMPool unregisteredPool = new MockFPMMPool(address(strat), address(stableToken), address(collateralToken));
    vm.label(address(unregisteredPool), "UnregisteredPoolForHookTest");

    bytes memory dataWithUnregisteredPool = abi.encode(0, ILiquidityStrategy.PriceDirection.ABOVE_ORACLE, 0);
    vm.prank(address(unregisteredPool));
    vm.expectRevert("RLS: UNREGISTERED_POOL");
    strat.hook(address(strat), 0, 0, dataWithUnregisteredPool);
  }

  function test_hook_expansion_mock() public {
    // Setup for expansion (ABOVE_ORACLE)
    uint256 amountIn = 100e18; // Amount of stables to mint
    uint256 amount1Out = 50e18; // Amount of collateral to transfer to reserve
    address mockStableToken = makeAddr("MockStableToken");
    address mockCollateralToken = makeAddr("MockCollateralToken");

    // Mock pool with our mocked token addresses
    MockFPMMPool testPool = new MockFPMMPool(address(strat), mockStableToken, mockCollateralToken);
    vm.prank(deployer);
    strat.addPool(address(testPool), 1 days, DEFAULT_INCENTIVE);

    uint256 incentiveAmount = (amountIn * DEFAULT_INCENTIVE) / 10_000;
    bytes memory callbackData = abi.encode(amountIn, ILiquidityStrategy.PriceDirection.ABOVE_ORACLE, incentiveAmount);

    vm.mockCall(
      mockStableToken,
      abi.encodeWithSelector(IERC20MintableBurnable.mint.selector, address(testPool), amountIn - incentiveAmount),
      abi.encode(true)
    );
    vm.mockCall(
      mockStableToken,
      abi.encodeWithSelector(IERC20MintableBurnable.mint.selector, address(strat), incentiveAmount),
      abi.encode(true)
    );

    vm.mockCall(
      mockCollateralToken,
      abi.encodeWithSelector(IERC20.transfer.selector, address(mockReserve), amount1Out),
      abi.encode(true)
    );

    vm.expectCall(
      mockStableToken,
      abi.encodeWithSelector(IERC20MintableBurnable.mint.selector, address(testPool), amountIn - incentiveAmount)
    );
    vm.expectCall(
      mockStableToken,
      abi.encodeWithSelector(IERC20MintableBurnable.mint.selector, address(strat), incentiveAmount)
    );

    vm.expectCall(
      mockCollateralToken,
      abi.encodeWithSelector(IERC20.transfer.selector, address(mockReserve), amount1Out)
    );

    // Execute hook
    vm.prank(address(testPool));
    strat.hook(address(strat), 0, amount1Out, callbackData);
  }

  function test_hook_contraction_mock() public {
    // Setup for contraction (BELOW_ORACLE)
    uint256 amount0Out = 50e18; // Amount of stables to burn
    uint256 collateralIn = 100e18; // Amount of collateral to transfer from reserve
    address mockStableToken = makeAddr("MockStableToken");
    address mockCollateralToken = makeAddr("MockCollateralToken");

    // Mock pool with our mocked token addresses
    MockFPMMPool testPool = new MockFPMMPool(address(strat), mockStableToken, mockCollateralToken);
    vm.prank(deployer);
    strat.addPool(address(testPool), 1 days, DEFAULT_INCENTIVE);

    uint256 incentiveAmount = (collateralIn * DEFAULT_INCENTIVE) / 10_000;
    bytes memory callbackData = abi.encode(
      collateralIn,
      ILiquidityStrategy.PriceDirection.BELOW_ORACLE,
      incentiveAmount
    );

    // Mock token calls
    vm.mockCall(
      mockStableToken,
      abi.encodeWithSelector(IERC20MintableBurnable.burn.selector, amount0Out),
      abi.encode(true)
    );

    // Mock the reserve transfers with corrected amounts
    vm.mockCall(
      address(mockReserve),
      abi.encodeWithSelector(
        mockReserve.transferExchangeCollateralAsset.selector,
        mockCollateralToken,
        payable(address(testPool)),
        collateralIn - incentiveAmount
      ),
      abi.encode(true)
    );
    vm.mockCall(
      address(mockReserve),
      abi.encodeWithSelector(
        mockReserve.transferExchangeCollateralAsset.selector,
        mockCollateralToken,
        payable(address(strat)),
        incentiveAmount
      ),
      abi.encode(true)
    );

    // Expect these calls to be made
    vm.expectCall(mockStableToken, abi.encodeWithSelector(IERC20MintableBurnable.burn.selector, amount0Out));

    // Expect both reserve transfers with corrected amounts
    vm.expectCall(
      address(mockReserve),
      abi.encodeWithSelector(
        mockReserve.transferExchangeCollateralAsset.selector,
        mockCollateralToken,
        payable(address(testPool)),
        collateralIn - incentiveAmount
      )
    );
    vm.expectCall(
      address(mockReserve),
      abi.encodeWithSelector(
        mockReserve.transferExchangeCollateralAsset.selector,
        mockCollateralToken,
        payable(address(strat)),
        incentiveAmount
      )
    );

    // Execute hook
    vm.prank(address(testPool));
    strat.hook(address(strat), amount0Out, 0, callbackData);
  }

  function test_hook_whenExpansionTransferFails_shouldRevert() public {
    // Setup for expansion (ABOVE_ORACLE) with failing transfer
    uint256 amountIn = 100e18;
    uint256 amount1Out = 50e18;

    uint256 incentiveAmount = (amountIn * DEFAULT_INCENTIVE) / 10_000;
    bytes memory callbackData = abi.encode(amountIn, ILiquidityStrategy.PriceDirection.ABOVE_ORACLE, incentiveAmount);

    // Mock the transfer to fail
    vm.mockCall(
      address(collateralToken),
      abi.encodeWithSelector(collateralToken.transfer.selector, address(mockReserve), amount1Out),
      abi.encode(false)
    );

    // Execute hook and expect revert
    vm.prank(address(mockPool));
    vm.expectRevert("SafeERC20: ERC20 operation did not succeed");
    strat.hook(address(strat), 0, amount1Out, callbackData);

    // Clear the mock to not affect other tests
    vm.clearMockedCalls();
  }

  function test_hook_whenContractionTransferFails_shouldRevert() public {
    // Setup for contraction (BELOW_ORACLE) with failing reserve transfer
    uint256 amount0Out = 50e18; // Amount of stables to burn
    uint256 collateralIn = 100e18; // Amount of collateral to transfer from reserve
    address mockStableToken = makeAddr("MockStableToken");
    address mockCollateralToken = makeAddr("MockCollateralToken");

    // Mock pool with our mocked token addresses
    MockFPMMPool testPool = new MockFPMMPool(address(strat), mockStableToken, mockCollateralToken);
    vm.prank(deployer);
    strat.addPool(address(testPool), 1 days, DEFAULT_INCENTIVE);

    uint256 incentiveAmount = (collateralIn * DEFAULT_INCENTIVE) / 10_000;
    bytes memory callbackData = abi.encode(
      collateralIn,
      ILiquidityStrategy.PriceDirection.BELOW_ORACLE,
      incentiveAmount
    );

    // First mock the burn to succeed
    vm.mockCall(
      mockStableToken,
      abi.encodeWithSelector(IERC20MintableBurnable.burn.selector, amount0Out),
      abi.encode(true)
    );

    // Then mock the reserve transfer to fail
    vm.mockCall(
      address(mockReserve),
      abi.encodeWithSelector(
        mockReserve.transferExchangeCollateralAsset.selector,
        mockCollateralToken,
        payable(address(testPool)),
        collateralIn - incentiveAmount
      ),
      abi.encode(false)
    );

    // Execute hook and expect revert
    vm.prank(address(testPool));
    vm.expectRevert("RLS: COLLATERAL_TRANSFER_FAILED");
    strat.hook(address(strat), amount0Out, 0, callbackData);

    // Clear the mock to not affect other tests
    vm.clearMockedCalls();
  }
}
