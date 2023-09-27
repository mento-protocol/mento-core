// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { TestSetup } from "../TestSetup.sol";
import { LockingHarness } from "../../mocks/LockingHarness.sol";
import { MockMentoToken } from "../../mocks/MockMentoToken.sol";
import { IERC20Upgradeable } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";

contract Locking_Test is TestSetup {
  LockingHarness public lockingContract;
  MockMentoToken public mentoToken;

  uint32 public startingPointWeek;
  uint32 public minCliffPeriod;
  uint32 public minSlopePeriod;

  uint32 public weekInBlocks;

  function setUp() public virtual {
    mentoToken = new MockMentoToken();
  }

  function _newLocking() internal {
    lockingContract = new LockingHarness();
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

  function _incrementBlock(uint32 _amount) internal {
    lockingContract.incrementBlock(_amount);
  }
}
