// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import "../utils/BaseTest.t.sol";
import "contracts/interfaces/IChainlinkAdapterFactory.sol";

contract ChainlinkAdapterFactoryTest is BaseTest {
  IChainlinkAdapterFactory adapterFactory;

  function setUp() public {
    adapterFactory = IChainlinkAdapterFactory(
      factory.createContract("ChainlinkAdapterFactory", abi.encode())
    );
  }
}

contract ChainlinkAdapterFactoryTest_constructor is ChainlinkAdapterFactoryTest {
}
