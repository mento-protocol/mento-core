// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { ICeloProxy } from "contracts/interfaces/ICeloProxy.sol";
import { IOwnable } from "contracts/interfaces/IOwnable.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { TempStable } from "contracts/tokens/TempStable.sol";

import { BaseForkTest } from "./BaseForkTest.sol";

contract GHSRenameForkTest is BaseForkTest {
  string public constant GHS_NAME = "Celo Ghanaian Cedi";

  address public stableTokenGHSProxy;
  address public originalImplementation; // StableTokenV2
  address public proxyOwner;
  address public alice;

  TempStable public tempImplementation; // Has the setName function

  constructor(uint256 _chainId) BaseForkTest(_chainId) {}

  function setUp() public override {
    super.setUp();
    uint256 chainId = block.chainid;

    if (chainId == 42220) {
      stableTokenGHSProxy = 0xfAeA5F3404bbA20D3cc2f8C4B0A888F55a3c7313;
    } else if (chainId == 44787) {
      stableTokenGHSProxy = 0x295B66bE7714458Af45E6A6Ea142A5358A6cA375;
    }

    require(stableTokenGHSProxy != address(0), "StableTokenGHS not on this chain");

    originalImplementation = ICeloProxy(stableTokenGHSProxy)._getImplementation();
    proxyOwner = IOwnable(stableTokenGHSProxy).owner();

    // Create a test user
    alice = makeAddr("testUser");

    // Give the test user some GHS
    deal(stableTokenGHSProxy, alice, 1000 ether, true);
  }

  function test_upgradeAndChangeName_shouldPreserveStorageAndName() public {
    // 1. First verify the initial state with original implementation
    IERC20 ghsProxy = IERC20(stableTokenGHSProxy);
    uint256 aliceBalance = ghsProxy.balanceOf(alice);

    // 2. Deploy new temporary implementation
    vm.startPrank(proxyOwner);
    tempImplementation = new TempStable();

    // 3. Upgrade the proxy to use the new implementation
    ICeloProxy(stableTokenGHSProxy)._setImplementation(address(tempImplementation));
    address newImpl = ICeloProxy(stableTokenGHSProxy)._getImplementation();
    assertEq(newImpl, address(tempImplementation), "Implementation not updated correctly");

    // 4. Set the name of the token to the correct name
    TempStable tempStableTokenGHS = TempStable(stableTokenGHSProxy);
    tempStableTokenGHS.setName(GHS_NAME);

    // Verify name change
    assertEq(ghsProxy.name(), GHS_NAME, "Name was not changed correctly");

    // 5. Change back to the original implementation
    ICeloProxy(stableTokenGHSProxy)._setImplementation(originalImplementation);
    vm.stopPrank();

    // 6. Verify that the original implementation is restored
    assertEq(
      ICeloProxy(stableTokenGHSProxy)._getImplementation(),
      originalImplementation,
      "Implementation not restored correctly"
    );

    // Check if the name change persisted (storage was preserved)
    assertEq(ghsProxy.name(), GHS_NAME, "Storage not preserved after reverting to original implementation");

    // 7. Test standard token functionality with the new implementation, just to make sure it works
    // Check balances carried over correctly
    assertEq(ghsProxy.balanceOf(alice), aliceBalance, "Balance not preserved after upgrade");

    // Test transfer
    address recipient = makeAddr("recipient");
    vm.startPrank(alice);
    bool transferSuccess = ghsProxy.transfer(recipient, 100 ether);
    vm.stopPrank();
    assertTrue(transferSuccess, "Transfer with new original implementation failed");

    // Verify balances after transfer
    assertEq(ghsProxy.balanceOf(alice), aliceBalance - 100 ether, "Incorrect sender balance after transfer");
    assertEq(ghsProxy.balanceOf(recipient), 100 ether, "Incorrect recipient balance after transfer");
  }
}
