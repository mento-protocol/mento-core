// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {Script} from "forge-std/Script.sol";
import {MinipayMentoClaim} from "contracts/governance/MinipayMentoClaim.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @title DeployMentoClaimToken
 * @notice Script to deploy the MinipayMentoClaim token and create campaigns
 * Usage:
 *   forge script script/DeployMentoClaimToken.sol --rpc-url <RPC_URL> --broadcast
 *   Environment variables:
 *    - CELO_DEPLOYER_PK: Private key of the deployer
 *    - BASE_URI (optional): Base URI for token metadata
 *    - CASHBACK_URI (optional): URI for the cashback campaign metadata 
 *    - BOOST_URI (optional): URI for the boost campaign metadata
 *    - NUM_RECIPIENTS (optional): Number of random recipients for test disbursements
 */
contract DeployMentoClaimToken is Script {
    // Default values if not provided in environment
    string private constant _DEFAULT_BASE_URI = "";
    uint256 private constant _CAMPAIGN_ALLOCATION = 100_000 * 1e18; // 100k tokens per campaign
    uint256 private constant _DEFAULT_NUM_RECIPIENTS = 5; // Default number of test recipients
    
    // Campaign constants
    string private constant _CASHBACK_CAMPAIGN = "march/2025:cashback-promotions";
    string private constant _BOOST_CAMPAIGN = "march/2025:mp-boost";
    
    // Default URI constants (used if not provided in environment)
    string private constant _DEFAULT_CASHBACK_URI = 
        "https://storage.googleapis.com/mento-dev-bucket/minipay-campaigns/march-2025-cashback-promotions.json";
    string private constant _DEFAULT_BOOST_URI = 
        "https://storage.googleapis.com/mento-dev-bucket/minipay-campaigns/march-2025-mp-boost.json";

    function run() public {
        // Load private key from environment
        uint256 deployerPrivateKey = vm.envUint("CELO_DEPLOYER_PK");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Get URIs from environment or use defaults
        string memory baseUri = vm.envOr("BASE_URI", _DEFAULT_BASE_URI);
        string memory cashbackUri = vm.envOr("CASHBACK_URI", _DEFAULT_CASHBACK_URI);
        string memory boostUri = vm.envOr("BOOST_URI", _DEFAULT_BOOST_URI);
        
        // Get number of random recipients
        uint256 numRecipients = vm.envOr("NUM_RECIPIENTS", _DEFAULT_NUM_RECIPIENTS);
        
        // Log deployment info
        console2.log("Deploying MinipayMentoClaim with base URI:", baseUri);
        console2.log("Deployer/Owner/Distributor:", deployer);
        console2.log("Campaign allocation:", _CAMPAIGN_ALLOCATION / 1e18, "tokens per campaign");
        console2.log("Number of test recipients:", numRecipients);
        console2.log("Cashback campaign URI:", cashbackUri);
        console2.log("Boost campaign URI:", boostUri);
        
        // Start broadcast with the loaded private key
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the MinipayMentoClaim token
        MinipayMentoClaim claimToken = new MinipayMentoClaim(baseUri);
        console2.log("MinipayMentoClaim deployed at:", address(claimToken));
        
        // Create cashback campaign with deployer as distributor
        bytes32 cashbackId = _createCampaign(
            claimToken, 
            _CASHBACK_CAMPAIGN, 
            0,
            deployer, 
            cashbackUri
        );

        claimToken.increaseAllocation(cashbackId, _CAMPAIGN_ALLOCATION);
        console2.log("Cashback campaign total supply:", claimToken.totalSupply(uint256(cashbackId)) / 1e18, "tokens");

        // Create boost campaign with deployer as distributor
        bytes32 boostId = _createCampaign(
            claimToken, 
            _BOOST_CAMPAIGN, 
            _CAMPAIGN_ALLOCATION, 
            deployer, 
            boostUri
        );

        claimToken.increaseAllocation(boostId, _CAMPAIGN_ALLOCATION);
        console2.log("Boost campaign total supply:", claimToken.totalSupply(uint256(boostId)) / 1e18, "tokens");
        
        // Create and distribute to random recipients
        address[] memory recipients = _generateRandomRecipients(numRecipients);
        _distributeTokens(claimToken, recipients, cashbackId, boostId, deployer);
        
        vm.stopBroadcast();
    }
    
    /**
     * @notice Creates a campaign and logs the result
     */
    function _createCampaign(
        MinipayMentoClaim claimToken,
        string memory campaignName,
        uint256 allocation,
        address distributor,
        string memory uri
    ) internal returns (bytes32) {
        claimToken.createCampaign(
            campaignName,
            allocation,
            distributor,
            uri
        );
        
        bytes32 campaignId = claimToken.getCampaignId(campaignName);
        console2.log("Created campaign:", campaignName);
        console2.log("Campaign ID:", vm.toString(campaignId));
        
        return campaignId;
    }
    
    /**
     * @notice Generates an array of random recipient addresses
     */
    function _generateRandomRecipients(uint256 count) internal returns (address[] memory) {
        address[] memory recipients = new address[](count);
        
        for (uint256 i = 0; i < count; i++) {
            // Generate random private key and derive address
            uint256 privateKey = uint256(keccak256(abi.encodePacked("recipient", i, block.timestamp)));
            address recipient = vm.addr(privateKey);
            recipients[i] = recipient;
            
            console2.log("Generated recipient", i, ":", recipient);
        }
        
        return recipients;
    }
    
    /**
     * @notice Distributes tokens from both campaigns to recipients
     */
    function _distributeTokens(
        MinipayMentoClaim claimToken, 
        address[] memory recipients, 
        bytes32 cashbackId, 
        bytes32 boostId,
        address distributor
    ) internal {
        for (uint256 i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];
            
            // Calculate random amounts (between 100 and 1000 tokens)
            uint256 cashbackAmount = (100 + uint256(keccak256(abi.encodePacked("cashback", recipient))) % 900) * 1e18;
            uint256 boostAmount = (100 + uint256(keccak256(abi.encodePacked("boost", recipient))) % 900) * 1e18;
            
            // Transfer tokens using the distributor address
            claimToken.safeTransferFrom(distributor, recipient, uint256(cashbackId), cashbackAmount, "");
            claimToken.safeTransferFrom(distributor, recipient, uint256(boostId), boostAmount, "");
            
            console2.log("Distributed to", recipient);
            console2.log("  Cashback tokens:", cashbackAmount / 1e18);
            console2.log("  Boost tokens:", boostAmount / 1e18);
        }
    }
}
