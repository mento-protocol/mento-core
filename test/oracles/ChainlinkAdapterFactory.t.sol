// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import "../utils/BaseTest.t.sol";
import "contracts/interfaces/IChainlinkAdapterFactory.sol";
import "contracts/interfaces/IChainlinkAdapter.sol";

contract ChainlinkAdapterFactoryTest is BaseTest {
  IChainlinkAdapterFactory adapterFactory;
  address mockSortedOracles = address(0xcafe);
  address mockAggregator = address(0xbeef);
  address aRateFeed = address(0x1337);

  event RelayerDeployed(address indexed relayerAddress, address indexed rateFeedId, address indexed aggregator);

  function setUp() public {
    adapterFactory = IChainlinkAdapterFactory(
      factory.createContract("ChainlinkAdapterFactory", abi.encode(mockSortedOracles))
    );
  }

  function expectedRelayerAddress(
    address rateFeedId,
    address sortedOracles,
    address chainlinkAggregator,
    address adapterFactoryAddress
  ) public returns (address) {
    bytes32 salt = keccak256("mento.chainlinkAdapter");
    return
      address(
        uint160(
          uint256(
            keccak256(
              abi.encodePacked(
                bytes1(0xff),
                adapterFactoryAddress,
                salt,
                keccak256(
                  abi.encodePacked(
                    vm.getCode(factory.contractPath("ChainlinkAdapter")),
                    abi.encode(rateFeedId, sortedOracles, chainlinkAggregator)
                  )
                )
              )
            )
          )
        )
      );
  }

  function relayerExistsError(
    address relayerAddress,
    address rateFeedId,
    address aggregator
  ) public returns (bytes memory) {
    return abi.encodeWithSignature("RelayerExists(address,address,address)", relayerAddress, rateFeedId, aggregator);
  }
}

contract ChainlinkAdapterFactoryTest_constructor is ChainlinkAdapterFactoryTest {
  function test_setsSortedOracles() public {
    address realSortedOracles = adapterFactory.sortedOracles();
    assertEq(realSortedOracles, mockSortedOracles);
  }
}

contract ChainlinkAdapterFactoryTest_deployRelayer is ChainlinkAdapterFactoryTest {
  function test_setsRateFeed() public {
    IChainlinkAdapter relayer = IChainlinkAdapter(adapterFactory.deployRelayer(aRateFeed, mockAggregator));

    address rateFeed = relayer.token();
    assertEq(rateFeed, aRateFeed);
  }

  function test_setsAggregator() public {
    IChainlinkAdapter relayer = IChainlinkAdapter(adapterFactory.deployRelayer(aRateFeed, mockAggregator));

    address aggregator = relayer.aggregator();
    assertEq(aggregator, mockAggregator);
  }

  function test_setsSortedOracles() public {
    IChainlinkAdapter relayer = IChainlinkAdapter(adapterFactory.deployRelayer(aRateFeed, mockAggregator));

    address sortedOracles = relayer.sortedOracles();
    assertEq(sortedOracles, mockSortedOracles);
  }

  function test_deploysToTheCorrectAddress() public {
    address relayer = adapterFactory.deployRelayer(aRateFeed, mockAggregator);

    address expectedAddress = expectedRelayerAddress(
      aRateFeed,
      mockSortedOracles,
      mockAggregator,
      address(adapterFactory)
    );

    assertEq(relayer, expectedAddress);
  }

  function test_emitsRelayerDeployedEvent() public {
    address expectedAddress = expectedRelayerAddress(
      aRateFeed,
      mockSortedOracles,
      mockAggregator,
      address(adapterFactory)
    );
    vm.expectEmit(true, true, true, false, address(adapterFactory));
    emit RelayerDeployed(expectedAddress, aRateFeed, mockAggregator);
    adapterFactory.deployRelayer(aRateFeed, mockAggregator);
  }

  function test_remembersTheRelayerAddress() public {
    address relayer = adapterFactory.deployRelayer(aRateFeed, mockAggregator);
    (address storedAddress, ) = adapterFactory.getRelayer(aRateFeed);
    assertEq(storedAddress, relayer);
  }

  function test_remembersTheRelayerVersion() public {
    address relayer = adapterFactory.deployRelayer(aRateFeed, mockAggregator);
    (, uint8 version) = adapterFactory.getRelayer(aRateFeed);
    assertEq(uint256(version), 1);
  }

  function test_revertsWhenDeployingTheSameRelayer() public {
    address relayer = adapterFactory.deployRelayer(aRateFeed, mockAggregator);
    vm.expectRevert(relayerExistsError(relayer, aRateFeed, mockAggregator));
    adapterFactory.deployRelayer(aRateFeed, mockAggregator);
  }
}
