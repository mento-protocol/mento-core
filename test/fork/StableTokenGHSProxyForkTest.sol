// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { BaseForkTest } from "./BaseForkTest.sol";
import { TempStableToken } from "contracts/tokens/TempStableToken.sol";
import { ICeloProxy } from "contracts/interfaces/ICeloProxy.sol";
import { IOwnable } from "contracts/interfaces/IOwnable.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { console } from "forge-std/console.sol";

contract StableTokenGHSProxyForkTest is BaseForkTest {
  address public stableTokenGHSProxy;
  address public originalImplementation; // StableTokenV2
  address public proxyOwner;
  address public testUser;

  TempStableToken public tempImplementation; // Has the setName function

  constructor(uint256 _chainId) BaseForkTest(_chainId) {}

  function setUp() public override {
    super.setUp();

    // Find the StableTokenGHS proxy contract
    stableTokenGHSProxy = lookup("StableTokenGHS");
    require(stableTokenGHSProxy != address(0), "StableTokenGHS not found in registry");

    originalImplementation = ICeloProxy(stableTokenGHSProxy)._getImplementation();
    proxyOwner = IOwnable(stableTokenGHSProxy).owner();

    // Create a test user
    testUser = makeAddr("testUser");

    // Give the test user some tokens
    mint(stableTokenGHSProxy, testUser, 1000 ether, true);
  }

  function test_upgradeStableTokenGHSProxy() public {
    // 1. First verify the initial state with original implementation
    IERC20 originalToken = IERC20(stableTokenGHSProxy);
    string memory originalName = originalToken.name();
    string memory originalSymbol = originalToken.symbol();
    uint8 originalDecimals = originalToken.decimals();
    uint256 testUserBalance = originalToken.balanceOf(testUser);

    // Log initial state
    console.log("Original implementation:", originalImplementation);
    console.log("Original name:", originalName);
    console.log("Original symbol:", originalSymbol);
    console.log("Original decimals:", originalDecimals);
    console.log("Test user balance:", testUserBalance);

    // 2. Deploy new temporary implementation
    tempImplementation = new TempStableToken(true);

    // 3. Upgrade the proxy to use the new implementation
    vm.prank(proxyOwner);
    ICeloProxy(stableTokenGHSProxy)._setImplementation(address(tempImplementation));

    address newImpl = ICeloProxy(stableTokenGHSProxy)._getImplementation();
    assertEq(newImpl, address(tempImplementation), "Implementation not updated correctly");

    // 4. Test the set name function on the new implementation
    TempStableToken upgradedToken = TempStableToken(stableTokenGHSProxy);
    vm.prank(proxyOwner);
    upgradedToken.setName("Celo Ghanaian Cedi");

    // Verify name change
    assertEq(upgradedToken.name(), "Celo Ghanaian Cedi", "Name was not changed correctly");

    // 5. Test standard token functionality with the new implementation, just to make sure it works
    // Check balances carried over correctly
    assertEq(upgradedToken.balanceOf(testUser), testUserBalance, "Balance not preserved after upgrade");

    // Test transfer with new implementation
    address recipient = makeAddr("recipient");
    vm.prank(testUser);
    bool transferSuccess = upgradedToken.transfer(recipient, 100 ether);
    assertTrue(transferSuccess, "Transfer with new implementation failed");

    // Verify balances after transfer
    assertEq(upgradedToken.balanceOf(testUser), testUserBalance - 100 ether, "Incorrect sender balance after transfer");
    assertEq(upgradedToken.balanceOf(recipient), 100 ether, "Incorrect recipient balance after transfer");

    // 6. Change back to the original implementation
    vm.prank(proxyOwner);
    ICeloProxy(stableTokenGHSProxy)._setImplementation(originalImplementation);

    // Confirm original implementation is restored
    assertEq(
      ICeloProxy(stableTokenGHSProxy)._getImplementation(),
      originalImplementation,
      "Failed to restore original implementation"
    );

    // 7. Test functionality with original implementation
    IERC20 restoredToken = IERC20(stableTokenGHSProxy);

    // Check if the name change persisted (storage was preserved)
    assertEq(
      restoredToken.name(),
      "Celo Ghanaian Cedi",
      "Storage not preserved after reverting to original implementation"
    );

    // Test transfer with restored implementation
    address newRecipient = makeAddr("newRecipient");
    vm.prank(testUser);
    bool restoredTransferSuccess = restoredToken.transfer(newRecipient, 50 ether);
    assertTrue(restoredTransferSuccess, "Transfer with restored implementation failed");

    // Verify final balances
    assertEq(
      restoredToken.balanceOf(testUser),
      testUserBalance - 150 ether,
      "Incorrect sender balance after restoration"
    );
    assertEq(restoredToken.balanceOf(newRecipient), 50 ether, "Incorrect new recipient balance after restoration");
    assertEq(restoredToken.balanceOf(recipient), 100 ether, "Original recipient balance changed after restoration");
  }
}
