// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
// solhint-disable modifier-name-mixedcase,
pragma solidity ^0.8;
import { Test } from "mento-std/Test.sol";
import { FPMM } from "contracts/swap/FPMM.sol";
import { ERC20DecimalsMock } from "openzeppelin-contracts-next/contracts/mocks/ERC20DecimalsMock.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";
contract FPMMBaseTest is Test {
  FPMM public fpmm;

  address public token0;
  address public token1;

  address public ALICE = makeAddr("ALICE");
  address public BOB = makeAddr("BOB");
  address public CHARLIE = makeAddr("CHARLIE");

  address public sortedOracles = makeAddr("SortedOracles");
  address public referenceRateFeedID = makeAddr("REFERENCE_RATE_FEED");

  function setUp() public virtual {
    fpmm = new FPMM(false);
    vm.prank(fpmm.owner());
    fpmm.setReferenceRateFeedID(referenceRateFeedID);
  }

  modifier initializeFPMM_withDecimalTokens(uint8 decimals0, uint8 decimals1) {
    token0 = address(new ERC20DecimalsMock("token0", "T0", decimals0));
    token1 = address(new ERC20DecimalsMock("token1", "T1", decimals1));

    fpmm.initialize(token0, token1, sortedOracles);

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

  modifier setupMockOracleRate(uint256 nominator, uint256 denominator) {
    bytes memory medianRateCalldata = abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID);
    vm.mockCall(sortedOracles, medianRateCalldata, abi.encode(nominator, denominator));

    _;
  }
}
