// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase, one-contract-per-file
// solhint-disable immutable-vars-naming
pragma solidity ^0.8.24;

import { Test } from "mento-std/Test.sol";

import { RouterWithReports } from "contracts/swap/router/RouterWithReports.sol";
import { IRouter } from "contracts/swap/router/interfaces/IRouter.sol";
import { IERC20 } from "contracts/swap/router/interfaces/IERC20.sol";
import { IDataStreamsRelayer } from "contracts/interfaces/IDataStreamsRelayer.sol";
import { IDataStreamsRelayerFactory } from "contracts/interfaces/IDataStreamsRelayerFactory.sol";
import { MockVerifierProxy } from "test/utils/mocks/MockVerifierProxy.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";

interface ISortedOracles {
  function initialize(uint256) external;

  function addOracle(address, address) external;

  function setTokenReportExpiry(address, uint256) external;

  function medianRate(address) external view returns (uint256, uint256);
}

/// @notice Approves every pool factory (the Router only calls this method on the registry).
contract MockFactoryRegistry {
  function isPoolFactoryApproved(address) external pure returns (bool) {
    return true;
  }
}

/// @notice Resolves token pairs to pool addresses (the subset of IRPoolFactory the Router uses).
contract MockRPoolFactory {
  mapping(bytes32 => address) internal pools;
  mapping(address => bool) public isPool;

  function setPool(address a, address b, address pool) external {
    pools[_key(a, b)] = pool;
    isPool[pool] = true;
  }

  function getOrPrecomputeProxyAddress(address a, address b) external view returns (address) {
    return pools[_key(a, b)];
  }

  function getPool(address a, address b) external view returns (address) {
    return pools[_key(a, b)];
  }

  function _key(address a, address b) internal pure returns (bytes32) {
    return a < b ? keccak256(abi.encode(a, b)) : keccak256(abi.encode(b, a));
  }
}

/// @notice A pool that gates its quote on SortedOracles freshness, mirroring getFXRateIfValid:
///         getAmountOut reverts StaleRate unless a (fresh) median exists for its referenceRateFeedID.
///         This is how we prove the ingest pre-step must run before the swap's oracle read.
contract MockOracleConsumerPool {
  address public immutable referenceRateFeedID;
  address public immutable sortedOracles;
  address public immutable token0;
  address public immutable token1;

  error StaleRate();

  constructor(address _rateFeedId, address _sortedOracles, address _tA, address _tB) {
    referenceRateFeedID = _rateFeedId;
    sortedOracles = _sortedOracles;
    (token0, token1) = _tA < _tB ? (_tA, _tB) : (_tB, _tA);
  }

  function getReserves() external view returns (uint256, uint256, uint256) {
    return (1e24, 1e24, block.timestamp);
  }

  function getAmountOut(uint256 amountIn, address) external view returns (uint256) {
    (uint256 median, ) = ISortedOracles(sortedOracles).medianRate(referenceRateFeedID);
    if (median == 0) revert StaleRate(); // no fresh report written this tx
    return amountIn; // 1:1 for test simplicity
  }

  function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata) external {
    uint256 out = amount0Out > 0 ? amount0Out : amount1Out;
    address tokenOut = amount0Out > 0 ? token0 : token1;
    IERC20(tokenOut).transfer(to, out);
  }
}

contract RouterWithReportsTest is Test {
  bytes constant STALE_RATE_ERROR = abi.encodeWithSignature("StaleRate()");

  ISortedOracles sortedOracles;
  MockVerifierProxy verifier;
  IDataStreamsRelayerFactory dsFactory;
  MockFactoryRegistry registry;
  MockRPoolFactory poolFactory;
  RouterWithReports router;

  MockERC20 tokenA;
  MockERC20 tokenB;
  MockERC20 tokenC;

  // Feed 1: A/B
  address rateFeed1 = makeAddr("A/B");
  bytes32 feedId1 = keccak256("A/B");
  MockOracleConsumerPool pool1;

  // Feed 2: B/C
  address rateFeed2 = makeAddr("B/C");
  bytes32 feedId2 = keccak256("B/C");
  MockOracleConsumerPool pool2;

  uint256 amountIn = 1e18;
  uint256 staleness = 600;

  function setUp() public {
    vm.warp(100_000);

    sortedOracles = ISortedOracles(deployCode("SortedOracles", abi.encode(true)));
    sortedOracles.initialize(3600);
    sortedOracles.setTokenReportExpiry(rateFeed1, 3600);
    sortedOracles.setTokenReportExpiry(rateFeed2, 3600);

    verifier = new MockVerifierProxy(); // echo: signed payload == verified report

    dsFactory = IDataStreamsRelayerFactory(deployCode("DataStreamsRelayerFactory", abi.encode(false)));
    dsFactory.initialize(address(sortedOracles), address(verifier), address(this));

    tokenA = new MockERC20("A", "A", 18);
    tokenB = new MockERC20("B", "B", 18);
    tokenC = new MockERC20("C", "C", 18);

    registry = new MockFactoryRegistry();
    poolFactory = new MockRPoolFactory();

    _deployRelayer(rateFeed1, "A/B", feedId1);
    _deployRelayer(rateFeed2, "B/C", feedId2);

    pool1 = new MockOracleConsumerPool(rateFeed1, address(sortedOracles), address(tokenA), address(tokenB));
    pool2 = new MockOracleConsumerPool(rateFeed2, address(sortedOracles), address(tokenB), address(tokenC));
    poolFactory.setPool(address(tokenA), address(tokenB), address(pool1));
    poolFactory.setPool(address(tokenB), address(tokenC), address(pool2));

    router = new RouterWithReports(address(0), address(registry), address(poolFactory), address(dsFactory));

    // Seed pool output liquidity and the caller's input balance.
    tokenB.mint(address(pool1), 100e18);
    tokenC.mint(address(pool2), 100e18);
    tokenA.mint(address(this), 100e18);
    tokenB.mint(address(this), 100e18);
    tokenA.approve(address(router), type(uint256).max);
    tokenB.approve(address(router), type(uint256).max);
  }

  function _deployRelayer(address rateFeedId, string memory desc, bytes32 feedId) internal {
    IDataStreamsRelayer.StreamLeg[] memory legs = new IDataStreamsRelayer.StreamLeg[](1);
    legs[0] = IDataStreamsRelayer.StreamLeg(feedId, false);
    address relayer = dsFactory.deployRelayer(rateFeedId, desc, 0, staleness, legs);
    sortedOracles.addOracle(rateFeedId, relayer);
  }

  function _report(bytes32 feedId, int192 price) internal view returns (bytes memory) {
    return
      abi.encode(
        feedId,
        uint32(0),
        uint32(block.timestamp),
        uint192(0),
        uint192(0),
        uint32(block.timestamp + 1000),
        price,
        int192(0),
        int192(0)
      );
  }

  function _route(address from, address to) internal pure returns (IRouter.Route[] memory routes) {
    routes = new IRouter.Route[](1);
    routes[0] = IRouter.Route(from, to, address(0)); // factory address(0) => default pool factory
  }

  function _wrap1(bytes memory r) internal pure returns (bytes[][] memory perHop) {
    perHop = new bytes[][](1);
    perHop[0] = new bytes[](1);
    perHop[0][0] = r;
  }

  // ---- the JIT ordering: ingest writes the rate, then the swap reads it fresh ----

  function test_withReports_ingestsThenSwapsSucceeds() public {
    (uint256 medianBefore, ) = sortedOracles.medianRate(rateFeed1);
    assertEq(medianBefore, 0, "precondition: rate is stale");

    uint256 balBefore = tokenB.balanceOf(address(this));
    router.swapExactTokensForTokensWithReports(
      amountIn,
      amountIn,
      _route(address(tokenA), address(tokenB)),
      address(this),
      block.timestamp,
      _wrap1(_report(feedId1, 5e17))
    );

    // ingest wrote a fresh median...
    (uint256 medianAfter, ) = sortedOracles.medianRate(rateFeed1);
    assertEq(medianAfter, uint256(uint192(int192(5e17))) * 1e6, "ingest must write the verified rate");
    // ...and the swap settled against it.
    assertEq(tokenB.balanceOf(address(this)) - balBefore, amountIn, "swap output not received");
  }

  function test_withoutReports_revertsStale() public {
    // The plain swap (no ingest) hits the staleness wall: getAmountOut reverts.
    vm.expectRevert(STALE_RATE_ERROR);
    router.swapExactTokensForTokens(
      amountIn,
      amountIn,
      _route(address(tokenA), address(tokenB)),
      address(this),
      block.timestamp
    );
  }

  function test_emptyHop_skipsIngest_revertsStale() public {
    // An empty per-hop bundle must NOT ingest; the rate stays stale and the swap reverts.
    bytes[][] memory perHop = new bytes[][](1);
    perHop[0] = new bytes[](0);
    vm.expectRevert(STALE_RATE_ERROR);
    router.swapExactTokensForTokensWithReports(
      amountIn,
      amountIn,
      _route(address(tokenA), address(tokenB)),
      address(this),
      block.timestamp,
      perHop
    );
    (uint256 median, ) = sortedOracles.medianRate(rateFeed1);
    assertEq(median, 0, "empty hop must not have ingested");
  }

  function test_reportsLengthMismatch_reverts() public {
    bytes[][] memory perHop = new bytes[][](2); // 2 bundles for a 1-hop route
    perHop[0] = new bytes[](1);
    perHop[0][0] = _report(feedId1, 5e17);
    perHop[1] = new bytes[](0);
    vm.expectRevert(abi.encodeWithSignature("ReportsLengthMismatch()"));
    router.swapExactTokensForTokensWithReports(
      amountIn,
      amountIn,
      _route(address(tokenA), address(tokenB)),
      address(this),
      block.timestamp,
      perHop
    );
  }

  function test_factoryNotSet_reverts() public {
    RouterWithReports noFactoryRouter = new RouterWithReports(
      address(0),
      address(registry),
      address(poolFactory),
      address(0) // no DataStreamsRelayerFactory
    );
    vm.expectRevert(abi.encodeWithSignature("DataStreamsRelayerFactoryNotSet()"));
    noFactoryRouter.swapExactTokensForTokensWithReports(
      amountIn,
      amountIn,
      _route(address(tokenA), address(tokenB)),
      address(this),
      block.timestamp,
      _wrap1(_report(feedId1, 5e17))
    );
  }

  // ---- multi-hop: each hop's feed is ingested before the route is priced ----

  function test_multiHop_twoFeeds_ingestsEachHop() public {
    IRouter.Route[] memory routes = new IRouter.Route[](2);
    routes[0] = IRouter.Route(address(tokenA), address(tokenB), address(0));
    routes[1] = IRouter.Route(address(tokenB), address(tokenC), address(0));

    bytes[][] memory perHop = new bytes[][](2);
    perHop[0] = new bytes[](1);
    perHop[0][0] = _report(feedId1, 5e17);
    perHop[1] = new bytes[](1);
    perHop[1][0] = _report(feedId2, 8e17);

    uint256 balBefore = tokenC.balanceOf(address(this));
    router.swapExactTokensForTokensWithReports(amountIn, amountIn, routes, address(this), block.timestamp, perHop);

    (uint256 m1, ) = sortedOracles.medianRate(rateFeed1);
    (uint256 m2, ) = sortedOracles.medianRate(rateFeed2);
    assertEq(m1, uint256(uint192(int192(5e17))) * 1e6, "feed 1 not ingested");
    assertEq(m2, uint256(uint192(int192(8e17))) * 1e6, "feed 2 not ingested");
    assertEq(tokenC.balanceOf(address(this)) - balBefore, amountIn, "multi-hop output not received");
  }
}
