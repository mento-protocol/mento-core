# Migration Plan — Mento V3 Oracles → Chainlink Data Streams (pull-based)

**Status:** Agreed design for the Mento V3 → Chainlink Data Streams migration. Implemented for
Chainlink (V3 crypto + V8 forex). **Next evolution:** generalizing this Chainlink-specific path to be
provider-agnostic (Pyth, RedStone, …) via a shared on-chain adapter + SDK data-source interface — see
[provider-agnostic-oracle-design.md](./provider-agnostic-oracle-design.md).
**Author:** generated audit + design draft.
**Repo audited:** `mento-core` @ branch `main`, HEAD `0e07807 Mento V3 🎉 (#701)`.
**Scope:** Replace the push-based `ChainlinkRelayerV1` oracle path with a **keeperless** pull-based Chainlink Data Streams path for the pairs Chainlink actually covers, keeping push relayers for the rest. Updates happen **only at swap time** (verify-on-swap); there is no Mento-operated keeper. Recovery runs through a **permissionless `relay()`**. The `MedianDeltaBreaker` EMA is replaced with a **time-normalized slew-rate breaker** that does not depend on a regular reporting cadence.

> **Reading note on callouts.** Every `> **Assumptions**`, `> **Divergence**`, and `> **Pushback**` block is a flag for reviewers. The code wins over prose; where the live code contradicted the original brief I called it out in §1 and propagated the correction.

> **Why keeperless.** A Mento-operated keeper heartbeat would cost a fixed amount _per pair, per chain_, growing with deployment surface and largest, relative to value, for the lowest-volume pairs — untenable across multiple chains. So there is no keeper: **(1)** the only update path is verify-on-swap (the swap brings its own fresh report; see §4), with recovery via a permissionless `relay()`; **(2)** the cadence-dependent EMA breaker is replaced by a slew-rate breaker (§2.3).

---

## 0. TL;DR of what the code actually says (read this first)

The single most important finding, which reshapes the whole design:

> **Divergence — the relayer cannot call `checkAndSetBreakers`.** > [`BreakerBox.checkAndSetBreakers`](../contracts/oracles/BreakerBox.sol#L321-L325) hard-requires `msg.sender == address(sortedOracles)`. The brief says "relayer ... writes to `SortedOracles`, runs `checkAndSetBreakers`". The relayer **must not and cannot** call `checkAndSetBreakers` directly. Breakers are triggered as a _side effect of `SortedOracles.report()`_ — the Mento fork of `SortedOracles` calls `breakerBox.checkAndSetBreakers(rateFeedId)` internally on each report (consistent with [`ISortedOracles.setBreakerBox`](../contracts/interfaces/ISortedOracles.sol#L44) and `breakerBox()` existing on the interface). So the relayer's only job is `report()`; breaker evaluation comes for free. This simplifies `DataStreamsRelayerV1` — it has the same write surface as `ChainlinkRelayerV1`.

Second most important finding:

> **Divergence — the swap-time read path is `view`; verification must be a separate state-changing pre-step.** > [`OracleAdapter.getFXRateIfValid`](../contracts/oracles/OracleAdapter.sol#L165-L171) and the FPMM read path [`FPMM._getRateFeed`](../contracts/swap/FPMM.sol#L723-L731) are `view`. You cannot verify-and-write inside them. Just-in-time verification therefore has to run as an explicit state-changing call _earlier in the same swap transaction_ (relayer `relay()` → `SortedOracles.report()` → breakers), after which the existing `view` read returns the freshly-written rate. This is a sequencing constraint, not a blocker, but it dictates where the new calldata parameter goes.

---

## 1. Current state audit (push-based, as built)

### 1.1 `ChainlinkRelayerV1` — [`contracts/oracles/ChainlinkRelayerV1.sol`](../contracts/oracles/ChainlinkRelayerV1.sol)

- Solidity `0.8.19`. Uses `prb/math` `UD60x18` (`import { UD60x18, ud, intoUint256 } from "prb/math/UD60x18.sol"`, line 7) — **good news: PRBMath (with `exp`) is already a dependency** for the breaker rewrite in §2.3.
- Talks to SortedOracles through a hand-rolled minimal interface [`ISortedOraclesMin`](../contracts/oracles/ChainlinkRelayerV1.sol#L16-L26) because SortedOracles is a Solidity 0.5.13 contract (see §1.3).
- **Immutable config** (lines 53-94): `rateFeedId`, `sortedOracles`, up to 4 aggregators (`aggregator0..3`), invert flags (`invert0..3`), `aggregatorCount` (1..4), `maxTimestampSpread`, `rateFeedDescription`.
- **`relay()`** (lines 202-233): reads `latestRoundData()` from each aggregator, chains via `report = report.mul(nextReport)` (line 213), inverting each leg if configured (line 304-306). Validation:
  - `newestChainlinkTs - oldestChainlinkTs > maxTimestampSpread` → `TimestampSpreadTooHigh` (line 218).
  - `lastReportTs > 0 && newestChainlinkTs <= lastReportTs` → `TimestampNotNew` (line 224) — **this is the existing replay/monotonicity guard**, keyed on `SortedOracles.medianTimestamp(rateFeedId)`.
  - `isTimestampExpired(newestChainlinkTs)` → `ExpiredTimestamp` (line 228); expiry uses `block.timestamp - timestamp >= getTokenReportExpirySeconds(rateFeedId)` (line 335-337).
  - `_price <= 0` → `InvalidPrice` (line 300).
- **`reportRate(uint256)`** (lines 246-289): the lesser/greater-key dance against `SortedOracles`. Happy path (0 reports, or 1 from self) reports with `address(0)` keys; otherwise computes keys for ≤1 foreign oracle and `removeExpiredReports(rateFeedId, 1)`. Reverts `TooManyExistingReports` if SortedOracles has >2 reports or 2 foreign. **`DataStreamsRelayerV1` should reuse this logic verbatim** — it is independent of how the rate was sourced.
- Scaling: `UD60X18_TO_FIXIDITY_SCALE = 1e6` (line 50); reports `intoUint256(report) * 1e6` to convert UD60x18 (1e18) → Fixidity (1e24).

### 1.2 `ChainlinkRelayerFactory` — [`contracts/oracles/ChainlinkRelayerFactory.sol`](../contracts/oracles/ChainlinkRelayerFactory.sol)

- `OwnableUpgradeable`; deployed behind a proxy (`ChainlinkRelayerFactoryProxy`, `ChainlinkRelayerFactoryProxyAdmin` also present).
- `deployRelayer` (lines 115-149) uses **CREATE2 with a constant salt** `keccak256("mento.chainlinkRelayer")` (line 228). Address is fully determined by init code + constructor args (`computedRelayerAddress`, lines 240-267).
- State: `sortedOracles`, `deployedRelayers[rateFeedId]`, `rateFeeds[]`, `relayerDeployer`. `onlyDeployer` = `relayerDeployer` or `owner` (lines 63-68).
- `redeployRelayer` = `removeRelayer` + `deployRelayer` (lines 188-196). This is the migration lever per-pair.

### 1.3 `SortedOracles` — **NOT in this repo**

> **Divergence / Assumption.** The brief lists `SortedOracles.sol` as a file to audit. It does **not exist in `mento-core@main`** (V3 restructured it out). The `ChainlinkRelayerV1` doc comment (line 14) points at `mento-protocol/mento-core/blob/develop/contracts/common/SortedOracles.sol`. In V3 it is treated as an **external, already-deployed Celo-core / Mento-fork contract**, consumed via [`ISortedOracles`](../contracts/interfaces/ISortedOracles.sol) and `ISortedOraclesMin`.
>
> - Key facts we rely on (verify against the deployed bytecode before cutover): `report(rateFeedId, value, lesserKey, greaterKey)`; `medianRate(id) → (uint256 num, 1e24 denom)`; `medianTimestamp(id)`; `getTokenReportExpirySeconds(id)`; `setBreakerBox`; and **`report()` internally invokes `breakerBox.checkAndSetBreakers(id)`** (the only caller `BreakerBox` accepts, line 322).
> - **Action:** confirm the exact deployed `SortedOracles` address and that its `report()` path calls `checkAndSetBreakers` (it is the lynchpin of the whole breaker story). TODO-SO-1.

### 1.4 `BreakerBox` — [`contracts/oracles/BreakerBox.sol`](../contracts/oracles/BreakerBox.sol)

- Solidity `^0.5.13`, `Ownable`.
- **Trigger entry point:** `checkAndSetBreakers(rateFeedID)` (lines 321-325) — `require(msg.sender == address(sortedOracles))`. Internal `_checkAndSetBreakers` (333-344) ORs each enabled breaker's trading mode.
- Per-breaker state machine: `updateBreaker` (351-356) → if currently tripped, `tryResetBreaker` (363-388); else `checkBreaker` (395-410).
  - `tryResetBreaker`: only resets if `cooldown > 0 && block.timestamp >= cooldown + lastUpdatedTime` **and** `breaker.shouldReset(id)` returns true. **`cooldown == 0` ⇒ manual reset only.**
  - `checkBreaker`: trips if `breaker.shouldTrigger(id)` true, sets `tradingMode` + `lastUpdatedTime`.
- `getRateFeedTradingMode(id)` (295-302) ORs the feed's own mode with all `rateFeedDependencies[id]` modes — this is how **cross-rate dependency halting** works today (a composite feed inherits the halt of any leg-feed it depends on).
- Storage layout (lines 24-45): `rateFeedIDs[]`, `rateFeedStatus`, `rateFeedBreakerStatus[id][breaker]`, `rateFeedTradingMode`, `rateFeedDependencies`, `breakerTradingMode`, `breakers[]`, `sortedOracles`.

> **Takeaway for the migration:** `BreakerBox` needs **zero changes**. It is driven entirely by `SortedOracles.report()`. Whether the report came from a push aggregator or a verified Data Streams report is invisible to it.

### 1.5 `MedianDeltaBreaker` — [`contracts/oracles/breakers/MedianDeltaBreaker.sol`](../contracts/oracles/breakers/MedianDeltaBreaker.sol)

- Solidity `^0.5.13`, `FixidityLib`, `WithCooldown`, `WithThreshold`, `Ownable`.
- **EMA is per-update, not time-weighted** (the thing the brief wants changed). [`shouldTrigger`](../contracts/oracles/breakers/MedianDeltaBreaker.sol#L175-L196):
  ```
  currentMedian = sortedOracles.medianRate(id)
  prevEMA = medianRatesEMA[id]
  if prevEMA == 0: medianRatesEMA[id] = currentMedian; return false   // seeding
  α = getSmoothingFactor(id)                                          // Fixidity, <= 1
  medianRatesEMA[id] = currentMedian*α + prevEMA*(1-α)                // update
  return exceedsThreshold(prevEMA, currentMedian, id)                 // compare current vs OLD ema
  ```
- `DEFAULT_SMOOTHING_FACTOR = 1e24` (line 38) = Fixidity `1.0` ⇒ **default behaviour is "no smoothing": EMA == latest median**, threshold compares each median against the previous median. Per-feed smoothing `< 1` must be set explicitly via `setSmoothingFactor` (line 134).
- No time/velocity term anywhere — the trip test is "delta since the last report", which assumes a regular cadence. This is the contract the slew-rate `MedianDeltaBreakerV2` replaces (§2.3); under keeperless sampling the cadence assumption no longer holds.
- `getCooldown` / cooldown live in [`WithCooldown`](../contracts/oracles/breakers/WithCooldown.sol) (default `defaultCooldownTime`, per-feed override; default 0 ⇒ manual reset). `exceedsThreshold` lives in [`WithThreshold`](../contracts/oracles/breakers/WithThreshold.sol#L46-L65): symmetric band `[ref*(1-thr), ref*(1+thr)]`, Fixidity 1e24 scale.

### 1.6 `ValueDeltaBreaker` — [`contracts/oracles/breakers/ValueDeltaBreaker.sol`](../contracts/oracles/breakers/ValueDeltaBreaker.sol)

- `shouldTrigger` (132-143): compares `currentMedian` vs a **fixed `referenceValues[id]`** (set by owner); returns false if reference unset. **Stateless w.r.t. time/EMA** — completely unaffected by push-vs-pull. No change needed.

### 1.7 `MarketHoursBreaker` — [`contracts/oracles/breakers/MarketHoursBreaker.sol`](../contracts/oracles/breakers/MarketHoursBreaker.sol)

- Solidity `0.8.24`. **Pure time function** (`isFXMarketOpen(timestamp)`, lines 20-22; weekend + holiday logic) — no oracle state, no cadence dependency.
- `shouldTrigger` **reverts** when the market is closed (line 27) rather than returning `true`.

> **Divergence vs brief's mental model.** `MarketHoursBreaker` is **not wired into `BreakerBox` as a tripping breaker** (its `shouldTrigger` reverts, which would brick `checkBreaker`/`report`). It is referenced **directly by `OracleAdapter`** (`setMarketHoursBreaker`, line 86-94) and consulted at _read time_ via `_isFXMarketOpen()` inside `getFXRateIfValid` (line 166). Consequence: FX-hours gating is **independent of report cadence** and works identically under push or pull. No change needed.

### 1.8 `OracleAdapter` — [`contracts/oracles/OracleAdapter.sol`](../contracts/oracles/OracleAdapter.sol)

- Solidity `0.8.24`, `OwnableUpgradeable`, **ERC-7201 namespaced storage** (`_ORACLE_ADAPTER_STORAGE_LOCATION`, line 20-21). Behind a proxy.
- Storage: `sortedOracles`, `breakerBox`, `marketHoursBreaker`, `l2SequencerUptimeFeed`.
- **All read entry points are `view`:**
  - `getFXRateIfValid(id)` (165-171): FX-open + trading-mode == `BIDIRECTIONAL(0)` + `_hasRecentRate` → `_getOracleRate`.
  - `getRateIfValid(id)` (157-162): same minus FX-hours.
  - `ensureRateValid(id)` (179-183): validate only (used by `OneToOneFPMM`).
  - `_getOracleRate` (212-222): `sortedOracles.medianRate(id)`, `assert(denominator == 1e24)`, rescale `/1e6` → 1e18 num/denom.
  - `_hasRecentRate` (224-231): `medianTimestamp(id) >= block.timestamp - getTokenReportExpirySeconds(id)`.

### 1.9 Swap / pricing modules — where the oracle read happens

| Path                 | Contract                                               | Read call                                                               | Site                                                                                               | Tx type                                                             |
| -------------------- | ------------------------------------------------------ | ----------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| **V3 FPMM** (priced) | [`FPMM`](../contracts/swap/FPMM.sol)                   | `oracleAdapter.getFXRateIfValid(referenceRateFeedID)`                   | `_getRateFeed` line 726, called from `swap` (413), `getAmountOut` (296), rebalancing (870)         | `swap` is `external nonReentrant` (state); `getAmountOut` is `view` |
| **V3 FPMM** (1:1)    | [`OneToOneFPMM`](../contracts/swap/OneToOneFPMM.sol)   | `oracleAdapter.ensureRateValid(referenceRateFeedID)`                    | `_getRateFeed` line 17 (returns hard 1e18:1e18)                                                    | as above                                                            |
| **V2**               | [`BiPoolManager`](../contracts/swap/BiPoolManager.sol) | `sortedOracles.medianRate(target)` **directly (not via OracleAdapter)** | `getOracleExchangeRate` line ~568, from `getUpdatedBuckets` during `swapIn/swapOut` (`onlyBroker`) | state                                                               |
| **V2 entry**         | [`Broker`](../contracts/swap/Broker.sol)               | none itself; delegates to exchange provider                             | `swapIn` (145-163), `swapOut` (166-184), both `nonReentrant`, no caller auth                       | state                                                               |

Key signatures (verbatim shape):

```solidity
// Broker — no bytes payload today
function swapIn(
  address exchangeProvider,
  bytes32 exchangeId,
  address tokenIn,
  address tokenOut,
  uint256 amountIn,
  uint256 amountOutMin
) external nonReentrant returns (uint256 amountOut);

// FPMM — ALREADY has a bytes payload, but it is the flash-swap callback data
function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external nonReentrant;
//   data, if non-empty, triggers IFPMMCallee(to).hook(...) at line 424 — so it is NOT free for oracle reports
```

> **Divergence — two live pricing stacks coexist.** The brief implies one pricing module. The repo has **both**: V2 `Broker`→`BiPoolManager` reading `SortedOracles` _directly_, and V3 `FPMM`/`OneToOneFPMM` reading via `OracleAdapter`. A complete migration must address **both** read surfaces, or scope explicitly to V3 FPMM only. The V2 `BiPoolManager` reading `sortedOracles.medianRate` directly means it transparently benefits from any fresh report the relayer writes — but it has **no place to attach signed reports** unless `Broker.swapIn/swapOut` gain a payload param.

> **Divergence — `FPMM.swap`'s `bytes calldata data` is taken.** It is the Uniswap-V2-style flash callback payload (`IFPMMCallee.hook`). Do **not** overload it for signed reports; add a distinct parameter or a wrapper entry point (§2.5).

### 1.10 Rate-feed ID convention (grounded in tests/scripts)

- Derived `rateFeedId = address(bytes20(keccak256("BASE/QUOTE")))` — e.g. `keccak256("USD/EUR")`, `keccak256("EUR/USDC")`, `keccak256("XOF/EUROC")` (`test/integration/protocol/ProtocolTest.sol:166-170`).
- For CELO pairs the `rateFeedId` is the **stable token address itself** (`cUSD_CELO_referenceRateFeedID = address(cUSDToken)`).
- A real mainnet example is hardcoded in `script/DeployV3FPMM.s.sol:70`: `kesUsdRateFeedId = 0xbAcEE37d31b9f022Ef5d232B9fD53F05a531c169` (KES/USD).

> **Note:** Mento `rateFeedId` ≠ Chainlink Data Streams `feedId` (a `bytes32` stream identifier). The new relayer maps **one Mento `rateFeedId` → N Data Streams `feedId` legs**, exactly as the current relayer maps one `rateFeedId` → N aggregators.

---

## 2. Target component designs (sketches only)

### 2.1 `IVerifierProxy` (the shape we need)

```solidity
interface IVerifierProxy {
  // Verifies a single signed report; returns the ABI-encoded full report payload.
  // On Celo there is NO FeeManager, so parameterPayload = bytes("") and no fee is taken.
  function verify(
    bytes calldata payload,
    bytes calldata parameterPayload
  ) external payable returns (bytes memory verifierResponse);

  // Batch variant (preferred for multi-leg cross-rates to amortize calldata + gas).
  function verifyBulk(
    bytes[] calldata payloads,
    bytes calldata parameterPayload
  ) external payable returns (bytes[] memory verifierResponses);

  function s_feeManager() external view returns (address); // expected address(0) on Celo
}
```

> **Assumptions (§2.1).**
>
> - `s_feeManager() == address(0)` on Celo ⇒ no LINK/native fee at `verify()`; pass `parameterPayload = ""`. **TODO-CL-1:** confirm `verifyBulk` exists/should be used vs looping `verify`, and confirm the exact `VerifierProxy` ABI/version deployed on Celo.
> - Billing is a Chainlink-Labs off-chain subscription (no on-chain payment). **TODO-CL-2.**

The verified report decodes (Data Streams **v3 crypto / v4-style FX** schema — exact version per-feed is **TODO-CL-3**):

```solidity
struct ReportV3 {
  // illustrative — confirm field order/version per feed before coding
  bytes32 feedId;
  uint32 validFromTimestamp;
  uint32 observationsTimestamp; // <-- relayer-side replay key + staleness numerator (see §5)
  uint192 nativeFee;
  uint192 linkFee;
  uint32 expiresAt; // <-- hard signature expiry: require block.timestamp <= expiresAt
  int192 price; // mid (1e18). Phase 1 writes this to SortedOracles.
  // int192 bid; int192 ask;       // LWBA — present on some schemas; deferred to Phase 3.
}
```

### 2.2 `IDataStreamsRelayer` / `DataStreamsRelayerV1`

Mirrors `ChainlinkRelayerV1` (same per-pair, CREATE2, immutable legs) but legs are Data Streams `feedId`s and the source is a signed report rather than `latestRoundData()`.

```solidity
interface IDataStreamsRelayer {
  struct StreamLeg {
    bytes32 feedId;
    bool invert;
  }

  function rateFeedId() external view returns (address);
  function sortedOracles() external view returns (address);
  function verifierProxy() external view returns (address);
  function getLegs() external view returns (StreamLeg[] memory);
  function maxTimestampSpread() external view returns (uint256);
  function maxStaleness() external view returns (uint256);
  function lastObservationsTimestamp() external view returns (uint256); // composite clock (§5)

  /// The single update path. PERMISSIONLESS — callable by anyone (a swap tx, an arbitrageur,
  /// the dapp, an integrator). Supplies one signed report per leg, in leg order.
  /// Verifies, composes, writes to SortedOracles (which triggers BreakerBox).
  /// Idempotent within a block: re-submitting the same observationsTimestamp is a no-op, not a revert.
  function relay(bytes[] calldata signedReports, bytes calldata parameterPayload) external;

  event Relayed(address indexed rateFeedId, uint256 rate, uint256 observationsTimestamp, address indexed via);
  event ReportSkippedIdempotent(uint256 observationsTimestamp);
}
```

> **No separate `refresh()`.** `relay()` is permissionless, so a single function serves both swap-time updates and ad-hoc recovery refreshes. Anyone who wants the feed live (the dapp before quoting, an arbitrageur, a Phase-2 integrator) calls `relay()` directly. See §4 / §8.

**Immutable storage** (CREATE2-determined, same pattern as `ChainlinkRelayerV1`): `rateFeedId`, `sortedOracles`, `verifierProxy`, `feedId0..3` (`bytes32`), `invert0..3`, `legCount`, `maxTimestampSpread`, `maxStaleness`, `rateFeedDescription`.

**Mutable storage** (the _only_ new persistent state vs the push relayer): `uint256 lastObservationsTimestamp` (composite clock, §5).

**`relay()` pseudocode:**

```
require(signedReports.length == legCount)
bytes[] verified = verifierProxy.verifyBulk(signedReports, parameterPayload)   // empty parameterPayload on Celo
UD60x18 rate = 1
uint256 oldestObs = ∞, newestObs = 0
for i in 0..legCount:
    r = decodeReport(verified[i])
    require(r.feedId == feedId[i], WrongFeedId)                 // bind leg → expected stream
    require(r.price > 0, InvalidPrice)
    require(block.timestamp <= r.expiresAt, ExpiredSignature)   // hard signature expiry
    require(block.timestamp - r.observationsTimestamp <= maxStaleness, TooStale)   // Mento policy
    UD60x18 p = toUD60x18(r.price); if (invert[i]) p = p.inv()
    rate = rate.mul(p)
    oldestObs = min(oldestObs, r.observationsTimestamp); newestObs = max(newestObs, r.observationsTimestamp)
require(newestObs - oldestObs <= maxTimestampSpread, SpreadTooHigh)
uint256 compositeObs = oldestObs                                // conservative: weakest leg defines freshness (§3)
if (compositeObs < lastObservationsTimestamp) revert StaleReport
if (compositeObs == lastObservationsTimestamp) { emit ReportSkippedIdempotent; return }   // idempotent no-op
lastObservationsTimestamp = compositeObs
reportRate(intoUint256(rate) * 1e6)                            // reuse ChainlinkRelayerV1.reportRate verbatim
// SortedOracles.report(...) → SortedOracles internally calls breakerBox.checkAndSetBreakers(rateFeedId)
```

> **Note on the existing monotonicity guard.** `SortedOracles.report` (via `medianTimestamp`) already rejects non-increasing timestamps (`TimestampNotNew`). Our `lastObservationsTimestamp` is a _stricter, relayer-owned_ guard that (a) lets us return a clean idempotent no-op instead of a revert, and (b) tracks the _composite_ (oldest-leg) timestamp, which is what we also pass to SortedOracles. Keep both.

**Unchanged vs `ChainlinkRelayerV1`:** `reportRate` lesser/greater-key logic; CREATE2 determinism; the "single reporter for this feed" assumption; UD60x18→Fixidity `*1e6` scaling; the multiply-and-invert composition kernel.
**Changed:** source = `verifierProxy.verify(signedReport)` instead of `aggregator.latestRoundData()`; timestamps come from `observationsTimestamp`/`expiresAt` instead of round data; adds `lastObservationsTimestamp` persistent state; adds `maxStaleness`; legs are `bytes32 feedId` not `address aggregator`.

> **Attribution via events.** The `via` field on `Relayed` (e.g. `msg.sender`) is enough to attribute swap-driven vs ad-hoc refresh updates off-chain.

### 2.3 `MedianDeltaBreakerV2` — time-normalized slew-rate breaker

Rewrite in Solidity `0.8.19`. It implements the same `IBreaker` ABI so `BreakerBox` (0.5.13) consumes it unchanged. (No `exp` needed — the formula is linear, so plain fixed-point arithmetic suffices.)

> **Why not a time-weighted EMA?** It is **incomplete for a keeperless world**. Time-weighting only makes the EMA _accumulation_ frequency-invariant; the trip test is still `exceedsThreshold(prevEMA, currentMedian)` — i.e. _"how far has the price moved since the last report?"_. With sparse, swap-driven sampling a long quiet gap compares _now_ against a stored value from hours ago, so a perfectly legitimate slow drift looks like a giant jump and **trips falsely**. Any EMA-style breaker inherits this, because it assumes a roughly regular sampling cadence — exactly what keeperless removes.

**The reframe: measure velocity, not absolute change.** Every Data Streams report is fresh-from-the-DON (we enforce `maxStaleness`, §5). So a large move over a **long** interval is just the on-chain median catching up to a real, slow market move — it should be allowed. A large move over a **short** interval is a flash crash / manipulation / bad print — it should trip. A rate-of-change (slew-rate) limit captures exactly this and is **cadence-independent**, so it is not a workaround — it is _more correct_ for pull than the EMA ever was.

**New per-feed state:** `mapping(address => uint256) public lastMedian;` and `mapping(address => uint256) public lastReportTime;` (replaces `medianRatesEMA` and `smoothingFactors`). Per-feed parameters: `baseJump`, `slewPerSecond`, `maxJump` (Fixidity-scaled fractions).

**The rule.**

```
prev  = lastMedian[id]
Δt    = block.timestamp - lastReportTime[id]        // (1) see clock note below
relΔ  = |currentMedian - prev| / prev
allowed = min(maxJump, baseJump + slewPerSecond * Δt)
trip if relΔ > allowed
```

- **`baseJump`** — instantaneous tolerance: covers same-block / tiny-Δt jitter, oracle rounding, and a single legitimate tick. Also the floor when `Δt = 0`.
- **`slewPerSecond`** — how fast fair value may legitimately move, per asset class (FX majors slow; crypto faster).
- **`maxJump`** — a hard ceiling on `allowed` regardless of `Δt`: any move beyond it trips no matter how long the gap, i.e. the genuine-discontinuity circuit.

> **(1) Clock note — use `block.timestamp`, not `observationsTimestamp`.** Celo's `SortedOracles.report()` stamps each report with `block.timestamp` (the `report` ABI has no timestamp parameter), so `medianTimestamp(id)` returns inclusion time, not the DON observation time. For the slew breaker that is the **better** choice: `block.timestamp` deltas between on-chain reports are objective and **ungameable** (a courier can't pick a favourable observation time to widen the allowance), and because we enforce `maxStaleness`, each report's observation time is ≈ its inclusion time anyway. The relayer still uses the decoded `observationsTimestamp` for replay + staleness (§5); only the breaker's Δt uses `block.timestamp`.

**Worked example.** FX-ish config: `baseJump = 0.5%`, `slewPerSecond = 2%/hour` (≈ `5.56e-6 /s`), `maxJump = 5%`.

| Scenario                          | Δt       | move | `allowed = min(maxJump, baseJump + slew·Δt)` | verdict                   |
| --------------------------------- | -------- | ---- | -------------------------------------------- | ------------------------- |
| Quiet 3 h, then a report          | 10,800 s | +3%  | min(5%, 0.5% + 6%) = **5%**                  | ✅ allow — legit catch-up |
| Flash move                        | 30 s     | +3%  | min(5%, 0.5% + 0.017%) = **0.52%**           | 🔴 trip                   |
| Same-block second report          | 0 s      | +3%  | min(5%, 0.5% + 0%) = **0.5%**                | 🔴 trip                   |
| (old EMA breaker on the 3 h move) | —        | +3%  | ~1% fixed band                               | ❌ **false trip**         |

The slew breaker **allows** the legitimate 3-hour catch-up but **trips** the 30-second flash — inverting the EMA's failure mode under sparse sampling.

**`shouldTriggerV2` pseudocode:**

```
require(msg.sender == breakerBox)
(currentMedian, ) = sortedOracles.medianRate(id)
prev = lastMedian[id]
if (prev == 0) { lastMedian[id]=currentMedian; lastReportTime[id]=block.timestamp; return false }  // seed
Δt    = block.timestamp - lastReportTime[id]
relΔ  = abs(currentMedian, prev) * FIX1 / prev
allowed = min(maxJump[id], baseJump[id] + slewPerSecond[id] * Δt)
lastMedian[id] = currentMedian
lastReportTime[id] = block.timestamp
return relΔ > allowed
```

`shouldReset(id)` returns `!shouldTrigger(id)` — i.e. the feed may un-trip once the move from the last accepted median is back within the (time-scaled) allowance, subject to `BreakerBox` cooldown.

> **Backstops (unchanged).** Pair this with `ValueDeltaBreaker` (fixed-band absolute guard — catches a gross depeg that drifts in under the slew limit) and `MarketHoursBreaker` (pure time gate). Both are cadence-independent already (§1.6, §1.7).

> **Assumptions (§2.3).** (a) `slewPerSecond` / `baseJump` / `maxJump` are policy values per feed — TODO-BR-1; calibrate `slewPerSecond` from historical realized volatility of each pair. (b) `lastMedian`/`lastReportTime` must be cleared by the existing reset/disable admin path so a re-enabled feed re-seeds rather than comparing against a stale anchor. (c) Fixidity 1e24 scaling and the `min`/division helpers are reused; no `exp`/PRBMath dependency.

### 2.4 `DataStreamsRelayerFactory`

Carbon-copy of `ChainlinkRelayerFactory` with: legs typed as `IDataStreamsRelayer.StreamLeg[]`; constructor/immutables include `verifierProxy` and `maxStaleness`; CREATE2 salt `keccak256("mento.dataStreamsRelayer")`; same `deployRelayer/redeployRelayer/removeRelayer`, `deployedRelayers`, `relayerDeployer`. `sortedOracles` and `verifierProxy` stored on the factory and passed to each relayer.
**Unchanged:** proxy/owner pattern, CREATE2 determinism, enumeration.

### 2.5 Swap-time verification — Broker vs OracleAdapter (decision)

**Decision: the verification call lives in the relayer, invoked as a state-changing pre-step from the swap entry contract (FPMM / Broker / Router). `OracleAdapter` stays a pure `view` read/validation layer.**

Justification:

1. `OracleAdapter`'s entire surface is `view` and is the security-critical _read_ policy (trading mode, FX hours, freshness). Making it a _writer_ and an authorized `SortedOracles` reporter conflates roles, enlarges its attack surface, and breaks every existing `view` caller.
2. The relayer is _already_ the authorized single reporter for its `rateFeedId`. Verification + write belongs there. Nothing else needs `SortedOracles.report` rights.
3. Sequencing is forced anyway (verify must be state-changing and precede the `view` read), so a pre-step is natural.

**Resolution of `rateFeedId → relayer`.** Add a thin, non-view router so swap contracts depend on one address, not on every relayer:

```solidity
// New: minimal non-view ingest router (could be a method ON the existing DataStreamsRelayerFactory,
// or a tiny dedicated OracleIngest contract). Recommended: on the Factory (it already owns the mapping).
function ingest(address rateFeedId, bytes[] calldata signedReports, bytes calldata parameterPayload) external {
  IDataStreamsRelayer relayer = deployedRelayers[rateFeedId];
  require(address(relayer) != address(0), NoRelayer);
  relayer.relay(signedReports, parameterPayload); // state-changing; no-op if already fresh this block
}
```

Swap flow (V3, recommended shape — Router-native):

```
Router.swapExactTokensForTokensWithReports(amountIn, amountOutMin, routes, to, deadline,
                                           bytes[][] signedReportsPerHop, bytes parameterPayload):
    for each hop i: factory.ingest(hop[i].referenceRateFeedID, signedReportsPerHop[i], parameterPayload)  // STATE pre-step
    ... existing getAmountsOut → _swap body, which calls the unchanged VIEW _getRateFeed() → getFXRateIfValid ...
```

> **Decision (see tasks B8/C11).** The swap path is a **Router-native** `swapExactTokensForTokensWithReports` on a **redeployed Router** (the Router is not upgradeable; `factoryRegistry`/forwarder are constructor-immutable). A stateless **Multicall3 periphery** was considered and **rejected on both correctness and security grounds**:
>
> - The Router pulls input tokens from `_msgSender()` ([`Router.swapExactTokensForTokens`](../contracts/swap/router/Router.sol#L249-L254)) and is [`ERC2771Context`](../contracts/swap/router/utils/ERC2771.sol#L25-L35). Calling it through Multicall3 makes `msg.sender == Multicall3` (Multicall3 is not the trusted forwarder), so the `transferFrom` pulls from Multicall3 — which holds nothing — and **the swap reverts**.
> - The only way to make it work is to approve Multicall3 for the input token, which is a **drainable shared-approval footgun**: Multicall3's `aggregate3` executes arbitrary calldata from any caller, so any lingering approval to Multicall3 lets anyone `transferFrom(victim → attacker)`.
>
> Router-native keeps `_msgSender()` intact, preserves the existing approve-the-Router UX and ERC-2771 meta-tx support, and is atomic in a single call frame (tighter than a batch). **MEV is unchanged either way** — `ingest`/`relay` can only write DON-signed, replay-guarded prices, so there is no forgeable-price sandwich vector regardless of the swap wrapper. `factory.ingest` remains the standalone permissionless entry point for recovery/relay (not the swap path).

### 2.6 `Broker` / `BiPoolManager` (V2) modifications

V2 `BiPoolManager` reads `sortedOracles.medianRate` directly, so it _passively_ sees any fresh report. To enable the JIT path on V2, `Broker.swapIn/swapOut` must gain an optional payload and a pre-step:

```solidity
function swapIn(..., bytes[] calldata signedReports) external nonReentrant returns (uint256) {
    if (signedReports.length > 0) factory.ingest(_rateFeedIdFor(exchangeId), signedReports, "");
    ... existing delegation to exchangeProvider.swapIn ...
}
```

This is a **breaking ABI change** to `Broker` (new param) → either a new overload or a `Broker` upgrade + Router update.

> **Scope decision for §10:** do we migrate V2 (`Broker`/`BiPoolManager`) at all, or freeze V2 on push relayers and only run Data Streams on V3 FPMM? Recommend **V3 FPMM first**; treat V2 as Phase-2+ or leave on push.

**Unchanged across §2.5/2.6:** `OracleAdapter` (all view methods), `BreakerBox`, `SortedOracles`, pricing modules' math, FPMM AMM invariant, flash-swap callback semantics.

---

## 3. Cross-rate composition (on-chain, in the relayer)

Same kernel as `ChainlinkRelayerV1` (multiply legs, invert per flag) but verifying signed reports. Example **CELO/PHP** relayer:

- Legs: `[ {feedId: CELO/USD, invert:false}, {feedId: PHP/USD, invert:true} ]`.
- `relay([reportCELOUSD, reportPHPUSD])` → `CELO/USD · (1/(PHP/USD)) = CELO/PHP`.

**`maxTimestampSpread` policy across legs.** Reject if `newestObs − oldestObs > maxTimestampSpread`. This prevents composing a fresh leg with a stale leg into a misleading rate. Recommended starting values are policy TODOs (§5).

**One fresh leg, one borderline-stale leg.** The composite is reported with `compositeObs = oldestObs` (the _weakest_ leg). Two independent gates apply:

1. `maxStaleness`: if `block.timestamp − oldestObs > maxStaleness` → revert `TooStale` (the borderline leg drags the whole composite).
2. `maxTimestampSpread`: if the legs are too far apart in time → revert `SpreadTooHigh`.
   So a fresh+borderline pair is accepted **only** if the borderline leg is still within both `maxStaleness` and the spread budget; otherwise the swap reverts and the swapper must fetch a fresher leg. The fresh leg is deliberately "held back" to the older timestamp — conservative and correct.

**`lastObservationsTimestamp` with multiple legs.** Track it **at the composite level**, equal to `compositeObs = oldestObs`. Rationale: to advance the composite clock you must supply a fresher _binding_ (oldest) leg, which is exactly the leg whose staleness matters. This implicitly defeats replay of an old leg (it can't raise the oldest-leg timestamp). **Per-leg replay tracking is optional defense-in-depth** (a `mapping(bytes32 feedId => uint256) lastSeenObs` to reject an individually-regressing leg early), but is **not** required for correctness given composite monotonicity + spread + staleness.

> **Assumptions (§3).** `BreakerBox.rateFeedDependencies` already lets a composite feed inherit a leg-feed's halt (§1.4). If both the composite _and_ its legs have their own Mento `rateFeedId`s reported, set dependencies so a leg halt halts the composite. If only the composite is reported (legs exist solely as Data Streams `feedId`s, never written to SortedOracles), dependency wiring is N/A and the composite's own breakers carry all the weight. **Decide which model per pair — TODO-XR-1.**

---

## 4. Breaker behaviour under the keeperless pull model

Recall: breakers fire **only inside `SortedOracles.report()` → `checkAndSetBreakers`**. "An update happened" ≡ "a report was written". With no keeper, every report comes from a **permissionless `relay()`** — normally bundled into a swap, occasionally a standalone refresh by anyone who wants the feed live.

The key enabler is the §3 swap-time ordering: within one swap tx the order is `relay() → report() → checkAndSetBreakers() → THEN the view read`. That single ordering is what makes freshness, tripping and recovery all work without a heartbeat.

### 4.1 Freshness is intrinsic — a stale quiet-market median is harmless

The swap **writes a fresh DON report before it reads**, so `OracleAdapter._hasRecentRate` always passes for the transaction that matters. In a quiet market the on-chain median ages, but no value is moving — and the moment someone trades, their own report refreshes it first. (Mandatory: for a migrated pair the swap path must require an attached report, so a swap can never read a stale median. The only consumers that can observe staleness are _view-only_ readers — see §4.5.)

### 4.2 `MedianDeltaBreakerV2` (slew-rate) — tripping is self-protecting

Each report computes the time-normalized allowance (§2.3) and trips if the move is too fast. Because evaluation happens _before_ the read in the same swap, **a swap that brings a flash/anomalous price trips the breaker and is then rejected by its own report** — protection lands exactly when someone tries to trade on a bad price, with no need to detect it in advance. A burst of swaps in one block are idempotent no-ops after the first (§5), so they don't perturb the breaker. Crucially, a _long quiet gap followed by a large legitimate move_ is **allowed** (low velocity), which is the failure mode the EMA had.

### 4.3 `ValueDeltaBreaker`

Stateless vs a fixed reference. Trips whenever a report's median leaves the band. No cadence dependency. Unchanged — and it is the absolute backstop for a gross depeg that creeps in _under_ the slew limit.

### 4.4 `MarketHoursBreaker`

Pure time gate read at swap time inside `OracleAdapter` (§1.7). Independent of report cadence. During FX-closed windows, FX-pair swaps are blocked regardless of report freshness — so FX `maxStaleness` only needs to hold _during_ market hours (§5). Unchanged.

### 4.5 Trip + recovery — who un-trips, with no keeper?

- **Trip:** inside the report that breaches the limit.
- **Un-trip:** `BreakerBox.tryResetBreaker` runs on the _next_ report after `cooldown` elapses and only if `breaker.shouldReset(id)`. A **swap attempt still runs `report()` + `tryResetBreaker` before the read reverts** — so an attempt after cooldown with a price back in band resets the feed and the same swap succeeds. And since `relay()` is permissionless, **anyone** (an arbitrageur wanting the pair live, the dapp, an integrator) can submit a fresh report to drive the reset without a full swap. Recovery is therefore **incentive-driven**, not keeper-dependent: whoever wants the feed live makes it live.
- **Config requirement:** `cooldown` **must be `> 0`** for automatic recovery. `cooldown == 0` forces a manual governance reset — acceptable only as a deliberate kill-switch per feed, never a default.
- **The honest residual:** if literally _nobody_ interacts with a tripped feed, it stays tripped — but no value is at risk while it's idle, and the first party who wants it live unsticks it. There is no keeper for recovery to depend on.

> **View-only readers (the one real downside of keeperless).** A consumer that _reads without writing first_ — a UI, or another protocol reading Mento's oracle — sees a stale median in a quiet market and should trigger a `relay()` (or accept `NoRecentRate`) before relying on the value. This is inherent to **any** pull oracle, not a regression specific to Mento. Document it for integrators (§8) and, for Phase-2 push pairs, this concern does not apply.

> **Assumptions (§4).** Per-feed `slewPerSecond`/`baseJump`/`maxJump` and `cooldown > 0` are policy values — see §2.3/§10.

---

## 5. Replay & staleness policy

### 5.1 Storage

Per relayer (one per `rateFeedId`): `uint256 lastObservationsTimestamp` (composite clock = oldest-leg `observationsTimestamp` last accepted). Optional per-leg `mapping(bytes32 => uint256) lastSeenObs` for defense-in-depth.

### 5.2 Acceptance rule (recommend)

On the composite timestamp `compositeObs`:

- `compositeObs >  lastObservationsTimestamp` → **accept**, write, update clock.
- `compositeObs == lastObservationsTimestamp` → **idempotent no-op** (return, emit `ReportSkippedIdempotent`), do **not** revert.
- `compositeObs <  lastObservationsTimestamp` → **revert `StaleReport`**.

**Why `==` is a no-op rather than `>` strict-revert:** multiple swaps can land in the same block (or two swaps can ride back-to-back before the DON emits a newer report) all carrying the freshest available report. A strict `>` would revert the second swap purely because the DON hasn't emitted a newer report yet. The no-op makes JIT verification **composable within a block** while still rejecting any genuinely older report. This is the "idempotent-within-block acceptable" requirement, implemented without needing block-number bookkeeping.

### 5.3 Dual staleness gates (both enforced, per leg)

- **Hard signature expiry:** `require(block.timestamp <= report.expiresAt)` — the DON-signed expiry; non-negotiable.
- **Mento policy staleness:** `require(block.timestamp - report.observationsTimestamp <= maxStaleness)` — tighter, per-asset-class.

### 5.4 `maxStaleness` defaults (recommended starting points — all TODO-confirm)

> **`maxStaleness` is the _sole_ freshness guarantee.** With no keeper backstop, the only thing forcing a swap to trade on a recent price is the per-leg `maxStaleness` check (plus `expiresAt`). Set it tight enough that no swap can execute against a meaningfully stale price, but loose enough that an honest swapper can always fetch a report and land it within the window. It also feeds the slew breaker indirectly: because every accepted report is within `maxStaleness`, the breaker's `block.timestamp`-Δt ≈ true observation-Δt (§2.3 clock note).

| Asset class                              | Recommended `maxStaleness`                               | Rationale                                                                  | TODO      |
| ---------------------------------------- | -------------------------------------------------------- | -------------------------------------------------------------------------- | --------- |
| Crypto (CELO/USD, USDC, USDT)            | 60–180 s                                                 | sub-second DON cadence; tight bound viable                                 | TODO-ST-1 |
| FX majors (EUR, GBP, JPY, CHF, AUD, CAD) | 300–600 s, **during market hours only**                  | FX updates frequently when open; `MarketHoursBreaker` gates closed windows | TODO-ST-2 |
| Cross-rate composite                     | `max(leg stalenesses)`; effective freshness = oldest leg | composite is only as fresh as its weakest leg                              | TODO-ST-3 |

`maxTimestampSpread` (cross-rate leg skew): recommend ≤ 30–60 s for crypto×crypto, ≤ 120 s for any FX leg. **TODO-ST-4.**

### 5.5 Multi-leg handling

Composite-level replay + spread + staleness as in §3. Per-leg replay optional. The composite timestamp passed to `SortedOracles` is `oldestObs`, so `medianTimestamp` (and hence `OracleAdapter._hasRecentRate` and `MedianDeltaBreakerV2`'s clock) all see the conservative figure.

---

## 6. Per-pair migration matrix

Tokens present in `contracts/tokens/` (proxy list): generic `StableTokenProxy` (cUSD), EUR, GBP, CHF, JPY, AUD, CAD, INR, BRL (cREAL), KES, GHS, ZAR, COP, NGN, PSO (Philippine peso / cPHP), XOF (eXOF). `rateFeedId` convention per §1.10.

Chainlink Data Streams FX coverage = **G10 majors + KRW/SGD/HKD/CNH** today; SGX-FX expansion is adding "G10, Asian, and emerging-market" pairs over time (see Sources). Mento regionals are mostly **not** covered yet.

| Mento pair (rateFeedId)               | Currency class      | Today's oracle              | Data Streams feedId today? | **Phase** | Notes / TODO                         |
| ------------------------------------- | ------------------- | --------------------------- | -------------------------- | --------- | ------------------------------------ |
| CELO/USD (`address(cUSD)` etc.)       | crypto              | `ChainlinkRelayerV1` (push) | likely yes (crypto stream) | **1**     | TODO-FID-1 confirm feedId            |
| USD/USDC (`keccak("USD/USDC")`)       | crypto-stable       | push                        | likely yes                 | **1**     | TODO-FID-2                           |
| EUR/USDC (`keccak("EUR/USDC")`) cross | FX major × stable   | push (multi-leg)            | EUR/USD yes; compose       | **1**     | cross-rate, §3                       |
| USD/EUR (`keccak("USD/EUR")`)         | FX major            | push                        | yes (EUR/USD, invert)      | **1**     | TODO-FID-3                           |
| EUROC/EUR, XOF/EUROC (eXOF stack)     | stable + exotic FX  | push (multi-leg)            | EUROC? XOF **no**          | **2**     | XOF blocks Phase 1; keep push        |
| GBP/USD                               | FX major            | push                        | yes                        | **1**     | TODO-FID-4                           |
| JPY/USD                               | FX major            | push                        | yes                        | **1**     | TODO-FID-5                           |
| CHF/USD                               | FX major            | push                        | yes                        | **1**     | TODO-FID-6                           |
| AUD/USD                               | FX major            | push                        | yes (G10)                  | **1**     | TODO-FID-7                           |
| CAD/USD                               | FX major            | push                        | yes (G10)                  | **1**     | TODO-FID-8                           |
| KES/USD (`0xbAcEE3…c169`)             | exotic FX (African) | push (FPMM cUSD/cKES)       | **no**                     | **2**     | wait for Chainlink                   |
| GHS/USD                               | exotic FX (African) | push                        | **no**                     | **2**     |                                      |
| ZAR/USD                               | EM FX               | push                        | maybe (EM expansion)       | **2**     | TODO-FID-9 reassess                  |
| NGN/USD                               | exotic FX (African) | push                        | **no**                     | **2**     |                                      |
| COP/USD                               | EM FX (LatAm)       | push                        | **no**                     | **2**     |                                      |
| PHP/USD (PSO)                         | EM FX (Asian)       | push                        | maybe (Asian expansion)    | **2**     | TODO-FID-10 reassess                 |
| BRL/USD (cREAL)                       | EM FX (LatAm)       | push                        | maybe (EM expansion)       | **2**     | TODO-FID-11 reassess                 |
| INR/USD                               | EM FX (Asian)       | push                        | maybe (Asian expansion)    | **2**     | TODO-FID-12 reassess                 |
| **All Phase-1 pairs (LWBA)**          | —                   | Data Streams (mid)          | bid/ask in report          | **3**     | expose `bid`/`ask` via OracleAdapter |

- **Phase 1** — migrate to `DataStreamsRelayerV1` now: crypto + G10 FX majors with a confirmed `feedId`.
- **Phase 2** — stays on `ChainlinkRelayerV1` (push) until Chainlink publishes the FX stream: KES, GHS, NGN, XOF, COP, and (reassess) ZAR/PHP/BRL/INR.
- **Phase 3** — LWBA `bid`/`ask` exposure in `OracleAdapter` for already-migrated pairs.

> **Assumptions (§6).** No vendored `mento-deployment` was found in-repo (`grep -ri "mento-deployment"` returned nothing actionable; the only mainnet anchor is `script/DeployV3FPMM.s.sol:70`). The pair list is reconstructed from `contracts/tokens/*Proxy.sol` + `test/integration/protocol/ProtocolTest.sol` fixtures and is **not** the authoritative production registry. **TODO-DEP-1:** reconcile against the real `mento-deployment` repo for the live `rateFeedId`s, aggregator configs, and which pairs are actually live on Celo mainnet. Currency↔stream-availability marked "maybe" must be verified at `docs.chain.link/data-streams/market-hours` (**TODO-CL-3**).

---

## 7. Test strategy

### 7.1 `DataStreamsRelayerV1` unit tests

- Verification: mock `IVerifierProxy.verify` returns a crafted report; assert decode → compose → `report` value.
- Composition: single-leg, 2-leg, 3-leg, 4-leg; invert flags; assert `rate = Πlegs` with inversion.
- Replay: `compositeObs < last` reverts; `== last` no-ops (no revert, no double-report); `> last` accepts.
- Staleness: `block.timestamp > expiresAt` reverts; `obs` older than `maxStaleness` reverts; boundary `==` cases.
- Spread: `newestObs - oldestObs == maxTimestampSpread` (accept) vs `+1` (revert).
- Wrong feedId: leg report `feedId != expected` reverts `WrongFeedId`.
- Reuse of `reportRate` lesser/greater paths (port `ChainlinkRelayerV1.t.sol` cases).

### 7.2 `MedianDeltaBreakerV2` (slew-rate) — verified against an independent reference

- Build a Python/numpy reference implementing `allowed = min(maxJump, baseJump + slewPerSecond·Δt)` and `trip = relΔ > allowed`. Run **≥10 scenarios**: short-Δt flash move (trip); long-gap legitimate drift within slew (allow — the §2.3 example that the old EMA false-tripped); `Δt = 0` same-block second report (uses `baseJump` floor); move exactly at `maxJump` ceiling regardless of huge Δt (trip); seeding (`prev == 0` → no trip, sets anchor); reset path (`shouldReset == !shouldTrigger`); boundary `relΔ == allowed` (no trip); monotone vs oscillating price; very small Δt with tiny move (no trip); `slewPerSecond = 0` degenerate (pure `baseJump`/`maxJump` band).
- Assert the Solidity verdict matches the reference verdict for every scenario, and the computed `allowed` is within `1e-9` relative.
- Regression guard: replay the exact sparse, swap-driven timestamp series from a fork capture (§7.3) and assert **no false trips on legitimate slow drift** — the property keeperless specifically requires.

### 7.3 Foundry fork tests vs real Celo `VerifierProxy`

- Fork Celo mainnet at a pinned block; call the **real** `VerifierProxy.verify`.
- **Fixture-capture flow (you cannot synthesize DON signatures):**
  1. Off-chain, subscribe to the Data Streams API for the target `feedId`s and capture real signed report blobs + the block range they're valid in.
  2. Pin the fork block so `block.timestamp <= expiresAt` holds for the captured reports (or use `vm.warp` to a timestamp inside `[validFromTimestamp, expiresAt]`).
  3. Commit captured blobs as test fixtures; assert end-to-end `relay()` → `SortedOracles.medianRate` updates and breakers evaluate.
- Negative fork tests: tamper one byte of the signature (expect `verify` revert); expired report (warp past `expiresAt`); wrong `feedId`.

### 7.4 Shadow-mode comparison (push vs pull)

- In a fork, run `ChainlinkRelayerV1` and `DataStreamsRelayerV1` for the same pair in parallel over a 24h captured replay; assert `|pull − push| / push <= tolerance` (tolerance TBD, e.g. 10–25 bps) at every step; log max divergence.

### 7.5 Property tests (replay invariants)

- Invariant: `lastObservationsTimestamp` is monotonically non-decreasing across any sequence of `relay` calls.
- Invariant: no two distinct accepted reports share the same `compositeObs` write (the second is a no-op).
- Invariant: a report with `obs <= lastObservationsTimestamp` never changes `SortedOracles.medianRate`.

### 7.6 Negative tests

Expired, mis-signed, wrong-`feedId`, out-of-order (older obs after newer), zero/negative price, leg-count mismatch, spread exceeded, market-closed FX swap.

---

## 8. Off-chain responsibilities (keeperless)

There is **no Mento-operated keeper service**. The off-chain work shrinks to a client SDK / integration concern: whoever submits the transaction fetches the signed report. Mento ships a small library and bears no per-pair, per-chain runtime cost.

**Swap client / SDK (the normal path)**

- Before a swap, fetch the latest signed report(s) for the pair's `feedId` legs from the Data Streams REST/WebSocket API and attach them to the swap calldata (§2.5). This is the only mandatory off-chain step, and it is paid for by the swapper as part of their tx.
- The dapp frontend does this transparently; third-party integrators use the same SDK helper (`fetchReports(rateFeedId) → bytes[]`).

**Recovery / liveness (permissionless, optional, not Mento-run)**

- A tripped or stale feed is unstuck by **anyone** calling `relay()` with a fresh report — typically an arbitrageur who wants the pair tradeable, or the dapp before showing a quote. No privileged role, no SLA.
- Optional public good: Mento _may_ run a tiny opportunistic poker as a convenience, but the system's correctness must **not** depend on it. If run at all, it is best-effort and can be off for any chain/pair.

**View-only integrators (the documented caveat, §4.5)**

- Any contract/UI that reads Mento's oracle without first writing must either trigger a `relay()` or tolerate `NoRecentRate` in quiet markets. Provide guidance + the SDK helper. Phase-2 push pairs are unaffected.

**Failure modes**

- Data Streams API outage → swappers can't fetch reports → swaps on migrated pairs revert (fail-safe). Phase-2 push pairs unaffected. No background process to fail.
- Signed-report stall (DON not advancing) → submitting the same `observationsTimestamp` is an idempotent no-op (§5.2); the swap simply trades on the last fresh value while it's within `maxStaleness`, else reverts.
- Tx revert (`StaleReport`, `SpreadTooHigh`, breaker tripped) → surfaced to the swapper as a normal swap failure; the SDK should re-fetch and retry once.

**Operational metrics (mostly client-side / indexer-derived now)**

- Verify success rate and gas per swap (client telemetry).
- Divergence: pull median vs push relayer during the dual-reporter window (§9), from chain events.
- Breaker trip count + false-positive rate (from `BreakerTripped`/`ResetSuccessful` events) — especially the keeperless-critical metric: **false trips attributable to sparse sampling** (should be ~0 with the slew breaker).
- Time-to-recovery for tripped feeds (event-derived), to confirm incentive-driven recovery is fast enough in practice.

> **Assumptions (§8).** No Chainlink Automation on Celo and, by choice, no Mento keeper. The economic claim — cost scales with usage and is $0 for idle pairs — is the core motivation for the keeperless design. Alert thresholds and whether to run an optional best-effort poker are TODO-OPS-1.

---

## 9. Deployment & governance sequence (per phase)

For each Phase-1 pair, promote **shadow → dual-reporter → single-reporter**.

**Contracts to deploy (addresses TBD):**

- `DataStreamsRelayerFactory` (impl + proxy + proxy-admin), initialized with `sortedOracles`, `verifierProxy` (TODO-CL-addr), `relayerDeployer`.
- One `DataStreamsRelayerV1` per Phase-1 `rateFeedId` (via factory CREATE2).
- `MedianDeltaBreakerV2` (slew-rate, 0.8.19), wired into `BreakerBox` (add breaker, toggle per feed, set `baseJump`/`slewPerSecond`/`maxJump` and **`cooldown > 0`**), keeping `MedianDeltaBreaker` V1 active during dual-run if feasible.
- Swap-side: **redeploy the Router** with `swapExactTokensForTokensWithReports` (+ `zapIn`/`zapOut` variants) that calls `Factory.ingest` per hop as a state-changing pre-step, then repoint the dapp/integrators to the new Router address (§2.5, tasks C11). `Factory.ingest` itself ships with the factory and stays as the standalone recovery entry point — no Multicall3 dependency.
- **No keeper infrastructure to deploy** — only the client SDK / dapp integration (§8).

**Governance proposals (MGP draft titles):**

- _MGP-DS-1: Deploy DataStreamsRelayerFactory & Phase-1 relayers (shadow mode)._
- _MGP-DS-2: Authorize DataStreamsRelayerV1 instances as SortedOracles reporters (dual-reporter)._
- _MGP-DS-3: Adopt MedianDeltaBreakerV2 (slew-rate); set per-feed baseJump/slewPerSecond/maxJump, cooldown > 0, and maxStaleness._
- _MGP-DS-4: Cut Phase-1 pairs to single-reporter (remove push relayer)._
- _MGP-DS-5 (Phase 3): Expose LWBA bid/ask via OracleAdapter._

**Dual-reporter dwell time:** run push + pull as two reporters on the same `SortedOracles` feed for **≥ 2 weeks** (TODO-GOV-1) of live divergence monitoring before removing the push relayer. Note `SortedOracles` median of two reporters = midpoint; `ChainlinkRelayerV1.reportRate` already tolerates exactly one foreign reporter (§1.1) — confirm both relayers coexist without `TooManyExistingReports`.

> **Shadow/dwell uses a temporary, migration-only harness — not the keeper.** To generate pull-side reports for comparison during the window (when organic swap volume may be too sparse to measure divergence), run a **short-lived, single-region** measurement bot that submits `relay()` on a fixed cadence purely for data collection. It is turned **off permanently** at single-reporter cutover — it is a migration instrument, not the steady-state design. The production system remains keeperless (§4/§8).

**Rollback path:** because cutover is a governance `redeployRelayer`/reporter-set change, rollback = re-authorize the push relayer (still deployed) and resume the push bot; or `BreakerBox.setRateFeedTradingMode` to halt the pair while investigating. Keep push relayers deployed and the push bot warm through Phase-1 + one dwell period post-cutover.

**Pre-flight promotion criteria (shadow→dual→single):**

- Divergence: 95th-pct `|pull−push|` ≤ X bps over the dwell window (TODO-GOV-2).
- Latency: report→mined p95 ≤ Y s.
- Breaker false-positive rate: 0 spurious trips attributable to the pull path over the window — **including 0 false trips from sparse/irregular sampling** (the keeperless-critical check for the slew breaker).
- Recovery verified: induce a test trip, then confirm a permissionless `relay()` (and a plain swap attempt) un-trips it after cooldown — no keeper involved.

---

## 10. Open questions for human decision

**Chainlink Labs / external**

- **TODO-CL-addr:** Exact Celo mainnet `VerifierProxy` address. _Could not be auto-fetched_ (the address table at `docs.chain.link/data-streams/crypto-streams` / `…/supported-networks` is JS-rendered). Confirm from the official "Stream Addresses / Supported Networks" page and on-chain before any deploy. **Do not hardcode until verified.**
- **TODO-CL-1/2:** Confirm `VerifierProxy` ABI/version on Celo, whether `verifyBulk` is available, and that `s_feeManager()==address(0)` (no fee, empty `parameterPayload`). Confirm subscription billing terms/coverage with Chainlink Labs.
- **TODO-CL-3 / TODO-FID-\*:** Definitive Data Streams `feedId`s for every Phase-1 pair, and the report schema _version_ per feed (v3 vs v4 / LWBA field layout). Re-confirm which "maybe" EM/Asian FX pairs (ZAR, PHP, BRL, INR) now have streams.

**Product / governance**

- LWBA in Phase 1 or defer to Phase 3? (Recommend **defer** — write mid `price` only first; smaller blast radius.)
- Keeperless confirmed? The swapper pays verification gas per swap (≈ one `verify` + `report`). Confirm this UX/gas trade is acceptable, and whether Mento runs an _optional_ best-effort poker for liveness convenience (not for correctness). (TODO-OPS-1)
- Migrate V2 (`Broker`/`BiPoolManager`) or freeze it on push and migrate only V3 FPMM? (Recommend **V3 FPMM first**.)
- `maxStaleness` / `maxTimestampSpread` per pair, and slew-breaker `baseJump`/`slewPerSecond`/`maxJump`/`cooldown` per feed (TODO-ST-1..4, TODO-BR-1). Note **`cooldown` must be `> 0`** for keeperless auto-recovery.
- Cross-rate model: write only composites, or also write legs as their own Mento feeds and use `rateFeedDependencies`? (TODO-XR-1)
- View-only integrators reading the oracle without writing must `relay()` first or tolerate `NoRecentRate` (§4.5) — confirm this is acceptable for current integrators and documented in the SDK.
- Dwell time and promotion thresholds (TODO-GOV-1/2).
- Reconcile pair list & live `rateFeedId`s against the real `mento-deployment` repo (TODO-DEP-1).

**Pushback callouts (architectural)**

> **Pushback 1 — "relayer runs `checkAndSetBreakers`" is wrong.** It can't (§0/§1.4). Drop it from the design; rely on `SortedOracles.report()` triggering breakers. This is _simpler_ than the brief, not harder.

> **Pushback 2 — swap-time verify cannot live in `OracleAdapter` (it's all `view`).** Put it in the relayer, invoked as a state-changing pre-step via `Factory.ingest`, and keep `OracleAdapter` a pure read layer (§2.5). The swap entry point is a **Router-native** `swapExactTokensForTokensWithReports` (redeployed Router) — **not** a Multicall3 periphery: the Router is `ERC2771Context` and pulls tokens from `_msgSender()`, so a Multicall3 wrapper breaks the token pull and would force a drainable shared approval to Multicall3. `FPMM`/`Broker` core stay untouched.

> **Pushback 3 — a time-weighted EMA does not survive keeperless.** A time-weighted EMA only fixes _accumulation_; its trip test is still "delta since last report" and false-trips on legitimate drift after a quiet gap. Replace it with the **slew-rate breaker** (§2.3), which measures velocity and is cadence-independent. This is the central correctness change — do not ship an EMA-style breaker on a keeperless feed.

> **Pushback 4 — keeperless shifts gas to swappers and leaves view-only readers to self-refresh.** These are the two real costs of removing the keeper (§4.5/§8). Both are acceptable and inherent to pull oracles, but they are product decisions, not silent ones: confirm the per-swap gas UX and give integrators an SDK path. Everything else the keeper did (freshness, tripping, recovery) is covered by the swap-time ordering (§3/§4).

> **Pushback 5 — `cooldown == 0` is now actively dangerous, not just inconvenient.** With no keeper, a feed with `cooldown == 0` can only be reset by manual governance. Make `cooldown > 0` the default and treat `0` as a deliberate, audited kill-switch per feed (§2.3/§4.5).

---

## Sources (Chainlink, for the external facts above — verify before coding)

- Data Streams overview & on-chain verification: <https://docs.chain.link/data-streams> , <https://docs.chain.link/data-streams/reference/data-streams-api/onchain-verification>
- Supported networks / stream (verifier) addresses (JS-rendered — open and expand for Celo): <https://docs.chain.link/data-streams/supported-networks>
- FX market hours & coverage: <https://docs.chain.link/data-streams/market-hours>
- FX expansion context (G10 + Asian + EM): SGX-FX × Chainlink (e.g. <https://www.financemagnates.com/institutional-forex/sgx-fx-adopts-chainlink-to-distribute-otc-forex-data-on-chain/>)
