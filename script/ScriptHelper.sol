// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { IScriptHelper } from "./IScriptHelper.sol";

// TODO: Do better.

contract ScriptHelper is IScriptHelper {
  uint256 constant NETWORK_ANVIL = 0;
  uint256 constant NETWORK_CELO = 42220;
  uint256 constant NETWORK_BAKLAVA = 62320;
  address constant REGISTRY_ADDRESS = 0x000000000000000000000000000000000000ce10;

  constructor() public {}

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
  function getNetworkProxies(uint256 network) internal pure returns (NetworkProxies memory proxies) {
    if (network == NETWORK_ANVIL) {
      proxies = NetworkProxies({
        registry: address(0),
        stableToken: 0x62492A644A588FD904270BeD06ad52B9abfEA1aE,
        stableTokenBRL: 0x6a0EEf2bed4C30Dc2CB42fe6c5f01F80f7EF16d1,
        stableTokenEUR: 0xf9ecE301247aD2CE21894941830A2470f4E774ca,
        broker: address(0),
        reserve: 0x68Dd816611d3DE196FDeb87438B74A9c29fd649f,
        sortedOracles: 0x88A187a876290E9843175027902B9f7f1B092c88,
        exchange: 0x190480908c11Efca37EDEA4405f4cE1703b68b23,
        exchangeBRL: 0x28e257d1E73018A116A7C68E9d07eba736D9Ec05,
        exchangeEUR: 0xC200CD8ac71A63e38646C34b51ee3cBA159dB544,
        biPoolManager: address(0),
        celoGovernance: 0x28443b1d87db521320a6517A4F1B6Ead77F8C811,
        celoToken: 0xdDc9bE57f553fe75752D61606B94CBD7e0264eF8
      });
    } else if (network == NETWORK_BAKLAVA) {
      proxies = NetworkProxies({
        registry: REGISTRY_ADDRESS,
        stableToken: 0x62492A644A588FD904270BeD06ad52B9abfEA1aE,
        stableTokenBRL: 0x6a0EEf2bed4C30Dc2CB42fe6c5f01F80f7EF16d1,
        stableTokenEUR: 0xf9ecE301247aD2CE21894941830A2470f4E774ca,
        broker: 0x916f249328701d2A63999663436Eef8A91e7d2AB,
        reserve: 0x68Dd816611d3DE196FDeb87438B74A9c29fd649f,
        sortedOracles: 0x88A187a876290E9843175027902B9f7f1B092c88,
        exchange: 0x190480908c11Efca37EDEA4405f4cE1703b68b23,
        exchangeBRL: 0x28e257d1E73018A116A7C68E9d07eba736D9Ec05,
        exchangeEUR: 0xC200CD8ac71A63e38646C34b51ee3cBA159dB544,
        biPoolManager: 0x1bb5f6803c23160B7056d86995fEca735cA9e650,
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
  function getNetworkImplementations(uint256 network)
    internal
    pure
    returns (NetworkImplementations memory implementations)
  {
    if (network == NETWORK_ANVIL) {
      implementations = NetworkImplementations({
        stableToken: 0x26FEB5166381ddb92Ec36F1Fa718522356F99855,
        stableTokenBRL: 0x190D7529728CBBE51aCAb0db0C547DC76a60fA77,
        stableTokenEUR: 0xaA551fDE8de1dDa8f2c47daD90E0fd33efF2aAA3,
        broker: 0x261D8c5e9742e6f7f1076Fa1F560894524e19cad,
        reserve: 0x33421a33D8666eE603110F0F07d434981c023FcA,
        sortedOracles: 0xce0B46A64b23c636D8ffFc63e362104945Bd4fE4,
        exchange: 0x247c0533Bb47AeB3633336982Ed3478dab1Ea616,
        exchangeBRL: 0x24c18EE6929e3D6524B4bD1313B8Aa9A27e1323D,
        exchangeEUR: 0x495Aa3DA7Ae19a0c63c46c02Ed2Aa76a29c1154D,
        biPoolManager: 0x057ef64E23666F000b34aE31332854aCBd1c8544,
        constantProductPricingModule: address(0),
        constantSumPricingModule: address(0),
        celoGovernance: 0x175ffD14F36228d1479CFB8051A9e09Dc41CFC52,
        celoToken: 0x0B26352b5e2019A39d23a8eea2A9Fe4B0489Bd47,
        usdcToken: 0x22a4aAF42A50bFA7238182460E32f15859c93dfe // ??
      });
    } else if (network == NETWORK_BAKLAVA) {
      implementations = NetworkImplementations({
        stableToken: 0x26FEB5166381ddb92Ec36F1Fa718522356F99855,
        stableTokenBRL: 0x190D7529728CBBE51aCAb0db0C547DC76a60fA77,
        stableTokenEUR: 0xaA551fDE8de1dDa8f2c47daD90E0fd33efF2aAA3,
        broker: 0x261D8c5e9742e6f7f1076Fa1F560894524e19cad,
        reserve: 0x33421a33D8666eE603110F0F07d434981c023FcA,
        sortedOracles: 0xce0B46A64b23c636D8ffFc63e362104945Bd4fE4,
        exchange: 0x247c0533Bb47AeB3633336982Ed3478dab1Ea616,
        exchangeBRL: 0x24c18EE6929e3D6524B4bD1313B8Aa9A27e1323D,
        exchangeEUR: 0x495Aa3DA7Ae19a0c63c46c02Ed2Aa76a29c1154D,
        biPoolManager: 0x057ef64E23666F000b34aE31332854aCBd1c8544,
        constantProductPricingModule: 0x16396273D244a651C2Bf3D33aD3CA21952E4dE2A,
        constantSumPricingModule: 0x85357878162F71B40f6a8036Edcf34DCaF80a2F4,
        celoGovernance: 0x175ffD14F36228d1479CFB8051A9e09Dc41CFC52,
        celoToken: 0x0B26352b5e2019A39d23a8eea2A9Fe4B0489Bd47,
        usdcToken: 0x22a4aAF42A50bFA7238182460E32f15859c93dfe // ??
      });
    } else {
      revert("Unknown network");
    }
  }
}
