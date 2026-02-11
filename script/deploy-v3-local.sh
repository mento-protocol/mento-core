#!/bin/bash
# Deploy V3 FPMM infrastructure to a local Anvil fork for UI testing
#
# This script automates the setup documented in DeployV3FPMM.s.sol

set -e

# Load environment variables from .env file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
else
    echo "Error: .env file not found at $ENV_FILE"
    exit 1
fi

# Verify required env vars are set
if [ -z "$DEPLOYER" ] || [ -z "$DEPLOYER_PK" ]; then
    echo "Error: DEPLOYER and DEPLOYER_PK must be set in .env"
    exit 1
fi

RPC_URL="http://celo-devnet.mento.org"

# Token addresses
CUSD="0x765DE816845861e75A25fCA122bb6898B8B1282a"
CKES="0x456a3D042C0DbD3db53D5489e98dFb038553B0d0"

# Whale addresses
CUSD_WHALE="0xCA31c88C2061243D70eb3a754E5D99817a311270"
CKES_WHALE="0x61Ef8708fc240DC7f9F2c0d81c3124Df2fd8829F"

# Pre-calculated FPMM pool address (from deployment)
FPMM_POOL="0xc69D6bBA6785e76998f870609345aA2BE7F64d19"

# Amount to transfer (100,000 tokens with 18 decimals)
AMOUNT="100000000000000000000000"

# 1 ETH in hex for gas funding
ONE_ETH="0xDE0B6B3A7640000"

echo "=== V3 FPMM Local Deployment Script ==="
echo ""

# Check if anvil is running
if ! cast block-number --rpc-url "$RPC_URL" &>/dev/null; then
    echo "Error: Anvil is not running at $RPC_URL"
    echo ""
    echo "Start Anvil with:"
    echo "  anvil --fork-url https://forno.celo.org --chain-id 42220 --code-size-limit 50000"
    echo ""
    echo "Or to load existing state:"
    echo "  anvil --fork-url https://forno.celo.org --chain-id 42220 --code-size-limit 50000 --load-state ./anvil-state.json"
    exit 1
fi

echo "Step 1: Fund cUSD whale and transfer cUSD to FPMM pool"
echo "  Impersonating cUSD whale: $CUSD_WHALE"
cast rpc anvil_impersonateAccount "$CUSD_WHALE" --rpc-url "$RPC_URL"

echo "  Transferring cUSD to FPMM pool: $FPMM_POOL"
cast send "$CUSD" "transfer(address,uint256)" "$FPMM_POOL" "$AMOUNT" \
    --from "$CUSD_WHALE" \
    --rpc-url "$RPC_URL" \
    --unlocked

echo ""
echo "Step 2: Fund cKES whale with native gas"
cast rpc anvil_setBalance "$CKES_WHALE" "$ONE_ETH" --rpc-url "$RPC_URL"

echo ""
echo "Step 3: Transfer cKES to FPMM pool"
echo "  Impersonating cKES whale: $CKES_WHALE"
cast rpc anvil_impersonateAccount "$CKES_WHALE" --rpc-url "$RPC_URL"

echo "  Transferring cKES to FPMM pool: $FPMM_POOL"
cast send "$CKES" "transfer(address,uint256)" "$FPMM_POOL" "$AMOUNT" \
    --from "$CKES_WHALE" \
    --rpc-url "$RPC_URL" \
    --unlocked

echo ""
echo "Step 4: Fund deployer with native gas"
cast rpc anvil_setBalance "$DEPLOYER" "$ONE_ETH" --rpc-url "$RPC_URL"

echo ""
echo "Step 5: Run forge deployment script"
FOUNDRY_PROFILE=optimized forge script script/DeployV3FPMM.s.sol:DeployV3FPMM \
    --rpc-url "$RPC_URL" \
    --private-key "$DEPLOYER_PK" \
    --broadcast \
    -vvv

echo ""
echo "Step 6: Mint liquidity to FPMM pool"
echo "  Impersonating deployer: $DEPLOYER"
cast rpc anvil_impersonateAccount "$DEPLOYER" --rpc-url "$RPC_URL"

echo "  Minting liquidity..."
cast send "$FPMM_POOL" "mint(address)" "$DEPLOYER" \
    --from "$DEPLOYER" \
    --rpc-url "$RPC_URL" \
    --unlocked

echo ""
echo "Step 7: Verify FPMM Pool Total Supply"
TOTAL_SUPPLY=$(cast call "$FPMM_POOL" "totalSupply()(uint256)" --rpc-url "$RPC_URL")
echo "  FPMM Pool total supply: $TOTAL_SUPPLY"

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "To save state for later:"
echo "  # In the anvil terminal, press Ctrl+C or run:"
echo "  # anvil --fork-url https://forno.celo.org --chain-id 42220 --code-size-limit 50000 --dump-state ./anvil-state.json"
