// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;

interface IScriptHelper {
  struct NetworkProxies {
    address registry;
    address stableToken;
    address stableTokenBRL;
    address stableTokenEUR;
    address broker;
    address breakerBox;
    address reserve;
    address sortedOracles;
    address exchange;
    address exchangeBRL;
    address exchangeEUR;
    address biPoolManager;
    address celoGovernance;
    address celoToken;
  }

  struct NetworkImplementations {
    address stableToken;
    address stableTokenBRL;
    address stableTokenEUR;
    address broker;
    address breakerBox;
    address medianDeltaBreaker;
    address reserve;
    address sortedOracles;
    address exchange;
    address exchangeBRL;
    address exchangeEUR;
    address biPoolManager;
    address constantProductPricingModule;
    address constantSumPricingModule;
    address celoGovernance;
    address celoToken;
    address usdcToken;
  }
}
