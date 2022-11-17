// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Script, console2 } from "forge-std/Script.sol";
import { ScriptHelper } from "../ScriptHelper.sol";
import { GovernanceHelper } from "../GovernanceHelper.sol";

import { FixidityLib } from "contracts/common/FixidityLib.sol";

import { ICeloGovernance } from "contracts/governance/interfaces/ICeloGovernance.sol";

// Baklava - forge script script/governance/CGP-00X-McMint.sol --rpc-url https://baklava-forno.celo-testnet.org --broadcast --legacy --private-key
contract McMintProposal is Script, ScriptHelper, GovernanceHelper {
  using FixidityLib for FixidityLib.Fraction;

  address reserveProxyAddress;
  address stableTokenProxyAddress;
  address stableTokenEURProxyAddress;
  address stableTokenBRLProxyAddress;
  address biPoolManagerAddress;

  ICeloGovernance.Transaction[] public transactions;

  function run() public {
    NetworkProxies memory proxies = getNetworkProxies(0);
    NetworkImplementations memory implementations = getNetworkImplementations(0);

    // Get addresses
    reserveProxyAddress = address(uint160(proxies.reserve));
    stableTokenProxyAddress = address(uint160(proxies.stableToken));
    stableTokenEURProxyAddress = address(uint160(proxies.stableTokenEUR));
    stableTokenBRLProxyAddress = address(uint160(proxies.stableTokenBRL));
    biPoolManagerAddress = proxies.biPoolManager;

    addProxyUpdateTransactions(implementations);

    // Set broker as reserve spender
    transactions.push(
      ICeloGovernance.Transaction(
        0,
        reserveProxyAddress,
        abi.encodeWithSignature("addSpender(address)", proxies.broker)
      )
    );

    addCreateExchangeTransactions(proxies, implementations);

    //TODO: Set Oracle report targets for new rates

    vm.startBroadcast();
    {
      // Serialize transactions
      (
        uint256[] memory values,
        address[] memory destinations,
        bytes memory data,
        uint256[] memory dataLengths
      ) = serializeTransactions(transactions);

      uint256 depositAmount = ICeloGovernance(proxies.celoGovernance).minDeposit();
      console2.log("Celo governance proposal required deposit amount: ", depositAmount);

      // Submit proposal
      (bool success, bytes memory returnData) = address(proxies.celoGovernance).call.value(depositAmount)(
        abi.encodeWithSignature(
          "propose(uint256[],address[],bytes,uint256[],string)",
          values,
          destinations,
          data,
          dataLengths,
          "CGP-00X-McMint"
        )
      );

      if (success == false) {
        console2.log("Failed to create proposal");
        console2.logBytes(returnData);
      }
      require(success);

      console2.log("Proposal was successfully created. ID: ", abi.decode(returnData, (uint256)));
    }
    vm.stopBroadcast();
  }

  function addProxyUpdateTransactions(NetworkImplementations memory implementations) private {
    transactions.push(
      ICeloGovernance.Transaction(
        0,
        reserveProxyAddress,
        abi.encodeWithSignature("_setImplementation(address)", implementations.reserve)
      )
    );

    transactions.push(
      ICeloGovernance.Transaction(
        0,
        stableTokenProxyAddress,
        abi.encodeWithSignature("_setImplementation(address)", implementations.stableToken)
      )
    );

    transactions.push(
      ICeloGovernance.Transaction(
        0,
        stableTokenEURProxyAddress,
        abi.encodeWithSignature("_setImplementation(address)", implementations.stableTokenEUR)
      )
    );

    transactions.push(
      ICeloGovernance.Transaction(
        0,
        stableTokenBRLProxyAddress,
        abi.encodeWithSignature("_setImplementation(address)", implementations.stableTokenBRL)
      )
    );
  }

  function addCreateExchangeTransactions(NetworkProxies memory proxies, NetworkImplementations memory implementations)
    private
  {
    // TODO: confirm values
    // Add pools to the BiPoolManager: cUSD/CELO, cEUR/CELO, cREAL/CELO, cUSD/USDCet

    // cUSD/CELO
    transactions.push(
      ICeloGovernance.Transaction(
        0,
        biPoolManagerAddress,
        abi.encodeWithSignature(
          "createExchange(address, address, address, uint256, uint256, uint256, ((uint256), address, uint256, uint256, uint256 ))",
          proxies.stableToken, //asset0
          proxies.celoToken, //asset1
          implementations.constantProductPricingModule, //pricingModule
          0, //bucket0
          0, //bucket1
          now, //lastBucketUpdate
          FixidityLib.newFixedFraction(5, 100).unwrap(), //spread
          proxies.stableToken, //Oracle report target
          60 * 5, //referenceRateResetFrequency
          5, //minReports
          1e24 //stablePoolResetSize
        )
      )
    );

    // cEUR/CELO
    transactions.push(
      ICeloGovernance.Transaction(
        0,
        biPoolManagerAddress,
        abi.encodeWithSignature(
          "createExchange(address, address, address, uint256, uint256, uint256, ((uint256), address, uint256, uint256, uint256 ))",
          proxies.stableTokenEUR, //asset0
          proxies.celoToken, //asset1
          implementations.constantProductPricingModule, //pricingModule
          0, //bucket0
          0, //bucket1
          now, //lastBucketUpdate
          FixidityLib.newFixedFraction(5, 100).unwrap(), //spread
          proxies.stableTokenEUR, //Oracle report target
          60 * 5, //referenceRateResetFrequency
          5, //minReports
          1e24 //stablePoolResetSize
        )
      )
    );

    // cREAL/CELO
    transactions.push(
      ICeloGovernance.Transaction(
        0,
        biPoolManagerAddress,
        abi.encodeWithSignature(
          "createExchange(address, address, address, uint256, uint256, uint256, ((uint256), address, uint256, uint256, uint256 ))",
          proxies.stableTokenBRL, //asset0
          proxies.celoToken, //asset1
          implementations.constantProductPricingModule, //pricingModule
          0, //bucket0
          0, //bucket1
          now, //lastBucketUpdate
          FixidityLib.newFixedFraction(5, 100).unwrap(), //spread
          proxies.stableTokenBRL, //Oracle report target
          60 * 5, //referenceRateResetFrequency
          5, //minReports
          1e24 //stablePoolResetSize
        )
      )
    );

    // cUSD/USDCet
    transactions.push(
      ICeloGovernance.Transaction(
        0,
        biPoolManagerAddress,
        abi.encodeWithSignature(
          "createExchange(address, address, address, uint256, uint256, uint256, ((uint256), address, uint256, uint256, uint256 ))",
          implementations.usdcToken, //asset0
          proxies.celoToken, //asset1
          implementations.constantSumPricingModule, //pricingModule
          0, //bucket0
          0, //bucket1
          now, //lastBucketUpdate
          FixidityLib.newFixedFraction(5, 100).unwrap(), //spread
          proxies.stableToken, //Oracle report target
          60 * 5, //referenceRateResetFrequency
          5, //minReports
          1e24 //stablePoolResetSize
        )
      )
    );
  }
}
