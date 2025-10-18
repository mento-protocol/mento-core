// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "test/integration/v3/LiquityDeployer.sol";

import "contracts/tokens/StableTokenV3.sol";
import "contracts/interfaces/IStableTokenV3.sol";

// import { IERC20Metadata } from "openzeppelin-contracts-next/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "bold/src/Interfaces/IBoldToken.sol";

contract Liquity is LiquityDeployer {
  LiquityDeployer deployer;
  IBoldToken public debtToken;
  IERC20Metadata public collateralToken;

  function setUp() public {
    console2.log("Liquity test started");

    debtToken = deployDebtToken();
    collateralToken = IERC20Metadata(address(new MockERC20("Collateral Token", "COLL", 18)));
    setTokens(debtToken, collateralToken);
    // deployer = new LiquityDeployer(_debtToken, _collateralToken);
    // setTokens(debtToken, collateralToken);
  }

  function test_deployLiquity() public {
    // LiquityDeployer.LiquityContractsDev memory contracts = deployer.deploy();
    LiquityContractsDev memory contracts = deploy();

    console2.log("Liquity test deployed");
    console2.log("contracts.systemParams", address(contracts.systemParams));
    console2.log("contracts.addressesRegistry", address(contracts.addressesRegistry));
    console2.log("contracts.priceFeed", address(contracts.priceFeed));
    console2.log("contracts.interestRouter", address(contracts.interestRouter));
    console2.log("contracts.borrowerOperations", address(contracts.borrowerOperations));
    console2.log("contracts.troveManager", address(contracts.troveManager));
  }

  function deployDebtToken() public returns (IBoldToken) {
    StableTokenV3 newDebtToken = new StableTokenV3(false);
    uint256[] memory numbers = new uint256[](0);
    address[] memory addresses = new address[](0);
    newDebtToken.initialize("Debt Token", "DEBT", addresses, numbers, addresses, addresses, addresses);

    return IBoldToken(address(newDebtToken));
  }
}
