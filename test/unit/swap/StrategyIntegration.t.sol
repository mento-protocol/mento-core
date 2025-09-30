// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
// solhint-disable modifier-name-mixedcase,
pragma solidity ^0.8;
import { Test } from "mento-std/Test.sol";

import { OracleAdapter } from "contracts/oracles/OracleAdapter.sol";
import { ReserveLiquidityStrategy } from "contracts/swap/ReserveLiquidityStrategy.sol";
import { IOracleAdapter } from "contracts/interfaces/IOracleAdapter.sol";
import { IBreakerBox } from "contracts/interfaces/IBreakerBox.sol";
import { IMarketHoursBreaker } from "contracts/interfaces/IMarketHoursBreaker.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";
import { MockReserve } from "test/utils/mocks/MockReserve.sol";
import { MockSortedOracles } from "test/utils/mocks/MockSortedOracles.sol";
import { FPMM } from "contracts/swap/FPMM.sol";

contract StrategyIntegrationTest is Test {
  MockERC20 public token0;
  MockERC20 public token1;
  MockReserve public reserve;
  IOracleAdapter public oracleAdapter;
  MockSortedOracles public sortedOracles;
  FPMM public pool;
  ReserveLiquidityStrategy public strategy;
  address public rateFeed;
  address public breakerBox;
  address public marketHoursBreaker;
  address public trader;

  function setUp() public {
    breakerBox = makeAddr("BreakerBox");
    marketHoursBreaker = makeAddr("MarketHoursBreaker");
    rateFeed = makeAddr("RateFeed");
    trader = makeAddr("Trader");

    token0 = new MockERC20("Token0", "T0", 18);
    token1 = new MockERC20("Token1", "T1", 6);
    reserve = new MockReserve();
    sortedOracles = new MockSortedOracles();
    sortedOracles.setMedianRate(rateFeed, 909884940000000000000000);
    sortedOracles.setTokenReportExpirySeconds(rateFeed, 0);
    sortedOracles.setMedianTimestamp(rateFeed, block.timestamp + 1 hours);
    oracleAdapter = IOracleAdapter(new OracleAdapter(false));
    oracleAdapter.initialize(address(sortedOracles), breakerBox, marketHoursBreaker);
    pool = new FPMM(false);
    strategy = new ReserveLiquidityStrategy(false);
    strategy.initialize(address(reserve));
    pool.initialize(address(token0), address(token1), address(oracleAdapter), rateFeed, true, address(this));
    pool.setLiquidityStrategy(address(strategy), true);
    strategy.addPool(address(pool), 0, 50);

    token0.mint(trader, 2e24);
    token1.mint(trader, 2e12);

    token1.mint(address(reserve), 10e12);

    vm.startPrank(trader);
    token0.transfer(address(pool), 1e24);
    token1.transfer(address(pool), 1e12);
    pool.mint(trader);
    vm.stopPrank();

    _mockOracleAdapterRequirements();
  }

  function test_rebalance_contraction() public {
    vm.startPrank(trader);
    token0.transfer(address(pool), 100_000 * 1e18);
    uint256 expectedAmountOut = pool.getAmountOut(100_000 * 1e18, address(token0));
    pool.swap(0, expectedAmountOut, trader, "");
    vm.stopPrank();

    strategy.rebalance(address(pool));
  }

  function test_rebalance_expansion() public {
    vm.startPrank(trader);
    token1.transfer(address(pool), 100_000 * 1e6);
    uint256 expectedAmountOut = pool.getAmountOut(100_000 * 1e6, address(token1));
    pool.swap(expectedAmountOut, 0, trader, "");
    vm.stopPrank();

    strategy.rebalance(address(pool));
  }

  function _mockOracleAdapterRequirements() private {
    bytes memory tradingModeCalldata = abi.encodeWithSelector(IBreakerBox.getRateFeedTradingMode.selector, rateFeed);
    vm.mockCall(breakerBox, tradingModeCalldata, abi.encode(0));

    bytes memory isMarketOpenCalldata = abi.encodeWithSelector(IMarketHoursBreaker.isMarketOpen.selector);
    vm.mockCall(address(marketHoursBreaker), isMarketOpenCalldata, abi.encode(true));
  }
}
