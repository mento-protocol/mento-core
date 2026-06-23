#!/usr/bin/env bash
# Local-fork-only: stand up a Data Streams stack on a forked Celo mainnet (anvil on :8545) so the
# verify-on-swap path can be exercised through the dapp with a MockVerifierProxy + synthesized
# reports. Prints an env block to paste into apps/app.mento.org/.env.
set -euo pipefail

RPC="${RPC:-http://localhost:8545}"
# anvil account[0] (deployer)
DEPLOYER_KEY="${DEPLOYER_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
# Celo fork can't serve EIP-1559 exchange-rate state -> force legacy txs with a fixed gas price.
LEGACY=(--legacy --gas-price 300000000000)

# Forked Celo mainnet addresses (discovered live).
export HARNESS_SORTED_ORACLES="${HARNESS_SORTED_ORACLES:-0xefB84935239dAcdecF7c5bA76d8dE40b077B7b33}"
SO_OWNER="${SO_OWNER:-0x58099B74F4ACd642Da77b4B7966b4138ec5Ba458}"
FACTORY_REGISTRY="${FACTORY_REGISTRY:-0x7b2f7d11eabD576782f77bF2CcA46a853410AdF6}"
FPMM_FACTORY="${FPMM_FACTORY:-0xa849b475FE5a4B5C9C3280152c7a1945b907613b}"
export HARNESS_RATE_FEED="${HARNESS_RATE_FEED:-0xF4f9bBdA9CD6841fCB9b1510f9269E2dB42a6e3a}" # cUSD/cEUR

echo "==> 1/4 Deploying MockVerifierProxy + factory + relayer (forge script)..."
OUT=$(forge script script/DeployDataStreamsForkHarness.s.sol --rpc-url "$RPC" --broadcast --private-key "$DEPLOYER_KEY" "${LEGACY[@]}" -vv)
echo "$OUT" | grep -E '^\s*HARNESS_' || true

VERIFIER=$(echo "$OUT" | grep -oE 'HARNESS_MOCK_VERIFIER=0x[0-9a-fA-F]{40}' | head -1 | cut -d= -f2)
FACTORY=$(echo "$OUT" | grep -oE 'HARNESS_RELAYER_FACTORY=0x[0-9a-fA-F]{40}' | head -1 | cut -d= -f2)
RELAYER=$(echo "$OUT" | grep -oE 'HARNESS_RELAYER=0x[0-9a-fA-F]{40}' | head -1 | cut -d= -f2)
LEG_FEED_ID=$(echo "$OUT" | grep -oE 'HARNESS_LEG_FEED_ID=0x[0-9a-fA-F]{64}' | head -1 | cut -d= -f2)
[ -n "$FACTORY" ] && [ -n "$RELAYER" ] || { echo "ERROR: failed to parse deployed addresses"; exit 1; }

echo "==> 2/4 Deploying RouterWithReports (forge create)..."
ROUTER=$(forge create contracts/swap/router/RouterWithReports.sol:RouterWithReports \
  --rpc-url "$RPC" --private-key "$DEPLOYER_KEY" --broadcast "${LEGACY[@]}" \
  --constructor-args 0x0000000000000000000000000000000000000000 "$FACTORY_REGISTRY" "$FPMM_FACTORY" "$FACTORY" \
  | grep -oE 'Deployed to: 0x[0-9a-fA-F]{40}' | head -1 | grep -oE '0x[0-9a-fA-F]{40}')
[ -n "$ROUTER" ] || { echo "ERROR: RouterWithReports deploy failed"; exit 1; }

echo "==> 3/4 Authorizing relayer on SortedOracles (impersonate owner)..."
cast rpc anvil_setBalance "$SO_OWNER" 0xDE0B6B3A7640000 --rpc-url "$RPC" >/dev/null
cast rpc anvil_impersonateAccount "$SO_OWNER" --rpc-url "$RPC" >/dev/null
cast send "$HARNESS_SORTED_ORACLES" "addOracle(address,address)" "$HARNESS_RATE_FEED" "$RELAYER" \
  --from "$SO_OWNER" --unlocked "${LEGACY[@]}" --rpc-url "$RPC" >/dev/null
cast rpc anvil_stopImpersonatingAccount "$SO_OWNER" --rpc-url "$RPC" >/dev/null
echo "    oracles now: $(cast call "$HARNESS_SORTED_ORACLES" 'getOracles(address)(address[])' "$HARNESS_RATE_FEED" --rpc-url "$RPC")"

echo "==> 4/4 Done. Add this to apps/app.mento.org/.env and restart the dev server:"
cat <<ENV

# ---- Data Streams local-fork harness ----
NEXT_PUBLIC_USE_FORK=true
NEXT_PUBLIC_DATA_STREAMS_SWAP_ENABLED=true
DATA_STREAMS_MOCK_MODE=true
DATA_STREAMS_RELAYER_FACTORY=$FACTORY
DATA_STREAMS_ROUTER=$ROUTER
# (informational)
# MockVerifierProxy=$VERIFIER  Relayer=$RELAYER  legFeedId=$LEG_FEED_ID  pool rateFeed=$HARNESS_RATE_FEED
ENV
