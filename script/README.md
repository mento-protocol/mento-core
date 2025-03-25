# Deployment Guide

This guide will walk you through deploying the implementation contracts and then the proxy contracts, including setting up your `.env` file.

## Step 1: Set Up Your Environment

1. **Create a `.env` File**: Copy the `.env.example` file to `.env` and fill in the necessary values. Here's a template based on the provided scripts:

   ```plaintext
   # .env.example
   PRIVATE_KEY=your_private_key_here
   AVATAR=0xYourAvatarAddress
   CUSD=0xYourCUSDAddress
   GOODDOLLAR=0xYourGoodDollarAddress
   ENV=your_environment_name
   DISTRIBUTION_HELPER=0xYourDistributionHelperAddress
   EXCHANGEPROVIDER_IMPL=0xYourExchangeProviderImplAddress
   EXPANSIONCONTROLLER_IMPL=0xYourExpansionControllerImplAddress
   RESERVE_IMPL=0xYourReserveImplAddress
   BROKER_IMPL=0xYourBrokerImplAddress
   ```

2. **Fill in the `.env` File**: Replace the placeholders with actual values. Ensure your private key is secure and not shared publicly.

## Step 2: Deploy Implementation Contracts

1. **Run the Implementation Deployment Script**: Use the `DeployGoodDollarImpl.s.sol` script to deploy the implementation contracts.

   ```bash
   forge script script/DeployGoodDollarImpl.s.sol --rpc-url <your_rpc_url> --broadcast
   ```

   This script will deploy the following contracts:
   - `GoodDollarExchangeProvider`
   - `GoodDollarExpansionController`
   - `Reserve`
   - `Broker`

2. **Log the Deployed Addresses**: The script will output the addresses of the deployed implementation contracts. Update your `.env` file with these addresses.

## Step 3: Deploy Proxy Contracts

1. **Run the Proxy Deployment Script**: Use the `DeployGoodDollar.sol` script to deploy the proxy contracts.

   ```bash
   forge script script/DeployGoodDollar.sol --rpc-url <your_rpc_url> --broadcast
   ```

   This script will deploy the following proxies:
   - `GoodDollarExchangeProviderProxy`
   - `GoodDollarExpansionControllerProxy`
   - `ReserveProxy`
   - `BrokerProxy`

2. **Initialize the Proxies**: The script will also initialize the proxies with the necessary parameters. Ensure that the initialization parameters in the script are correct for your deployment.

## Step 4: Verify Contracts

1. **Run the Verification Script**: Use the `verify.sh` script to verify the deployed contracts on CeloScan or Sourcify.

   ```bash
   bash script/verify.sh
   ```

   Ensure that your `.env` file contains the `CELOSCAN_KEY` for verification.

## Summary

- **Environment Setup**: Ensure your `.env` file is correctly configured.
- **Deploy Implementations**: Use `DeployGoodDollarImpl.s.sol` to deploy implementation contracts.
- **Deploy Proxies**: Use `DeployGoodDollar.sol` to deploy and initialize proxy contracts.
- **Verify Contracts**: Use `verify.sh` to verify contracts on CeloScan or Sourcify.

This guide provides a structured approach to deploying and verifying your contracts using Foundry. Make sure to replace placeholders with actual values and verify each step for successful deployment.
