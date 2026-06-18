# Audit Review — Chainlink Data Streams Migration (`feat/chainlink-data-streams`)

Read-only review of the branch vs `develop`. Reviewer did not write this code.
External 0.5.13 contracts (SortedOracles, BreakerBox) and external Chainlink
contracts (VerifierProxy) are **not** in this repo; their behavior is treated as
an assumption to be confirmed, not asserted as fact.

## Scope / diff coverage

Committed (`git diff develop...HEAD --stat`, merge-base `4048a6c`) plus untracked
working-tree files. Files reviewed:

- `contracts/interfaces/IVerifierProxy.sol`
- `contracts/interfaces/IDataStreamsRelayer.sol`
- `contracts/interfaces/IDataStreamsRelayerFactory.sol`
- `contracts/oracles/DataStreamsRelayerV1.sol`
- `contracts/oracles/DataStreamsRelayerFactory.sol`
- `contracts/oracles/breakers/MedianDeltaBreakerV2.sol`
- `contracts/oracles/DataStreamsRelayerFactoryProxy.sol` (untracked)
- `contracts/oracles/DataStreamsRelayerFactoryProxyAdmin.sol` (untracked)
- `script/DeployDataStreams.s.sol` (untracked)
- `test/oracles/DataStreamsRelayerV1.t.sol`, `DataStreamsRelayerFactory.t.sol`,
  `MedianDeltaBreakerV2.t.sol`, `test/oracles/fork/DataStreamsRelayerFork.t.sol` (untracked)
- `test/references/median_delta_breaker_v2_reference.py`
- `test/utils/mocks/MockVerifierProxy.sol`
- `fixtures/datastreams/*` (untracked), `.gitignore`, `foundry.toml`, `.prettierrc.yml`

---

## Severity summary

| Severity | Count |
|----------|-------|
| Critical | 0 confirmed in-code; 2 DEPENDS-ON-external |
| High     | 1 confirmed; 1 DEPENDS-ON-external |
| Medium   | 4 |
| Low      | 4 |
| Nit      | 3 |

Each finding is tagged **[CONFIRMED]** (a bug provable from in-repo code) or
**[DEPENDS]** (correctness rests on an unverified external ABI/fact that needs
Chainlink/human confirmation). Critical/High first.

---

## Seam 2 — VerifierProxy report decode

### C1 [DEPENDS] verify/verifyBulk return shape is assumed to be the bare report struct — never validated in-repo
`contracts/oracles/DataStreamsRelayerV1.sol:351-362` decodes the **return value**
of `verifyBulk` at fixed byte offsets (feedId@+32, obsTs@+96, expiresAt@+192,
price@+224). This is correct **only if** `VerifierProxy.verifyBulk` returns each
verified report as a bare ABI-encoded report struct (`bytes32,uint32,uint32,
uint192,uint192,uint32,int192,...`) and **not** an envelope (e.g.
`(bytes32[3] reportContext, bytes reportData, ...)`).

- The unit tests use `MockVerifierProxy`, which **echoes the input back**
  (`test/utils/mocks/MockVerifierProxy.sol:75-82`). So the offsets are validated
  against a self-fulfilling mock, never the real return shape.
- The only test that would exercise the real return shape is the live fork test
  (`test/oracles/fork/DataStreamsRelayerFork.t.sol:175-253`), which is **gated and
  skips** without captured fixtures + env vars (lines 192-198).
- `fixtures/datastreams/README.md:29-32` describes the API blob as the
  `(bytes32[3] reportContext, bytes reportData, ...)` envelope that is the
  **input** to `verify` — it does not state what `verify` *returns*. If the
  decoder were ever pointed at the envelope/input layout, every field offset is
  wrong and a corrupted price is written silently (price>0 and feedId checks could
  still pass by coincidence of layout).

Condition: manifests the first time `relay()` runs against the real VerifierProxy.
Action: confirm the exact `verifyBulk` return ABI with Chainlink and add a passing
fork test before mainnet. Do not treat the echo-mock tests as proof.

### C2 [DEPENDS] V3 vs V4 schema field order is assumed common for first 7 slots
`DataStreamsRelayerV1.sol:329-362` claims slots 0/2/5/6 are common across V3
(crypto) and V4 (FX) and reads only those. Documented Chainlink V3 and V4 structs
do share `feedId, validFromTimestamp, observationsTimestamp, nativeFee, linkFee,
expiresAt, price` as the first 7 fields, so the assumption is *plausible*, but:
- It is asserted in a comment, not enforced. There is no schema-version byte check.
  A future schema (V5+) or a feed configured with a different layout would be
  decoded at the wrong offset and write a wrong price (no revert).
- `int192 price := mload(...)` reads a full 32-byte word into an `int192`; this
  relies on ABI sign-extension of `int192`. Correct for the documented layout, but
  again unverified against the live return.

Condition: any feed whose verified-report layout differs from the documented
V3/V4 first-7-field order. Action: confirm per-feed schema (B4) and, if feasible,
bind the expected schema version per leg.

---

## Seam 1 — SortedOracles integration

### H1 [CONFIRMED] Dual-run (push + pull) only survives if a feed has exactly the push relayer + this pull relayer as reporters
`DataStreamsRelayerV1.sol:375-418` reuses ChainlinkRelayerV1's `reportRate`
verbatim. It only tolerates: 0 reports, 1 self, 1 foreign, or 2 where one is self
(lines 380, 386). If during migration a feed has the V1 push ChainlinkRelayer **and**
the pull DataStreamsRelayer **and any third oracle** (or the two relayers happen to
both be "foreign" from the perspective of a third), `numRates > 2` →
`TooManyExistingReports()` revert (line 387) and the dual-run write path is dead.

It works **iff** the feed has at most two reporters total and at most one is
foreign to the caller. This is a hard operational constraint, not a code bug, but
it is undocumented at the call site and is exactly the dual-run window the plan
asks about. Confirm each migrating feed has no legacy third oracle before enabling
the pull relayer.

Note (holds): `report(rateFeedId, value, lesserKey, greaterKey)` signature matches
`ISortedOraclesMin` (line 17) and the Celo SortedOracles `report` triggers
`breakerBox.checkAndSetBreakers(token)` as its last step — verified in the Celo
11.0.0 source. Nothing in the relayer bypasses `report()`; the only path that skips
it is the idempotent no-op (see M1).

Note (holds): UD60x18 (1e18) → Fixidity (1e24) scaling via `* 1e6`
(`DataStreamsRelayerV1.sol:55, 249`). `UD60x18.mul` keeps the product 1e18-scaled,
`intoUint256 * 1e6` → 1e24. Verified against tests and SortedOracles' fixidity
median. No off-by-decimals.

---

## Seam 3 — BreakerBox ↔ MedianDeltaBreakerV2

### M1 [CONFIRMED] Anchor advances on every untripped `checkAndSetBreakers`, even when the median did not change; `checkAndSetBreakers` is permissionless
`MedianDeltaBreakerV2.shouldTrigger` (lines 308-335) overwrites
`lastMedian`/`lastReportTime` on every call while the breaker is untripped.
`BreakerBox.checkAndSetBreakers(rateFeedID)` is `external` and callable by anyone
(`contracts/oracles/BreakerBox.sol:321`), and it calls `shouldTrigger` via
`checkBreaker` (line 401) whenever the breaker's `tradingMode == 0`.

Consequence: an attacker can repeatedly call `checkAndSetBreakers` to keep
`lastReportTime` pinned to the current block. Because the allowance grows with
`Δt = block.timestamp - lastReportTime` (lines 324, 328, 282), keeping `Δt`
small keeps the allowance near `baseJump`. This makes the breaker *more* likely to
trip on the next genuine move (a DoS-toward-halt vector), or — conversely —
resetting the anchor to the latest median right before a real move can make a
two-step move look like two small in-band moves (a trip-evasion vector). The V1
EMA breaker reads a value but does not advance a per-feed timestamp anchor that an
external caller can reset, so this is a new exposure introduced by the slew design.

Condition: anyone calling `BreakerBox.checkAndSetBreakers` (or relaying) at chosen
times. Recommend gating anchor advancement so it only progresses when the median
actually changed, or documenting that the slew breaker's safety does not depend on
caller-controlled cadence.

### M2 [DEPENDS] IBreaker ABI match across the 0.5.13/0.8.19 boundary holds at the selector level, but trading-mode/return semantics are unverified against the live BreakerBox
`MedianDeltaBreakerV2` implements `getCooldown(address) view returns(uint256)`,
`shouldTrigger(address) returns(bool)`, `shouldReset(address) returns(bool)` and
emits `SortedOraclesUpdated` — matching `contracts/interfaces/IBreaker.sol:21-39`
exactly, and the in-repo `BreakerBox` (`_checkAndSetBreakers` at lines 333-410)
consumes exactly those. This holds against the in-repo BreakerBox.

It is tagged DEPENDS because the *deployed* mainnet BreakerBox is the external
0.5.13 contract; this review can only confirm the ABI against the repo copy.
Confirm the deployed BreakerBox is the same version (it accepts an arbitrary
`tradingMode` per breaker via `addBreaker`, and the deploy script sets it to `2`
by default — `script/DeployDataStreams.s.sol:279`).

Notes (hold):
- `msg.sender == breakerBox` guard present (`MedianDeltaBreakerV2.sol:309`).
- Reads `medianRate(id)` (line 312), not `medianTimestamp`.
- Δt uses `block.timestamp` (lines 324, 332), NOT `observationsTimestamp`; the
  relayer uses `observationsTimestamp` for staleness/replay
  (`DataStreamsRelayerV1.sol:300-302, 306`). They are not swapped.
- `resetBreakerState(id)` clears `lastMedian`/`lastReportTime` (lines 228-233) so a
  re-enabled feed re-seeds instead of comparing to a stale anchor — but this is
  **owner-gated and manual**; nothing auto-clears the anchor on
  BreakerBox.toggleBreaker(disable). See L1.

### M3 [CONFIRMED] On disable/re-enable, the anchor is NOT auto-cleared — relies on an operator remembering to call `resetBreakerState`
`MedianDeltaBreakerV2` has no hook tying into BreakerBox's
`toggleBreaker(...false)`. If a feed's breaker is disabled and later re-enabled
after a long gap, the first post-re-enable `shouldTrigger` compares the fresh
median against a stale `lastMedian` with a stale `lastReportTime`. Because Δt will
be large, the allowance is capped at `maxJump` (lines 282-285), so a within-maxJump
move won't trip — but a move larger than `maxJump` that accumulated legitimately
during the disabled period will **false-trip** on re-enable. The code provides
`resetBreakerState` (lines 228-233) but enforces nothing; the comment at lines
225-227 only *recommends* calling it. The deploy script wires breakers but never
calls `resetBreakerState` (`script/DeployDataStreams.s.sol:235-259`).

Condition: feed breaker disabled, large legitimate drift, re-enabled without a
manual reset. Recommend documenting this as a required runbook step or auto-seeding
on first call after re-enable.

Note (coexistence with V1 — holds): `_deployBreaker`/`_wireBreakerBox`
(`script/DeployDataStreams.s.sol:207-259`) add V2 as an additional breaker and
explicitly leave V1 enabled (comment line 258). BreakerBox ORs all enabled
breakers' trading modes (`BreakerBox.sol:340`), so dual-run coexistence holds.

---

## Seam 4 — Replay / idempotency

### Holds, with one in-repo dependency clarified
`DataStreamsRelayerV1.relay` (lines 242-248): `compositeObs < last` →
`StaleReport` revert; `== last` → emits `ReportSkippedIdempotent` and **returns
without reverting** (M1-adjacent: it also skips `report()`, so breakers are not
re-evaluated on a duplicate — acceptable, nothing changed). `> last` → accepted and
`lastObservationsTimestamp` updated. `compositeObs` is the **oldest** leg
(`composeRate` lines 268-279), so the weakest leg gates freshness. Monotonic.

Important correction to the seam premise: the **Celo 11.0.0 SortedOracles.report**
stamps each report with `now` (block.timestamp) and has **no `TimestampNotNew`
revert** in this version (verified in `@celo/contracts` SortedOracles source,
report body uses `now`). So there is no conflict between the relayer's
`observationsTimestamp`-based replay guard and SortedOracles' own timestamp
handling — they operate on different clocks and SortedOracles does not reject a
repeated `now`. This is the correct outcome, but it is a **DEPENDS** on the exact
deployed SortedOracles version: if a newer SortedOracles with a strict
`TimestampNotNew(now)` guard is deployed and two relays land in the same block,
the second `report()` could revert. Confirm the deployed version.

---

## Seam 5 — Composition / validation

### Holds
- Multiply-and-invert: `composeRate` multiplies legs, `decodeAndValidateLeg`
  inverts via `UD60x18.inv()` when `leg.invert` (lines 304-305). Verified by
  `test_relay_*Legs_composeWithInvert`.
- Spread gate: `newestObs - oldestObs > maxTimestampSpread` (line 278); boundary
  `==` accepted (test `test_relay_spread_boundary_accepts`).
- Both staleness gates present: `block.timestamp > expiresAt` →
  `ExpiredSignature` (line 300) AND `block.timestamp - obsTs > maxStaleness` →
  `ReportTooStale` (line 302). Boundary `==` cases accepted (strict `>`),
  confirmed by tests at lines 337-367.
- `signedReports.length == legCount` enforced (line 237).

### L2 [CONFIRMED] `block.timestamp - obsTs` underflow if a report's obsTs is in the future
`DataStreamsRelayerV1.sol:302`. If `obsTs > block.timestamp` (a future
observationsTimestamp), `block.timestamp - obsTs` underflows and reverts (0.8.x
checked math) rather than producing a clean `ReportTooStale`/validity error. A
future-dated leg should arguably be rejected with a clear error. Low impact
(reverts either way, no bad write), but the revert reason is opaque
(`Arithmetic over/underflow`) and there is no explicit "future report" guard. The
`expiresAt` check does not cover this (a report can be future-observed yet
unexpired).

### L3 [CONFIRMED] No explicit upper bound on composed price / overflow relies on UD60x18
`composeRate` multiplies up to 4 legs. `UD60x18.mul` reverts on overflow, and
`intoUint256(...) * 1e6` could overflow for an absurd composed rate; both revert
safely. No silent corruption, but extreme/garbage prices (within int192) cause a
revert rather than a validation error. Acceptable; noted for completeness.

---

## Seam 6 — Factory / CREATE2

### Holds
- Salt `keccak256("mento.dataStreamsRelayer")` (`DataStreamsRelayerFactory.sol:292`)
  is distinct from ChainlinkRelayerFactory's `keccak256("mento.chainlinkRelayer")`
  (`contracts/oracles/ChainlinkRelayerFactory.sol:228`). Even with equal salts there
  would be no collision because `address(this)` (different factory) is in the CREATE2
  preimage (line 261). Distinct per-relayer addresses come from constructor args in
  the init code hash (lines 264-274).
- Determinism: `computeRelayerAddress` matches the deployed address; asserted
  on-chain (`UnexpectedAddress`, line 147) and in tests.
- `ingest` resolves `rateFeedId → relayer` with a zero-address guard
  (`NoRelayerForRateFeedId`, lines 209-210). Holds.

### M4 [CONFIRMED] `deployRelayer` blocks redeploy by mapping check but `computeRelayerAddress` collides for identical params, requiring `removeRelayer` first
Two relayers for the *same* rateFeedId with *identical* params produce the same
CREATE2 address; `deployRelayer` guards via `RelayerForFeedExists` (line 126) and
`ContractAlreadyExists` (line 135). `redeployRelayer` only changes the address if
*some* constructor arg changes (legs/spread/staleness/description). Redeploying
with byte-identical params after `removeRelayer` would hit `ContractAlreadyExists`
because the old contract still has code at that address. This is by design
(immutable per-config relayers), but operationally it means you cannot "reset" a
relayer to identical params — any reconfiguration must change at least one arg.
Document this.

---

## Seam 7 — External-call ordering / reentrancy

### Holds (with a trust assumption)
`relay` writes `lastObservationsTimestamp` (line 248) **before** the external
`reportRate → report()` call (lines 250 / 382,416). CEI is respected for the state
guard. The first external call is `verifyBulk` (line 239), which occurs before any
state mutation; a malicious/compromised `verifierProxy` could reenter `relay`
before the guard is set, but `verifierProxy` is immutable and is the trusted
Chainlink contract — flagged as a trust assumption, not a bug. `report()` →
`checkAndSetBreakers` → breaker callbacks are all into trusted Mento contracts.
No reentrancy guard, consistent with ChainlinkRelayerV1. Holds.

---

## Seam 8 — Open-blocker exposure (hardcoded external facts)

### N1 [CONFIRMED] Hardcoded VerifierProxy addresses in a doc comment (informational)
`contracts/interfaces/IVerifierProxy.sol:8-9` hardcodes
`0x57A97148C1fa50f35F0639f380077017D8893b6b` (Celo mainnet) and
`0xfa58eE98c9d56A3e6e903f300BE8C60Bf031808D` (Alfajores) in a NatSpec comment.
These are **comments only**, not used in any code path (the proxy address is
passed in via constructor/factory). Still, per the plan's "forbid hardcoding any
unverified external fact" these are unverified literals (B1) and should be removed
or marked clearly as unconfirmed until B1 lands, since comments are routinely
copy-pasted into deploy configs.

### Otherwise holds
No hardcoded VerifierProxy address, feedId, schema version, SortedOracles address,
or per-feed param (maxStaleness/spread/baseJump/slewPerSecond/maxJump/cooldown)
exists in any executable code path of the relayer, factory, or breaker. The deploy
script reads every one from an env var with an obviously-fake non-zero TBD
placeholder fallback (`script/DeployDataStreams.s.sol:269-334`,
`_tbdAddr`/`_tbdFeedId`). The example fixture is all zeros
(`fixtures/datastreams/reports.example.json`) and real `reports.json` is
gitignored (`.gitignore`). B1/B4/B5/B10/B13 are correctly externalized.

---

## Seam 9 — Events match the indexer contract

### Holds
`Relayed(address indexed rateFeedId, uint256 rate, uint256 observationsTimestamp,
address indexed via)` and `ReportSkippedIdempotent(uint256 observationsTimestamp)`
are declared in `IDataStreamsRelayer.sol:61, 68` and emitted in
`DataStreamsRelayerV1.sol:251, 244` with matching argument order/types. Holds.

---

## Additional findings (proxy / deploy / tests)

### M5 [CONFIRMED] Mixed OpenZeppelin proxy lineages — proxy uses `openzeppelin-contracts-next`, factory logic uses `openzeppelin-contracts-upgradeable`
`DataStreamsRelayerFactoryProxy.sol:5-7` and
`DataStreamsRelayerFactoryProxyAdmin.sol:4` import from
`openzeppelin-contracts-next`, while `DataStreamsRelayerFactory.sol:4` uses
`openzeppelin-contracts-upgradeable` `OwnableUpgradeable` + `initializer`. This is
the same TransparentUpgradeableProxy/ProxyAdmin pattern used elsewhere in the repo,
but the proxy admin and the transparent-proxy admin-collision rules must be
consistent across the two OZ versions. Confirm the `-next` TransparentProxy uses
the ERC-1967 admin slot the matching `-next` ProxyAdmin expects, and that the
factory's `OwnableUpgradeable` owner is distinct from the proxy admin (admin cannot
call through the proxy). The deploy script keeps them separate (ProxyAdmin vs
initialize owner), which is correct; flagging only to confirm version alignment.

### L1 [CONFIRMED] Deploy script default slew params are placeholders but look authoritative
`script/DeployDataStreams.s.sol:276-278, 301-323` ships concrete fallback values
(0.5%/2%-per-hour/5%, etc.) tagged B10. They are env-overridable, but a deploy run
without env vars set will silently use these unvetted economic parameters. Because
they are non-zero and plausible, an operator could ship them by accident. Consider
requiring the env vars (revert if unset) for the param fields rather than
defaulting, the way addresses arguably should also hard-fail.

### L4 [CONFIRMED] `_configureBreakerPerFeed` reuses single-element arrays across iterations
`script/DeployDataStreams.s.sol:223-233` allocates `ids`/`cooldowns` once and
overwrites index 0 each loop. Functionally fine (one `setCooldownTimes` call per
feed), but it sets cooldown per-feed in N separate txs; minor gas/clarity nit, not
a correctness issue.

### N2 [CONFIRMED] `decodeReport` minimum length check is 224, but reads bytes up to offset 224..255
`DataStreamsRelayerV1.sol:354` requires `report.length >= 224`, then reads `price`
at `mload(add(report, 224))`, i.e. data bytes 192..223 — that is the 7th 32-byte
word, which requires `report.length >= 224`. Correct (the check is `>= 224` and the
last read word ends at data-offset 224). Verified, no off-by-one; noted because the
boundary is easy to misread.

### N3 Tests validate decode offsets only against an echoing mock
Reiterating C1 from the test-quality angle: `DataStreamsRelayerV1.t.sol` and the
factory test build reports with `abi.encode(...)` of a flat tuple and feed them
through `MockVerifierProxy` which echoes them. This proves the decoder is
self-consistent with the test's own encoding but proves nothing about the real
VerifierProxy return ABI. The branch is honest about this (the live fork test
exists and skips), but no green test currently covers the real seam. Land the
fixtures + fork test before relying on the unit suite as decode-correctness
evidence.

---

## What holds (positive confirmations)

- `reportRate` lesser/greater-key logic is byte-identical to the audited
  ChainlinkRelayerV1 (verified by diff).
- All per-leg validations present and boundary-correct (feedId binding, price>0,
  expiresAt, maxStaleness, spread).
- Idempotent `==` is a no-op, not a revert; `<` reverts; `>` accepts. Monotonic.
- CEI ordering for the state guard vs `report()`.
- CREATE2 salt distinct from Chainlink relayer; determinism asserted on-chain.
- Breaker selectors match IBreaker against the in-repo BreakerBox; correct clock
  separation (breaker=block.timestamp, relayer=observationsTimestamp).
- Events match the declared interface.
- No real external facts hardcoded in executable code; all externalized to env.

## Top priorities

1. **C1/C2** — Confirm the live `verifyBulk` return ABI and per-feed schema with
   Chainlink and land a *passing* fork test. Everything downstream of the decoder
   is unproven against reality.
2. **H1** — Verify no migrating feed has a third oracle before enabling dual-run.
3. **M1/M3** — Decide whether the slew anchor should advance on caller-controlled
   cadence and whether re-enable must auto-reseed; both are new exposures vs V1.
