// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Script, console } from "forge-std/Script.sol";

// Pull-oracle contracts
import { PullOracleRelayerFactory } from "contracts/oracles/PullOracleRelayerFactory.sol";
import { PullOracleRelayerFactoryProxy } from "contracts/oracles/PullOracleRelayerFactoryProxy.sol";
import { PullOracleRelayerFactoryProxyAdmin } from "contracts/oracles/PullOracleRelayerFactoryProxyAdmin.sol";
import { ChainlinkDataStreamsAdapter } from "contracts/oracles/adapters/ChainlinkDataStreamsAdapter.sol";

// Interfaces
import { IPullOracleRelayer } from "contracts/interfaces/IPullOracleRelayer.sol";
import { IPullOracleRelayerFactory } from "contracts/interfaces/IPullOracleRelayerFactory.sol";

// Breakers
import { MedianDeltaBreakerV2 } from "contracts/oracles/breakers/MedianDeltaBreakerV2.sol";

/**
 * @notice Minimal subset of BreakerBox used for wiring. Hand-copied because BreakerBox
 *         is a 0.5.13 contract, so we can't import the interface directly.
 */
interface IBreakerBoxMin {
  function owner() external view returns (address);

  function isBreaker(address breaker) external view returns (bool);

  function rateFeedStatus(address rateFeedID) external view returns (bool);

  function addBreaker(address breaker, uint8 tradingMode) external;

  function addRateFeed(address rateFeedID) external;

  function toggleBreaker(address breakerAddress, address rateFeedID, bool enable) external;
}

/**
 * Usage:
 *   # Dry run (no broadcast); all config read from env vars with TBD placeholder fallbacks:
 *   forge script script/DeployDataStreams.s.sol:DeployDataStreams --sig 'run()'
 *
 *   # Against a Celo fork, broadcasting:
 *   forge script script/DeployDataStreams.s.sol:DeployDataStreams \
 *     --rpc-url $CELO_RPC_URL \
 *     --broadcast
 *
 * This is the Phase-1 deploy for the Chainlink Data Streams oracle path (task DP1). It
 * deploys the PullOracleRelayerFactory behind a transparent proxy, one PullOracleRelayerV1
 * per Phase-1 rateFeedId (via the factory's CREATE2 path), and MedianDeltaBreakerV2, then
 * wires the breaker into the existing BreakerBox.
 *
 * Because blockers B1/B4/B5/B10/B13 are unresolved, every external address, feedId and
 * per-feed parameter is read from an environment variable and falls back to a clearly-marked,
 * non-zero TBD placeholder when unset, so nothing real is hardcoded. The BreakerBox wiring
 * only runs when a BreakerBox exists at the configured address and the deployer owns it;
 * otherwise it is skipped (on mainnet it is an owner-gated governance/MGP action). The legacy
 * MedianDeltaBreaker (V1) is intentionally left intact so both breakers run in parallel
 * during migration (dual-run).
 */
contract DeployDataStreams is Script {
  // ============ Config Types ============
  /**
   * @notice Per-feed deployment + breaker configuration.
   * @custom:member rateFeedId Mento rateFeedId the relayer reports for (TBD: B13).
   * @custom:member description Human-readable rate feed, e.g. "CELO/USD".
   * @custom:member maxTimestampSpread Cross-leg skew budget; must be 0 for single-leg feeds.
   * @custom:member maxStaleness Relayer freshness bound in seconds (TBD: B10).
   * @custom:member legs Data Streams legs composing the price path (feedIds TBD: B4).
   * @custom:member baseJump Slew breaker base jump, Fixidity 1e24 (TBD: B10).
   * @custom:member slewPerSecond Slew breaker per-second allowance (TBD: B10).
   * @custom:member maxJump Slew breaker hard ceiling (TBD: B10).
   * @custom:member cooldown Breaker auto-reset cooldown; must be > 0 (TBD: B10).
   */
  struct FeedConfig {
    address rateFeedId;
    string description;
    uint256 maxTimestampSpread;
    uint256 maxStaleness;
    IPullOracleRelayer.OracleLeg[] legs;
    uint256 baseJump;
    uint256 slewPerSecond;
    uint256 maxJump;
    uint256 cooldown;
  }

  /**
   * @notice Global, non-per-feed configuration.
   * @custom:member sortedOracles Existing SortedOracles the relayers report to (TBD: B5).
   * @custom:member verifierProxy Chainlink Data Streams VerifierProxy (TBD: B1).
   * @custom:member breakerBox Existing BreakerBox the breaker is wired into.
   * @custom:member relayerDeployer Account allowed to deploy relayers via the factory.
   * @custom:member finalOwner Owner the breaker (and factory) is handed to after setup.
   * @custom:member defaultCooldown Breaker default cooldown; must be > 0 (TBD: B10).
   * @custom:member defaultBaseJump Breaker default base jump (TBD: B10).
   * @custom:member defaultSlewPerSecond Breaker default slew per second (TBD: B10).
   * @custom:member defaultMaxJump Breaker default max jump (TBD: B10).
   * @custom:member breakerTradingMode Trading mode imposed when tripped; must be != 0.
   */
  struct Globals {
    address sortedOracles;
    address verifierProxy;
    address breakerBox;
    address relayerDeployer;
    address finalOwner;
    uint256 defaultCooldown;
    uint256 defaultBaseJump;
    uint256 defaultSlewPerSecond;
    uint256 defaultMaxJump;
    uint8 breakerTradingMode;
  }

  // ============ Deployed Contracts ============
  ChainlinkDataStreamsAdapter public chainlinkAdapter;
  PullOracleRelayerFactoryProxyAdmin public proxyAdmin;
  PullOracleRelayerFactoryProxy public factoryProxy;
  IPullOracleRelayerFactory public factory;
  MedianDeltaBreakerV2 public breakerV2;
  address[] public relayers;
  string[] public relayerDescriptions;

  function run() public {
    address deployer = msg.sender;
    Globals memory g = _loadGlobals(deployer);
    FeedConfig[] memory feeds = _loadFeeds();
    _warnPlaceholders(g, feeds);

    console.log("=== Data Streams Phase-1 Deployment (DP1) ===");
    console.log("Deployer:       ", deployer);
    console.log("Chain ID:       ", block.chainid);
    console.log("SortedOracles:  ", g.sortedOracles);
    console.log("VerifierProxy:  ", g.verifierProxy);
    console.log("BreakerBox:     ", g.breakerBox);
    console.log("Phase-1 feeds:  ", feeds.length);

    vm.startBroadcast(deployer);

    // Deploy the factory (impl + proxyAdmin + proxy)
    _deployFactory(g);

    // Deploy one relayer per Phase-1 rate feed via the factory's CREATE2 path
    _deployRelayers(feeds);

    // Deploy the slew-rate breaker and configure its per-feed parameters
    _deployBreaker(g);
    _configureBreakerPerFeed(feeds);

    // Wire the breaker into the existing BreakerBox (governance action on mainnet)
    _wireBreakerBox(g, feeds, deployer);

    // Hand the breaker over to the final owner (e.g. governance)
    _handOverOwnership(g, deployer);

    vm.stopBroadcast();

    _printSummary(g);
  }

  // ============ Deploy Steps ============

  function _deployFactory(Globals memory g) internal {
    // Provider adapter: isolates all Chainlink Data Streams specifics (VerifierProxy, report
    // schemas) behind the IPullOracleAdapter interface the factory/relayers consume.
    chainlinkAdapter = new ChainlinkDataStreamsAdapter(g.verifierProxy);
    vm.label(address(chainlinkAdapter), "ChainlinkDataStreamsAdapter");
    console.log("ChainlinkDataStreamsAdapter:", address(chainlinkAdapter));

    // The implementation has its initializer disabled; the proxy is the live instance.
    PullOracleRelayerFactory impl = new PullOracleRelayerFactory(true);
    vm.label(address(impl), "PullOracleRelayerFactory Implementation");
    console.log("Factory Implementation:", address(impl));

    proxyAdmin = new PullOracleRelayerFactoryProxyAdmin();
    vm.label(address(proxyAdmin), "PullOracleRelayerFactory ProxyAdmin");
    console.log("Factory ProxyAdmin:    ", address(proxyAdmin));

    bytes memory initData = abi.encodeWithSelector(
      IPullOracleRelayerFactory.initialize.selector,
      g.sortedOracles,
      address(chainlinkAdapter),
      g.relayerDeployer
    );
    factoryProxy = new PullOracleRelayerFactoryProxy(address(impl), address(proxyAdmin), initData);
    factory = IPullOracleRelayerFactory(address(factoryProxy));
    vm.label(address(factoryProxy), "PullOracleRelayerFactory");
    console.log("Factory (proxy):       ", address(factoryProxy));
  }

  function _deployRelayers(FeedConfig[] memory feeds) internal {
    for (uint256 i = 0; i < feeds.length; i++) {
      FeedConfig memory f = feeds[i];

      // Predict the CREATE2 address, then deploy and assert they match.
      address predicted = factory.computeRelayerAddress(
        f.rateFeedId,
        f.description,
        f.maxTimestampSpread,
        f.maxStaleness,
        f.legs
      );
      address deployed = factory.deployRelayer(
        f.rateFeedId,
        f.description,
        f.maxTimestampSpread,
        f.maxStaleness,
        f.legs
      );
      require(deployed == predicted, "CREATE2 address mismatch");

      relayers.push(deployed);
      relayerDescriptions.push(f.description);
      vm.label(deployed, string.concat("PullOracleRelayer ", f.description));
      console.log(string.concat("Relayer [", f.description, "]:"), deployed);
    }
  }

  function _deployBreaker(Globals memory g) internal {
    // Owner is the deployer for now so this script can configure per-feed params below;
    // ownership is handed to finalOwner at the end of the run.
    breakerV2 = new MedianDeltaBreakerV2(
      g.defaultCooldown,
      g.sortedOracles,
      g.breakerBox,
      g.defaultBaseJump,
      g.defaultSlewPerSecond,
      g.defaultMaxJump,
      msg.sender
    );
    vm.label(address(breakerV2), "MedianDeltaBreakerV2");
    console.log("MedianDeltaBreakerV2:  ", address(breakerV2));
  }

  function _configureBreakerPerFeed(FeedConfig[] memory feeds) internal {
    address[] memory ids = new address[](1);
    uint256[] memory cooldowns = new uint256[](1);
    for (uint256 i = 0; i < feeds.length; i++) {
      FeedConfig memory f = feeds[i];
      breakerV2.setSlewParameters(f.rateFeedId, f.baseJump, f.slewPerSecond, f.maxJump);
      ids[0] = f.rateFeedId;
      cooldowns[0] = f.cooldown; // must be > 0 for automatic recovery
      breakerV2.setCooldownTimes(ids, cooldowns);
    }
  }

  function _wireBreakerBox(Globals memory g, FeedConfig[] memory feeds, address deployer) internal {
    // Bare simulation: no contract at the address, so skip rather than revert.
    if (g.breakerBox.code.length == 0) {
      console.log("BreakerBox has no code; skipping wiring (simulation / no fork).");
      return;
    }
    // Real network: BreakerBox is owner-gated, so wiring is a governance action.
    if (IBreakerBoxMin(g.breakerBox).owner() != deployer) {
      console.log("Deployer is not the BreakerBox owner; wiring must run via governance (MGP).");
      return;
    }

    IBreakerBoxMin breakerBox = IBreakerBoxMin(g.breakerBox);
    if (!breakerBox.isBreaker(address(breakerV2))) {
      breakerBox.addBreaker(address(breakerV2), g.breakerTradingMode);
    }
    for (uint256 i = 0; i < feeds.length; i++) {
      address rateFeedId = feeds[i].rateFeedId;
      if (!breakerBox.rateFeedStatus(rateFeedId)) {
        breakerBox.addRateFeed(rateFeedId);
      }
      breakerBox.toggleBreaker(address(breakerV2), rateFeedId, true);
    }
    // The legacy MedianDeltaBreaker (V1) is intentionally left enabled (dual-run).
  }

  function _handOverOwnership(Globals memory g, address deployer) internal {
    if (g.finalOwner != deployer) {
      breakerV2.transferOwnership(g.finalOwner);
    }
  }

  // ============ Config Loading (env var > TBD placeholder) ============

  function _loadGlobals(address deployer) internal view returns (Globals memory g) {
    g.sortedOracles = vm.envOr("DS_SORTED_ORACLES", _tbdAddr("sortedOracles")); // B5
    g.verifierProxy = vm.envOr("DS_VERIFIER_PROXY", _tbdAddr("verifierProxy")); // B1
    g.breakerBox = vm.envOr("DS_BREAKER_BOX", _tbdAddr("breakerBox"));
    g.relayerDeployer = vm.envOr("DS_RELAYER_DEPLOYER", deployer);
    g.finalOwner = vm.envOr("DS_FINAL_OWNER", deployer);
    g.defaultCooldown = vm.envOr("DS_DEFAULT_COOLDOWN", uint256(300)); // > 0 (B10)
    g.defaultBaseJump = vm.envOr("DS_DEFAULT_BASE_JUMP", uint256(5e21)); // 0.5% (B10)
    g.defaultSlewPerSecond = vm.envOr("DS_DEFAULT_SLEW_PER_SECOND", uint256(5555555555555555555)); // 2%/h (B10)
    g.defaultMaxJump = vm.envOr("DS_DEFAULT_MAX_JUMP", uint256(5e22)); // 5% (B10)
    g.breakerTradingMode = uint8(vm.envOr("DS_BREAKER_TRADING_MODE", uint256(2))); // != 0
  }

  /**
   * @notice Builds the Phase-1 feed list as two representative shapes: a single-leg crypto
   *         feed and a two-leg cross-rate. Every value is env-overridable; defaults are TBD
   *         placeholders. Extend once B4 (feedIds), B13 (rateFeedIds) and B10 (params) land.
   */
  function _loadFeeds() internal view returns (FeedConfig[] memory feeds) {
    feeds = new FeedConfig[](2);
    feeds[0] = _celoUsd();
    feeds[1] = _celoPhp();
  }

  // Single-leg crypto feed: CELO/USD.
  function _celoUsd() internal view returns (FeedConfig memory f) {
    IPullOracleRelayer.OracleLeg[] memory legs = new IPullOracleRelayer.OracleLeg[](1);
    legs[0] = IPullOracleRelayer.OracleLeg(vm.envOr("DS_FEEDID_CELO_USD", _tbdFeedId("CELO/USD")), false);

    f.rateFeedId = vm.envOr("DS_RATEFEED_CELO_USD", _tbdAddr("rateFeed:CELO/USD"));
    f.description = "CELO/USD";
    f.maxTimestampSpread = 0; // single leg => must be 0
    f.maxStaleness = vm.envOr("DS_STALENESS_CELO_USD", uint256(120)); // crypto (B10)
    f.legs = legs;
    f.baseJump = vm.envOr("DS_BASEJUMP_CELO_USD", uint256(1e22)); // 1%
    f.slewPerSecond = vm.envOr("DS_SLEW_CELO_USD", uint256(27777777777777777777)); // 10%/h
    f.maxJump = vm.envOr("DS_MAXJUMP_CELO_USD", uint256(2e23)); // 20%
    f.cooldown = vm.envOr("DS_COOLDOWN_CELO_USD", uint256(300)); // > 0
  }

  // Two-leg cross-rate: CELO/PHP = CELO/USD * inverse(PHP/USD).
  function _celoPhp() internal view returns (FeedConfig memory f) {
    IPullOracleRelayer.OracleLeg[] memory legs = new IPullOracleRelayer.OracleLeg[](2);
    legs[0] = IPullOracleRelayer.OracleLeg(vm.envOr("DS_FEEDID_CELO_USD", _tbdFeedId("CELO/USD")), false);
    legs[1] = IPullOracleRelayer.OracleLeg(vm.envOr("DS_FEEDID_PHP_USD", _tbdFeedId("PHP/USD")), true);

    f.rateFeedId = vm.envOr("DS_RATEFEED_CELO_PHP", _tbdAddr("rateFeed:CELO/PHP"));
    f.description = "CELO/PHP";
    f.maxTimestampSpread = vm.envOr("DS_SPREAD_CELO_PHP", uint256(60)); // multi-leg => > 0
    f.maxStaleness = vm.envOr("DS_STALENESS_CELO_PHP", uint256(300)); // FX-ish (B10)
    f.legs = legs;
    f.baseJump = vm.envOr("DS_BASEJUMP_CELO_PHP", uint256(5e21)); // 0.5%
    f.slewPerSecond = vm.envOr("DS_SLEW_CELO_PHP", uint256(5555555555555555555)); // 2%/h
    f.maxJump = vm.envOr("DS_MAXJUMP_CELO_PHP", uint256(5e22)); // 5%
    f.cooldown = vm.envOr("DS_COOLDOWN_CELO_PHP", uint256(300)); // > 0
  }

  // ============ TBD Placeholder Helpers (non-zero and obviously fake) ============

  function _tbdAddr(string memory label) internal pure returns (address) {
    return address(uint160(uint256(keccak256(abi.encodePacked("TBD:", label)))));
  }

  function _tbdFeedId(string memory label) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked("TBD:feedId:", label));
  }

  // ============ Placeholder / unvetted-param warning ============

  /**
   * @notice Prints a loud warning for any config still on its built-in placeholder, so an operator
   *         cannot silently ship the obviously-fake addresses or the unvetted economic defaults.
   * @dev The breaker economics (baseJump/slewPerSecond/maxJump/cooldown/maxStaleness) are non-zero,
   *      plausible-looking B10 placeholders: a run without DS_* env vars set will use them. They
   *      MUST be vetted before mainnet. Addresses/feedIds (B1/B5/B13/B4) fall back to non-zero
   *      `_tbdAddr`/`_tbdFeedId` sentinels that are detected and flagged here.
   */
  function _warnPlaceholders(Globals memory g, FeedConfig[] memory feeds) internal view {
    bool anyPlaceholder = false;
    if (g.sortedOracles == _tbdAddr("sortedOracles")) {
      console.log("  [!] DS_SORTED_ORACLES unset -> TBD placeholder (B5):", g.sortedOracles);
      anyPlaceholder = true;
    }
    if (g.verifierProxy == _tbdAddr("verifierProxy")) {
      console.log("  [!] DS_VERIFIER_PROXY unset -> TBD placeholder (B1):", g.verifierProxy);
      anyPlaceholder = true;
    }
    if (g.breakerBox == _tbdAddr("breakerBox")) {
      console.log("  [!] DS_BREAKER_BOX unset -> TBD placeholder:", g.breakerBox);
      anyPlaceholder = true;
    }
    for (uint256 i = 0; i < feeds.length; i++) {
      if (feeds[i].rateFeedId == _tbdAddr(string.concat("rateFeed:", feeds[i].description))) {
        console.log(string.concat("  [!] rateFeedId unset -> TBD placeholder (B13): ", feeds[i].description));
        anyPlaceholder = true;
      }
    }

    if (anyPlaceholder) {
      console.log("==================== WARNING ====================");
      console.log("One or more addresses/feedIds are TBD placeholders (env vars unset).");
      console.log("This is fine for a dry run; DO NOT broadcast to mainnet like this.");
    }
    console.log("==================== WARNING ====================");
    console.log("Breaker economics (baseJump/slew/maxJump/cooldown/maxStaleness) use built-in");
    console.log("B10 defaults unless DS_* env vars override them. Vet these before mainnet.");
    console.log("================================================\n");
  }

  // ============ Summary ============

  function _printSummary(Globals memory g) internal view {
    console.log("\n========================================");
    console.log("=== Data Streams Phase-1 Deploy Complete ===");
    console.log("========================================");
    console.log("");
    console.log("Contracts:");
    console.log("  Factory (proxy):     ", address(factoryProxy));
    console.log("  Factory ProxyAdmin:  ", address(proxyAdmin));
    console.log("  MedianDeltaBreakerV2:", address(breakerV2));
    console.log("");
    console.log("Relayers:");
    for (uint256 i = 0; i < relayers.length; i++) {
      console.log(string.concat("  ", relayerDescriptions[i], ":"), relayers[i]);
    }
    console.log("");
    console.log("Breaker owner:", g.finalOwner);
    console.log("");
  }
}
