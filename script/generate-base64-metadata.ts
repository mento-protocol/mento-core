#!/usr/bin/env ts-node

import * as fs from 'fs';
import * as path from 'path';

/**
 * Generates base64 encoded data URIs for both SVG images and JSON metadata
 * for the MinipayMentoClaim token campaigns.
 * 
 * This script:
 * 1. Reads SVG files and encodes them as base64 data URIs
 * 2. Embeds these URIs in the corresponding JSON metadata
 * 3. Encodes the entire JSON metadata as base64 data URIs
 * 4. Outputs the final URIs that can be used directly in the smart contract
 */

// Define the campaign data
const campaigns = [
  {
    name: 'march-2025-cashback-promotions',
    svgPath: 'metadata/images/march-2025-cashback-promotions.svg',
    jsonPath: 'metadata/march-2025-cashback-promotions.json'
  },
  {
    name: 'march-2025-mp-boost',
    svgPath: 'metadata/images/march-2025-mp-boost.svg',
    jsonPath: 'metadata/march-2025-mp-boost.json'
  }
];

/**
 * Reads a file and encodes it as base64
 */
function encodeFileToBase64(filePath: string): string {
  const file = fs.readFileSync(filePath);
  return Buffer.from(file).toString('base64');
}

/**
 * Creates a data URI for an SVG image
 */
function createSvgDataUri(base64Content: string): string {
  return `data:image/svg+xml;base64,${base64Content}`;
}

/**
 * Creates a data URI for JSON metadata
 */
function createJsonDataUri(base64Content: string): string {
  return `data:application/json;base64,${base64Content}`;
}

/**
 * Processes a campaign by encoding its SVG and JSON
 */
function processCampaign(campaign: typeof campaigns[0]): void {
  console.log(`\n===== Processing Campaign: ${campaign.name} =====`);
  
  // Step 1: Encode the SVG
  console.log(`Reading SVG from: ${campaign.svgPath}`);
  const svgBase64 = encodeFileToBase64(campaign.svgPath);
  const svgDataUri = createSvgDataUri(svgBase64);
  console.log('SVG encoded as data URI');
  
  // Step 2: Read and update the JSON metadata
  console.log(`Reading JSON from: ${campaign.jsonPath}`);
  const jsonMetadata = JSON.parse(fs.readFileSync(campaign.jsonPath, 'utf8'));
  
  // Step 3: Replace the image URL with the SVG data URI
  jsonMetadata.image = svgDataUri;
  console.log('Updated JSON with embedded SVG data URI');
  
  // Step 4: Encode the entire JSON
  const jsonString = JSON.stringify(jsonMetadata, null, 2);
  const jsonBase64 = Buffer.from(jsonString).toString('base64');
  const jsonDataUri = createJsonDataUri(jsonBase64);
  
  // Step 5: Output results
  console.log('\n=== RESULTS ===');
  console.log(`\nCampaign: ${campaign.name}`);
  console.log(`\nBase64 JSON Data URI (use this as the campaign URI):`);
  console.log(jsonDataUri);
  
  // Step 6: Save the results to a file
  const outputDir = path.join('metadata', 'encoded');
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }
  
  // Save the data URI to a file
  const outputFile = path.join(outputDir, `${campaign.name}-uri.txt`);
  fs.writeFileSync(outputFile, jsonDataUri);
  console.log(`\nData URI saved to: ${outputFile}`);
}

// Main function to run the script
function main() {
  console.log('Generating base64 encoded metadata for MinipayMentoClaim campaigns');
  
  try {
    campaigns.forEach(processCampaign);
    console.log('\nAll campaigns processed successfully!');
    console.log('The generated data URIs can be used directly in the createCampaign function');
    console.log('as the campaignUri parameter instead of a remote URL.');
  } catch (error) {
    console.error('Error processing campaigns:', error);
  }
}

// Run the script
main(); 