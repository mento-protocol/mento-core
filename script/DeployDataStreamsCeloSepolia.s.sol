// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { DeployDataStreams } from "./DeployDataStreams.s.sol";
import { IPullOracleRelayer } from "contracts/interfaces/IPullOracleRelayer.sol";

/**
 * Usage:
 *   forge script script/DeployDataStreamsCeloSepolia.s.sol:DeployDataStreamsCeloSepolia \
 *     --rpc-url https://forno.celo-sepolia.celo-testnet.org \
 *     --sender <deployer> [--broadcast]
 *
 * Celo Sepolia (chainId 11142220) Phase-1 deploy: the generic DeployDataStreams flow with the
 * confirmed testnet config baked in as defaults (every value still env-overridable). Single
 * feed: EUR/USD, one V8 forex Data Streams leg, direct orientation (report price is EUR in
 * USD, matching the existing SortedOracles median ~1.14e24).
 *
 * Confirmed on-chain/testnet facts (2026-06/07 fork sessions + live reads 2026-07-20):
 *   - VerifierProxy 2.0.0, s_feeManager() == 0 (fee-less verifyBulk, empty parameterPayload)
 *   - SortedOracles and BreakerBox are both owned by the team testnet deployer EOA
 *   - EUR/USD rateFeedId has exactly one existing reporter (0x0839...bD69), so the relayer
 *     fits within PullOracleRelayerV1's <=2-reporter constraint
 */
contract DeployDataStreamsCeloSepolia is DeployDataStreams {
  uint256 public constant CELO_SEPOLIA_CHAIN_ID = 11142220;

  // Chainlink Data Streams on Celo Sepolia
  address public constant VERIFIER_PROXY = 0x72790f9eB82db492a7DDb6d2af22A270Dcc3Db64;
  // EUR/USD V8 forex testnet feedId (the V4 feed is deprecated)
  bytes32 public constant FEED_ID_EUR_USD = 0x0008a5f1391bcc93839075abbbd2b10eaf17cbc278996e843a2e38352f60a7a5;

  // Mento on Celo Sepolia
  address public constant SORTED_ORACLES = 0xfaa7Ca2B056E60F6733aE75AA0709140a6eAfD20;
  address public constant BREAKER_BOX = 0x578bD46003B9D3fd4c3C3f47c98B329562a6a1dE;
  // referenceRateFeedID of the USDm/EURm FPMM pool
  address public constant RATE_FEED_EUR_USD = 0x5D5a22116233BDb2a9C2977279cC348B8b8Ce917;

  function _loadGlobals(address deployer) internal view override returns (Globals memory g) {
    require(block.chainid == CELO_SEPOLIA_CHAIN_ID, "wrong chain: expected Celo Sepolia");
    g = super._loadGlobals(deployer);
    if (g.sortedOracles == _tbdAddr("sortedOracles")) g.sortedOracles = SORTED_ORACLES;
    if (g.verifierProxy == _tbdAddr("verifierProxy")) g.verifierProxy = VERIFIER_PROXY;
    if (g.breakerBox == _tbdAddr("breakerBox")) g.breakerBox = BREAKER_BOX;
  }

  function _loadFeeds() internal view override returns (FeedConfig[] memory feeds) {
    IPullOracleRelayer.OracleLeg[] memory legs = new IPullOracleRelayer.OracleLeg[](1);
    legs[0] = IPullOracleRelayer.OracleLeg(vm.envOr("DS_FEEDID_EUR_USD", FEED_ID_EUR_USD), false);

    feeds = new FeedConfig[](1);
    feeds[0].rateFeedId = vm.envOr("DS_RATEFEED_EUR_USD", RATE_FEED_EUR_USD);
    feeds[0].description = "EUR/USD";
    feeds[0].maxTimestampSpread = 0; // single leg => must be 0
    feeds[0].maxStaleness = vm.envOr("DS_STALENESS_EUR_USD", uint256(300)); // forex
    feeds[0].legs = legs;
    feeds[0].baseJump = vm.envOr("DS_BASEJUMP_EUR_USD", uint256(5e21)); // 0.5%
    feeds[0].slewPerSecond = vm.envOr("DS_SLEW_EUR_USD", uint256(5555555555555555555)); // 2%/h
    feeds[0].maxJump = vm.envOr("DS_MAXJUMP_EUR_USD", uint256(5e22)); // 5%
    feeds[0].cooldown = vm.envOr("DS_COOLDOWN_EUR_USD", uint256(300)); // > 0
  }
}
