// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { IScriptHelper } from "./IScriptHelper.sol";

contract ScriptHelper is IScriptHelper {
  uint256 constant NETWORK_ANVIL = 0;
  uint256 constant NETWORK_CELO = 42220;
  uint256 constant NETWORK_BAKLAVA = 62320;

  constructor() public {}

  /**
   * @notice Helper function to retrieve deployed proxy addresses.
   */
  function getNetworkProxies(uint256 network) internal pure returns (NetworkProxies memory proxies) {
    if (network == NETWORK_ANVIL) {
      proxies = NetworkProxies({
        stableToken: 0x765DE816845861e75A25fCA122bb6898B8B1282a,
        stableTokenBRL: 0xe8537a3d056DA446677B9E9d6c5dB704EaAb4787,
        stableTokenEUR: 0xD8763CBa276a3738E6DE85b4b3bF5FDed6D6cA73,
        broker: 0xD8a5a9b31c3C0232E196d518E89Fd8bF83AcAd43,
        reserve: 0x9380fA34Fd9e4Fd14c06305fd7B6199089eD4eb9,
        sortedOracles: 0xefB84935239dAcdecF7c5bA76d8dE40b077B7b33,
        exchange: 0x67316300f17f063085Ca8bCa4bd3f7a5a3C66275,
        exchangeBRL: 0x8f2cf9855C919AFAC8Bd2E7acEc0205ed568a4EA,
        exchangeEUR: 0xE383394B913d7302c49F794C7d3243c429d53D1d,
        biPoolManager: 0xdbC43Ba45381e02825b14322cDdd15eC4B3164E6,
        celoGovernance: 0xD533Ca259b330c7A88f74E000a3FaEa2d63B7972,
        celoToken: 0x471EcE3750Da237f93B8E339c536989b8978a438
      });
    } else {
      revert("Unknown network");
    }
  }

  /**
   * @notice Helper function to retrieve deployed implementation addresses.
   */
  function getNetworkImplementations(uint256 network) internal pure returns (NetworkImplementations memory implementations) {
    if (network == NETWORK_ANVIL) {
      implementations = NetworkImplementations({
        stableToken: 0x0355B7B8cb128fA5692729Ab3AAa199C1753f726,
        stableTokenBRL: 0x202CCe504e04bEd6fC0521238dDf04Bc9E8E15aB,
        stableTokenEUR: 0xf4B146FbA71F41E0592668ffbF264F1D186b2Ca8,
        broker: 0x2E2Ed0Cfd3AD2f1d34481277b3204d807Ca2F8c2,
        reserve: 0x8198f5d8F8CfFE8f9C413d98a0A55aEB8ab9FbB7,
        sortedOracles: 0xaf5D514bB94023C9Af979821F59A5Eecde0986EF,
        exchange: 0x9A470D789BCd392ae4c8f22DB8425b5eF139906C,
        exchangeBRL: 0x0d4a42B2fc30AfBF6b6e8f5CE49A659E38A2D112,
        exchangeEUR: 0x32C2dcB7730eD6Fc1Eac0444a668F38Fd7B5dc8D,
        biPoolManager: 0x1fA02b2d6A771842690194Cf62D91bdd92BfE28d,
        constantProductPricingModule: 0x5081a39b8A5f0E35a8D959395a630b68B74Dd30f,
        constantSumPricingModule: 0x922D6956C99E12DFeB3224DEA977D0939758A1Fe,
        celoGovernance: 0xe6F77e6c1Df6Aea40923659C0415d82119F34882,
        celoToken: 0x4DdeB8F7041aB3260c6ec5Afb6FEab0650F4ABB4,
        usdcToken: 0x22a4aAF42A50bFA7238182460E32f15859c93dfe
      });
    } else {
      revert("Unknown network");
    }
  }
}
