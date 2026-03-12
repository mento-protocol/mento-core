# Mento Core — Architecture

This document describes the contract subsystems, key interaction flows, upgradeability patterns, and recommended entry points for `mento-core`.

For a higher-level product overview, see the [Mento documentation](https://docs.mento.org/mento/mento-protocol/readme).

---

## 1. System Overview

`mento-core` implements the on-chain infrastructure for Mento — a decentralized, multi-currency stablecoin platform and FX-rate settlement layer built initially on Celo and expanding multi-chain.

The protocol lets users swap between collateral assets and stable tokens at oracle-determined FX rates, subject to circuit breakers and trading limits enforced in smart contracts. Stable tokens are minted or burned through the **Broker** based on pool reserves. Governance is handled by a fully on-chain DAO (MentoToken + MentoGovernor + TimelockController).

---

## 2. Contract Subsystems

### 2.1 Broker / Exchange Providers (Swap routing)

| Contract | Location | Role |
|----------|----------|------|
| `Broker.sol` | `contracts/swap/Broker.sol` | Main swap entry point. Routes swaps through registered exchange providers, enforces trading limits, and mints/burns stable tokens. |
| `BrokerProxy.sol` | `contracts/swap/BrokerProxy.sol` | Celo Proxy wrapper for Broker. |
| `BiPoolManager.sol` | `contracts/swap/BiPoolManager.sol` | Manages two-token (bi-directional) exchange pools. Implements `IExchangeProvider`. Reads from BreakerBox to apply circuit breakers. |
| `FPMM.sol` | `contracts/swap/FPMM.sol` | Fixed Product Market Maker (constant-product AMM) pool implementation. |
| `FPMMFactory.sol` | `contracts/swap/FPMMFactory.sol` | Factory for creating FPMM pool instances. |
| `Router.sol` | `contracts/swap/router/Router.sol` | Higher-level router that composes multi-hop swaps across pools. |
| `VirtualPool.sol` | `contracts/swap/virtual/VirtualPool.sol` | Abstraction for virtual (off-chain liquidity backed) pools. |
| `ConstantProductPricingModule.sol` | `contracts/swap/` | Constant-product pricing math (Uniswap V2 style). |
| `ConstantSumPricingModule.sol` | `contracts/swap/` | Constant-sum pricing math (for pegged pairs). |

**GoodDollar Exchange Providers:**

| Contract | Location | Role |
|----------|----------|------|
| `BancorExchangeProvider.sol` | `contracts/goodDollar/` | Bancor-formula AMM for GoodDollar expansion. |
| `BancorFormula.sol` | `contracts/goodDollar/` | Pure math library implementing the Bancor bonding curve. |
| `GoodDollarExchangeProvider.sol` | `contracts/goodDollar/` | GoodDollar-specific exchange provider wired to the expansion controller. |
| `GoodDollarExpansionController.sol` | `contracts/goodDollar/` | Controls GoodDollar token supply expansion via the exchange provider. |

---

### 2.2 Oracle / Relayers (Price feeds and circuit breakers)

| Contract | Location | Role |
|----------|----------|------|
| `BreakerBox.sol` | `contracts/oracles/BreakerBox.sol` | Aggregates oracle rate data and evaluates circuit breakers. BiPoolManager consults it before allowing a swap. |
| `ChainlinkRelayerV1.sol` | `contracts/oracles/ChainlinkRelayerV1.sol` | Reads from a Chainlink price feed and relays the result into the Mento oracle system (SortedOracles). |
| `ChainlinkRelayerFactory.sol` | `contracts/oracles/ChainlinkRelayerFactory.sol` | Factory for deploying new `ChainlinkRelayerV1` instances. |
| `OracleAdapter.sol` | `contracts/oracles/OracleAdapter.sol` | Adapts raw oracle prices for consumption by exchange providers. |
| `MedianDeltaBreaker.sol` | `contracts/oracles/breakers/` | Circuit breaker that trips when price deviates too far from a recent median. |
| `ValueDeltaBreaker.sol` | `contracts/oracles/breakers/` | Circuit breaker based on absolute value deviation. |
| `MarketHoursBreaker.sol` | `contracts/oracles/breakers/` | Circuit breaker that restricts trading to defined market hours. |

---

### 2.3 Tokens (Stable assets)

| Contract | Location | Role |
|----------|----------|------|
| `StableTokenV2.sol` | `contracts/tokens/StableTokenV2.sol` | Core ERC-20 stable token with mint/burn capability. Base for all Mento stable currencies (cUSD, cEUR, cREAL, etc.). |
| `StableTokenV3.sol` | `contracts/tokens/StableTokenV3.sol` | Enhanced V3 stable token with additional features. |
| `StableTokenSpoke.sol` | `contracts/tokens/StableTokenSpoke.sol` | Bridge-compatible spoke token for cross-chain deployments. |
| `TempStable.sol` | `contracts/tokens/TempStable.sol` | Temporary stub used during new stable-token deployment bootstrapping. |
| `StableToken*Proxy.sol` | `contracts/tokens/` | Per-currency Celo Proxy wrappers (15+ currencies: AUD, BRL, CAD, CHF, COP, EUR, GBP, GHS, INR, JPY, KES, NGN, PSO, XOF, ZAR). |

---

### 2.4 Governance (DAO)

| Contract | Location | Role |
|----------|----------|------|
| `MentoToken.sol` | `contracts/governance/MentoToken.sol` | ERC-20 governance token (MENTO). Supports locking for voting power. |
| `MentoGovernor.sol` | `contracts/governance/MentoGovernor.sol` | On-chain governance executor (OpenZeppelin Governor). Proposals pass through the timelock. |
| `TimelockController.sol` | `contracts/governance/TimelockController.sol` | Timelock that delays execution of governance decisions. |
| `Locking.sol` | `contracts/governance/locking/Locking.sol` | Vote escrow — lock MENTO to receive time-weighted voting power. |
| `Emission.sol` | `contracts/governance/Emission.sol` | Controls the MENTO emission schedule. |
| `Airgrab.sol` | `contracts/governance/Airgrab.sol` | Merkle-proof airdrop for initial token distribution. |
| `GovernanceFactory.sol` | `contracts/governance/GovernanceFactory.sol` | Deploys the full governance stack atomically. |

---

### 2.5 Reserve

| Contract | Location | Role |
|----------|----------|------|
| `Reserve.sol` | `contracts/swap/Reserve.sol` | Holds collateral assets backing the stable tokens. Broker calls into Reserve to transfer collateral during swaps. |
| `ReserveV2.sol` | `contracts/swap/ReserveV2.sol` | Extended reserve with additional asset management and strategy support. |

---

### 2.6 Liquidity Strategies

| Contract | Location | Role |
|----------|----------|------|
| `CDPLiquidityStrategy.sol` | `contracts/liquidityStrategies/` | CDP (Collateralized Debt Position) based liquidity provisioning. |
| `OpenLiquidityStrategy.sol` | `contracts/liquidityStrategies/` | Open market rebalancing strategy that allows direct rebalancing calls. |
| `ReserveLiquidityStrategy.sol` | `contracts/liquidityStrategies/` | Reserve-backed liquidity provisioning. |

---

## 3. Key Interaction Flows

### 3.1 Swap Flow

```
User
 │
 ▼
Broker.swap(exchangeProvider, exchangeId, tokenIn, tokenOut, amountIn, minAmountOut)
 │
 ├─► TradingLimits.update()          [check & update per-pool limits]
 │
 ├─► IExchangeProvider(BiPoolManager).swap()
 │     │
 │     ├─► BreakerBox.checkAndSetBreakers()   [oracle circuit breaker check]
 │     │     └─► MedianDeltaBreaker / ValueDeltaBreaker / MarketHoursBreaker
 │     │
 │     └─► PricingModule.getAmountOut()       [constant-product / constant-sum math]
 │
 ├─► Reserve.transferOut(tokenIn)    [pull collateral from user → reserve]
 │
 └─► StableToken.mint(tokenOut)      [mint stable token → user]
     OR Reserve.transferIn(tokenOut) [transfer stable → collateral]
```

### 3.2 Oracle Update Flow

```
Chainlink Feed (off-chain)
 │
 ▼
ChainlinkRelayerV1.relay()
 │
 └─► SortedOracles.report(rateFeedId, price, ...)   [Celo oracle contract]
       │
       └─► BreakerBox (consulted lazily on next swap)
             └─► Breakers evaluate deviation / market hours
```

### 3.3 Governance Proposal Flow

```
MENTO Holder
 │
 ▼ lock MENTO
Locking.lock()   →   voting power accrues
 │
 ▼
MentoGovernor.propose(targets, values, calldatas, description)
 │
 ▼ (voting period passes, quorum reached, vote succeeds)
MentoGovernor.queue()
 │
 └─► TimelockController.schedule(...)   [delay enforced here]
       │
       ▼ (timelock delay elapses)
TimelockController.execute(...)
 │
 └─► target.call(calldata)              [e.g. Broker.addExchangeProvider, Reserve.addToken]
```

---

## 4. Upgradeability Notes

Two proxy patterns are used in `mento-core`:

### 4.1 Celo Proxy Pattern

Most protocol contracts use a lightweight `Proxy.sol` inherited from Celo's contract suite. Proxy ownership is managed separately and upgrade calls go through the proxy's `_setImplementation` / `_transferOwnership` functions.

**Contracts using Celo Proxy:**
- `BrokerProxy` → `Broker`
- `BiPoolManagerProxy` → `BiPoolManager`
- `ReserveProxy` → `Reserve`
- All `StableToken*Proxy` contracts (15+ currencies)

### 4.2 Transparent Upgradeable Proxy (OpenZeppelin)

Some newer contracts use OpenZeppelin's `TransparentUpgradeableProxy`, managed by a `ProxyAdmin`.

**Contracts using Transparent Proxy:**
- `FPMMProxy` → `FPMM`
- `ChainlinkRelayerFactoryProxy` → `ChainlinkRelayerFactory`

### 4.3 Non-upgradeable Contracts

Governance contracts (`MentoToken`, `MentoGovernor`, `TimelockController`, `Locking`) are **not upgradeable** — they are deployed directly without proxies. Changes require governance to deploy a new instance and migrate.

---

## 5. Entry Points — Where to Start Reading

| Goal | Start here |
|------|-----------|
| Understand swap mechanics | `contracts/swap/Broker.sol` |
| Understand AMM pricing | `contracts/swap/FPMM.sol`, `ConstantProductPricingModule.sol` |
| Understand oracle circuit breakers | `contracts/oracles/BreakerBox.sol` |
| Understand Chainlink price relay | `contracts/oracles/ChainlinkRelayerV1.sol` |
| Understand stable token minting | `contracts/tokens/StableTokenV2.sol` |
| Understand governance voting | `contracts/governance/MentoGovernor.sol`, `Locking.sol` |
| Understand reserve collateral | `contracts/swap/Reserve.sol` |
| Understand GoodDollar integration | `contracts/goodDollar/BancorExchangeProvider.sol` |
| Understand multi-hop routing | `contracts/swap/router/Router.sol` |
| See all interfaces | `contracts/interfaces/` |

