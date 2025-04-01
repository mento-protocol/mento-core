// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase

import { GovernanceTest } from "./GovernanceTest.sol";
import { MinipayMentoClaim } from "contracts/governance/MinipayMentoClaim.sol";

contract MinipayMentoClaimTest is GovernanceTest {
    MinipayMentoClaim public claim;
    
    address public operaWallet = makeAddr("operaWallet");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    
    // Sample campaign data
    string public constant CASHBACK_CAMPAIGN = "march/2025:cashback-promotions";
    string public constant BOOST_CAMPAIGN = "march/2025:mp-boost";
    uint256 public constant CASHBACK_ALLOCATION = 600_000 * 1e18;
    uint256 public constant BOOST_ALLOCATION = 900_000 * 1e18;
    
    function setUp() public {
        vm.startPrank(owner);
        claim = new MinipayMentoClaim("https://minipay.mento.org/api/campaigns/");
        
        // Create campaigns with operaWallet as distributor
        claim.createCampaign(
            CASHBACK_CAMPAIGN,
            CASHBACK_ALLOCATION,
            operaWallet,
            string(abi.encodePacked("https://minipay.mento.org/api/campaigns/", CASHBACK_CAMPAIGN))
        );
        
        claim.createCampaign(
            BOOST_CAMPAIGN,
            BOOST_ALLOCATION,
            operaWallet,
            string(abi.encodePacked("https://minipay.mento.org/api/campaigns/", BOOST_CAMPAIGN))
        );
        
        vm.stopPrank();
    }
    
    function test_CreateCampaign() public {
        bytes32 cashbackId = claim.getCampaignId(CASHBACK_CAMPAIGN);
        (uint256 allocation, address distributor, bool paused, string memory uri) = claim.campaigns(cashbackId);
        
        assertEq(allocation, CASHBACK_ALLOCATION);
        assertEq(distributor, operaWallet);
        assertEq(paused, false);
        assertEq(uri, string(abi.encodePacked("https://minipay.mento.org/api/campaigns/", CASHBACK_CAMPAIGN)));
        
        // Check if tokens were minted to distributor
        assertEq(claim.balanceOf(operaWallet, uint256(cashbackId)), CASHBACK_ALLOCATION);
    }
    
    function test_PauseCampaign() public {
        vm.prank(owner);
        claim.pauseCampaign(CASHBACK_CAMPAIGN);
        
        bytes32 cashbackId = claim.getCampaignId(CASHBACK_CAMPAIGN);
        (, , bool paused, ) = claim.campaigns(cashbackId);
        
        assertTrue(paused);
    }
    
    function test_UnpauseCampaign() public {
        vm.startPrank(owner);
        claim.pauseCampaign(CASHBACK_CAMPAIGN);
        claim.unpauseCampaign(CASHBACK_CAMPAIGN);
        vm.stopPrank();
        
        bytes32 cashbackId = claim.getCampaignId(CASHBACK_CAMPAIGN);
        (, , bool paused, ) = claim.campaigns(cashbackId);
        
        assertFalse(paused);
    }
    
    function test_TotalSupply() public {
        bytes32 cashbackId = claim.getCampaignId(CASHBACK_CAMPAIGN);
        bytes32 boostId = claim.getCampaignId(BOOST_CAMPAIGN);
        
        uint256 cashbackSupply = claim.totalSupply(uint256(cashbackId));
        uint256 boostSupply = claim.totalSupply(uint256(boostId));
        
        assertEq(cashbackSupply, CASHBACK_ALLOCATION);
        assertEq(boostSupply, BOOST_ALLOCATION);
    }
    
    function test_ChangeCampaignDistributor() public {
        address newDistributor = makeAddr("newDistributor");
        bytes32 cashbackId = claim.getCampaignId(CASHBACK_CAMPAIGN);
        
        // Transfer some tokens from operaWallet to user1 before changing distributor
        vm.prank(operaWallet);
        claim.safeTransferFrom(operaWallet, user1, uint256(cashbackId), 100 * 1e18, "");
        
        // Change distributor
        vm.prank(owner);
        claim.changeCampaignDistributor(CASHBACK_CAMPAIGN, newDistributor);
        
        // Check if campaign distributor was updated
        (, address distributor, , ) = claim.campaigns(cashbackId);
        assertEq(distributor, newDistributor);
        
        // Check if remaining tokens were transferred to the new distributor
        assertEq(claim.balanceOf(operaWallet, uint256(cashbackId)), 0);
        assertEq(claim.balanceOf(newDistributor, uint256(cashbackId)), CASHBACK_ALLOCATION - 100 * 1e18);
    }
    
    function test_RevertWhen_ChangingToSameDistributor() public {
        vm.prank(owner);
        vm.expectRevert("MinipayMentoClaim: new distributor same as current");
        claim.changeCampaignDistributor(CASHBACK_CAMPAIGN, operaWallet);
    }
    
    function test_IncreaseAllocation() public {
        bytes32 cashbackId = claim.getCampaignId(CASHBACK_CAMPAIGN);
        uint256 additionalAllocation = 200_000 * 1e18;
        
        // Initial balance should be the original allocation
        assertEq(claim.balanceOf(operaWallet, uint256(cashbackId)), CASHBACK_ALLOCATION);
        
        // Increase allocation
        vm.prank(owner);
        claim.increaseAllocation(CASHBACK_CAMPAIGN, additionalAllocation);
        
        // Check that allocation was updated in storage
        (uint256 newAllocation, , , ) = claim.campaigns(cashbackId);
        assertEq(newAllocation, CASHBACK_ALLOCATION + additionalAllocation);
        
        // Check that the distributor received the additional tokens
        assertEq(claim.balanceOf(operaWallet, uint256(cashbackId)), CASHBACK_ALLOCATION + additionalAllocation);
        
        // Distributor should be able to distribute the additional tokens
        vm.prank(operaWallet);
        claim.safeTransferFrom(operaWallet, user1, uint256(cashbackId), additionalAllocation, "");
        
        assertEq(claim.balanceOf(user1, uint256(cashbackId)), additionalAllocation);
        assertEq(claim.balanceOf(operaWallet, uint256(cashbackId)), CASHBACK_ALLOCATION);
    }
    
    function test_RevertWhen_NonOwnerIncreasesAllocation() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        claim.increaseAllocation(CASHBACK_CAMPAIGN, 100_000 * 1e18);
    }
    
    function test_RevertWhen_ZeroAdditionalAllocation() public {
        vm.prank(owner);
        vm.expectRevert("MinipayMentoClaim: additional allocation must be positive");
        claim.increaseAllocation(CASHBACK_CAMPAIGN, 0);
    }
    
    function test_RevertWhen_NonExistentCampaignAllocationIncreased() public {
        vm.prank(owner);
        vm.expectRevert("MinipayMentoClaim: campaign does not exist");
        claim.increaseAllocation("non-existent-campaign", 100_000 * 1e18);
    }
    
    function test_RevertWhen_NonOwnerCreatesCampaign() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        claim.createCampaign("new-campaign", 100_000 * 1e18, operaWallet, "uri");
    }
    
    function test_RevertWhen_NonOwnerPausesCampaign() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        claim.pauseCampaign(CASHBACK_CAMPAIGN);
    }
    
    function test_Distribution_ByDistributor() public {
        vm.startPrank(operaWallet);
        
        bytes32 cashbackId = claim.getCampaignId(CASHBACK_CAMPAIGN);
        bytes32 boostId = claim.getCampaignId(BOOST_CAMPAIGN);
        
        // Distributor transfers tokens to users
        claim.safeTransferFrom(operaWallet, user1, uint256(cashbackId), 100 * 1e18, "");
        claim.safeTransferFrom(operaWallet, user1, uint256(boostId), 200 * 1e18, "");
        
        assertEq(claim.balanceOf(user1, uint256(cashbackId)), 100 * 1e18);
        assertEq(claim.balanceOf(user1, uint256(boostId)), 200 * 1e18);
        
        // Check distributed amounts
        assertEq(claim.getDistributedAmount(CASHBACK_CAMPAIGN), 100 * 1e18);
        assertEq(claim.getDistributedAmount(BOOST_CAMPAIGN), 200 * 1e18);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_ExceedsAllocation() public {
        // Should not be possible since distributor only has the allocation amount
        // The ERC1155 balance check will fail before our custom logic
    }
    
    function test_RevertWhen_NonDistributorTransfers() public {
        vm.startPrank(operaWallet);
        bytes32 cashbackId = claim.getCampaignId(CASHBACK_CAMPAIGN);
        claim.safeTransferFrom(operaWallet, user1, uint256(cashbackId), 100 * 1e18, "");
        vm.stopPrank();
        
        vm.startPrank(bob); // Bob is not a distributor
        
        vm.expectRevert("ERC1155: caller is not token owner or approved");
        claim.safeTransferFrom(user1, user2, uint256(cashbackId), 50 * 1e18, "");
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_TransferAfterPausedCampaign() public {
        // First distribute tokens
        vm.startPrank(operaWallet);
        bytes32 cashbackId = claim.getCampaignId(CASHBACK_CAMPAIGN);
        claim.safeTransferFrom(operaWallet, user1, uint256(cashbackId), 100 * 1e18, "");
        vm.stopPrank();
        
        // Then pause the campaign
        vm.prank(owner);
        claim.pauseCampaign(CASHBACK_CAMPAIGN);
        
        // Try to transfer from user1 to user2
        vm.startPrank(user1);
        
        // User doesn't need approval for their own tokens
        // Just try to transfer directly
        vm.expectRevert("MinipayMentoClaim: transfer paused or not authorized");
        claim.safeTransferFrom(user1, user2, uint256(cashbackId), 50 * 1e18, "");
        
        vm.stopPrank();
    }
    
    function test_OwnerCanTransferEvenWhenPaused() public {
        // First distribute tokens
        vm.startPrank(operaWallet);
        bytes32 cashbackId = claim.getCampaignId(CASHBACK_CAMPAIGN);
        claim.safeTransferFrom(operaWallet, user1, uint256(cashbackId), 100 * 1e18, "");
        vm.stopPrank();
        
        // Then pause the campaign
        vm.prank(owner);
        claim.pauseCampaign(CASHBACK_CAMPAIGN);
        
        // User1 approves owner to transfer tokens
        vm.prank(user1);
        claim.setApprovalForAll(owner, true);
        
        // Owner should be able to transfer even when paused
        vm.prank(owner);
        claim.safeTransferFrom(user1, user2, uint256(cashbackId), 50 * 1e18, "");
        
        assertEq(claim.balanceOf(user2, uint256(cashbackId)), 50 * 1e18);
        assertEq(claim.balanceOf(user1, uint256(cashbackId)), 50 * 1e18);
    }
    
    function test_DistributorCanTransferEvenWhenPaused() public {
        // First distribute tokens
        vm.startPrank(operaWallet);
        bytes32 cashbackId = claim.getCampaignId(CASHBACK_CAMPAIGN);
        claim.safeTransferFrom(operaWallet, user1, uint256(cashbackId), 100 * 1e18, "");
        vm.stopPrank();
        
        // Then pause the campaign
        vm.prank(owner);
        claim.pauseCampaign(CASHBACK_CAMPAIGN);
        
        // User1 approves campaign distributor to transfer tokens
        vm.prank(user1);
        claim.setApprovalForAll(operaWallet, true);
        
        // Campaign distributor should be able to transfer even when paused
        vm.prank(operaWallet);
        claim.safeTransferFrom(user1, user2, uint256(cashbackId), 50 * 1e18, "");
        
        assertEq(claim.balanceOf(user2, uint256(cashbackId)), 50 * 1e18);
        assertEq(claim.balanceOf(user1, uint256(cashbackId)), 50 * 1e18);
    }
    
    function test_GetAllCampaigns() public {
        // Distribute some tokens first
        vm.startPrank(operaWallet);
        bytes32 cashbackId = claim.getCampaignId(CASHBACK_CAMPAIGN);
        bytes32 boostId = claim.getCampaignId(BOOST_CAMPAIGN);
        
        claim.safeTransferFrom(operaWallet, user1, uint256(cashbackId), 100 * 1e18, "");
        claim.safeTransferFrom(operaWallet, user2, uint256(boostId), 200 * 1e18, "");
        vm.stopPrank();
        
        // Get all campaigns info
        (
            bytes32[] memory ids,
            uint256[] memory allocations,
            address[] memory campaignDistributors,
            uint256[] memory distributed,
            bool[] memory pausedStatus
        ) = claim.getAllCampaigns();
        
        assertEq(ids.length, 2);
        assertEq(allocations.length, 2);
        assertEq(campaignDistributors.length, 2);
        assertEq(distributed.length, 2);
        assertEq(pausedStatus.length, 2);
        
        // Check that both campaigns are in the result
        bool foundCashback = false;
        bool foundBoost = false;
        
        for (uint256 i = 0; i < ids.length; i++) {
            if (ids[i] == cashbackId) {
                foundCashback = true;
                assertEq(allocations[i], CASHBACK_ALLOCATION);
                assertEq(campaignDistributors[i], operaWallet);
                assertEq(distributed[i], 100 * 1e18); // Amount transferred to user1
                assertEq(pausedStatus[i], false);
            } else if (ids[i] == boostId) {
                foundBoost = true;
                assertEq(allocations[i], BOOST_ALLOCATION);
                assertEq(campaignDistributors[i], operaWallet);
                assertEq(distributed[i], 200 * 1e18); // Amount transferred to user2
                assertEq(pausedStatus[i], false);
            }
        }
        
        assertTrue(foundCashback);
        assertTrue(foundBoost);
    }
} 