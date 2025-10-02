// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { CDPPolicy } from "contracts/v3/CDPPolicy.sol";
import { LiquidityTypes as LQ } from "contracts/v3/libraries/LiquidityTypes.sol";
import { ICollateralRegistry } from "bold/Interfaces/ICollateralRegistry.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";

import { console } from "forge-std/console.sol";
import { uints, addresses } from "mento-std/Array.sol";
import { Test } from "forge-std/Test.sol";

contract CDPPolicyTest is Test {
  error CDPPolicy_CONSTRUCTOR_ARRAY_LENGTH_MISMATCH();

  CDPPolicy public policy;

  MockERC20 public debtToken6;
  MockERC20 public collateralToken6;

  MockERC20 public debtToken18;
  MockERC20 public collateralToken18;

  address collateralRegistry = makeAddr("collateralRegistry");
  address stabilityPool = makeAddr("stabilityPool");
  address fpmm = makeAddr("fpmm");

  function setUp() public {
    policy = new CDPPolicy(new address[](0), new address[](0), new address[](0), new uint256[](0));
    debtToken6 = new MockERC20("DebtToken6", "DT6", 6);
    collateralToken6 = new MockERC20("CollateralToken6", "CT6", 6);
    debtToken18 = new MockERC20("DebtToken18", "DT18", 18);
    collateralToken18 = new MockERC20("CollateralToken18", "CT18", 18);
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

  function test_constructor_whenArrayLengthsMismatch_shouldRevert() public {
    vm.expectRevert(abi.encodeWithSelector(CDPPolicy_CONSTRUCTOR_ARRAY_LENGTH_MISMATCH.selector));
    policy = new CDPPolicy(new address[](2), new address[](0), new address[](0), new uint256[](0));
  }

  function test_constructor_shouldSetCorrectState() public {
    address[] memory debtTokens = addresses(address(debtToken6), address(debtToken18));
    address[] memory stabilityPools = addresses(stabilityPool, stabilityPool);
    address[] memory collateralRegistries = addresses(collateralRegistry, collateralRegistry);
    uint256[] memory redemptionBetas = uints(1, 2);
    policy = new CDPPolicy(debtTokens, stabilityPools, collateralRegistries, redemptionBetas);
    assertEq(policy.deptTokenStabilityPool(address(debtToken6)), stabilityPool);
    assertEq(policy.deptTokenCollateralRegistry(address(debtToken6)), collateralRegistry);
    assertEq(policy.deptTokenStabilityPool(address(debtToken18)), stabilityPool);
    assertEq(policy.deptTokenCollateralRegistry(address(debtToken18)), collateralRegistry);
    assertEq(policy.deptTokenRedemptionBeta(address(debtToken6)), 1);
    assertEq(policy.deptTokenRedemptionBeta(address(debtToken18)), 2);
  }

  function test_setDeptTokenStabilityPool_whenNotOwneri_shouldRevert() public {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("notOwner"));
    policy.setDeptTokenStabilityPool(address(debtToken6), stabilityPool);
  }

  function test_setDeptTokenStabilityPool_whenCalledByOwner_shouldSucceed() public {
    policy.setDeptTokenStabilityPool(address(debtToken6), makeAddr("newStabilityPool"));
    assertEq(policy.deptTokenStabilityPool(address(debtToken6)), makeAddr("newStabilityPool"));
  }

  function test_setDeptTokenCollateralRegistry_whenNotOwner_shouldRevert() public {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("notOwner"));
    policy.setDeptTokenCollateralRegistry(address(debtToken6), collateralRegistry);
  }

  function test_setDeptTokenCollateralRegistry_whenCalledByOwner_shouldSucceed() public {
    policy.setDeptTokenCollateralRegistry(address(debtToken6), makeAddr("newCollateralRegistry"));
    assertEq(policy.deptTokenCollateralRegistry(address(debtToken6)), makeAddr("newCollateralRegistry"));
  }

  function test_setDeptTokenRedemptionBeta_whenNotOwner_shouldRevert() public {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("notOwner"));
    policy.setDeptTokenRedemptionBeta(address(debtToken6), 1);
  }

  function test_setDeptTokenRedemptionBeta_whenCalledByOwner_shouldSucceed() public {
    policy.setDeptTokenRedemptionBeta(address(debtToken6), 1);
    assertEq(policy.deptTokenRedemptionBeta(address(debtToken6)), 1);
  }

  function test_whenPoolPriceAbove() public {
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

    LQ.Context memory ctx;
    ctx.pool = fpmm;

    uint256 reserve0 = 1_000_000 * 1e18; // usdfx
    uint256 reserve1 = 1_500_000 * 1e6; // usdc
    ctx.reserves = LQ.Reserves({
      reserveNum: reserve1 * 1e12, // reserve token 1 (1M) USDC
      reserveDen: reserve0 // reserve token 0 (1.5M) usdfx
    });

    ctx.prices = LQ.Prices({
      oracleNum: 999884980000000000,
      oracleDen: 1e18,
      poolPriceAbove: true,
      diffBps: 1_000 // 10%
    });

    ctx.token0 = address(debtToken18);
    ctx.token1 = address(collateralToken6);
    ctx.incentiveBps = 50; // 0.5%
    ctx.token0Dec = 1e18;
    ctx.token1Dec = 1e6;
    ctx.isToken0Debt = true;

    policy.setDeptTokenStabilityPool(address(debtToken18), stabilityPool);
    policy.setDeptTokenCollateralRegistry(address(debtToken18), collateralRegistry);

    setStabilityPoolBalance(address(debtToken18), 100_000 * 1e18);

    (, LQ.Action memory action) = policy.determineAction(ctx);

    console.log("action.amount0Out", action.amount0Out);
    console.log("action.amount1Out", action.amount1Out);
    console.log("action.inputAmount", action.inputAmount);

    reserve0 -= action.amount0Out;
    reserve1 -= action.amount1Out;
    reserve0 += action.inputAmount;

    console.log("reserve0", reserve0);
    console.log("reserve1", reserve1 * 1e12);
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

    policy.setDeptTokenStabilityPool(address(debtToken18), stabilityPool);
    policy.setDeptTokenCollateralRegistry(address(debtToken18), collateralRegistry);
    policy.setDeptTokenRedemptionBeta(address(debtToken18), 1);
    setTokenTotalSupply(address(debtToken18), 10_000_000 * 1e18);
    mockGetRedemptionRateWithDecay(3e15); // 0.3%

    setStabilityPoolBalance(address(collateralToken6), 100_000 * 1e6);

    (, LQ.Action memory action) = policy.determineAction(ctx);

    console.log("action.amount0Out", action.amount0Out);
    console.log("action.amount1Out", action.amount1Out);
    console.log("action.inputAmount", action.inputAmount);

    reserve0 -= action.amount0Out;
    reserve1 -= action.amount1Out;
    uint256 inputAmount = (action.inputAmount * (10_000 - action.incentiveBps)) / 10_000;
    reserve0 += inputAmount;

    // console.log("reserve0", reserve0);
    console.log("reserve1", reserve1 * 1e12);
  }
}
