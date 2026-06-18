# Data Streams fork-test fixtures

The fork tests in [`test/oracles/fork/DataStreamsRelayerFork.t.sol`](../../test/oracles/fork/DataStreamsRelayerFork.t.sol)
exercise `DataStreamsRelayerV1.relay()` against the **real** Chainlink Data Streams
`VerifierProxy` on a Celo fork, using **captured, DON-signed** report blobs.

We cannot synthesize DON signatures off-chain, so these fixtures must be captured from the
live Data Streams API by a human, **once blockers B1 (VerifierProxy address) and B4 (feedIds)
are resolved**. Until `reports.json` exists and the fork env vars are set, the live tests
**SKIP** (they are never silently passed or deleted). The negative-path tests (tampered
signature, expired report, wrong feedId) run unconditionally against a mock.

## Files

| File                   | Committed?          | Purpose                                                              |
| ---------------------- | ------------------- | -------------------------------------------------------------------- |
| `README.md`            | yes                 | This document.                                                       |
| `reports.example.json` | yes                 | Schema template; copy to `reports.json` and fill in.                 |
| `reports.json`         | **no** (gitignored) | The captured fixtures the live tests read. Absent → live tests skip. |

## Capture flow (run once B1/B4 land)

1. **Resolve the inputs** (blocked today):

   - `VerifierProxy` address on the target chain (B1).
   - The Data Streams `feedId`(s) for each leg of the pair (B4).
   - The Mento `rateFeedId` the relayer reports for (B13).

2. **Fetch a fresh signed report** for each leg from the Data Streams API (REST or WebSocket;
   see the `chainlink-data-streams` tooling / SDK). The API returns a `fullReport` blob — the
   ABI-encoded `(bytes32[3] reportContext, bytes reportData, ...)` envelope that `VerifierProxy.verify`
   accepts. Capture the raw blob as `0x`-prefixed hex. This blob is what goes into `signedReport`.

3. **Pin a block.** Record a Celo block number whose timestamp falls inside the report's
   `[validFromTimestamp, expiresAt]` window (and within `maxStaleness` of `observationsTimestamp`).
   The fork is created at this block so the signed report is valid at fork time. The test also
   `vm.warp`s into the validity window as a belt-and-braces measure.

4. **Write `reports.json`** next to this README, matching `reports.example.json`:

   ```json
   {
     "pinBlock": 0,
     "rateFeedId": "0x0000000000000000000000000000000000000000",
     "description": "CELO/USD",
     "maxTimestampSpread": 0,
     "maxStaleness": 120,
     "legs": [{ "feedId": "0x00..32bytes", "invert": false, "signedReport": "0x..." }]
   }
   ```

   - `legs` is ordered (leg `i` → the relayer's leg `i`); `signedReport` is the captured blob.
   - JSON object keys are decoded into the Solidity `FixtureLeg` struct in **alphabetical** order
     (`feedId`, `invert`, `signedReport`) — keep these three keys exactly as named.
   - For a single-leg feed, `maxTimestampSpread` MUST be `0`; for multi-leg it MUST be `> 0`.

5. **Set the fork env vars** and run:

   ```bash
   export DS_FORK_RPC_URL="$CELO_MAINNET_RPC_URL"   # an archive node at/after pinBlock
   export DS_VERIFIER_PROXY=0x...                   # B1
   export DS_SORTED_ORACLES=0x...                   # B5 (deployed SortedOracles)
   forge test --match-path 'test/oracles/fork/*' -vvv
   ```

   With `reports.json` present and the env set, the live test forks, deploys a relayer pointed at
   the real `VerifierProxy`, authorizes it as a reporter on `SortedOracles`, calls `relay()`, and
   asserts a non-zero median is written and the slew breaker evaluates. If any of the file or env
   inputs are missing, the live test skips with a clear reason.

## Why not commit a sample `reports.json`?

A sample blob with a fake signature would fail real verification (correctly), so committing one
would only make the live test skip-or-fail on garbage. The example schema is committed instead;
real, signed fixtures are captured locally. **Do not** weaken the live path to accept unsigned or
mock data — that would defeat the purpose of a fork test against the real verifier.
