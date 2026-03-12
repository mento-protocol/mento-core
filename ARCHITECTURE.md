# Mento Core Architecture

Mento is a decentralized multi-currency stablecoin platform and onchain FX infrastructure. This document provides a high-level map of the contract system for new contributors and auditors.

## System Overview

Mento enables users to swap between a reserve asset (e.g., CELO) and Mento-issued stablecoins (e.g., USDm, EURm, BRLm) using oracle-driven AMMs. The protocol maintains a shared reserve of collateral assets and enforces circuit breakers to halt trading during price anomalies.

The system is going multi-chain, with cross-chain stable token spokes (`StableTokenSpoke`) alongside the original Celo-native hub contracts.

---

## Contract Subsystems

### 1. Broker / Exchange Providers — Swap Routing

**Location:** `contracts/swap/`

The **Broker** (`Broker.sol`) is the main entry point for all token swaps. It:
- Routes swap requests to registered exchange providers
- Enforces per-pair trading limits via the `TradingLimits` library
- Executes minting/burning of stable tokens through the reserve

**Exchange Providers** implement the actual AMM pricing:

| Contract | Description |
|---|---|
| `BiPoolManager.sol` | V1: Virtual two-asset pools with spread-based pricing using SortedOracles |
| `FPMM.sol` | V2: Fixed Price Market Maker — oracle-based AMM with pool rebalancing |
| `FPMMFactory.sol` | Factory for deploying FPMM pool instances |
| `BancorExchangeProvider.sol` | Bancor-formula AMM for the GoodDollar integration |
| `GoodDollarExchangeProvider.sol` | Extends BancorExchangeProvider with expansion controller and DAO Avatar access |

The `Router.sol` provides a multi-hop swap path through compatible exchange providers.

**Liquidity Strategies** (`contracts/liquidityStrategies/`) govern pool rebalancing:
- `OpenLiquidityStrategy` — rebalances by swapping via FPMM
- `ReserveLiquidityStrategy` — rebalances by drawing from the Reserve
- `CDPLiquidityStrategy` — rebalances using a CDP system for collateral

---

### 2. Oracle / Relayers

**Location:** `contracts/oracles/`

| Contract | Description |
|---|---|
| `ChainlinkRelayerV1.sol` | Bridges Chainlink aggregator feeds to SortedOracles. Supports up to 4 feeds, rate inversion, and composite rates (e.g., CELO/PHP = CELO/USD / PHP/USD). One instance per rate feed. |
| `ChainlinkRelayerFactory.sol` | Factory for deploying ChainlinkRelayerV1 instances |
| `OracleAdapter.sol` | Unified price interface consumed by FPMM and liquidity strategies. Aggregates SortedOracles + BreakerBox. Checks L2 sequencer uptime on Arbitrum/Optimism. |
| `BreakerBox.sol` | Circuit breaker registry. Maintains a list of breakers per rate feed and returns a trading mode (bidirectional / sell-only / buy-only / halted). |

**Breaker types** (`contracts/oracles/breakers/`):
- `MedianDeltaBreaker` — triggers on large relative price deviations
- `ValueDeltaBreaker` — triggers on absolute value changes
- `MarketHoursBreaker` — halts trading outside defined market hours

---

### 3. Tokens

**Location:** `contracts/tokens/`, `contracts/governance/`

| Contract | Description |
|---|---|
| `StableTokenV2.sol` | Primary ERC20 stable asset with ERC20Permit support. Multiple currency deployments (USDm, EURm, BRLm, etc.) each have their own proxy. |
| `StableTokenV3.sol` | Extended stable token with additional features |
| `StableTokenSpoke.sol` | Cross-chain stable token for multi-chain deployments |
| `TempStable.sol` | Temporary stable token used during migrations or bootstrapping |
| `MentoToken.sol` | Governance token (MENTO). ERC20Burnable, 1B total supply. Locking and Emission contracts have transfer permission when paused. Not upgradeable. |

Each stable currency has a corresponding proxy contract (e.g., `StableTokenAUDProxy.sol`, `StableTokenEURProxy.sol`) to allow independent deployments sharing the same implementation.

---

### 4. Governance

**Location:** `contracts/governance/`

| Contract | Description |
|---|---|
| `MentoGovernor.sol` | OpenZeppelin Governor with voting power from locked MENTO tokens. 7-day voting period, 2% quorum, 10,000 MENTO proposal threshold. |
| `TimelockController.sol` | 2-day delay timelock. Queues and executes approved governance proposals. Roles: PROPOSER (Governor), EXECUTOR (anyone after delay). |
| `Locking.sol` | Token locking with cliff+slope vesting schedule. Locked MENTO earns voting power. Supports delegation and relocking. |
| `MentoToken.sol` | Governance token (see Tokens above) |
| `Emission.sol` | Controls ongoing token emission schedule |
| `Airgrab.sol` | Merkle-based airdrop distribution |
| `GovernanceFactory.sol` | Deploys the entire governance system in one transaction (MentoToken, Locking, Emission, Airgrab, TimelockController, MentoGovernor, ProxyAdmin). Pre-calculates contract addresses by nonce for verification. |

---

### 5. Reserve

**Location:** `contracts/swap/`

| Contract | Description |
|---|---|
| `Reserve.sol` | V1: Manages protocol collateral. Handles stable token lists, collateral asset lists, Tobin tax, daily spending limits, and asset allocation weights. |
| `ReserveV2.sol` | Modern reserve with cleaner API. Two spender roles: LiquidityStrategySpender (unrestricted destination) and ReserveManagerSpender (inter-reserve transfers). No Tobin tax or registry dependency. |

---

## Key Interaction Flows

### Swap Flow

```
User calls Broker.swapIn(tokenIn, tokenOut, amount)
  │
  ├─ Broker looks up exchange provider for the pair
  │
  ├─ ExchangeProvider (FPMM or BiPoolManager) called
  │     └─ FPMM queries OracleAdapter for price
  │           └─ OracleAdapter checks BreakerBox (circuit breakers)
  │
  ├─ Broker enforces TradingLimits for the pair
  │
  └─ Token transfer:
       - tokenIn burned (if stable) or transferred to Reserve
       - tokenOut minted (if stable) or transferred from Reserve
```

### Oracle Update Flow

```
Chainlink network updates aggregator price
  │
  ├─ ChainlinkRelayerV1.relay() called (permissionlessly)
  │     └─ Validates timestamp spread across feeds
  │     └─ Computes composite rate if needed
  │     └─ Reports to SortedOracles
  │
  ├─ BreakerBox breakers evaluate new rate
  │     └─ MedianDeltaBreaker / ValueDeltaBreaker / MarketHoursBreaker
  │     └─ Update trading mode for the rate feed
  │
  └─ OracleAdapter reflects new rate and trading mode
        └─ Consumed by FPMM, liquidity strategies, and BiPoolManager
```

### Governance Proposal Flow

```
MENTO holder calls Locking.lock(amount, slope, cliff)
  │
  └─ Voting power accrues week-by-week per vesting schedule

Holder calls MentoGovernor.propose(targets, values, calldatas, description)
  │
  └─ Voting period opens (7 days)

Voters call MentoGovernor.castVote(proposalId, support)
  │
  └─ After voting period: if quorum met and FOR > AGAINST

MentoGovernor.queue(proposalId)
  │
  └─ TimelockController queues execution (2-day delay)

After delay: MentoGovernor.execute(proposalId)
  │
  └─ TimelockController calls target contracts
```

---

## Upgradeability Notes

| Pattern | Used By |
|---|---|
| **Celo Proxy** (custom, non-OZ) | `Broker`, `BiPoolManager`, `Reserve` (V1 contracts) |
| **OpenZeppelin TransparentUpgradeableProxy** | `FPMM`, `FPMMFactory`, `MentoGovernor`, `Locking`, `ReserveV2`, `LiquidityStrategy` variants |
| **ERC-7201 namespaced storage** | `FPMM`, `LiquidityStrategy` — avoids storage collisions in upgradeable contracts |
| **Non-upgradeable (direct deployment)** | `MentoToken`, `ChainlinkRelayerV1` |

All upgradeable contracts use `Initializable` and `_disableInitializers()` in their constructors to prevent implementation contract initialization.

---

## Entry Points

**Start here depending on your focus area:**

| Area | Start With |
|---|---|
| Swap / AMM | `contracts/interfaces/IBroker.sol` → `contracts/swap/FPMM.sol` |
| Oracle system | `contracts/oracles/OracleAdapter.sol` → `contracts/oracles/BreakerBox.sol` |
| Governance | `contracts/governance/GovernanceFactory.sol` → `contracts/governance/locking/Locking.sol` |
| Token issuance | `contracts/tokens/StableTokenV2.sol` → `contracts/swap/ReserveV2.sol` |
| Pool rebalancing | `contracts/liquidityStrategies/LiquidityStrategy.sol` |
| GoodDollar integration | `contracts/goodDollar/GoodDollarExchangeProvider.sol` |
| Deployment scripts | `contracts/governance/deployers/` |

**Solidity versions:** Legacy contracts use `^0.5.13`; modern contracts use `^0.8.18–0.8.24`.

**Testing:** All tests are in `test/` and run with Foundry (`forge test --no-match-contract ForkTest` for unit tests only, as fork tests require RPC access).
