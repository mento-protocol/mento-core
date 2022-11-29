// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Script, console2 } from "forge-std/Script.sol";
import { IScriptHelper } from "./IScriptHelper.sol";

// TODO: Do better.

contract ScriptHelper is IScriptHelper, Script {
  uint256 constant NETWORK_ANVIL = 0;
  uint256 constant NETWORK_CELO = 42220;
  uint256 constant NETWORK_BAKLAVA = 62320;
  address constant REGISTRY_ADDRESS = 0x000000000000000000000000000000000000ce10;

  constructor() public {}

  /**
   * @notice Setup a fork environment for the current chain
   */
  function enableFork() internal {
    uint256 _chainId = chainId();
    if (_chainId == NETWORK_BAKLAVA) {
      uint256 forkId = vm.createFork("baklava");
      vm.selectFork(forkId);
    } else if (_chainId == NETWORK_CELO) {
      uint256 forkId = vm.createFork("celo_mainnet");
      vm.selectFork(forkId);
    } else {
      revert("Unknown network");
    }
  }

  /**
   * @notice Get the current chainId
   * @return the chain id
   */
  function chainId() internal pure returns (uint256 _chainId) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      _chainId := chainid
    }
  }

  /**
   * @notice Helper function to retrieve deployed proxy addresses.
   */
  function getNetworkProxies() internal pure returns (NetworkProxies memory proxies) {
    uint256 _chainId = chainId();
    if (_chainId == NETWORK_BAKLAVA) {
      proxies = NetworkProxies({
        registry: REGISTRY_ADDRESS,
        stableToken: 0x62492A644A588FD904270BeD06ad52B9abfEA1aE,
        stableTokenBRL: 0x6a0EEf2bed4C30Dc2CB42fe6c5f01F80f7EF16d1,
        stableTokenEUR: 0xf9ecE301247aD2CE21894941830A2470f4E774ca,
        broker: 0x23a4D848b3976579d7371AFAF18b989D4ae0b031,
        breakerBox: 0x6618A3EBa94A769AA94c4f0d1669dCC5069B0C7D,
        reserve: 0x68Dd816611d3DE196FDeb87438B74A9c29fd649f,
        sortedOracles: 0x88A187a876290E9843175027902B9f7f1B092c88,
        exchange: 0x190480908c11Efca37EDEA4405f4cE1703b68b23,
        exchangeBRL: 0x28e257d1E73018A116A7C68E9d07eba736D9Ec05,
        exchangeEUR: 0xC200CD8ac71A63e38646C34b51ee3cBA159dB544,
        biPoolManager: 0xa43C2012c207a15bE6dBF37308Ac7Cc514461D47,
        celoGovernance: 0x28443b1d87db521320a6517A4F1B6Ead77F8C811,
        celoToken: 0xdDc9bE57f553fe75752D61606B94CBD7e0264eF8
      });
    } else {
      revert("Unknown network");
    }
  }

  /**
   * @notice Helper function to retrieve deployed implementation addresses.
   */
  function getNetworkImplementations() internal pure returns (NetworkImplementations memory implementations) {
    uint256 _chainId = chainId();
    if (_chainId == NETWORK_BAKLAVA) {
      implementations = NetworkImplementations({
        stableToken: 0x0Dfa02B150742BA1f0622a086892687edFB04994,
        stableTokenBRL: 0x0F4ad316B240260f915ed93484CbE5B0012BbA91,
        stableTokenEUR: 0x9b3Cb4E895128Fd7F507cF429d565C38ef49Fa23,
        broker: 0x98d2776372F5769DD051a4522e00048345101aaC,
        breakerBox: 0x6618A3EBa94A769AA94c4f0d1669dCC5069B0C7D,
        medianDeltaBreaker: 0x5F234B6b82F5fF67Eeb4aB5D676c50ac9A07D009,
        reserve: 0xC57A5608404D094C8bcE307E0bE2A8fD743EE913,
        sortedOracles: 0xce0B46A64b23c636D8ffFc63e362104945Bd4fE4,
        exchange: 0x247c0533Bb47AeB3633336982Ed3478dab1Ea616,
        exchangeBRL: 0x24c18EE6929e3D6524B4bD1313B8Aa9A27e1323D,
        exchangeEUR: 0x495Aa3DA7Ae19a0c63c46c02Ed2Aa76a29c1154D,
        biPoolManager: 0x94227F69a11d264a1EcfEB66C4C3a79C420B54Fb,
        constantProductPricingModule: 0x16396273D244a651C2Bf3D33aD3CA21952E4dE2A,
        constantSumPricingModule: 0x85357878162F71B40f6a8036Edcf34DCaF80a2F4,
        celoGovernance: 0x175ffD14F36228d1479CFB8051A9e09Dc41CFC52,
        celoToken: 0x0B26352b5e2019A39d23a8eea2A9Fe4B0489Bd47,
        usdcToken: 0x37f750B7cC259A2f741AF45294f6a16572CF5cAd // ??
      });
    } else {
      revert("Unknown network");
    }
  }
}
