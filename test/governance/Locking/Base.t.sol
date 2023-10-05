// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { TestSetup } from "../TestSetup.sol";
import { TestLocking } from "../../utils/TestLocking.sol";
import { MockMentoToken } from "../../mocks/MockMentoToken.sol";
import { IERC20Upgradeable } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";

contract Locking_Test is TestSetup {
  TestLocking public lockingContract;
  MockMentoToken public mentoToken;

  uint32 public weekInBlocks;

  function setUp() public virtual {
    mentoToken = new MockMentoToken();
    lockingContract = new TestLocking();

    vm.prank(owner);
    lockingContract.__Locking_init(IERC20Upgradeable(address(mentoToken)), 0, 0, 0);

    weekInBlocks = uint32(lockingContract.WEEK());

    vm.prank(alice);
    mentoToken.approve(address(lockingContract), type(uint256).max);

    _incrementBlock(2 * weekInBlocks);
  }

  function _incrementBlock(uint32 _amount) internal {
    lockingContract.incrementBlock(_amount);
  }
}
