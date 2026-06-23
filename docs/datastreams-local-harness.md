# Data Streams verify-on-swap — local fork harness

How to run the Chainlink Data Streams verify-on-swap path **end-to-end through the dapp** on a
forked Celo mainnet, before the external blockers (B1 VerifierProxy address, B4 feedIds, a Data
Streams subscription) are resolved.

Because real DON signatures can't be minted off-chain, the harness substitutes **exactly the two
externally-blocked pieces** — a `MockVerifierProxy` on-chain and a **synthesized report** from the
server route. Everything else is the real path:

```
UI swap → /api/data-streams/swap → RouterWithReports.swapExactTokensForTokensWithReports
        → Factory.ingest → relayer.relay → MockVerifierProxy.verify → SortedOracles.report (fresh)
        → fresh oracle read → swap settles
```

This spans three repos: `mento-core` (contracts + harness), `mento-sdk` (resolver + calldata
builder, **linked** into the monorepo), `frontend-monorepo` (server route + gated swap hook).

> **Local/dev only.** Nothing here is for CI or production. The mock mode and the feature flag both
> default to **off**.

---

## 1. Prerequisites: link the local SDK into the monorepo

The app pins a published SDK that predates this work, so point it at the local checkout:

```bash
# in frontend-monorepo/package.json -> pnpm.overrides (local dev only, do NOT merge):
#   "@mento-protocol/mento-sdk": "link:../mento-sdk",
#   "viem": "2.48.4"      # align with the SDK's viem to avoid link-induced duplicate types
cd mento-sdk && pnpm build           # produce dist/ (the link resolves to dist)
cd ../frontend-monorepo && pnpm install
```

## 2. Start the fork

```bash
anvil --fork-url https://forno.celo.org --port 8545
cast rpc anvil_setIntervalMining 4   # advance block time in real time (keeps quotes/reports fresh)
```

## 3. Deploy the harness

```bash
cd mento-core
bash script/fork-harness.sh
```

It deploys `MockVerifierProxy`, the relayer factory (verifier = mock), a single-leg relayer for the
cUSD/cEUR rate feed, and `RouterWithReports`, authorizes the relayer on SortedOracles (impersonating
the owner), and **prints an env block** to paste into `apps/app.mento.org/.env`. Addresses change on
every run — the printed block is the source of truth. Example from one run:

| Contract | Address (example — re-read from the script output) |
|---|---|
| MockVerifierProxy | `0x2b5A4e5493d4a54E717057B127cf0C000C876f9B` |
| DataStreamsRelayerFactory | `0x821f3361D454cc98b7555221A06Be563a7E2E0A6` |
| DataStreamsRelayerV1 (relayer) | `0x5E9a8067b9C87E046516DCf84B90A8C6015c55AD` |
| RouterWithReports | `0x5133BBdfCCa3Eb4F739D599ee4eC45cBCD0E16c5` |

## 4. Configure the app

Append the harness env block to `apps/app.mento.org/.env` and set the fork/flags (the script prints
this for you):

```ini
NEXT_PUBLIC_USE_FORK=true
NEXT_PUBLIC_DATA_STREAMS_SWAP_ENABLED=true
DATA_STREAMS_MOCK_MODE=true
DATA_STREAMS_RELAYER_FACTORY=0x...   # factory from step 3
DATA_STREAMS_ROUTER=0x...            # RouterWithReports from step 3
```

```bash
pnpm --filter app.mento.org dev      # http://localhost:3000
```

## 5. Fund + approve the swap account, and keep the feed fresh

The swap account is **anvil[0]** (`0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`, key
`0xac0974…ff80`). Fund it with cUSD (impersonate a non-target pool that holds cUSD) and pre-approve
**both** routers (the dapp's approval step targets the old Router; the DS swap sends to
RouterWithReports):

```bash
RPC=http://localhost:8545; ME=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
CUSD=0x765DE816845861e75A25fCA122bb6898B8B1282a
WHALE=0x462fe04b4FD719Cbd04C0310365D421D02AaA19E   # cUSD/USDC FPMM pool
OLD_ROUTER=0x4861840C2EfB2b98312B0aE34d86fD73E8f9B6f6; NEW_ROUTER=<RouterWithReports>
KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
G="--legacy --gas-price 300000000000"

cast rpc anvil_impersonateAccount $WHALE --rpc-url $RPC
cast send $CUSD "transfer(address,uint256)" $ME 1000000000000000000000 --from $WHALE --unlocked $G --rpc-url $RPC
cast rpc anvil_stopImpersonatingAccount $WHALE --rpc-url $RPC
cast send $CUSD "approve(address,uint256)" $OLD_ROUTER 100000000000000000000000 --private-key $KEY $G --rpc-url $RPC
cast send $CUSD "approve(address,uint256)" $NEW_ROUTER 100000000000000000000000 --private-key $KEY $G --rpc-url $RPC
```

A background **poker** keeps the median fresh (otherwise `getAmountsOut` reverts on a stale feed). It
relays every ~2 min from **anvil[1]** (`0x70997970C51812dc3A010C7d01b50e0d17dc79C8`, so its nonces
don't clash with your swaps), back-dating `obsTs` by 60s. See the loop in the chat history / recreate
with `cast abi-encode` + `factory.ingest`.

## 6. Swap in the UI

1. Point your wallet's **Celo (42220) RPC at `http://localhost:8545`** (otherwise the send hits real
   mainnet).
2. Import the anvil[0] key.
3. Open `http://localhost:3000`, select **USDm → EURm**, enter an amount, swap. It POSTs to
   `/api/data-streams/swap`, gets the verify-on-swap calldata, estimates gas, and sends.

---

## Discovered forked-Celo addresses (reference)

| Thing | Address |
|---|---|
| SortedOracles | `0xefB84935239dAcdecF7c5bA76d8dE40b077B7b33` |
| SortedOracles owner (impersonated for `addOracle`) | `0x58099B74F4ACd642Da77b4B7966b4138ec5Ba458` |
| FactoryRegistry | `0x7b2f7d11eabD576782f77bF2CcA46a853410AdF6` |
| FPMMFactory (defaultFactory) | `0xa849b475FE5a4B5C9C3280152c7a1945b907613b` |
| Existing Router | `0x4861840C2EfB2b98312B0aE34d86fD73E8f9B6f6` |
| cUSD/cEUR FPMM pool | `0x1aD2EA06502919F935D9c09028dF73a462979e29` |
| rate feed (EUR/USD) | `0xF4f9bBdA9CD6841fCB9b1510f9269E2dB42a6e3a` |
| USDm (cUSD) / EURm (cEUR) | `0x765DE8…1282a` / `0xD8763C…6cA73` |

## Gotchas hit while building this (so they're not rediscovered)

- **Celo fork breaks EIP-1559** ("failed to get exchange rates" / "max fee per gas less than base
  fee"). Use legacy txs everywhere: `--legacy --gas-price 300000000000`. In the wallet, set the swap
  to legacy gas if it errors on fees.
- **Fork clock drift.** The fork's block time lags real time, but anvil runs `estimateGas`/txs
  against **real** time, and the SDK validates the deadline against `Date.now()`. The route therefore
  (a) builds the deadline from real time, and (b) back-dates report `obsTs` by 60s so
  `block.timestamp - obsTs` doesn't underflow and the report isn't already past `expiresAt`. Interval
  mining + the poker keep `getAmountsOut` fresh.
- **Approval spender mismatch.** The dapp approves the old Router; the DS swap targets
  RouterWithReports. Pre-approve RouterWithReports (step 5), or fix the approval flow to use the DS
  router when the flag is on.
- **`getPublicClient` is client-only** in `@repo/web3` — the server route builds its own viem client.
- **SDK ESM build** uses extensionless imports (fine for the app's bundler; native `node` ESM
  chokes). Use `require` (CJS) for one-off node scripts.

## Pre-merge checklist (none of this should ship as-is)

- [ ] `frontend-monorepo`: drop the `pnpm.overrides` SDK `link:` and the `viem` pin; consume a
      **published** SDK version instead.
- [ ] Publish the `mento-sdk` Data Streams work as a new version (don't reuse `3.3.0-beta.1`).
- [ ] Keep `DATA_STREAMS_MOCK_MODE` / `NEXT_PUBLIC_DATA_STREAMS_SWAP_ENABLED` **off** outside local
      dev; the mock branch in the route is fork-only.
- [ ] Real path still needs B1 (VerifierProxy), B4 (feedIds), a Data Streams subscription, and the
      production deploy of `DataStreamsRelayerFactory` + `RouterWithReports` (+ registry entry).
- [ ] Fix the approval flow to target the active router when the flag is on.
