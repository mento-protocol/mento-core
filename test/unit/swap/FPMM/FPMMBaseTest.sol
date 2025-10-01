// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable var-name-mixedcase
pragma solidity ^0.8;
import { Test } from "mento-std/Test.sol";
import { FPMM } from "contracts/swap/FPMM.sol";
import { ERC20DecimalsMock } from "openzeppelin-contracts-next/contracts/mocks/ERC20DecimalsMock.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";
import { IOracleAdapter } from "contracts/interfaces/IOracleAdapter.sol";
import { IBreakerBox } from "contracts/interfaces/IBreakerBox.sol";
import { IMarketHoursBreaker } from "contracts/interfaces/IMarketHoursBreaker.sol";

import { OracleAdapter } from "contracts/oracles/OracleAdapter.sol";

contract FPMMBaseTest is Test {
  FPMM public fpmm;
  IOracleAdapter public oracleAdapter;

  address public token0;
  address public token1;

  address public ALICE = makeAddr("ALICE");
  address public BOB = makeAddr("BOB");
  address public CHARLIE = makeAddr("CHARLIE");

  address public sortedOracles = makeAddr("SortedOracles");
  address public breakerBox = makeAddr("BreakerBox");
  address public marketHoursBreaker = makeAddr("MarketHoursBreaker");
  address public referenceRateFeedID = makeAddr("REFERENCE_RATE_FEED");
  address public owner = makeAddr("OWNER");

  uint256 public constant TRADING_MODE_BIDIRECTIONAL = 0;
  uint256 public constant TRADING_MODE_DISABLED = 3;

  function setUp() public virtual {
    fpmm = new FPMM(false);
    oracleAdapter = IOracleAdapter(new OracleAdapter(false));
    oracleAdapter.initialize(address(sortedOracles), address(breakerBox), address(marketHoursBreaker));

    vm.prank(fpmm.owner());

    bytes memory tradingModeCalldata = abi.encodeWithSelector(
      IBreakerBox.getRateFeedTradingMode.selector,
      referenceRateFeedID
    );
    vm.mockCall(breakerBox, tradingModeCalldata, abi.encode(TRADING_MODE_BIDIRECTIONAL));
  }

  modifier initializeFPMM_withDecimalTokens(uint8 decimals0, uint8 decimals1) {
    token0 = address(new ERC20DecimalsMock("token0", "T0", decimals0));
    token1 = address(new ERC20DecimalsMock("token1", "T1", decimals1));

    fpmm.initialize(token0, token1, address(oracleAdapter), referenceRateFeedID, false, owner);

    deal(token0, ALICE, 1_000 * 10 ** decimals0);
    deal(token1, ALICE, 1_000 * 10 ** decimals1);
    deal(token0, BOB, 1_000 * 10 ** decimals0);
    deal(token1, BOB, 1_000 * 10 ** decimals1);

    _;
  }

  modifier mintInitialLiquidity(uint8 decimals0, uint8 decimals1) {
    vm.startPrank(ALICE);
    IERC20(token0).transfer(address(fpmm), 100 * 10 ** decimals0);
    IERC20(token1).transfer(address(fpmm), 200 * 10 ** decimals1);
    fpmm.mint(ALICE);
    vm.stopPrank();

    _;
  }

  modifier withFXMarketOpen(bool isFXMarketOpen) {
    bytes memory isFXMarketOpenCalldata = abi.encodeWithSelector(IMarketHoursBreaker.isFXMarketOpen.selector);
    vm.mockCall(marketHoursBreaker, isFXMarketOpenCalldata, abi.encode(isFXMarketOpen));
    _;
  }

  modifier withRecentRate(bool hasRecentRate) {
    if (hasRecentRate) {
      _mockRecentRate();
    } else {
      _mockExpiredRate();
    }

    _;
  }

  modifier withOracleRate(uint256 nominator, uint256 denominator) {
    bytes memory medianRateCalldata = abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID);
    vm.mockCall(sortedOracles, medianRateCalldata, abi.encode(nominator, denominator));

    _;
  }

  modifier withTradingMode(uint256 tradingMode) {
    bytes memory tradingModeCalldata = abi.encodeWithSelector(
      IBreakerBox.getRateFeedTradingMode.selector,
      referenceRateFeedID
    );
    vm.mockCall(breakerBox, tradingModeCalldata, abi.encode(tradingMode));

    _;
  }

  function _mockRecentRate() private {
    bytes memory reportExpiryCalldata = abi.encodeWithSelector(
      ISortedOracles.getTokenReportExpirySeconds.selector,
      referenceRateFeedID
    );
    vm.mockCall(sortedOracles, reportExpiryCalldata, abi.encode(0));

    bytes memory medianTimestampCalldata = abi.encodeWithSelector(
      ISortedOracles.medianTimestamp.selector,
      referenceRateFeedID
    );
    vm.mockCall(sortedOracles, medianTimestampCalldata, abi.encode(block.timestamp + 1 hours));
  }

  function _mockExpiredRate() private {
    bytes memory reportExpiryCalldata = abi.encodeWithSelector(
      ISortedOracles.getTokenReportExpirySeconds.selector,
      referenceRateFeedID
    );
    vm.mockCall(sortedOracles, reportExpiryCalldata, abi.encode(0));

    bytes memory medianTimestampCalldata = abi.encodeWithSelector(
      ISortedOracles.medianTimestamp.selector,
      referenceRateFeedID
    );
    vm.mockCall(sortedOracles, medianTimestampCalldata, abi.encode(0));
  }
}
