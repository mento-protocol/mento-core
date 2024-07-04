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
  address mockSortedOracles = address(0x1337);
  address[3] mockAggregators = [address(0xcafe), address(0xc0ffee), address(0xdecaf)];
  address[3] rateFeeds = [address(0xbeef), address(0xbee5), address(0xca75)];
  address mockAggregator = mockAggregators[0];
  address aRateFeed = rateFeeds[0];

  event RelayerDeployed(address indexed relayerAddress, address indexed rateFeedId, address indexed aggregator);
  event RelayerRemoved(address indexed rateFeedId, address indexed relayerAddress);

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

  function noSuchRelayerError(address rateFeedId) public returns (bytes memory) {
    return abi.encodeWithSignature("NoSuchRelayer(address)", rateFeedId);
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
    address storedAddress = adapterFactory.getRelayer(aRateFeed);
    assertEq(storedAddress, relayer);
  }

  function test_revertsWhenDeployingTheSameRelayer() public {
    address relayer = adapterFactory.deployRelayer(aRateFeed, mockAggregator);
    vm.expectRevert(relayerExistsError(relayer, aRateFeed, mockAggregator));
    adapterFactory.deployRelayer(aRateFeed, mockAggregator);
  }
}

contract ChainlinkAdapterFactoryTest_getRelayers is ChainlinkAdapterFactoryTest {
  function test_emptyWhenNoRelayers() public {
    address[] memory relayers = adapterFactory.getRelayers();
    assertEq(relayers.length, 0);
  }

  function test_returnsRelayerWhenThereIsOne() public {
    address adapterAddress = adapterFactory.deployRelayer(aRateFeed, mockAggregator);
    address[] memory relayers = adapterFactory.getRelayers();
    assertEq(relayers.length, 1);
    assertEq(relayers[0], adapterAddress);
  }

  function test_returnsMultipleRelayersWhenThereAreMore() public {
    address adapterAddress1 = adapterFactory.deployRelayer(rateFeeds[0], mockAggregators[0]);
    address adapterAddress2 = adapterFactory.deployRelayer(rateFeeds[1], mockAggregators[1]);
    address adapterAddress3 = adapterFactory.deployRelayer(rateFeeds[2], mockAggregators[2]);
    address[] memory relayers = adapterFactory.getRelayers();
    assertEq(relayers.length, 3);
    assertEq(relayers[0], adapterAddress1);
    assertEq(relayers[1], adapterAddress2);
    assertEq(relayers[2], adapterAddress3);
  }

  function test_returnsADifferentRelayerAfterRedeployment() public {
    address adapterAddress1 = adapterFactory.deployRelayer(rateFeeds[0], mockAggregators[0]);
    adapterFactory.deployRelayer(rateFeeds[1], mockAggregators[1]);
    address adapterAddress2 = adapterFactory.redeployRelayer(rateFeeds[1], mockAggregators[2]);
    address[] memory relayers = adapterFactory.getRelayers();
    assertEq(relayers.length, 2);
    assertEq(relayers[0], adapterAddress1);
    assertEq(relayers[1], adapterAddress2);
  }

  function test_doesntReturnARemovedRelayer() public {
    address adapterAddress1 = adapterFactory.deployRelayer(rateFeeds[0], mockAggregators[0]);
    address adapterAddress2 = adapterFactory.deployRelayer(rateFeeds[1], mockAggregators[1]);
    adapterFactory.deployRelayer(rateFeeds[2], mockAggregators[2]);
    adapterFactory.removeRelayer(rateFeeds[2]);
    address[] memory relayers = adapterFactory.getRelayers();
    assertEq(relayers.length, 2);
    assertEq(relayers[0], adapterAddress1);
    assertEq(relayers[1], adapterAddress2);
  }
}

contract ChainlinkAdapterFactoryTest_removeRelayer is ChainlinkAdapterFactoryTest {
  address adapterAddress;

  function setUp() public {
    super.setUp();

    adapterAddress = adapterFactory.deployRelayer(aRateFeed, mockAggregator);
  }

  function test_removesTheRelayer() public {
    adapterFactory.removeRelayer(aRateFeed);
    address relayer = adapterFactory.getRelayer(aRateFeed);
    assertEq(relayer, address(0));
  }

  function test_emitsRelayerRemovedEvent() public {
    vm.expectEmit(true, true, true, false, address(adapterFactory));
    emit RelayerRemoved(aRateFeed, adapterAddress);
    adapterFactory.removeRelayer(aRateFeed);
  }

  function test_doesntRemoveOtherRelayers() public {
    address adapterAddress = adapterFactory.deployRelayer(rateFeeds[1], mockAggregators[1]);
    adapterFactory.removeRelayer(aRateFeed);
    address[] memory relayers = adapterFactory.getRelayers();

    assertEq(relayers.length, 1);
    assertEq(relayers[0], adapterAddress);
  }

  function test_revertsOnNonexistentRelayer() public {
    vm.expectRevert(noSuchRelayerError(rateFeeds[1]));
    adapterFactory.removeRelayer(rateFeeds[1]);
  }
}

contract ChainlinkAdapterFactoryTest_redeployRelayer is ChainlinkAdapterFactoryTest {
  address oldAddress;

  function setUp() public {
    super.setUp();
    oldAddress = adapterFactory.deployRelayer(aRateFeed, mockAggregator);
  }

  function test_setsRateFeedOnNewRelayer() public {
    IChainlinkAdapter relayer = IChainlinkAdapter(adapterFactory.redeployRelayer(aRateFeed, mockAggregators[1]));

    address rateFeed = relayer.token();
    assertEq(rateFeed, aRateFeed);
  }

  function test_setsAggregatorOnNewRelayer() public {
    IChainlinkAdapter relayer = IChainlinkAdapter(adapterFactory.redeployRelayer(aRateFeed, mockAggregators[1]));

    address aggregator = relayer.aggregator();
    assertEq(aggregator, mockAggregators[1]);
  }

  function test_setsSortedOraclesOnNewRelayer() public {
    IChainlinkAdapter relayer = IChainlinkAdapter(adapterFactory.redeployRelayer(aRateFeed, mockAggregators[1]));

    address sortedOracles = relayer.sortedOracles();
    assertEq(sortedOracles, mockSortedOracles);
  }

  function test_deploysToTheCorrectNewAddress() public {
    address relayer = adapterFactory.redeployRelayer(aRateFeed, mockAggregators[1]);

    address expectedAddress = expectedRelayerAddress(
      aRateFeed,
      mockSortedOracles,
      mockAggregators[1],
      address(adapterFactory)
    );

    assertEq(relayer, expectedAddress);
  }

  function test_emitsRelayerRemovedAndDeployedEvents() public {
    address expectedAddress = expectedRelayerAddress(
      aRateFeed,
      mockSortedOracles,
      mockAggregators[1],
      address(adapterFactory)
    );
    vm.expectEmit(true, true, true, false, address(adapterFactory));
    emit RelayerRemoved(aRateFeed, oldAddress);
    vm.expectEmit(true, true, true, false, address(adapterFactory));
    emit RelayerDeployed(expectedAddress, aRateFeed, mockAggregators[1]);
    adapterFactory.redeployRelayer(aRateFeed, mockAggregators[1]);
  }

  function test_remembersTheNewRelayerAddress() public {
    address relayer = adapterFactory.redeployRelayer(aRateFeed, mockAggregators[1]);
    address storedAddress = adapterFactory.getRelayer(aRateFeed);
    assertEq(storedAddress, relayer);
  }

  function test_revertsWhenDeployingTheSameExactRelayer() public {
    vm.expectRevert(relayerExistsError(oldAddress, aRateFeed, mockAggregator));
    adapterFactory.redeployRelayer(aRateFeed, mockAggregator);
  }
}
