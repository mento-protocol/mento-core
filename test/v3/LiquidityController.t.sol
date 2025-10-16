// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { ERC20DecimalsMock } from "openzeppelin-contracts-next/contracts/mocks/ERC20DecimalsMock.sol";

import { Test } from "mento-std/Test.sol";
import { MockLiquidityPolicy } from "test/utils/mocks/MockLiquidityPolicy.sol";
import { MockFPMM } from "test/utils/mocks/MockFPMM.sol";
import { MockLiquidityStrategy } from "test/utils/mocks/MockLiquidityStrategy.sol";

import { LiquidityController } from "contracts/v3/LiquidityController.sol";
import { ILiquidityPolicy } from "contracts/v3/Interfaces/ILiquidityPolicy.sol";
import { ILiquidityStrategy } from "contracts/v3/Interfaces/ILiquidityStrategy.sol";
import { LiquidityTypes as LQ } from "contracts/v3/libraries/LiquidityTypes.sol";

contract LiquidityControllerTest is Test {
  LiquidityController public liquidityController;
  MockFPMM public mockPool;
  MockLiquidityPolicy public mockPolicy;
  MockLiquidityStrategy public mockStrategy;

  address public debtToken;
  address public collateralToken;

  address public OWNER = makeAddr("OWNER");
  address public ALICE = makeAddr("ALICE");
  address public BOB = makeAddr("BOB");
  address public NOT_OWNER = makeAddr("NOT_OWNER");
  bool public isToken0Debt;

  event PoolAdded(address indexed pool, address debt, address collateral, uint64 cooldown, uint32 incentiveBps);
  event PoolRemoved(address indexed pool);
  event RebalanceCooldownSet(address indexed pool, uint64 cooldown);
  event RebalanceIncentiveSet(address indexed pool, uint32 incentiveBps);
  event PipelineSet(address indexed pool, address[] policies);
  event StrategySet(LQ.LiquiditySource indexed source, address strategy);
  event RebalanceExecuted(address indexed pool, uint256 diffBeforeBps, uint256 diffAfterBps);

  function setUp() public {
    vm.label(OWNER, "OWNER");
    vm.label(ALICE, "ALICE");
    vm.label(BOB, "BOB");
    vm.label(NOT_OWNER, "NOT_OWNER");

    vm.startPrank(OWNER);

    liquidityController = new LiquidityController();
    liquidityController.initialize(OWNER);

    debtToken = address(new ERC20DecimalsMock("DebtToken", "DEBT", 18));
    collateralToken = address(new ERC20DecimalsMock("CollateralToken", "COLL", 18));
    // Calculate token ordering once
    isToken0Debt = debtToken < collateralToken;

    mockPool = new MockFPMM(debtToken, collateralToken, false);
    mockPolicy = new MockLiquidityPolicy();
    mockStrategy = new MockLiquidityStrategy();

    // LiquidityController.rebalance() uses the block timestamp & configured cooldown time
    // to determine if the rebalance can be executed. If the block timestamp is 0, the
    // cooldown check will always fail. So to ensure the cooldown check uses a
    // realistic scenario (block.timestamp != 0 && block.timestamp > cooldown time) we set the block timestamp
    // as part of the setup
    vm.warp(1755811765);

    vm.stopPrank();
  }

  /* ============================================================ */
  /* ==================== Initialization Tests ================== */
  /* ============================================================ */

  function test_initialize_whenCalledWithOwner_shouldSetOwnerCorrectly() public {
    LiquidityController newController = new LiquidityController();
    newController.initialize(ALICE);
    assertEq(newController.owner(), ALICE);
  }

  function test_initialize_whenCalledTwice_shouldRevert() public {
    LiquidityController newController = new LiquidityController();
    newController.initialize(ALICE);
    vm.expectRevert("Initializable: contract is already initialized");
    newController.initialize(BOB);
  }

  /* ============================================================ */
  /* ================ Admin Functions - Pools =================== */
  /* ============================================================ */

  function test_addPool_whenCalledByOwner_shouldSucceed() public {
    vm.startPrank(OWNER);

    vm.expectEmit(true, false, false, true);
    emit PoolAdded(address(mockPool), debtToken, collateralToken, 3600, 50);

    liquidityController.addPool(address(mockPool), debtToken, collateralToken, 3600, 50);

    assertTrue(liquidityController.isPoolRegistered(address(mockPool)));

    (
      address storedDebt,
      address storedCollateral,
      ,
      uint64 storedCooldown,
      uint32 storedIncentive
    ) = liquidityController.poolConfigs(address(mockPool));

    assertEq(storedDebt, debtToken);
    assertEq(storedCollateral, collateralToken);
    assertEq(storedCooldown, 3600);
    assertEq(storedIncentive, 50);

    vm.stopPrank();
  }

  function test_addPool_whenCalledByNonOwner_shouldRevert() public {
    vm.prank(NOT_OWNER);
    vm.expectRevert("Ownable: caller is not the owner");
    liquidityController.addPool(address(mockPool), debtToken, collateralToken, 3600, 50);
  }

  function test_addPool_whenPoolAddressIsZero_shouldRevert() public {
    vm.prank(OWNER);
    vm.expectRevert("LC: POOL_MUST_BE_SET");
    liquidityController.addPool(address(0), debtToken, collateralToken, 3600, 50);
  }

  function test_addPool_whenTokenAddressesAreZero_shouldRevert() public {
    vm.prank(OWNER);
    vm.expectRevert("LC: TOKENS_MUST_BE_SET");
    liquidityController.addPool(address(mockPool), address(0), collateralToken, 3600, 50);

    vm.prank(OWNER);
    vm.expectRevert("LC: TOKENS_MUST_BE_SET");
    liquidityController.addPool(address(mockPool), debtToken, address(0), 3600, 50);
  }

  function test_addPool_whenTokensAreIdentical_shouldRevert() public {
    vm.prank(OWNER);
    vm.expectRevert("LC: TOKENS_MUST_BE_DIFFERENT");
    liquidityController.addPool(address(mockPool), debtToken, debtToken, 3600, 50);
  }

  function test_addPool_whenTokenOrderMismatchesFPMM_shouldRevert() public {
    MockFPMM wrongOrderPool = new MockFPMM(debtToken, collateralToken, true);
    // When we pass (debtToken, collateralToken) to addPool,
    // LC expects: token0 = collateralToken, token1 = debtToken (since collateral < debt in address)
    // But the pool has: token0 = debtToken, token1 = collateralToken
    vm.prank(OWNER);
    vm.expectRevert("LC: FPMM_TOKEN_ORDER_MISMATCH");
    liquidityController.addPool(address(wrongOrderPool), debtToken, collateralToken, 3600, 50);
  }

  function test_addPool_whenIncentiveExceedsLimit_shouldRevert() public {
    vm.startPrank(OWNER);
    vm.expectRevert("LC: BAD_INCENTIVE");
    liquidityController.addPool(
      address(mockPool),
      debtToken,
      collateralToken,
      3600,
      10001 // > 100%
    );

    vm.expectRevert("LC: BAD_INCENTIVE");
    liquidityController.addPool(
      address(mockPool),
      debtToken,
      collateralToken,
      3600,
      101 // > pool's 100 (1%)
    );
    vm.stopPrank();
  }

  function test_addPool_whenPoolAlreadyRegistered_shouldRevert() public {
    vm.startPrank(OWNER);
    liquidityController.addPool(address(mockPool), debtToken, collateralToken, 3600, 50);

    vm.expectRevert("LC: POOL_ALREADY_EXISTS");
    liquidityController.addPool(address(mockPool), debtToken, collateralToken, 3600, 50);
    vm.stopPrank();
  }

  function test_removePool_whenCalledByOwner_shouldSucceed() public {
    vm.startPrank(OWNER);
    liquidityController.addPool(address(mockPool), debtToken, collateralToken, 3600, 50);

    vm.expectEmit(true, false, false, false);
    emit PoolRemoved(address(mockPool));

    liquidityController.removePool(address(mockPool));

    assertFalse(liquidityController.isPoolRegistered(address(mockPool)));
    vm.stopPrank();
  }

  function test_removePool_whenCalledByNonOwner_shouldRevert() public {
    vm.prank(OWNER);
    liquidityController.addPool(address(mockPool), debtToken, collateralToken, 3600, 50);

    vm.prank(NOT_OWNER);
    vm.expectRevert("Ownable: caller is not the owner");
    liquidityController.removePool(address(mockPool));
  }

  function test_removePool_whenPoolNotRegistered_shouldRevert() public {
    vm.prank(OWNER);
    vm.expectRevert("LC: POOL_NOT_FOUND");
    liquidityController.removePool(address(mockPool));
  }

  function test_setRebalanceCooldown_whenCalledByOwner_shouldSucceed() public {
    vm.startPrank(OWNER);
    liquidityController.addPool(address(mockPool), debtToken, collateralToken, 3600, 50);

    vm.expectEmit(true, false, false, true);
    emit RebalanceCooldownSet(address(mockPool), 7200);

    liquidityController.setRebalanceCooldown(address(mockPool), 7200);

    (, , , uint64 cooldown, ) = liquidityController.poolConfigs(address(mockPool));
    assertEq(cooldown, 7200);
    vm.stopPrank();
  }

  function test_setRebalanceCooldown_whenCalledByNonOwner_shouldRevert() public {
    vm.prank(OWNER);
    liquidityController.addPool(address(mockPool), debtToken, collateralToken, 3600, 50);

    vm.prank(NOT_OWNER);
    vm.expectRevert("Ownable: caller is not the owner");
    liquidityController.setRebalanceCooldown(address(mockPool), 7200);
  }

  function test_setRebalanceCooldown_whenPoolNotRegistered_shouldRevert() public {
    vm.prank(OWNER);
    vm.expectRevert("LC: POOL_NOT_FOUND");
    liquidityController.setRebalanceCooldown(address(mockPool), 7200);
  }

  function test_setRebalanceIncentive_whenCalledByOwner_shouldSucceed() public {
    vm.startPrank(OWNER);
    liquidityController.addPool(address(mockPool), debtToken, collateralToken, 3600, 50);

    vm.expectEmit(true, false, false, true);
    emit RebalanceIncentiveSet(address(mockPool), 75);

    liquidityController.setRebalanceIncentive(address(mockPool), 75);

    (, , , , uint32 incentive) = liquidityController.poolConfigs(address(mockPool));
    assertEq(incentive, 75);
    vm.stopPrank();
  }

  function test_setRebalanceIncentive_whenCalledByNonOwner_shouldRevert() public {
    vm.prank(OWNER);
    liquidityController.addPool(address(mockPool), debtToken, collateralToken, 3600, 50);

    vm.prank(NOT_OWNER);
    vm.expectRevert("Ownable: caller is not the owner");
    liquidityController.setRebalanceIncentive(address(mockPool), 75);
  }

  function test_setRebalanceIncentive_whenPoolNotRegistered_shouldRevert() public {
    vm.prank(OWNER);
    vm.expectRevert("LC: POOL_NOT_FOUND");
    liquidityController.setRebalanceIncentive(address(mockPool), 75);
  }

  function test_setRebalanceIncentive_whenIncentiveExceedsLimit_shouldRevert() public {
    vm.startPrank(OWNER);
    liquidityController.addPool(address(mockPool), debtToken, collateralToken, 3600, 50);

    vm.expectRevert("LC: BAD_INCENTIVE");
    liquidityController.setRebalanceIncentive(address(mockPool), 101); // > pool cap

    vm.expectRevert("LC: BAD_INCENTIVE");
    liquidityController.setRebalanceIncentive(address(mockPool), 10001); // > 100%
    vm.stopPrank();
  }

  /* ============================================================ */
  /* ======== Admin Functions - Pipelines & Strategies ========== */
  /* ============================================================ */

  function test_setPoolPipeline_whenCalledByOwner_shouldSucceed() public {
    vm.startPrank(OWNER);
    liquidityController.addPool(address(mockPool), debtToken, collateralToken, 3600, 50);

    ILiquidityPolicy[] memory policies = new ILiquidityPolicy[](2);
    policies[0] = ILiquidityPolicy(address(mockPolicy));
    policies[1] = ILiquidityPolicy(address(new MockLiquidityPolicy()));

    address[] memory expectedAddresses = new address[](2);
    expectedAddresses[0] = address(policies[0]);
    expectedAddresses[1] = address(policies[1]);

    vm.expectEmit(true, false, false, true);
    emit PipelineSet(address(mockPool), expectedAddresses);

    liquidityController.setPoolPipeline(address(mockPool), policies);

    assertEq(address(liquidityController.pipelines(address(mockPool), 0)), address(policies[0]));
    assertEq(address(liquidityController.pipelines(address(mockPool), 1)), address(policies[1]));
    vm.stopPrank();
  }

  function test_setPoolPipeline_whenCalledByNonOwner_shouldRevert() public {
    vm.prank(OWNER);
    liquidityController.addPool(address(mockPool), debtToken, collateralToken, 3600, 50);

    ILiquidityPolicy[] memory policies = new ILiquidityPolicy[](1);
    policies[0] = ILiquidityPolicy(address(mockPolicy));

    vm.prank(NOT_OWNER);
    vm.expectRevert("Ownable: caller is not the owner");
    liquidityController.setPoolPipeline(address(mockPool), policies);
  }

  function test_setPoolPipeline_whenPoolNotRegistered_shouldRevert() public {
    ILiquidityPolicy[] memory policies = new ILiquidityPolicy[](1);
    policies[0] = ILiquidityPolicy(address(mockPolicy));

    vm.prank(OWNER);
    vm.expectRevert("LC: POOL_NOT_FOUND");
    liquidityController.setPoolPipeline(address(mockPool), policies);
  }

  function test_setPoolPipeline_whenPipelineExists_shouldReplaceExisting() public {
    vm.startPrank(OWNER);
    liquidityController.addPool(address(mockPool), debtToken, collateralToken, 3600, 50);

    ILiquidityPolicy[] memory policies1 = new ILiquidityPolicy[](2);
    policies1[0] = ILiquidityPolicy(address(mockPolicy));
    policies1[1] = ILiquidityPolicy(address(new MockLiquidityPolicy()));

    liquidityController.setPoolPipeline(address(mockPool), policies1);

    ILiquidityPolicy[] memory policies2 = new ILiquidityPolicy[](1);
    policies2[0] = ILiquidityPolicy(address(new MockLiquidityPolicy()));

    liquidityController.setPoolPipeline(address(mockPool), policies2);

    assertEq(address(liquidityController.pipelines(address(mockPool), 0)), address(policies2[0]));

    vm.expectRevert();
    liquidityController.pipelines(address(mockPool), 1);
    vm.stopPrank();
  }

  function test_setLiquiditySourceStrategy_whenCalledByOwner_shouldSucceed() public {
    vm.startPrank(OWNER);

    vm.expectEmit(true, false, false, true);
    emit StrategySet(LQ.LiquiditySource.Reserve, address(mockStrategy));

    liquidityController.setLiquiditySourceStrategy(LQ.LiquiditySource.Reserve, mockStrategy);

    assertEq(address(liquidityController.strategies(LQ.LiquiditySource.Reserve)), address(mockStrategy));
    vm.stopPrank();
  }

  function test_setLiquiditySourceStrategy_whenCalledByNonOwner_shouldRevert() public {
    vm.prank(NOT_OWNER);
    vm.expectRevert("Ownable: caller is not the owner");
    liquidityController.setLiquiditySourceStrategy(LQ.LiquiditySource.Reserve, mockStrategy);
  }

  function test_setLiquiditySourceStrategy_whenStrategyAddressIsZero_shouldRevert() public {
    vm.prank(OWNER);
    vm.expectRevert("LC: STRATEGY_ADDRESS_IS_ZERO");
    liquidityController.setLiquiditySourceStrategy(LQ.LiquiditySource.Reserve, ILiquidityStrategy(address(0)));
  }

  /* ============================================================ */
  /* ==================== Rebalance Tests ======================= */
  /* ============================================================ */

  function test_rebalance_whenPoolNotRegistered_shouldRevert() public {
    vm.expectRevert("LC: POOL_NOT_FOUND");
    liquidityController.rebalance(address(mockPool));
  }

  function test_rebalance_whenCooldownNotElapsed_shouldRevert() public {
    vm.startPrank(OWNER);
    liquidityController.addPool(address(mockPool), debtToken, collateralToken, 3600, 50);

    ILiquidityPolicy[] memory policies = new ILiquidityPolicy[](1);
    policies[0] = ILiquidityPolicy(address(mockPolicy));
    liquidityController.setPoolPipeline(address(mockPool), policies);

    liquidityController.setLiquiditySourceStrategy(LQ.LiquiditySource.Reserve, mockStrategy);
    vm.stopPrank();

    mockPool.setDiffBps(600, true);
    mockPolicy.setShouldAct(true);

    (uint256 amount0Out, uint256 amount1Out) = LQ.toTokenOrder(0, 100e18, isToken0Debt);

    mockPolicy.setAction(
      LQ.Action({
        pool: address(mockPool),
        dir: LQ.Direction.Expand,
        liquiditySource: LQ.LiquiditySource.Reserve,
        amount0Out: amount0Out,
        amount1Out: amount1Out,
        inputAmount: 100e18,
        incentiveBps: 50,
        data: bytes("")
      })
    );

    vm.prank(ALICE);
    liquidityController.rebalance(address(mockPool));

    vm.prank(BOB);
    vm.expectRevert("LC: COOLDOWN_ACTIVE");
    liquidityController.rebalance(address(mockPool));
  }

  function test_rebalance_whenPriceWithinThreshold_shouldRevert() public {
    vm.startPrank(OWNER);
    liquidityController.addPool(address(mockPool), debtToken, collateralToken, 3600, 50);
    vm.stopPrank();

    mockPool.setDiffBps(100, true); // Below threshold

    vm.expectRevert("LC: POOL_PRICE_IN_RANGE");
    liquidityController.rebalance(address(mockPool));
  }

  function test_rebalance_whenNoPoliciesConfigured_shouldRevert() public {
    vm.prank(OWNER);
    liquidityController.addPool(address(mockPool), debtToken, collateralToken, 3600, 50);

    mockPool.setDiffBps(600, true); // Above threshold

    vm.expectRevert("LC: NO_POLICIES_IN_PIPELINE");
    liquidityController.rebalance(address(mockPool));
  }

  function test_rebalance_whenStrategyNotConfigured_shouldRevert() public {
    vm.startPrank(OWNER);
    liquidityController.addPool(address(mockPool), debtToken, collateralToken, 3600, 50);

    ILiquidityPolicy[] memory policies = new ILiquidityPolicy[](1);
    policies[0] = ILiquidityPolicy(address(mockPolicy));
    liquidityController.setPoolPipeline(address(mockPool), policies);
    vm.stopPrank();

    mockPool.setDiffBps(600, true);
    mockPolicy.setShouldAct(true);

    (uint256 amount0Out, uint256 amount1Out) = LQ.toTokenOrder(0, 100e18, isToken0Debt);

    mockPolicy.setAction(
      LQ.Action({
        pool: address(mockPool),
        dir: LQ.Direction.Expand,
        liquiditySource: LQ.LiquiditySource.Reserve,
        amount0Out: amount0Out,
        amount1Out: amount1Out,
        inputAmount: 100e18,
        incentiveBps: 50,
        data: bytes("")
      })
    );

    vm.expectRevert("LC: NO_STRATEGY_FOR_LIQUIDITY_SOURCE");
    liquidityController.rebalance(address(mockPool));
  }

  function test_rebalance_whenStrategyReturnsFalse_shouldRevert() public {
    vm.startPrank(OWNER);
    liquidityController.addPool(address(mockPool), debtToken, collateralToken, 3600, 50);

    ILiquidityPolicy[] memory policies = new ILiquidityPolicy[](1);
    policies[0] = ILiquidityPolicy(address(mockPolicy));
    liquidityController.setPoolPipeline(address(mockPool), policies);

    liquidityController.setLiquiditySourceStrategy(LQ.LiquiditySource.Reserve, mockStrategy);
    vm.stopPrank();

    mockPool.setDiffBps(600, true);
    mockPolicy.setShouldAct(true);
    mockPolicy.setAction(
      LQ.Action({
        pool: address(mockPool),
        dir: LQ.Direction.Expand,
        liquiditySource: LQ.LiquiditySource.Reserve,
        amount0Out: isToken0Debt ? 0 : 100e18,
        amount1Out: isToken0Debt ? 100e18 : 0,
        inputAmount: 100e18,
        incentiveBps: 50,
        data: bytes("")
      })
    );
    mockStrategy.setExecutionResult(false);

    vm.expectRevert("LC: STRATEGY_EXECUTION_FAILED");
    liquidityController.rebalance(address(mockPool));
  }

  function test_rebalance_whenConditionsMet_shouldExecuteSuccessfully() public {
    vm.startPrank(OWNER);
    liquidityController.addPool(address(mockPool), debtToken, collateralToken, 3600, 50);

    ILiquidityPolicy[] memory policies = new ILiquidityPolicy[](1);
    policies[0] = ILiquidityPolicy(address(mockPolicy));
    liquidityController.setPoolPipeline(address(mockPool), policies);

    liquidityController.setLiquiditySourceStrategy(LQ.LiquiditySource.Reserve, mockStrategy);
    vm.stopPrank();

    mockPool.setDiffBps(600, true);
    mockPolicy.setShouldAct(true);
    mockPolicy.setAction(
      LQ.Action({
        pool: address(mockPool),
        dir: LQ.Direction.Expand,
        liquiditySource: LQ.LiquiditySource.Reserve,
        amount0Out: isToken0Debt ? 0 : 100e18,
        amount1Out: isToken0Debt ? 100e18 : 0,
        inputAmount: 100e18,
        incentiveBps: 50,
        data: bytes("")
      })
    );

    vm.expectEmit(true, false, false, true);
    emit RebalanceExecuted(address(mockPool), 600, 600);

    vm.prank(ALICE);
    liquidityController.rebalance(address(mockPool));

    (, , uint128 lastRebalance, , ) = liquidityController.poolConfigs(address(mockPool));
    assertEq(lastRebalance, block.timestamp);
  }

  function test_rebalance_whenMultiplePoliciesConfigured_shouldExecuteInOrder() public {
    vm.startPrank(OWNER);
    liquidityController.addPool(address(mockPool), debtToken, collateralToken, 3600, 50);

    // Create a second mock policy
    MockLiquidityPolicy policy2 = new MockLiquidityPolicy();

    // Create the pipeline then set for pool
    ILiquidityPolicy[] memory policies = new ILiquidityPolicy[](2);
    policies[0] = ILiquidityPolicy(address(mockPolicy));
    policies[1] = ILiquidityPolicy(address(policy2));
    liquidityController.setPoolPipeline(address(mockPool), policies);

    liquidityController.setLiquiditySourceStrategy(LQ.LiquiditySource.Reserve, mockStrategy);
    vm.stopPrank();

    mockPool.setDiffBps(600, true);

    mockPolicy.setShouldAct(false);
    policy2.setShouldAct(true);
    policy2.setAction(
      LQ.Action({
        pool: address(mockPool),
        dir: LQ.Direction.Contract,
        liquiditySource: LQ.LiquiditySource.Reserve,
        amount0Out: isToken0Debt ? 100e18 : 0,
        amount1Out: isToken0Debt ? 0 : 100e18,
        inputAmount: 100e18,
        incentiveBps: 25,
        data: bytes("")
      })
    );

    vm.prank(ALICE);
    liquidityController.rebalance(address(mockPool));

    (, , , , , uint256 inputAmount, , ) = mockStrategy.lastAction();
    assertEq(inputAmount, 100e18);
    (, LQ.Direction dir, , , , , , ) = mockStrategy.lastAction();
    assertEq(uint256(dir), uint256(LQ.Direction.Contract));
  }

  function test_rebalance_whenPriceReturnsToRange_shouldStopEarly() public {
    vm.startPrank(OWNER);
    liquidityController.addPool(address(mockPool), debtToken, collateralToken, 3600, 50);

    // Create two policies - first one will bring price back to range,
    // second one should not execute
    MockLiquidityPolicy policy1 = new MockLiquidityPolicy();
    MockLiquidityPolicy policy2 = new MockLiquidityPolicy();

    MockLiquidityStrategy newStrat = new MockLiquidityStrategy();

    ILiquidityPolicy[] memory policies = new ILiquidityPolicy[](2);
    policies[0] = ILiquidityPolicy(address(policy1));
    policies[1] = ILiquidityPolicy(address(policy2));
    liquidityController.setPoolPipeline(address(mockPool), policies);

    liquidityController.setLiquiditySourceStrategy(LQ.LiquiditySource.Reserve, newStrat);
    vm.stopPrank();

    // Set initial price out of range (600 bps difference, above threshold of 500)
    mockPool.setDiffBps(600, true);

    // Configure policy1 to act and bring price closer to range
    policy1.setShouldAct(true);
    policy1.setAction(
      LQ.Action({
        pool: address(mockPool),
        dir: LQ.Direction.Expand,
        liquiditySource: LQ.LiquiditySource.Reserve,
        amount0Out: isToken0Debt ? 0 : 100e18,
        amount1Out: isToken0Debt ? 100e18 : 0,
        inputAmount: 100e18,
        incentiveBps: 50,
        data: bytes("")
      })
    );

    // Configure policy2 to also act (but it shouldn't execute because price will be in range)
    policy2.setShouldAct(true);
    policy2.setAction(
      LQ.Action({
        pool: address(mockPool),
        dir: LQ.Direction.Expand,
        liquiditySource: LQ.LiquiditySource.Reserve,
        amount0Out: isToken0Debt ? 0 : 50e18,
        amount1Out: isToken0Debt ? 50e18 : 0,
        inputAmount: 50e18,
        incentiveBps: 50,
        data: bytes("")
      })
    );

    // Set up strategy to simulate price improvement after first policy execution
    // After first execution, price should be within range (e.g., 400 bps, below 500 threshold)
    newStrat.setExecutionCallback(abi.encodeWithSignature("setDiffBps(uint256,bool)", 400, true));

    // Execute rebalance
    vm.expectEmit(true, false, false, true);
    emit RebalanceExecuted(address(mockPool), 600, 400);

    vm.prank(ALICE);
    liquidityController.rebalance(address(mockPool));

    // Verify that only one strategy execution occurred (first policy only)
    assertEq(newStrat.executionCount(), 1, "Only one policy should have been executed");

    // Verify the input amount from the first (and only) execution
    assertEq(newStrat.lastInputAmount(), 100e18, "Should have executed policy1's action");

    // Verify last rebalance timestamp was updated
    (, , uint128 lastRebalance, , ) = liquidityController.poolConfigs(address(mockPool));
    assertEq(lastRebalance, block.timestamp, "Last rebalance should be updated");

    // Verify the final price is in range (400 bps < 500 bps threshold)
    (, , , , uint256 finalDiff, ) = mockPool.getPrices();
    assertEq(finalDiff, 400, "Final price difference should be 400 bps");
    assertLt(finalDiff, mockPool.rebalanceThresholdAbove(), "Price should be within threshold");
  }

  function test_rebalance_whenReentrantCall_shouldRevert() public {
    // This test simulates a reentrant call scenario where the strategy tries to call rebalance again
    // during execution to bypass cooldowns and extract multiple incentive payments before state updates complete
    // The chances of this happening are pretty slim and would require:
    // - Malicious Strategy Registration: Attacker needs their malicious strategy registered on both the pool
    //                                    and the controller side (requires admin/governance compromise)
    // - Policy Configuration: Need a policy that would trigger the malicious strategy

    vm.startPrank(OWNER);
    liquidityController.addPool(
      address(mockPool),
      debtToken,
      collateralToken,
      0, // No cooldown
      50
    );

    ReentrantStrategy reentrantStrategy = new ReentrantStrategy(liquidityController, address(mockPool));

    ILiquidityPolicy[] memory policies = new ILiquidityPolicy[](1);
    policies[0] = ILiquidityPolicy(address(mockPolicy));
    liquidityController.setPoolPipeline(address(mockPool), policies);

    liquidityController.setLiquiditySourceStrategy(
      LQ.LiquiditySource.Reserve,
      ILiquidityStrategy(address(reentrantStrategy))
    );
    vm.stopPrank();

    mockPool.setDiffBps(600, true);
    mockPolicy.setShouldAct(true);
    mockPolicy.setAction(
      LQ.Action({
        pool: address(mockPool),
        dir: LQ.Direction.Expand,
        liquiditySource: LQ.LiquiditySource.Reserve,
        amount0Out: isToken0Debt ? 0 : 100e18,
        amount1Out: isToken0Debt ? 100e18 : 0,
        inputAmount: 100e18,
        incentiveBps: 50,
        data: bytes("")
      })
    );

    vm.expectRevert("ReentrancyGuard: reentrant call");
    liquidityController.rebalance(address(mockPool));
  }

  /* ============================================================ */
  /* ==================== View Functions Tests ================== */
  /* ============================================================ */

  function test_isPoolRegistered_whenPoolAddedAndRemoved_shouldReturnCorrectStatus() public {
    assertFalse(liquidityController.isPoolRegistered(address(mockPool)));

    vm.prank(OWNER);
    liquidityController.addPool(address(mockPool), debtToken, collateralToken, 3600, 50);

    assertTrue(liquidityController.isPoolRegistered(address(mockPool)));
  }

  function test_getPools_whenMultiplePoolsRegistered_shouldReturnAll() public {
    address[] memory pools = liquidityController.getPools();
    assertEq(pools.length, 0);

    vm.startPrank(OWNER);
    MockFPMM pool2 = new MockFPMM(debtToken, collateralToken, false);

    liquidityController.addPool(address(mockPool), debtToken, collateralToken, 3600, 50);

    liquidityController.addPool(address(pool2), debtToken, collateralToken, 3600, 50);
    vm.stopPrank();

    pools = liquidityController.getPools();
    assertEq(pools.length, 2);
    assertTrue(pools[0] == address(mockPool) || pools[1] == address(mockPool));
    assertTrue(pools[0] == address(pool2) || pools[1] == address(pool2));
  }

  /* ============================================================ */
  /* ==================== Edge Cases Tests ====================== */
  /* ============================================================ */

  function test_addPool_whenMaxValuesProvided_shouldStoreCorrectly() public {
    vm.prank(OWNER);
    liquidityController.addPool(
      address(mockPool),
      debtToken,
      collateralToken,
      type(uint64).max,
      100 // Max allowed by pool
    );

    (, , , uint64 cooldown, uint32 incentive) = liquidityController.poolConfigs(address(mockPool));
    assertEq(cooldown, type(uint64).max);
    assertEq(incentive, 100);
  }

  function test_rebalance_whenZeroIncentive_shouldExecuteWithoutIncentive() public {
    vm.startPrank(OWNER);
    liquidityController.addPool(
      address(mockPool),
      debtToken,
      collateralToken,
      3600,
      0 // Zero incentive
    );

    ILiquidityPolicy[] memory policies = new ILiquidityPolicy[](1);
    policies[0] = ILiquidityPolicy(address(mockPolicy));
    liquidityController.setPoolPipeline(address(mockPool), policies);

    liquidityController.setLiquiditySourceStrategy(LQ.LiquiditySource.Reserve, mockStrategy);
    vm.stopPrank();

    mockPool.setDiffBps(600, true);
    mockPolicy.setShouldAct(true);
    mockPolicy.setAction(
      LQ.Action({
        pool: address(mockPool),
        dir: LQ.Direction.Expand,
        liquiditySource: LQ.LiquiditySource.Reserve,
        amount0Out: isToken0Debt ? 0 : 100e18,
        amount1Out: isToken0Debt ? 100e18 : 0,
        inputAmount: 100e18,
        incentiveBps: 0,
        data: bytes("")
      })
    );

    vm.prank(ALICE);
    liquidityController.rebalance(address(mockPool));

    // Check the incentive amount tracked by the mock strategy
    uint256 incentiveAmount = mockStrategy.lastIncentiveAmount();
    assertEq(incentiveAmount, 0);
  }

  function test_addPool_whenDifferentTokenOrdering_shouldStoreCorrectly() public {
    address higherToken = address(uint160(collateralToken) + 1);
    address lowerToken = address(uint160(debtToken) - 1);

    MockFPMM newPool = new MockFPMM(higherToken, lowerToken, false);

    vm.prank(OWNER);
    liquidityController.addPool(address(newPool), higherToken, lowerToken, 3600, 50);

    (address storedDebt, address storedCollateral, , , ) = liquidityController.poolConfigs(address(newPool));
    assertEq(storedDebt, higherToken);
    assertEq(storedCollateral, lowerToken);
  }
}

contract ReentrantStrategy is ILiquidityStrategy {
  LiquidityController public controller;
  address public pool;

  constructor(LiquidityController _controller, address _pool) {
    controller = _controller;
    pool = _pool;
  }

  function execute(LQ.Action calldata) external returns (bool) {
    controller.rebalance(pool);
    return true;
  }

  function hook(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
    // do nothing
  }
}
