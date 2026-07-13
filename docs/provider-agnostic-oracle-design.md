# Provider-Agnostic Pull-Oracle Design

**Status:** Implemented on-chain (mento-core) for the Chainlink adapter; SDK generalization next.
Extends the Chainlink Data Streams migration plan toward a provider-neutral architecture (Chainlink
Data Streams today; Pyth, RedStone, and others next).

**Implementation notes (deviations from the original draft):**

1. The adapter interface is named **`IPullOracleAdapter`** — `IOracleAdapter` was already taken by
   the FPMM's read-side oracle adapter in Mento V3.
2. **Exact-fee match, no refunds**: the router reverts `FeeMismatch` unless `msg.value` exactly
   equals the sum of per-hop `verificationFee`s (no mid-swap native transfer back to the caller →
   no reentrancy surface). The SDK precomputes the total.
3. The phased A/B migration was collapsed into one step — nothing was deployed to a real network,
   so the target shape (adapter + opaque payable `updateData` + neutral names) shipped directly.

**Goal:** Decouple the pull-oracle path from Chainlink so any signed-data provider can feed the same
`SortedOracles` sink through one shared interface — on-chain and in the SDK — without touching the
composition, breaker, or swap-settlement logic.

---

## 1. Why: the current coupling

The verify-on-swap path we shipped is correct but Chainlink-specific at three layers:

| Layer | Chainlink coupling (today) | File |
| --- | --- | --- |
| SDK fetch | `DataStreamsClient` — Chainlink REST + HMAC auth | `mento-sdk/src/services/dataStreams/DataStreamsClient.ts` |
| SDK decode | V3/V8 report-schema decode (`midPrice`, slot layout) | same |
| SDK build | `fetchReportsForPools` → `bytes[][] signedReportsPerHop` | `mento-sdk/src/services/dataStreams/DataStreamsService.ts`, `SwapService.ts` |
| On-chain verify | `IVerifierProxy.verifyBulk(payloads, parameterPayload)` | `contracts/oracles/DataStreamsRelayerV1.sol` |
| On-chain decode | `decodeReport` — Chainlink report struct (schema-aware slot read) | same |
| On-chain shape | `StreamLeg{bytes32 feedId; bool invert}`, `relay(bytes[] signedReports, bytes parameterPayload)` | `IDataStreamsRelayer.sol` |
| Router | `swapExactTokensForTokensWithReports(..., bytes[][] signedReportsPerHop)` → `factory.ingest` | `RouterWithReports.sol` |

Everything downstream of the decoded `(price, observationsTimestamp)` is already provider-neutral:
the UD60x18 multiply/invert composition, the 1e18→1e24 scaling, the `reportRate` lesser/greater-key
write to `SortedOracles`, and the `MedianDeltaBreakerV2` slew breaker. **Those stay untouched.**

---

## 2. How the providers actually differ

Researched Chainlink Data Streams, Pyth, and RedStone (July 2026). The mechanics differ, but there is
one shared shape that fits all three.

| Aspect | Chainlink Data Streams | Pyth | RedStone (Core/Pull) |
| --- | --- | --- | --- |
| Off-chain fetch | REST API + HMAC → signed report `bytes` | Hermes → update `bytes[]` | Gateway/cache → signed data-package `bytes` |
| Feed id | `bytes32` (schema-version-prefixed) | `bytes32` price id | `bytes32` short-string (e.g. `"CELO"`) |
| **Verify + return in one call** | `verifierProxy.verify(payload) → report struct` | `parsePriceFeedUpdates(data, ids, minT, maxT)` **payable** → `PriceFeed[]` (verifies, returns, **no storage write**) | manual-payload extractor: pass `redstonePayload` as explicit `bytes`, base contract verifies sigs+timestamps → value |
| How data is passed | explicit `bytes` | explicit `bytes[]` | explicit `bytes` (manual mode) **or** appended to calldata (default) |
| Verification fee | FeeManager (**0 on Celo**) | native fee via `getUpdateFee(data)` | none |
| Price shape | `int192`, 1e18 | `int64 price` + `int32 expo` | `int256`, 8 decimals (typical) |
| Timestamp | `observationsTimestamp` (seconds) | `publishTime` (seconds) | package timestamp (milliseconds) |

**The linchpin:** all three support **verify-and-return from an explicit `bytes` argument in a single
call** (RedStone via its manual-payload extractor; Pyth via `parsePriceFeedUpdates`; Chainlink via
`verify`). So one adapter interface — `(feedIds, updateData) → normalized prices` — covers all of them.

**Deployment prerequisites (verified July 2026):**

- Pyth is deployed on Celo at `0xff1a0f4744e8582DF1aE09D5611b887B6a12925C` (the canonical multichain
  address; re-verify against the Pyth contract-addresses page before wiring).
- RedStone pull needs **no pre-deployed RedStone contract at all** — signature verification runs
  inside the consumer (our adapter). Flip side: the **authorized signer set and uniqueness threshold
  live in our adapter**, so signer rotation is a Mento governance action (upgradeable config or
  adapter redeploy), not something RedStone handles for us on-chain.
- Chainlink: the VerifierProxy per chain, as today.

---

## 3. Target architecture

Two shared interfaces (on-chain + SDK) plus a thin per-provider adapter/source. Everything else is
reused.

```
 SDK                                        On-chain
 ┌────────────────────┐   updateData        ┌───────────────────────────┐
 │ IOracleDataSource  │ ─── (opaque) ─────▶ │ PullOracleRelayer         │
 │  · ChainlinkSource │   + fee (msg.value) │  holds IPullOracleAdapter      │
 │  · PythSource      │                     │  legs = feedIds + invert   │
 │  · RedStoneSource  │                     │   │                        │
 └────────────────────┘                     │   ▼ adapter.verify(...)    │
                                            │  ┌──────────────────────┐  │
                                            │  │ IPullOracleAdapter        │  │
                                            │  │ · ChainlinkDSAdapter  │  │
                                            │  │ · PythAdapter         │  │
                                            │  │ · RedStoneAdapter     │  │
                                            │  └──────────────────────┘  │
                                            │   │ (price1e18, obsTs)     │
                                            │   ▼ compose · invert       │
                                            │  SortedOracles.report ─────┼─▶ breaker, swap read
                                            └───────────────────────────┘
```

### 3.1 On-chain: `IPullOracleAdapter`

```solidity
interface IPullOracleAdapter {
  /// @notice Verifies provider-specific `updateData` for `feedIds` and returns normalized prices.
  /// @dev Opaque per-provider blob: Chainlink = abi.encode(signedReports[]); Pyth = abi.encode(
  ///      hermesUpdate[]); RedStone = the signed payload. Reverts if a report fails verification or
  ///      its embedded feedId != the requested one. Payable to fund providers that charge a fee.
  /// @return prices Mid/benchmark prices normalized to 1e18 fixed-point, aligned to feedIds.
  /// @return observationsTimestamps DON/publish observation time in unix seconds, aligned to feedIds.
  /// @return expiresAt Hard expiry in unix seconds (type(uint32).max if the provider has none).
  function verify(bytes32[] calldata feedIds, bytes calldata updateData)
    external
    payable
    returns (uint256[] memory prices, uint256[] memory observationsTimestamps, uint256[] memory expiresAt);

  /// @notice Native-token fee required to verify `updateData` (0 for Chainlink-on-Celo / RedStone).
  function verificationFee(bytes calldata updateData) external view returns (uint256);

  /// @notice Provider identifier for off-chain resolution (e.g. bytes32("chainlink-data-streams"),
  ///         bytes32("pyth"), bytes32("redstone")). The SDK reads relayer.adapter().provider() to
  ///         pick the matching IOracleDataSource — no external registry needed.
  function provider() external view returns (bytes32);
}
```

**Interface invariants (part of the spec, enforced by every adapter):**

1. **`updateData` MUST be the last parameter** of `verify` and callers MUST pass it via standard ABI
   encoding. This makes its content the final calldata tail, which the RedStone adapter depends on
   (RedStone parses its payload marker from the *end* of `msg.data`). The signature above satisfies
   this; any future variant must preserve it.
2. **Adapters MUST revert on a non-positive or missing price** — the interface returns `uint256`, so
   the relayer can no longer see a negative value (Pyth's `int64 price` can be ≤ 0; Chainlink's
   `int192` likewise). The relayer keeps a `price == 0` sanity revert as defense in depth.
3. **Adapters MUST bind each returned price to the requested feedId** (the `WrongFeedId` check moves
   into the adapter): Chainlink = compare report feedId; Pyth = `parsePriceFeedUpdates` enforces id
   alignment natively; RedStone = per-feed extraction reverts on a missing feed.
4. **Freshness stays in the relayer.** Adapters normalize timestamps to unix **seconds** and pass
   them through; they do not enforce staleness themselves (Pyth's `minPublishTime/maxPublishTime`
   window is set maximally wide in the adapter; RedStone's default in-consumer timestamp validation
   is configured permissively). The relayer's uniform gates (FutureReport / ExpiredSignature /
   ReportTooStale / spread) remain the single freshness policy.
5. **`verify` MUST refund or reject excess `msg.value`** deterministically (recommended: revert on
   `msg.value != verificationFee(updateData)` for fee-charging adapters, require 0 for free ones).

Per-provider adapters (each isolates one provider's SDK/ABI + normalization):

- **`ChainlinkDataStreamsAdapter`** — wraps `IVerifierProxy.verifyBulk` + today's schema-aware
  `decodeReport` (V3 slot 6 / V8 slot 7). Price is already 1e18. Fee = 0 on Celo. *This is exactly
  the current relayer's inner logic, lifted out verbatim.*
- **`PythAdapter`** — holds the `IPyth` address; calls `parsePriceFeedUpdates{value: fee}` and
  normalizes `price · 10^(18+expo)`; timestamp = `publishTime`; `verificationFee = getUpdateFee`.
- **`RedStoneAdapter`** — extracts values from the explicit `redstonePayload` (manual-payload
  extractor / `RedstoneConsumerNumericBase`), normalizes 8→18 decimals; timestamp = package time
  (ms→s); fee = 0.

### 3.2 On-chain: the relayer becomes adapter-driven

`DataStreamsRelayerV1` → **`PullOracleRelayerV1`**. The only structural change: replace the immutable
`verifierProxy` + inline `decodeReport` with an immutable `IPullOracleAdapter adapter`; keep legs
(`feedId` + `invert`) and all validation/compose/report logic.

```solidity
function relay(bytes calldata updateData) external payable {
  bytes32[] memory feedIds = _legFeedIds();
  (uint256[] memory prices, uint256[] memory obsTs, uint256[] memory expiresAt) =
    adapter.verify{value: msg.value}(feedIds, updateData);
  // per-leg: FutureReport / ExpiredSignature / ReportTooStale / spread — UNCHANGED
  // compose (UD60x18 multiply + invert), scale 1e18→1e24 — UNCHANGED
  // reportRate(...) → SortedOracles — UNCHANGED
}
```

Notes:
- `relay` becomes **`payable`** and forwards `msg.value` to the adapter (Pyth fee). Zero-fee
  providers ignore it.
- One opaque `updateData` blob per call covers all legs (matches Pyth's single combined update and
  RedStone's single payload; Chainlink packs `signedReports[]` inside it). Simpler than `bytes[]`.
- The `WrongFeedId` binding moves into each adapter (it must prove the returned price is for the
  requested feedId).

### 3.3 On-chain: factory + router

- `DataStreamsRelayerFactory` → **`PullOracleRelayerFactory`**: unchanged responsibilities
  (rateFeedId → relayer, `ingest` recovery), now deploying adapter-bound relayers. `ingest` gains a
  `payable` + forwards value.
- `RouterWithReports.swapExactTokensForTokensWithReports(..., bytes[] updateDataPerHop)` becomes
  **`payable`**. `signedReportsPerHop` (`bytes[][]`) collapses to `updateDataPerHop` (`bytes[]`, one
  opaque blob per hop). Empty entry = push pair, skip.
- **Fee routing (concrete mechanism):** for each hop, the router resolves the relayer's adapter and
  queries `verificationFee(updateDataPerHop[i])`, forwards exactly that value with `ingest`, and
  **requires msg.value to match the fee sum exactly** (reverts `FeeMismatch` on over- or
  underfunding; no refunds, so no mid-swap native transfer back to the caller). For the current providers on Celo the
  fee is 0 everywhere except Pyth, so the common case forwards nothing and skips the refund branch.
  The SDK precomputes the total (`sum of fetchUpdateData().fee`) and sets it as the tx `value`.

### 3.4 SDK: `IOracleDataSource`

```typescript
type OracleProvider = 'chainlink-data-streams' | 'pyth' | 'redstone'

interface IOracleDataSource {
  readonly provider: OracleProvider
  /// Fetch the opaque updateData blob to submit for these feedIds (in order), plus any native fee.
  fetchUpdateData(feedIds: Hex[]): Promise<{ updateData: Hex; fee: bigint }>
}
```

- **`ChainlinkDataStreamsSource`** — today's `DataStreamsClient` (HMAC), then `abi.encode` the
  reports; `fee = 0n`.
- **`PythSource`** — Hermes fetch → `abi.encode([hermesBytes])`; `fee = getUpdateFee`.
- **`RedStoneSource`** — RedStone gateway → the signed payload; `fee = 0n`.

`SwapService`/`DataStreamsService` become resolution-driven: read the relayer's `provider()` (or
`adapter()` → known type) on-chain, pick the matching source, fetch `updateData`, and encode the
router call **forwarding `fee` as tx `value`**. `mento.reports` (the ingest/recovery helper)
generalizes the same way.

---

## 4. What stays invariant (the reuse surface)

- `SortedOracles` as the single sink; `reportRate` lesser/greater-key write; dual-run reporter rules.
- `MedianDeltaBreakerV2` slew breaker (reads the written median; provider-independent).
- UD60x18 multiply/invert composition + 1e18→1e24 fixidity scaling.
- Per-leg freshness gates (expiry, staleness, spread, future-timestamp) — they operate on the
  normalized `(price, obsTs, expiresAt)` the adapter returns.
- rateFeedId registry + CREATE2 factory determinism + permissionless relay/recovery.

---

## 5. Naming (provider-neutral rename)

| Today | Proposed |
| --- | --- |
| `DataStreamsRelayerV1` | `PullOracleRelayerV1` |
| `IDataStreamsRelayer` / `StreamLeg` | `IPullOracleRelayer` / `OracleLeg` |
| `DataStreamsRelayerFactory` | `PullOracleRelayerFactory` |
| `IVerifierProxy` (relayer dep) | `IPullOracleAdapter` |
| `signedReports` / `parameterPayload` | `updateData` |
| `RouterWithReports` | keep, or `RouterWithOracleUpdates` |
| `mento.reports` (SDK) | `mento.oracleUpdates` (or keep, alias) |

Chainlink specifics (`feedId` schema prefixes, VerifierProxy) live **only inside**
`ChainlinkDataStreamsAdapter` / `ChainlinkDataStreamsSource`.

---

## 6. Migration path (non-breaking)

1. **Phase A — extract, no behavior change.** Introduce `IPullOracleAdapter`; move the current
   VerifierProxy+decode logic verbatim into `ChainlinkDataStreamsAdapter`; make the relayer hold an
   adapter. SDK: introduce `IOracleDataSource` with the Chainlink impl wrapping today's client. The
   proven Chainlink/V8 Sepolia flow keeps working; only indirection is added. Ship behind the same
   flag.
2. **Phase B — generalize the shape.** `relay`/`ingest`/router become `payable` + opaque
   `updateData`; rename to provider-neutral types (with back-compat aliases if any external ABI
   depends on the old names).
3. **Phase C — add providers.** Implement `PythAdapter`/`PythSource` and
   `RedStoneAdapter`/`RedStoneSource`. Each is additive; a rate feed picks its provider at relayer
   deploy time.

---

## 7. Open questions / tradeoffs to resolve before building

- **Pyth fee UX on Celo.** `parsePriceFeedUpdates` charges a native (CELO) fee. Verify-on-swap must
  source that value — from the swapper (extra CELO on the swap tx, which the SDK can precompute) or a
  protocol-funded buffer. Chainlink/RedStone are fee-free, so this is a Pyth-only wrinkle.
  (Deployment itself is resolved: Pyth is live on Celo — see §2; RedStone needs no deployment.)
- **Per-relayer vs per-leg provider.** Simplest V1: one relayer = one adapter = one provider (all
  legs same provider). A composed cross-rate mixing providers (leg A Chainlink, leg B Pyth) needs
  per-leg adapters — defer unless a real feed requires it.
- **Decimals / expo normalization.** Pyth `expo` and RedStone 8-decimals must normalize to 1e18 in
  the adapter; add adapter-level unit tests with real fixtures per provider.
- **Timestamp units + freshness semantics.** RedStone timestamps are ms and RedStone validates
  freshness in its own base contract; Pyth `publishTime` and Chainlink `observationsTimestamp` are
  seconds. Normalize to seconds and keep our own staleness gate as the uniform check.
- **RedStone explicit payload — mechanics resolved, benchmarks pending.** The explicit-payload mode
  is RedStone's documented *extractor* pattern (`extractPrice(bytes32 feedId, bytes redstonePayload)`
  → `getOracleNumericValueFromTxMsg`); it requires the payload to be generated with
  `getRedstonePayloadForManualUsage` (32-byte-aligned so the end-of-calldata marker survives ABI
  encoding) and `updateData` to be the last argument — both captured as interface invariants in
  §3.1. Remaining: gas benchmark vs the calldata-append default, and the **signer-set governance**
  question (the authorized-signers config lives in our adapter — decide upgradeable config vs
  redeploy for rotation).
- **`marketStatus` / risk flags.** V8 (and RWA schemas) carry `marketStatus`; Pyth/RedStone have
  their own staleness/confidence signals. Decide whether the adapter surfaces a normalized "tradable"
  flag or we rely solely on freshness + the breaker.
- **RedStone Classic (push) as an alternative.** RedStone also offers Chainlink-compatible push
  adapters. If a feed is better served push-style, it can bypass the relayer entirely and report to
  SortedOracles via the existing push path — worth noting as an escape hatch.

---

## 8. Bottom line

The generalization is a **clean extraction, not a rewrite**: one on-chain `IPullOracleAdapter` and one
SDK `IOracleDataSource`, with the current Chainlink logic moved behind them unchanged, and Pyth/
RedStone added as sibling implementations. The composition, breaker, SortedOracles sink, and swap
settlement — the parts that actually encode Mento's oracle semantics — are already provider-neutral
and stay put.
