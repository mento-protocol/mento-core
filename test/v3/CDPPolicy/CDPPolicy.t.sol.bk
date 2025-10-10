// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { ICDPPolicy } from "contracts/v3/Interfaces/ICDPPolicy.sol";
import { CDPLiquidityStrategy } from "contracts/v3/CDPLiquidityStrategy.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/v3/libraries/LiquidityStrategyTypes.sol";
import { ICollateralRegistry } from "bold/Interfaces/ICollateralRegistry.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";
import { IStabilityPool } from "bold/Interfaces/IStabilityPool.sol";
import { console } from "forge-std/console.sol";
import { uints, addresses } from "mento-std/Array.sol";
import { Test } from "forge-std/Test.sol";

contract CDPLiquidityStrategyHarness is CDPLiquidityStrategy {
  constructor(address initialOwner) CDPLiquidityStrategy(initialOwner) {}

  function determineAction(LQ.Context memory ctx) external view returns (bool shouldAct, LQ.Action memory action) {
    return _determineAction(ctx);
  }
}

contract CDPPolicyTest is Test {
  error CDPPolicy_CONSTRUCTOR_ARRAY_LENGTH_MISMATCH();
  error CDPPolicy_INVALID_STABILITY_POOL_PERCENTAGE();

  CDPLiquidityStrategyHarness public cdpLS;

  MockERC20 public debtToken6;
  MockERC20 public collateralToken6;

  MockERC20 public debtToken18;
  MockERC20 public collateralToken18;

  address collateralRegistry = makeAddr("collateralRegistry");
  address stabilityPool = makeAddr("stabilityPool");
  address fpmm = makeAddr("fpmm");

  function setUp() public {
    cdpLS = new CDPLiquidityStrategyHarness(address(this));
    debtToken6 = new MockERC20("DebtToken6", "DT6", 6);
    collateralToken6 = new MockERC20("CollateralToken6", "CT6", 6);
    debtToken18 = new MockERC20("DebtToken18", "DT18", 18);
    collateralToken18 = new MockERC20("CollateralToken18", "CT18", 18);
  }

  function test_addPool_shouldSetCorrectState() public {
    address fpmm0 = makeAddr("fpmm0");
    address fpmm1 = makeAddr("fpmm1");

    cdpLS.addPool({
      pool: makeAddr("fpmm0"),
      debtToken: address(debtToken6),
      collateralToken: address(collateralToken6),
      cooldown: 0 seconds,
      incentiveBps: 50,
      stabilityPool: stabilityPool,
      collateralRegistry: collateralRegistry,
      redemptionBeta: 1,
      stabilityPoolPercentage: 100
    });

    cdpLS.addPool({
      pool: makeAddr("fpmm1"),
      debtToken: address(debtToken6),
      collateralToken: address(collateralToken6),
      cooldown: 0 seconds,
      incentiveBps: 50,
      stabilityPool: stabilityPool,
      collateralRegistry: collateralRegistry,
      redemptionBeta: 1,
      stabilityPoolPercentage: 100
    });

    ICDPPolicy.CDPPolicyPoolConfig memory poolConfig0 = cdpLS.getCDPPolicyPoolConfig(fpmm0);
    ICDPPolicy.CDPPolicyPoolConfig memory poolConfig1 = cdpLS.getCDPPolicyPoolConfig(fpmm1);

    assertEq(poolConfig0.stabilityPool, stabilityPool);
    assertEq(poolConfig0.stabilityPool, stabilityPool);
    assertEq(poolConfig0.redemptionBeta, 1);
    assertEq(poolConfig0.stabilityPoolPercentage, 100);
    assertEq(poolConfig1.collateralRegistry, collateralRegistry);
    assertEq(poolConfig1.collateralRegistry, collateralRegistry);
    assertEq(poolConfig1.redemptionBeta, 2);
    assertEq(poolConfig1.stabilityPoolPercentage, 200);
  }

  function test_setCDPPolicyPoolConfig_whenNotOwner_shouldRevert() public {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("notOwner"));
    cdpLS.setCDPPolicyPoolConfig(fpmm, ICDPPolicy.CDPPolicyPoolConfig(stabilityPool, collateralRegistry, 0, 0));
  }

  function test_setCDPPolicyPoolConfig_whenCalledByOwner_shouldSucceed() public {
    cdpLS.setCDPPolicyPoolConfig(fpmm, ICDPPolicy.CDPPolicyPoolConfig(stabilityPool, collateralRegistry, 3, 300));
    CDPLiquidityStrategy.CDPPolicyPoolConfig memory poolConfig = cdpLS.getCDPPolicyPoolConfig(fpmm);
    assertEq(poolConfig.stabilityPool, stabilityPool);
    assertEq(poolConfig.stabilityPool, stabilityPool);
    assertEq(poolConfig.redemptionBeta, 3);
    assertEq(poolConfig.stabilityPoolPercentage, 300);
  }

  function test_whenPoolPriceAboveAndToken0Debt() public {
    /*
      struct Context {
        address pool;
        Reserves reserves;
        Prices prices;
        address token0;
        address token1;
        uint128 incentiveBps;
        uint64 token0Dec;
        uint64 token1Dec;
        bool isToken0Debt;
    }
  */
    uint256 reserve0 = 1_000_000 * 1e18; // usdfx
    uint256 reserve1 = 1_500_000 * 1e6; // usdc

    LQ.Context memory ctx;

    ctx.token0 = address(debtToken18);
    ctx.token1 = address(collateralToken6);
    ctx.token0Dec = 1e18;
    ctx.token1Dec = 1e6;

    ctx.isToken0Debt = true;
    ctx.reserves = LQ.Reserves({
      reserveNum: reserve1 * 1e12, // reserve token 1 (1M) USDC
      reserveDen: reserve0 // reserve token 0 (1.5M) usdfx
    });

    ctx.pool = fpmm;

    ctx.prices = LQ.Prices({
      oracleNum: 999884980000000000,
      oracleDen: 1e18,
      poolPriceAbove: true,
      diffBps: 5_000 // 50%
    });
    ctx.incentiveBps = 50; // 0.5%

    cdpLS.addPool({
      pool: fpmm,
      debtToken: address(debtToken18),
      collateralToken: address(collateralToken6),
      cooldown: 0 seconds,
      incentiveBps: 50,
      stabilityPool: stabilityPool,
      collateralRegistry: collateralRegistry,
      redemptionBeta: 1,
      stabilityPoolPercentage: 9000
    });

    // enough to cover the full expansion
    setStabilityPoolBalance(address(debtToken18), 1_000_000 * 1e18);
    setStabilityPoolMinBoldAfterRebalance(1e18);

    (, LQ.Action memory action) = cdpLS.determineAction(ctx);
    console.log("action.amount0Out", action.amount0Out);
    console.log("action.amount1Out", action.amount1Out);
    console.log("action.inputAmount", action.inputAmount);
    console.log("action.dir", uint256(action.dir));

    reserve0 -= action.amount0Out;
    reserve1 -= action.amount1Out;
    reserve0 += action.inputAmount;
    console.log("reserve0", reserve0);
    console.log("reserve1", reserve1 * 1e12);

    assertEq(uint256(action.dir), uint256(LQ.Direction.Expand));
    assertEq(action.amount0Out, 0);
  }

  function test_whenPoolPriceBelow() public {
    LQ.Context memory ctx;
    ctx.pool = fpmm;

    uint256 reserve0 = 1_500_000 * 1e18; // usdfx
    console.log("reserve0", reserve0);
    uint256 reserve1 = 1_000_000 * 1e6; // usdc
    console.log("reserve1", reserve1);
    ctx.reserves = LQ.Reserves({
      reserveNum: reserve1 * 1e12, // reserve token 1 (1M) USDC
      reserveDen: reserve0 // reserve token 0 (1.5M) usdfx
    });

    ctx.prices = LQ.Prices({
      oracleNum: 999884980000000000,
      oracleDen: 1e18,
      poolPriceAbove: false,
      diffBps: 1_000 // 10%
    });

    ctx.token0 = address(debtToken18);
    ctx.token1 = address(collateralToken6);
    ctx.incentiveBps = 50; // 0.5%
    ctx.token0Dec = 1e18;
    ctx.token1Dec = 1e6;
    ctx.isToken0Debt = true;

    cdpLS.addPool({
      pool: fpmm,
      debtToken: address(debtToken18),
      collateralToken: address(collateralToken6),
      cooldown: 0 seconds,
      incentiveBps: 50,
      stabilityPool: stabilityPool,
      collateralRegistry: collateralRegistry,
      redemptionBeta: 1,
      stabilityPoolPercentage: 9000
    });

    setTokenTotalSupply(address(debtToken18), 10_000_000 * 1e18);
    mockGetRedemptionRateWithDecay(3e15); // 0.3%

    setStabilityPoolBalance(address(collateralToken6), 100_000 * 1e6);

    (, LQ.Action memory action) = cdpLS.determineAction(ctx);

    console.log("action.amount0Out", action.amount0Out);
    console.log("action.amount1Out", action.amount1Out);
    console.log("action.inputAmount", action.inputAmount);

    reserve0 -= action.amount0Out;
    reserve1 -= action.amount1Out;
    uint256 inputAmount = (action.inputAmount * (10_000 - 50)) / 10_000;
    reserve0 += inputAmount;

    // console.log("reserve0", reserve0);
    console.log("reserve1", reserve1 * 1e12);
  }

  function setStabilityPoolMinBoldAfterRebalance(uint256 minBalance) public {
    vm.mockCall(
      address(stabilityPool),
      abi.encodeWithSelector(IStabilityPool.MIN_BOLD_AFTER_REBALANCE.selector),
      abi.encode(minBalance)
    );
  }

  function setStabilityPoolBalance(address token, uint256 balance) public {
    MockERC20(token).setBalance(stabilityPool, balance);
  }

  function setTokenTotalSupply(address token, uint256 totalSupply) public {
    MockERC20(token).setTotalSupply(totalSupply);
  }

  function mockGetRedemptionRateWithDecay(uint256 redemptionRate) public {
    vm.mockCall(
      address(collateralRegistry),
      abi.encodeWithSelector(ICollateralRegistry.getRedemptionRateWithDecay.selector),
      abi.encode(redemptionRate)
    );
  }
}
