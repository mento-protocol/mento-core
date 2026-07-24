#!/usr/bin/env bash
# Deploy the Data Streams pull-oracle stack to the Celo Sepolia devnet (Anvil fork)
# and authorize the EUR/USD relayer as a SortedOracles reporter — no private keys
# needed: the fork impersonates the owner EOA.
#
# Usage:
#   ./script/devnet-deploy-datastreams.sh [RPC_URL]
#
# Default RPC is the team devnet. Works against any Celo Sepolia Anvil fork
# (e.g. a local `anvil --fork-url https://forno.celo-sepolia.celo-testnet.org`).
set -euo pipefail

RPC="${1:-http://34.32.22.77:8545}"
OWNER=0x2738F38Fde510743e0c589415E0598C4ceE6eAa7   # owns SortedOracles + BreakerBox on Celo Sepolia
SORTED_ORACLES=0xfaa7Ca2B056E60F6733aE75AA0709140a6eAfD20
RATE_FEED_EUR_USD=0x5D5a22116233BDb2a9C2977279cC348B8b8Ce917
# Celo forks reject EIP-1559 estimation quirks; use legacy txs priced above base fee.
GAS_PRICE=2000gwei

cd "$(dirname "$0")/.."

echo "== Devnet: $RPC (chain $(cast chain-id --rpc-url "$RPC"))"

echo "== Impersonating owner $OWNER"
cast rpc anvil_impersonateAccount "$OWNER" --rpc-url "$RPC" > /dev/null

echo "== Deploying Data Streams stack (adapter, factory, EUR/USD relayer, breaker + wiring)"
forge script script/DeployDataStreamsCeloSepolia.s.sol:DeployDataStreamsCeloSepolia \
  --rpc-url "$RPC" \
  --sender "$OWNER" \
  --unlocked \
  --legacy \
  --with-gas-price "$GAS_PRICE" \
  --broadcast

BROADCAST=broadcast/DeployDataStreamsCeloSepolia.s.sol/11142220/run-latest.json
FACTORY=$(python3 -c "
import json
txs = json.load(open('$BROADCAST'))['transactions']
# contractName may carry a compiler-version suffix, e.g. 'PullOracleRelayerFactoryProxy.0.8.19'
print(next(t['contractAddress'] for t in txs
           if t.get('transactionType') == 'CREATE'
           and (t.get('contractName') or '').startswith('PullOracleRelayerFactoryProxy')))
")
RELAYER=$(cast call "$FACTORY" "getRelayer(address)(address)" "$RATE_FEED_EUR_USD" --rpc-url "$RPC")

echo "== Factory (proxy): $FACTORY"
echo "== EUR/USD relayer: $RELAYER"

echo "== Authorizing relayer as SortedOracles reporter"
cast send "$SORTED_ORACLES" "addOracle(address,address)" "$RATE_FEED_EUR_USD" "$RELAYER" \
  --rpc-url "$RPC" --from "$OWNER" --unlocked --legacy --gas-price "$GAS_PRICE" > /dev/null

echo "== Reporters now on EUR/USD:"
cast call "$SORTED_ORACLES" "getOracles(address)(address[])" "$RATE_FEED_EUR_USD" --rpc-url "$RPC"

echo "== Grafting RouterWithReports onto the registry Router (devnet-only anvil_setCode)"
# The Router is immutable by design; in production a fresh RouterWithReports is deployed and
# integrators repoint. On the devnet we graft its code onto the registry address instead, so the
# SDK/frontend work unmodified. Constructor params mirror the live router's immutables.
ROUTER=0xcf6cD45210b3ffE3cA28379C4683F1e60D0C2CCd
FACTORY_REGISTRY=$(cast call "$ROUTER" "factoryRegistry()(address)" --rpc-url "$RPC")
DEFAULT_FACTORY=$(cast call "$ROUTER" "defaultFactory()(address)" --rpc-url "$RPC")
ANVIL0=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
ANVIL0_PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80  # anvil default key, not a secret
TWIN=$(forge create --rpc-url "$RPC" --private-key "$ANVIL0_PK" --legacy --gas-price "$GAS_PRICE" --broadcast \
  contracts/swap/router/RouterWithReports.sol:RouterWithReports \
  --constructor-args 0x0000000000000000000000000000000000000000 "$FACTORY_REGISTRY" "$DEFAULT_FACTORY" "$FACTORY" \
  | grep "Deployed to:" | awk '{print $3}')
cast rpc anvil_setCode "$ROUTER" "$(cast code "$TWIN" --rpc-url "$RPC")" --rpc-url "$RPC" > /dev/null
[ "$(cast call "$ROUTER" "pullOracleRelayerFactory()(address)" --rpc-url "$RPC")" = "$FACTORY" ] \
  && echo "== Router graft OK (pullOracleRelayerFactory -> $FACTORY)"

echo "== Funding anvil account 0 with USDm for swap testing"
USDM=0xdE9e4C3ce781b4bA68120d6261cbad65ce0aB00b
cast send "$USDM" "transfer(address,uint256)(bool)" "$ANVIL0" 1000000000000000000 \
  --from "$OWNER" --unlocked --legacy --gas-price "$GAS_PRICE" --rpc-url "$RPC" > /dev/null
cast send "$USDM" "approve(address,uint256)(bool)" "$ROUTER" 100000000000000000000 \
  --private-key "$ANVIL0_PK" --legacy --gas-price "$GAS_PRICE" --rpc-url "$RPC" > /dev/null

cast rpc anvil_stopImpersonatingAccount "$OWNER" --rpc-url "$RPC" > /dev/null
echo "== Done. Factory=$FACTORY Relayer=$RELAYER Router(grafted)=$ROUTER"
