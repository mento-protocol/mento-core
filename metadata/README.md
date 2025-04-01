# MiniPay Mento Campaign Metadata

This directory contains metadata files for the MiniPay Mento campaigns. These files are used to display campaign information in wallets and other applications that support ERC1155 tokens.

## Directory Structure

```
metadata/
├── README.md
├── march-2025-cashback-promotions.json
├── march-2025-mp-boost.json
└── images/
    ├── march-2025-cashback-promotions.svg
    ├── march-2025-mp-boost.svg
```

## Metadata Structure

Each campaign metadata file is a JSON document with the following structure:

```json
{
  "description": "Description of the campaign, explaining its purpose and benefits.",
  "image": "ipfs://QmHashPlaceholder/campaign-image.svg",
  "name": "Campaign Name",
  "attributes": [
    {
      "trait_type": "Campaign Type",
      "value": "Type (e.g., Cashback, Boost)"
    },
    {
      "trait_type": "Season",
      "value": "Time period (e.g., March 2025)"
    },
    {
      "trait_type": "Redeem Currency",
      "value": "Mento"
    },
    {
      "trait_type": "Sponsor",
      "value": "Sponsoring organization"
    },
    {
      "trait_type": "Category",
      "value": "Category (e.g., Rewards, Loyalty)"
    }
  ],
  "external_url": "URL to campaign page",
  "background_color": "Hex code without the # prefix"
}
```

## Campaign Images

The campaign images are stored as SVG files in the `images` directory. These are vector graphics that can be rendered at any size without loss of quality. They are referenced in the metadata JSON files using IPFS URIs.

### Image Requirements

- **Format**: SVG (Scalable Vector Graphics)
- **Size**: 800x600 pixels viewport
- **File Size**: Keep under 100KB if possible
- **Hosting**: Will be hosted on IPFS, with the hash replacing the `QmHashPlaceholder` in the metadata files

### Current Campaign Images

#### 1. March 2025 Cashback Promotions

- **Color Scheme**: Green (#3BDE7C)
- **Main Elements**: Wallet icon with coins, dollar symbols, cashback theme
- **Key Attributes**: Showcases campaign type (Cashback), season (March 2025), and redemption currency (Mento)

#### 2. March 2025 MP Boost

- **Color Scheme**: Blue (#4A90E2)
- **Main Elements**: Rocket icon, upward motion theme
- **Key Attributes**: Showcases campaign type (Boost), season (March 2025), and redemption currency (Mento)

## Hosting Guidelines

Before deployment, these files should be:

1. Upload all SVG files to IPFS
2. Update the metadata JSON files with the correct IPFS URIs
3. Upload the updated metadata JSON files to IPFS or a reliable CDN
4. Ensure the baseURI in the MinipayMentoClaim contract points to the metadata hosting location

## Usage with MinipayMentoClaim

The MinipayMentoClaim contract uses the `tokenURI` function to return the URI for a given token ID. This function concatenates the base URI with the token ID to form the complete URI.

For example, if the base URI is `ipfs://QmHash/` and the token ID is `1`, the complete URI would be `ipfs://QmHash/1`. 