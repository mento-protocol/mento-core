// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable gas-custom-errors, immutable-vars-naming
pragma solidity 0.8.18;

import { ERC1155 } from "openzeppelin-contracts-next/contracts/token/ERC1155/ERC1155.sol";
import { Ownable } from "openzeppelin-contracts-next/contracts/access/Ownable.sol";
import { Pausable } from "openzeppelin-contracts-next/contracts/security/Pausable.sol";
import { IERC165 } from "openzeppelin-contracts-next/contracts/utils/introspection/IERC165.sol";

/**
 * @title MiniPay Mento Claim
 * @author Mento Labs
 * @notice This contract allows us to distribute campaign-based rewards to MiniPay users
 * as soulbound ERC1155 tokens that can be claimed for cUSD
 */
contract MinipayMentoClaim is ERC1155, Ownable, Pausable {
    /**
     * @notice Campaign represents a MiniPay reward campaign
     * @param allocation The total allocation for this campaign
     * @param distributor The address of the campaign's distributor
     * @param paused Whether the campaign is paused
     * @param uri Metadata URI for the campaign
     */
    struct Campaign {
        uint256 allocation;
        address distributor;
        bool paused;
        string uri;
    }

    string public constant baseUri = "";

    /// @notice Mapping from campaign ID to Campaign struct
    mapping(bytes32 => Campaign) public campaigns;

    /// @notice Array to store all campaign IDs
    bytes32[] public campaignIds;

    /// @dev Creates a campaign ID from a string
    function getCampaignId(string memory campaignName) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(campaignName));
    }

    string public constant name = "Minipay Mento Claim";
    string public constant symbol = "MPMC";
    string public contractUri;

    /**
     * @dev Constructor for the MinipayMentoClaim token
     * @param baseUri_ The base URI for token metadata
     */
    constructor(string memory baseUri_) ERC1155(baseUri_) Ownable() {
        contractUri = string.concat(baseUri_, "/contract.json");
    }

    /**
     * @notice Creates a new campaign and mints all tokens to the campaign distributor
     * @param campaignName String identifier for the campaign (e.g. "march/2025:cashback-promotions")
     * @param allocation The total allocation for this campaign
     * @param campaignDistributor The address that will distribute tokens for this campaign
     * @param campaignUri The metadata URI for the campaign
     */
    function createCampaign(
        string memory campaignName,
        uint256 allocation,
        address campaignDistributor,
        string memory campaignUri
    ) external onlyOwner {
        require(campaignDistributor != address(0), "MinipayMentoClaim: distributor is zero address");
        
        bytes32 campaignId = getCampaignId(campaignName);
        require(campaigns[campaignId].allocation == 0, "MinipayMentoClaim: campaign already exists");
        
        campaigns[campaignId] = Campaign({
            allocation: allocation,
            distributor: campaignDistributor,
            paused: false,
            uri: campaignUri
        });
        
        campaignIds.push(campaignId);
        
        // Emit URI event for the new campaign
        emit URI(campaignUri, uint256(campaignId));
        
        // Mint the entire allocation to the campaign distributor
        if (allocation > 0) {
            _mint(campaignDistributor, uint256(campaignId), allocation, "");
        }
    }

    /**
     * @notice Changes the distributor for a campaign and transfers remaining tokens
     * @param campaignName The name of the campaign
     * @param newDistributor The new distributor address
     */
    function changeCampaignDistributor(string memory campaignName, address newDistributor) external onlyOwner {
        require(newDistributor != address(0), "MinipayMentoClaim: distributor is zero address");
        
        bytes32 campaignId = getCampaignId(campaignName);
        Campaign storage campaign = campaigns[campaignId];
        require(campaign.allocation > 0, "MinipayMentoClaim: campaign does not exist");
        
        address oldDistributor = campaign.distributor;
        require(oldDistributor != newDistributor, "MinipayMentoClaim: new distributor same as current");
        
        uint256 remainingBalance = balanceOf(oldDistributor, uint256(campaignId));
        
        // Transfer remaining tokens to the new distributor
        campaign.distributor = newDistributor;
        if (remainingBalance > 0) {
            _safeTransferFrom(oldDistributor, newDistributor, uint256(campaignId), remainingBalance, "");
        }
    }

    /**
     * @notice Increases the allocation for an existing campaign by minting additional tokens to the distributor
     * @param campaignId The ID of the campaign
     * @param additionalAllocation The additional amount to allocate
     */
    function increaseAllocation(bytes32 campaignId, uint256 additionalAllocation) external onlyOwner {
        require(additionalAllocation > 0, "MinipayMentoClaim: additional allocation must be positive");
        
        Campaign storage campaign = campaigns[campaignId];
        require(campaign.distributor != address(0), "MinipayMentoClaim: campaign does not exist");
        
        // Increase the recorded allocation
        campaign.allocation += additionalAllocation;
        
        // Mint additional tokens to the current distributor
        _mint(campaign.distributor, uint256(campaignId), additionalAllocation, "");
    }

    /**
     * @notice Pauses a campaign to prevent token transfers
     * @param campaignName The name of the campaign to pause
     */
    function pauseCampaign(string memory campaignName) external onlyOwner {
        bytes32 campaignId = getCampaignId(campaignName);
        require(campaigns[campaignId].allocation > 0, "MinipayMentoClaim: campaign does not exist");
        campaigns[campaignId].paused = true;
    }

    /**
     * @notice Unpauses a campaign
     * @param campaignName The name of the campaign to unpause
     */
    function unpauseCampaign(string memory campaignName) external onlyOwner {
        bytes32 campaignId = getCampaignId(campaignName);
        require(campaigns[campaignId].allocation > 0, "MinipayMentoClaim: campaign does not exist");
        campaigns[campaignId].paused = false;
    }

    /**
     * @notice Returns URI for token metadata by overriding ERC1155 function
     * @param tokenId The ID of the token
     * @return string URI for token metadata
     */
    function uri(uint256 tokenId) public view override returns (string memory) {
        bytes32 campaignId = bytes32(tokenId);
        require(campaigns[campaignId].allocation > 0, "MinipayMentoClaim: invalid token ID");
        return campaigns[campaignId].uri;
    }

    /**
     * @notice Set a new URI for an existing campaign
     * @param campaignName The name of the campaign
     * @param newUri The new URI for the campaign metadata
     */
    function setCampaignUri(string memory campaignName, string memory newUri) external onlyOwner {
        bytes32 campaignId = getCampaignId(campaignName);
        require(campaigns[campaignId].allocation > 0, "MinipayMentoClaim: campaign does not exist");
        
        campaigns[campaignId].uri = newUri;
        
        // Emit URI event for updated metadata
        emit URI(newUri, uint256(campaignId));
    }

    /**
     * @notice Get the amount distributed from a campaign (allocation - distributor balance)
     * @param campaignName The name of the campaign
     * @return amount The amount distributed from the campaign
     */
    function getDistributedAmount(string memory campaignName) external view returns (uint256) {
        bytes32 campaignId = getCampaignId(campaignName);
        Campaign memory campaign = campaigns[campaignId];
        require(campaign.allocation > 0, "MinipayMentoClaim: campaign does not exist");
        
        uint256 distributorBalance = balanceOf(campaign.distributor, uint256(campaignId));
        return campaign.allocation - distributorBalance;
    }

    /**
     * @notice Returns the total supply (allocation) for a token ID
     * @param tokenId The ID of the token
     * @return supply The total allocation for the campaign
     */
    function totalSupply(uint256 tokenId) external view returns (uint256) {
        bytes32 campaignId = bytes32(tokenId);
        Campaign memory campaign = campaigns[campaignId];
        require(campaign.allocation > 0, "MinipayMentoClaim: campaign does not exist");
        
        return campaign.allocation;
    }

    /**
     * @notice Returns all campaign details
     * @return campaignIds Array of campaign IDs
     * @return allocations Array of allocations
     * @return campaignDistributors Array of distributors
     * @return distributed Array of distributed amounts
     * @return pausedStatus Array of paused statuses
     */
    function getAllCampaigns() external view returns (
        bytes32[] memory,
        uint256[] memory allocations,
        address[] memory campaignDistributors,
        uint256[] memory distributed,
        bool[] memory pausedStatus
    ) {
        uint256 count = campaignIds.length;
        allocations = new uint256[](count);
        campaignDistributors = new address[](count);
        distributed = new uint256[](count);
        pausedStatus = new bool[](count);
        
        for (uint256 i = 0; i < count; i++) {
            bytes32 campaignId = campaignIds[i];
            Campaign memory campaign = campaigns[campaignId];
            
            allocations[i] = campaign.allocation;
            campaignDistributors[i] = campaign.distributor;
            pausedStatus[i] = campaign.paused;
            
            uint256 distributorBalance = balanceOf(campaign.distributor, uint256(campaignId));
            distributed[i] = campaign.allocation - distributorBalance;
        }
        
        return (campaignIds, allocations, campaignDistributors, distributed, pausedStatus);
    }

    /**
     * @dev Override to implement soulbound token functionality and handle paused campaigns
     */
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
        
        // Skip checks for minting (when from is zero address)
        if (from == address(0)) {
            return;
        }
        
        // Skip checks if the operator is the owner
        if (owner() == operator) {
            return;
        }
        
        // For non-owner operators, enforce campaign pausing rules
        for (uint256 i = 0; i < ids.length; i++) {
            bytes32 campaignId = bytes32(ids[i]);
            Campaign memory campaign = campaigns[campaignId];
            
            // Allow transfers if:
            // 1. Campaign is not paused OR
            // 2. Operator is the campaign distributor
            require(
                !campaign.paused || campaign.distributor == operator,
                "MinipayMentoClaim: transfer paused or not authorized"
            );
        }
    }
}
