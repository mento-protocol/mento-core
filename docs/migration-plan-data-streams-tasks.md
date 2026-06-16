# Data Streams Migration — Cross-Repo Task Breakdown

**Companion to:** [`migration-plan-data-streams.md`](./migration-plan-data-streams.md) and its visual [`migration-plan-data-streams.html`](./migration-plan-data-streams.html).
**Status:** WORKING DRAFT for planning. Task IDs are stable handles for tracking; estimates and owners are TBD.
**Design in one line:** keeperless pull oracle — signed Chainlink Data Streams reports verified on-chain and attached just-in-time to swaps; regional FX stays on push; the cadence-dependent EMA breaker is replaced by a slew-rate breaker.

---

## 0. How to read this

- Tasks are grouped **by repo**. Each has an ID, the plan section it traces to, its **phase** (1 = crypto + G10 FX cutover, 2 = regional FX once Chainlink ships streams, 3 = LWBA bid/ask), and blocking dependencies.
- **`[BLOCKER]`** items gate implementation — most are external/decision tasks in §1. Do not start the contracts that depend on a feedId/address/schema until the corresponding blocker clears.
- "Recommend" = the plan's recommendation; still needs a human ✔ before it's locked.

### Repos involved (grounded against the local checkout)

| Repo | Role in this migration |
|---|---|
| **mento-core** (this repo) | All on-chain contracts: relayer, factory, slew breaker, swap-side ingestion, tests |
| **mento-deployment** / **deployments-v2** | Foundry deploy scripts, BreakerBox wiring, reporter authorization, MGP governance proposals, rollback runbooks |
| **oracle-relayer** | The **existing off-chain push bot / keeper** — decommission path + the temporary dwell-only measurement harness; this is the cost center being removed |
| **mento-sdk** (+ `mento-sdk-main`) | TS client: fetch signed reports from the Data Streams API, attach to swap calldata, permissionless `relay()` helper, integrator docs |
| **mento-web** | Dapp: integrate the SDK fetch+attach into the swap flow, freshness/breaker UX, gas messaging |
| **mento-subgraph** + **mento-analytics-api** | Index `Relayed`/`BreakerTripped`/`ResetSuccessful`; divergence + keeperless-critical dashboards |
| **rebalance-bot** | *Optional* best-effort `relay()` poker (must NOT be load-bearing) |
| **mento-automation-tests** / **governance-tests** | E2E swap-with-report flows + MGP simulation tests |

> **Assumption.** Repo roles above are inferred from local repo names + the plan. Confirm the SDK package, the dapp swap path, and which deployment repo is canonical (`mento-deployment` vs `deployments-v2`) before assigning work. (TODO-REPO-1)

---

## 1. Blockers — external facts & decisions (gate everything)

These come straight from §10 of the plan. **Nothing in §3 (contracts) should be merged against guessed values.**

| ID | Task | Plan ref | Owner |
|---|---|---|---|
| **B1** `[BLOCKER]` | Confirm the exact Celo mainnet **`VerifierProxy` address** (JS-rendered docs table; verify on-chain). Do not hardcode until verified. | TODO-CL-addr | Eng + Chainlink |
| **B2** `[BLOCKER]` | Confirm `VerifierProxy` **ABI/version** on Celo, whether **`verifyBulk`** exists, and that **`s_feeManager() == address(0)`** (empty `parameterPayload`, no fee). | TODO-CL-1 | Eng + Chainlink |
| **B3** `[BLOCKER]` | Confirm **subscription terms / billing / coverage** with Chainlink Labs (no on-chain fee on Celo). | TODO-CL-2 | BD + Chainlink |
| **B4** `[BLOCKER]` | Get the definitive **`feedId`s** for every Phase-1 pair + the **report schema version** per feed (v3 vs v4 / LWBA layout). | TODO-CL-3, FID-* | Eng + Chainlink |
| **B5** `[BLOCKER]` | Confirm deployed **`SortedOracles` address** and that its `report()` path calls `checkAndSetBreakers` (lynchpin of the breaker story). | TODO-SO-1 | Eng |
| **B6** | Decide **LWBA in Phase 1 vs defer to Phase 3** (recommend defer — write mid `price` only first). | §2.1, §6 | Product |
| **B7** | Decide **migrate V2 (`Broker`/`BiPoolManager`) or freeze on push** (recommend V3 FPMM first). | §1.9, §2.6 | Eng + Product |
| **B8** `[TODO-SWAP-1]` | Decide **swap-side integration shape**. Per the §2.7 deep-read, **recommend a new `swapExactTokensForTokensWithReports` on a redeployed Router** + `Factory.ingest` — *not* a periphery wrapper (the Router is `ERC2771Context`, so a wrapper breaks `_msgSender()` token pulls) and *not* an `FPMM` change (it reverts safely without a report; `FPMM.swap` stays untouched). | §2.5, §2.7 | Eng |
| **B9** | Decide **cross-rate model**: composite-only vs also writing legs as their own feeds + `rateFeedDependencies`. | §3 | Eng |
| **B10** | Set **per-feed params**: `maxStaleness`, `maxTimestampSpread`, slew `baseJump`/`slewPerSecond`/`maxJump`, and **`cooldown > 0`**. Calibrate slew from realized volatility. | §2.3, §5.4 | Eng + Risk |
| **B11** | Confirm **keeperless gas UX** acceptable (swapper pays verify+report); decide whether to run an *optional* best-effort poker (not for correctness). | §8, §10 | Product |
| **B12** | Set **dwell time + promotion thresholds** (divergence bps, latency, false-trip rate). | TODO-GOV-1/2 | Eng + Risk |
| **B13** | Reconcile **live `rateFeedId`s + aggregator configs** against the real `mento-deployment` registry. | TODO-DEP-1 | Eng |

---

## 2. Critical path (sequencing)

```
B1–B5 (external facts)            B6–B13 (decisions)
        │                                │
        └──────────────┬─────────────────┘
                       ▼
   mento-core: C1 interfaces → C2 relayer + C3 factory + C4 slew breaker
                       │
                       ├── C5 swap-side ingestion (per B8)         ── C7/C8 tests (incl. fork vs real VerifierProxy)
                       ▼
   mento-sdk: SDK1 fetch → SDK2 attach            mento-deployment: DP1–DP3 deploy/wire
                       │                                    │
                       ▼                                    ▼
   mento-web: WEB1–WEB3            DP4 MGP-DS-1 (shadow) → oracle-relayer OR2 dwell harness
                       │                                    │
                       └──────────────┬─────────────────────┘
                                      ▼
            Indexing IDX1–IDX3 (divergence + false-trip dashboards)
                                      ▼
        DP4 MGP-DS-2 (dual-reporter) → dwell ≥ B12 → DP4 MGP-DS-4 (single-reporter cutover)
                                      ▼
        oracle-relayer OR1/OR3 decommission push bot for migrated pairs
                                      ▼
                       Phase 2 (regional FX, when B4 lands) · Phase 3 (LWBA, MGP-DS-5)
```

---

## 3. `mento-core` — contracts

| ID | Task | Phase | Plan ref | Depends on |
|---|---|---|---|---|
| **C1** | `IVerifierProxy` + `IDataStreamsRelayer` interfaces (incl. `StreamLeg`, `relay`, events). | 1 | §2.1, §2.2 | B2, B4 |
| **C2** | `DataStreamsRelayerV1`: `verify(Bulk)` → decode → bind `feedId` → invert/compose → `expiresAt`/`maxStaleness`/spread checks → `lastObservationsTimestamp` replay (idempotent `==`) → reuse `ChainlinkRelayerV1.reportRate` verbatim. | 1 | §2.2, §3, §5 | C1, B1, B4, B9 |
| **C3** | `DataStreamsRelayerFactory` (+ proxy + proxyAdmin): CREATE2 salt `keccak256("mento.dataStreamsRelayer")`, `deployRelayer`/`redeployRelayer`/`removeRelayer`, holds `sortedOracles`+`verifierProxy`. | 1 | §2.4 | C2 |
| **C4** | `MedianDeltaBreakerV2` (slew-rate): `lastMedian`/`lastReportTime` state, `allowed = min(maxJump, baseJump + slewPerSecond·Δt)` on `block.timestamp`-Δt, same `IBreaker` ABI. Linear math (no PRBMath `exp`). | 1 | §2.3 | B10 |
| **C5** | `Factory.ingest(rateFeedId, signedReports)` — non-view router resolving `rateFeedId → relayer → relay()`. Keep `OracleAdapter` pure-`view`. Shared base for every swap/rebalance pre-step. | 1 | §2.5, §2.7.4 | C3 |
| **C6** | *(only if B7 = migrate V2)* `Broker.swapIn/swapOut` payload param + pre-step `ingest`; Router update. Breaking ABI → overload/upgrade. | 2+ | §2.6 | B7, C5 |
| **C7** | Unit tests: relayer (decode/compose/invert/replay/staleness/spread/wrong-feedId) + **slew breaker vs numpy reference (≥10 scenarios)** + replay property tests + negative tests. | 1 | §7.1, §7.2, §7.5, §7.6 | C2, C4 |
| **C8** | Foundry **fork tests vs the real Celo `VerifierProxy`**, incl. the signed-report **fixture-capture flow** (capture from API, pin block / `vm.warp` inside validity). | 1 | §7.3 | C2, B1, B4 |
| **C9** | Shadow-mode comparison test: push vs pull in a fork over a captured replay; assert divergence ≤ tolerance. | 1 | §7.4 | C2, C8 |
| **C10** | NatSpec, slither/lint clean, internal review, audit hand-off package. | 1 | — | C2–C5, C11–C13 |
| **C11** | **Router: redeploy with `swapExactTokensForTokensWithReports(... , bytes[][] signedReportsPerHop)`** — ingest per hop (resolve each pool's `referenceRateFeedID`), then run the existing `getAmountsOut → _swap` body verbatim. Apply the same to `zapIn`/`zapOut`. Router is **not upgradeable** → redeploy + repoint the dapp/integrators to the new address (the Router references `FactoryRegistry`, not vice versa, so governance is only needed if an on-chain contract hardcodes the Router). | 1 | §2.7.4, §2.7.5 | C5, B8 |
| **C12** | **Liquidity-strategy `ingest`-before-`rebalance`**: `CDPLiquidityStrategy` / `ReserveLiquidityStrategy` must call `Factory.ingest` before `FPMM.rebalance` (it reads the oracle via `_getRebalancingState`). | 1 | §2.7.2 | C5 |
| **C13** | Swap-path integration tests: per-hop ingest, multi-hop with two `rateFeedId`s, OneToOneFPMM (still needs a report), stale-rate revert (`NoRecentRate`), depeg-trips-then-swap-reverts, idempotent shared-feed hop. | 1 | §2.7 | C11, C12 |

> **Note (C4 clock):** the slew breaker uses `block.timestamp` between on-chain reports (objective/ungameable), not `observationsTimestamp`; the relayer still uses decoded `observationsTimestamp` for replay/staleness. See §2.3 clock note.

---

## 4. `mento-deployment` / `deployments-v2` — deploy & governance

| ID | Task | Phase | Plan ref | Depends on |
|---|---|---|---|---|
| **DP1** | Deploy scripts: `DataStreamsRelayerFactory` (impl+proxy+admin) initialized with `sortedOracles`, `verifierProxy` (B1), `relayerDeployer`; one relayer per Phase-1 `rateFeedId` via CREATE2. | 1 | §9 | C3, B1, B13 |
| **DP2** | BreakerBox wiring: add `MedianDeltaBreakerV2`, toggle per feed, set `baseJump`/`slewPerSecond`/`maxJump`/**`cooldown > 0`** + `maxStaleness`. | 1 | §9 | C4, B10 |
| **DP3** | Authorize each `DataStreamsRelayerV1` as a `SortedOracles` reporter (dual-reporter alongside push). | 1 | §9 | DP1 |
| **DP4** | Draft + simulate governance proposals: **MGP-DS-1** (shadow) → **DS-2** (dual-reporter) → **DS-3** (adopt slew breaker + params) → **DS-4** (single-reporter cutover) → **DS-5** (Phase 3 LWBA). | 1→3 | §9 | DP1–DP3 |
| **DP5** | **Rollback runbook + scripts**: re-authorize push relayer (kept warm), `BreakerBox.setRateFeedTradingMode` halt, revert reporter set. | 1 | §9 | DP3 |
| **DP6** | Reconcile live `rateFeedId`s, aggregator configs, and which pairs are actually live on Celo mainnet (the registry of record). | 1 | §6 | B13 |

---

## 5. `oracle-relayer` — existing off-chain service (the cost center being removed)

| ID | Task | Phase | Plan ref | Depends on |
|---|---|---|---|---|
| **OR1** | Per-migrated-pair **decommission plan** for the push bot; keep it warm through the dwell window + one period post-cutover (rollback safety). | 1 | §9 | DP4 |
| **OR2** | Build the **temporary, single-region dwell-only measurement harness** that submits `relay()` on a fixed cadence purely to generate pull-side data for divergence comparison. **Hard requirement: turned off permanently at single-reporter cutover** — not the steady state. | 1 | §9 | C2, SDK1 |
| **OR3** | Remove keeper/heartbeat code paths for migrated pairs; ensure no steady-state keeper remains (no steady-state keeper is the goal). Keep push relay logic only for Phase-2 pairs. | 1→2 | §4, §8 | OR1 |

---

## 6. `mento-sdk` — client library

| ID | Task | Phase | Plan ref | Depends on |
|---|---|---|---|---|
| **SDK1** | `fetchReports(rateFeedId) → bytes[]`: Data Streams REST/WebSocket client that returns the freshest signed report(s) for a pair's `feedId` legs. | 1 | §8 | B2, B4 |
| **SDK2** | Swap helpers that build `swapExactTokensForTokensWithReports` calldata: resolve each hop's `rateFeedId`, align `bytes[][] signedReportsPerHop`, fetch the matching reports (incl. OneToOneFPMM hops, which still need one). | 1 | §2.7.4, §8 | SDK1, C11, B8 |
| **SDK3** | Permissionless `relay()`/`Factory.ingest` helper for integrators & recovery (anyone can unstick a feed). | 1 | §4.5, §8 | SDK1, C5 |
| **SDK4** | Integrator docs: **view-only readers must `relay()` first or tolerate `NoRecentRate`** in quiet markets; gas expectations. | 1 | §4.5, §8 | SDK2 |
| **SDK5** | **Quoting without an on-chain fresh rate** (§2.7.6): `getAmountsOut`/`getAmountOut` now revert when stale. Provide off-chain quoting from the fetched report **and/or** an `eth_call` state-override simulation of `…WithReports` (ingest-then-quote). | 1 | §2.7.6 | SDK1, C11 |

---

## 7. `mento-web` — dapp

| ID | Task | Phase | Plan ref | Depends on |
|---|---|---|---|---|
| **WEB1** | Integrate SDK fetch+attach into the swap flow (every migrated-pair swap carries a fresh report). | 1 | §8 | SDK2 |
| **WEB2** | Freshness + breaker UX: pre-quote `relay()` when needed; clear states for tripped/`NoRecentRate`/stale; retry-with-refresh on `StaleReport`/`SpreadTooHigh`. | 1 | §4, §8 | WEB1 |
| **WEB3** | Gas UX messaging — surface that the swapper pays verification gas (per-swap, not Mento-subsidized). | 1 | §8, B11 | WEB1, B11 |

---

## 8. `mento-subgraph` + `mento-analytics-api` — observability

| ID | Task | Phase | Plan ref | Depends on |
|---|---|---|---|---|
| **IDX1** | Index `Relayed` (+ `via`), `ReportSkippedIdempotent`, `BreakerTripped`, `ResetSuccessful`. | 1 | §8 | C2, C4 |
| **IDX2** | **Divergence dashboard** (pull vs push) for the dwell window — the gate for promotion. | 1 | §7.4, §9 | IDX1, OR2 |
| **IDX3** | Keeperless-critical metrics: **false-trip rate from sparse/irregular sampling** (≈0 expected), **time-to-recovery** for tripped feeds, verify success rate + gas/swap. | 1 | §8, §9 | IDX1 |

---

## 9. `mento-automation-tests` / `governance-tests` — E2E & governance

| ID | Task | Phase | Plan ref | Depends on |
|---|---|---|---|---|
| **T1** | E2E swap-with-report on testnet/fork: fetch real signed report → swap → assert rate written, breaker evaluated, swap settles. | 1 | §7.3 | SDK2, C5 |
| **T2** | Governance simulation tests for MGP-DS-1..5 (proposal executes, reporters authorized, breaker wired, params set). | 1→3 | §9 | DP4 |
| **T3** | Recovery test: induce a trip, confirm a permissionless `relay()` and a plain swap attempt un-trip it after cooldown — no keeper. | 1 | §4.5, §9 | C4, SDK3 |

---

## 10. Phase rollups

- **Phase 1 (crypto + G10 FX cutover):** B1–B5, B8–B12 → C1–C5, C7–C10 → SDK1–SDK4 → WEB1–WEB3 → DP1–DP6 → IDX1–IDX3 → OR1–OR3 → T1–T3 → MGP-DS-1→2→4 with dwell.
- **Phase 2 (regional FX):** re-run B4/FID-* per pair as Chainlink ships streams; reuse C2/C3 (new relayer instances), DP1–DP4; optionally C6 if V2 in scope. Pairs without streams stay on push (no work beyond keeping `oracle-relayer` running for them).
- **Phase 3 (LWBA bid/ask):** B6 if deferred → `OracleAdapter` bid/ask exposure (new mento-core task **C11**, scoped later) → DP4 MGP-DS-5 → SDK/WEB surfacing.

---

## 11. Quick checklist (copy into a tracker)

```
[ ] B1  Celo VerifierProxy address verified on-chain
[ ] B2  VerifierProxy ABI/verifyBulk/feeManager==0 confirmed
[ ] B3  Chainlink subscription terms confirmed
[ ] B4  Phase-1 feedIds + report schema version confirmed
[ ] B5  SortedOracles address + report()->checkAndSetBreakers confirmed
[ ] B6  LWBA Phase 1 vs Phase 3 decided
[ ] B7  V2 migrate vs freeze decided
[ ] B8  Swap-side integration shape decided
[ ] B9  Cross-rate model decided
[ ] B10 Per-feed params set (incl. cooldown > 0)
[ ] B11 Keeperless gas UX confirmed; optional poker decided
[ ] B12 Dwell time + promotion thresholds set
[ ] B13 Live rateFeedIds/aggregator configs reconciled
[ ] C1  Interfaces        [ ] C2  Relayer        [ ] C3  Factory
[ ] C4  Slew breaker      [ ] C5  Factory.ingest [ ] C6  Broker/V2 (if)
[ ] C7  Unit tests        [ ] C8  Fork tests     [ ] C9  Shadow test   [ ] C10 Audit prep
[ ] C11 Router +WithReports (redeploy)  [ ] C12 Liq-strategy ingest  [ ] C13 Swap-path integration tests
[ ] DP1 Deploy scripts    [ ] DP2 Breaker wiring [ ] DP3 Authorize reporters
[ ] DP4 MGP-DS-1..5       [ ] DP5 Rollback runbook [ ] DP6 Registry reconcile
[ ] OR1 Push decommission [ ] OR2 Dwell harness  [ ] OR3 Remove keeper paths
[ ] SDK1 fetchReports     [ ] SDK2 attach (per-hop) [ ] SDK3 relay helper [ ] SDK4 integrator docs [ ] SDK5 quoting
[ ] WEB1 swap integrate   [ ] WEB2 freshness UX  [ ] WEB3 gas UX
[ ] IDX1 events           [ ] IDX2 divergence    [ ] IDX3 keeperless metrics
[ ] T1  E2E swap          [ ] T2  gov sim        [ ] T3  recovery test
```
