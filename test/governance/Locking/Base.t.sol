// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { TestSetup } from "../TestSetup.sol";
import { Locking } from "contracts/governance/Locking.sol";
import { MockMentoToken } from "../../mocks/MockMentoToken.sol";
import { IERC20Upgradeable } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";

contract Locking_Test is TestSetup {
  Locking public lockingContract;
  MockMentoToken public mentoToken;

  uint32 public startingPointWeek;
  uint32 public minCliffPeriod;
  uint32 public minSlopePeriod;

  function setUp() public virtual {
    mentoToken = new MockMentoToken();
  }

  function _newLocking() internal {
    lockingContract = new Locking();
  }

  function _initLocking() internal {
    _newLocking();

    vm.prank(owner);
    lockingContract.__Locking_init(
      IERC20Upgradeable(address(mentoToken)),
      startingPointWeek,
      minCliffPeriod,
      minSlopePeriod
    );
  }
}
