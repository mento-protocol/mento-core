// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, max-line-length

import { addresses } from "mento-std/Array.sol";
import { Vm } from "forge-std/Vm.sol";

import { MinipayMentoClaim } from "contracts/governance/MinipayMentoClaim.sol";
import { VmExtension } from "test/utils/VmExtension.sol";
import { GovernanceTest } from "test/unit/governance/GovernanceTest.sol";

/**
 * @title MinipayMentoClaimIntegrationTest
 * @notice Integration tests for the MinipayMentoClaim token focusing on end-to-end flows
 */
contract MinipayMentoClaimIntegrationTest is GovernanceTest {
    using VmExtension for Vm;

    MinipayMentoClaim public claim;
    
    address public operaWallet;
    address[] public users;
    
    // Sample campaign data
    string[] public campaignNames;
    uint256[] public allocations;
    string public constant BASE_URI = "https://minipay.mento.org/api/campaigns/";
    
    function setUp() public {
        // Create 10 users
        users = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", vm.toString(i))));
        }
        
        operaWallet = makeAddr("operaWallet");
        
        // Setup campaigns
        campaignNames = new string[](3);
        campaignNames[0] = "march/2025:cashback-promotions";
        campaignNames[1] = "march/2025:mp-boost";
        campaignNames[2] = "april/2025:referral-bonus";
        
        allocations = new uint256[](3);
        allocations[0] = 600_000 * 1e18;
        allocations[1] = 900_000 * 1e18;
        allocations[2] = 500_000 * 1e18;
        
        vm.startPrank(owner);
        
        // Deploy claim token
        claim = new MinipayMentoClaim(BASE_URI);
        
        // Create campaigns
        for (uint256 i = 0; i < campaignNames.length; i++) {
            claim.createCampaign(
                campaignNames[i],
                allocations[i],
                operaWallet,
                string(abi.encodePacked(BASE_URI, campaignNames[i]))
            );
        }
        
        vm.stopPrank();
    }
    
    function test_EndToEnd_DistributionAndPauseFlow() public {
        // 1. Distribute tokens to users
        vm.startPrank(operaWallet);
        
        for (uint256 i = 0; i < users.length; i++) {
            for (uint256 j = 0; j < campaignNames.length; j++) {
                bytes32 campaignId = claim.getCampaignId(campaignNames[j]);
                claim.safeTransferFrom(
                    operaWallet, 
                    users[i], 
                    uint256(campaignId),
                    (i + 1) * 100 * 1e18,
                    ""
                );
            }
        }
        
        vm.stopPrank();
        
        // 2. Verify distribution amounts
        for (uint256 i = 0; i < users.length; i++) {
            for (uint256 j = 0; j < campaignNames.length; j++) {
                bytes32 campaignId = claim.getCampaignId(campaignNames[j]);
                assertEq(
                    claim.balanceOf(users[i], uint256(campaignId)),
                    (i + 1) * 100 * 1e18,
                    "User balance incorrect"
                );
            }
        }
        
        // 3. Pause a campaign
        vm.prank(owner);
        claim.pauseCampaign(campaignNames[0]);
        
        // 4. User attempts to transfer paused campaign tokens (should fail)
        vm.startPrank(users[0]);
        bytes32 pausedCampaignId = claim.getCampaignId(campaignNames[0]);
        
        // No need to approve self
        vm.expectRevert("MinipayMentoClaim: transfer paused or not authorized");
        claim.safeTransferFrom(users[0], users[1], uint256(pausedCampaignId), 50 * 1e18, "");
        
        // 5. User transfers active campaign tokens (should succeed)
        bytes32 activeCampaignId = claim.getCampaignId(campaignNames[1]);
        claim.safeTransferFrom(users[0], users[1], uint256(activeCampaignId), 50 * 1e18, "");
        
        vm.stopPrank();
        
        // 6. Verify transfer was successful
        assertEq(
            claim.balanceOf(users[0], uint256(activeCampaignId)),
            50 * 1e18,
            "Sender balance incorrect after transfer"
        );
        assertEq(
            claim.balanceOf(users[1], uint256(activeCampaignId)),
            250 * 1e18,
            "Recipient balance incorrect after transfer"
        );
        
        // 7. Owner transfers paused campaign tokens (should succeed)
        vm.prank(users[0]);
        claim.setApprovalForAll(owner, true);
        
        vm.prank(owner);
        claim.safeTransferFrom(users[0], users[1], uint256(pausedCampaignId), 50 * 1e18, "");
        
        // 8. Verify owner transfer was successful
        assertEq(
            claim.balanceOf(users[0], uint256(pausedCampaignId)),
            50 * 1e18,
            "Sender balance incorrect after owner transfer"
        );
        assertEq(
            claim.balanceOf(users[1], uint256(pausedCampaignId)),
            250 * 1e18,
            "Recipient balance incorrect after owner transfer"
        );
    }
    
    function test_Campaign_DistributorChange() public {
        // 1. Distribute some tokens from the original distributor
        vm.startPrank(operaWallet);
        bytes32 campaignId = claim.getCampaignId(campaignNames[0]);
        
        // Distribute half the tokens
        uint256 distributeAmount = allocations[0] / 2;
        for (uint256 i = 0; i < 5; i++) {
            uint256 userAmount = distributeAmount / 5;
            claim.safeTransferFrom(operaWallet, users[i], uint256(campaignId), userAmount, "");
        }
        vm.stopPrank();
        
        // 2. Change distributor
        address newDistributor = makeAddr("newDistributor");
        vm.prank(owner);
        claim.changeCampaignDistributor(campaignNames[0], newDistributor);
        
        // 3. Verify distributor was changed
        (, address currentDistributor, , ) = claim.campaigns(campaignId);
        assertEq(currentDistributor, newDistributor);
        
        // 4. Verify remaining tokens were transferred to new distributor
        uint256 remainingTokens = allocations[0] - distributeAmount;
        assertEq(claim.balanceOf(operaWallet, uint256(campaignId)), 0);
        assertEq(claim.balanceOf(newDistributor, uint256(campaignId)), remainingTokens);
        
        // 5. Distribute remaining tokens from new distributor
        vm.startPrank(newDistributor);
        for (uint256 i = 5; i < 10; i++) {
            uint256 userAmount = remainingTokens / 5;
            claim.safeTransferFrom(newDistributor, users[i], uint256(campaignId), userAmount, "");
        }
        vm.stopPrank();
        
        // 6. Verify all tokens have been distributed
        assertEq(claim.getDistributedAmount(campaignNames[0]), allocations[0]);
        assertEq(claim.balanceOf(newDistributor, uint256(campaignId)), 0);
    }
    
    function test_RevertWhen_ChangingToSameDistributor() public {
        vm.prank(owner);
        vm.expectRevert("MinipayMentoClaim: new distributor same as current");
        claim.changeCampaignDistributor(campaignNames[0], operaWallet);
    }
    
    function test_IncreaseAllocation_Integration() public {
        // 1. Distribute all tokens from the initial allocation
        vm.startPrank(operaWallet);
        bytes32 campaignId = claim.getCampaignId(campaignNames[0]);
        
        // Distribute to multiple users
        uint256 initialDistribution = allocations[0] / users.length;
        for (uint256 i = 0; i < users.length; i++) {
            claim.safeTransferFrom(operaWallet, users[i], uint256(campaignId), initialDistribution, "");
        }
        vm.stopPrank();
        
        // Verify all tokens are distributed
        assertEq(claim.balanceOf(operaWallet, uint256(campaignId)), 0);
        assertEq(claim.getDistributedAmount(campaignNames[0]), allocations[0]);
        
        // 2. Increase allocation
        uint256 additionalAllocation = 500_000 * 1e18;
        vm.prank(owner);
        claim.increaseAllocation(campaignNames[0], additionalAllocation);
        
        // 3. Verify campaign allocation is updated
        (uint256 newAllocation, , , ) = claim.campaigns(campaignId);
        assertEq(newAllocation, allocations[0] + additionalAllocation);
        
        // 4. Verify distributor balance has increased
        assertEq(claim.balanceOf(operaWallet, uint256(campaignId)), additionalAllocation);
        
        // 5. Distribute some of the new tokens
        vm.startPrank(operaWallet);
        uint256 secondDistribution = additionalAllocation / 2;
        claim.safeTransferFrom(operaWallet, users[0], uint256(campaignId), secondDistribution, "");
        vm.stopPrank();
        
        // 6. Verify distribution was successful
        assertEq(claim.balanceOf(operaWallet, uint256(campaignId)), additionalAllocation - secondDistribution);
        assertEq(claim.balanceOf(users[0], uint256(campaignId)), initialDistribution + secondDistribution);
        
        // 7. Verify distributed amount calculation includes both allocations
        assertEq(
            claim.getDistributedAmount(campaignNames[0]), 
            allocations[0] + secondDistribution
        );
    }
    
    function test_DistributorCanTransferEvenWhenPaused() public {
        // First distribute tokens
        vm.startPrank(operaWallet);
        bytes32 campaignId = claim.getCampaignId(campaignNames[0]);
        claim.safeTransferFrom(operaWallet, users[0], uint256(campaignId), 100 * 1e18, "");
        vm.stopPrank();
        
        // Then pause the campaign
        vm.prank(owner);
        claim.pauseCampaign(campaignNames[0]);
        
        // User approves campaign distributor to transfer tokens
        vm.prank(users[0]);
        claim.setApprovalForAll(operaWallet, true);
        
        // Campaign distributor should be able to transfer even when paused
        vm.prank(operaWallet);
        claim.safeTransferFrom(users[0], users[1], uint256(campaignId), 50 * 1e18, "");
        
        assertEq(claim.balanceOf(users[1], uint256(campaignId)), 50 * 1e18);
        assertEq(claim.balanceOf(users[0], uint256(campaignId)), 50 * 1e18);
    }
    
    function test_GetAllCampaigns() public {
        // Distribute some tokens first
        vm.startPrank(operaWallet);
        
        for (uint256 j = 0; j < campaignNames.length; j++) {
            bytes32 campaignId = claim.getCampaignId(campaignNames[j]);
            claim.safeTransferFrom(operaWallet, users[0], uint256(campaignId), 100 * 1e18, "");
        }
        
        vm.stopPrank();
        
        // Get all campaigns info
        (
            bytes32[] memory ids,
            uint256[] memory campaignAllocations,
            address[] memory campaignDistributors,
            uint256[] memory distributed,
            bool[] memory pausedStatus
        ) = claim.getAllCampaigns();
        
        assertEq(ids.length, 3);
        assertEq(campaignAllocations.length, 3);
        assertEq(campaignDistributors.length, 3);
        assertEq(distributed.length, 3);
        assertEq(pausedStatus.length, 3);
        
        // Check all campaigns are in the result
        for (uint256 i = 0; i < campaignNames.length; i++) {
            bytes32 campaignId = claim.getCampaignId(campaignNames[i]);
            bool found = false;
            
            for (uint256 j = 0; j < ids.length; j++) {
                if (ids[j] == campaignId) {
                    found = true;
                    assertEq(campaignAllocations[j], this.allocations(i));
                    assertEq(campaignDistributors[j], operaWallet);
                    assertEq(distributed[j], 100 * 1e18); // Amount we distributed
                    assertEq(pausedStatus[j], false);
                    break;
                }
            }
            
            assertTrue(found, "Campaign not found in results");
        }
    }
} 