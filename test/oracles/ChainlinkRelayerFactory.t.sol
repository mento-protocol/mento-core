// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import "openzeppelin-contracts/ownership/Ownable.sol";

import "../utils/BaseTest.t.sol";
import "contracts/interfaces/IChainlinkRelayerFactory.sol";
import "contracts/interfaces/IChainlinkRelayer.sol";

contract ChainlinkRelayerFactoryTest is BaseTest {
  IChainlinkRelayerFactory relayerFactory;
  address owner = actor("owner");
  address nonOwner = actor("nonOwner");
  address mockSortedOracles = address(0x1337);
  address[3] mockAggregators = [address(0xcafe), address(0xc0ffee), address(0xdecaf)];
  address[3] rateFeeds = [address(0xbeef), address(0xbee5), address(0xca75)];
  address mockAggregator = mockAggregators[0];
  address aRateFeed = rateFeeds[0];

  event RelayerDeployed(address indexed relayerAddress, address indexed rateFeedId, address indexed aggregator);
  event RelayerRemoved(address indexed rateFeedId, address indexed relayerAddress);

  function setUp() public {
    relayerFactory = IChainlinkRelayerFactory(factory.createContract("ChainlinkRelayerFactory", abi.encode(false)));
    vm.prank(owner);
    relayerFactory.initialize(mockSortedOracles);
  }

  function expectedRelayerAddress(
    address rateFeedId,
    address sortedOracles,
    address chainlinkAggregator,
    address relayerFactoryAddress
  ) public returns (address) {
    bytes32 salt = keccak256("mento.chainlinkRelayer");
    return
      address(
        uint160(
          uint256(
            keccak256(
              abi.encodePacked(
                bytes1(0xff),
                relayerFactoryAddress,
                salt,
                keccak256(
                  abi.encodePacked(
                    vm.getCode(factory.contractPath("ChainlinkRelayerV1")),
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

  function relayerForFeedExistsError(address rateFeedId) public returns (bytes memory) {
    return abi.encodeWithSignature("RelayerForFeedExists(address)", rateFeedId);
  }

  function noSuchRelayerError(address rateFeedId) public returns (bytes memory) {
    return abi.encodeWithSignature("NoSuchRelayer(address)", rateFeedId);
  }
}

contract ChainlinkRelayerFactoryTest_initialize is ChainlinkRelayerFactoryTest {
  function test_setsSortedOracles() public {
    address realSortedOracles = relayerFactory.sortedOracles();
    assertEq(realSortedOracles, mockSortedOracles);
  }

  function test_setsOwner() public {
    address realOwner = Ownable(address(relayerFactory)).owner();
    assertEq(realOwner, owner);
  }
}

contract ChainlinkRelayerFactoryTest_transferOwnership is ChainlinkRelayerFactoryTest {
  function test_setsNewOwner() public {
    vm.prank(owner);
    Ownable(address(relayerFactory)).transferOwnership(nonOwner);
    address realOwner = Ownable(address(relayerFactory)).owner();
    assertEq(realOwner, nonOwner);
  }

  function test_failsWhenCalledByNonOwner() public {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(nonOwner);
    Ownable(address(relayerFactory)).transferOwnership(nonOwner);
  }
}

contract ChainlinkRelayerFactoryTest_renounceOwnership is ChainlinkRelayerFactoryTest {
  function test_setsOwnerToZeroAddress() public {
    vm.prank(owner);
    Ownable(address(relayerFactory)).renounceOwnership();
    address realOwner = Ownable(address(relayerFactory)).owner();
    assertEq(realOwner, address(0));
  }

  function test_failsWhenCalledByNonOwner() public {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(nonOwner);
    Ownable(address(relayerFactory)).renounceOwnership();
  }
}

contract ChainlinkRelayerFactoryTest_deployRelayer is ChainlinkRelayerFactoryTest {
  function test_setsRateFeed() public {
    IChainlinkRelayer relayer = IChainlinkRelayer(relayerFactory.deployRelayer(aRateFeed, mockAggregator));

    address rateFeed = relayer.rateFeedId();
    assertEq(rateFeed, aRateFeed);
  }

  function test_setsAggregator() public {
    IChainlinkRelayer relayer = IChainlinkRelayer(relayerFactory.deployRelayer(aRateFeed, mockAggregator));

    address aggregator = relayer.chainlinkAggregator();
    assertEq(aggregator, mockAggregator);
  }

  function test_setsSortedOracles() public {
    IChainlinkRelayer relayer = IChainlinkRelayer(relayerFactory.deployRelayer(aRateFeed, mockAggregator));

    address sortedOracles = relayer.sortedOracles();
    assertEq(sortedOracles, mockSortedOracles);
  }

  function test_deploysToTheCorrectAddress() public {
    address relayer = relayerFactory.deployRelayer(aRateFeed, mockAggregator);

    address expectedAddress = expectedRelayerAddress(
      aRateFeed,
      mockSortedOracles,
      mockAggregator,
      address(relayerFactory)
    );

    assertEq(relayer, expectedAddress);
  }

  function test_emitsRelayerDeployedEvent() public {
    address expectedAddress = expectedRelayerAddress(
      aRateFeed,
      mockSortedOracles,
      mockAggregator,
      address(relayerFactory)
    );
    vm.expectEmit(true, true, true, false, address(relayerFactory));
    emit RelayerDeployed(expectedAddress, aRateFeed, mockAggregator);
    relayerFactory.deployRelayer(aRateFeed, mockAggregator);
  }

  function test_remembersTheRelayerAddress() public {
    address relayer = relayerFactory.deployRelayer(aRateFeed, mockAggregator);
    address storedAddress = relayerFactory.getRelayer(aRateFeed);
    assertEq(storedAddress, relayer);
  }

  function test_revertsWhenDeployingTheSameRelayer() public {
    address relayer = relayerFactory.deployRelayer(aRateFeed, mockAggregator);
    vm.expectRevert(relayerExistsError(relayer, aRateFeed, mockAggregator));
    relayerFactory.deployRelayer(aRateFeed, mockAggregator);
  }

  function test_revertsWhenDeployingForTheSameRateFeed() public {
    relayerFactory.deployRelayer(aRateFeed, mockAggregators[0]);
    vm.expectRevert(relayerForFeedExistsError(aRateFeed));
    relayerFactory.deployRelayer(aRateFeed, mockAggregators[1]);
  }
}

contract ChainlinkRelayerFactoryTest_getRelayers is ChainlinkRelayerFactoryTest {
  function test_emptyWhenNoRelayers() public {
    address[] memory relayers = relayerFactory.getRelayers();
    assertEq(relayers.length, 0);
  }

  function test_returnsRelayerWhenThereIsOne() public {
    address relayerAddress = relayerFactory.deployRelayer(aRateFeed, mockAggregator);
    address[] memory relayers = relayerFactory.getRelayers();
    assertEq(relayers.length, 1);
    assertEq(relayers[0], relayerAddress);
  }

  function test_returnsMultipleRelayersWhenThereAreMore() public {
    address relayerAddress1 = relayerFactory.deployRelayer(rateFeeds[0], mockAggregators[0]);
    address relayerAddress2 = relayerFactory.deployRelayer(rateFeeds[1], mockAggregators[1]);
    address relayerAddress3 = relayerFactory.deployRelayer(rateFeeds[2], mockAggregators[2]);
    address[] memory relayers = relayerFactory.getRelayers();
    assertEq(relayers.length, 3);
    assertEq(relayers[0], relayerAddress1);
    assertEq(relayers[1], relayerAddress2);
    assertEq(relayers[2], relayerAddress3);
  }

  function test_returnsADifferentRelayerAfterRedeployment() public {
    address relayerAddress1 = relayerFactory.deployRelayer(rateFeeds[0], mockAggregators[0]);
    relayerFactory.deployRelayer(rateFeeds[1], mockAggregators[1]);
    address relayerAddress2 = relayerFactory.redeployRelayer(rateFeeds[1], mockAggregators[2]);
    address[] memory relayers = relayerFactory.getRelayers();
    assertEq(relayers.length, 2);
    assertEq(relayers[0], relayerAddress1);
    assertEq(relayers[1], relayerAddress2);
  }

  function test_doesntReturnARemovedRelayer() public {
    address relayerAddress1 = relayerFactory.deployRelayer(rateFeeds[0], mockAggregators[0]);
    address relayerAddress2 = relayerFactory.deployRelayer(rateFeeds[1], mockAggregators[1]);
    relayerFactory.deployRelayer(rateFeeds[2], mockAggregators[2]);
    relayerFactory.removeRelayer(rateFeeds[2]);
    address[] memory relayers = relayerFactory.getRelayers();
    assertEq(relayers.length, 2);
    assertEq(relayers[0], relayerAddress1);
    assertEq(relayers[1], relayerAddress2);
  }
}

contract ChainlinkRelayerFactoryTest_removeRelayer is ChainlinkRelayerFactoryTest {
  address relayerAddress;

  function setUp() public {
    super.setUp();

    relayerAddress = relayerFactory.deployRelayer(aRateFeed, mockAggregator);
  }

  function test_removesTheRelayer() public {
    relayerFactory.removeRelayer(aRateFeed);
    address relayer = relayerFactory.getRelayer(aRateFeed);
    assertEq(relayer, address(0));
  }

  function test_emitsRelayerRemovedEvent() public {
    vm.expectEmit(true, true, true, false, address(relayerFactory));
    emit RelayerRemoved(aRateFeed, relayerAddress);
    relayerFactory.removeRelayer(aRateFeed);
  }

  function test_doesntRemoveOtherRelayers() public {
    address relayerAddress = relayerFactory.deployRelayer(rateFeeds[1], mockAggregators[1]);
    relayerFactory.removeRelayer(aRateFeed);
    address[] memory relayers = relayerFactory.getRelayers();

    assertEq(relayers.length, 1);
    assertEq(relayers[0], relayerAddress);
  }

  function test_revertsOnNonexistentRelayer() public {
    vm.expectRevert(noSuchRelayerError(rateFeeds[1]));
    relayerFactory.removeRelayer(rateFeeds[1]);
  }
}

contract ChainlinkRelayerFactoryTest_redeployRelayer is ChainlinkRelayerFactoryTest {
  address oldAddress;

  function setUp() public {
    super.setUp();
    oldAddress = relayerFactory.deployRelayer(aRateFeed, mockAggregator);
  }

  function test_setsRateFeedOnNewRelayer() public {
    IChainlinkRelayer relayer = IChainlinkRelayer(relayerFactory.redeployRelayer(aRateFeed, mockAggregators[1]));

    address rateFeed = relayer.rateFeedId();
    assertEq(rateFeed, aRateFeed);
  }

  function test_setsAggregatorOnNewRelayer() public {
    IChainlinkRelayer relayer = IChainlinkRelayer(relayerFactory.redeployRelayer(aRateFeed, mockAggregators[1]));

    address aggregator = relayer.chainlinkAggregator();
    assertEq(aggregator, mockAggregators[1]);
  }

  function test_setsSortedOraclesOnNewRelayer() public {
    IChainlinkRelayer relayer = IChainlinkRelayer(relayerFactory.redeployRelayer(aRateFeed, mockAggregators[1]));

    address sortedOracles = relayer.sortedOracles();
    assertEq(sortedOracles, mockSortedOracles);
  }

  function test_deploysToTheCorrectNewAddress() public {
    address relayer = relayerFactory.redeployRelayer(aRateFeed, mockAggregators[1]);

    address expectedAddress = expectedRelayerAddress(
      aRateFeed,
      mockSortedOracles,
      mockAggregators[1],
      address(relayerFactory)
    );

    assertEq(relayer, expectedAddress);
  }

  function test_emitsRelayerRemovedAndDeployedEvents() public {
    address expectedAddress = expectedRelayerAddress(
      aRateFeed,
      mockSortedOracles,
      mockAggregators[1],
      address(relayerFactory)
    );
    vm.expectEmit(true, true, true, false, address(relayerFactory));
    emit RelayerRemoved(aRateFeed, oldAddress);
    vm.expectEmit(true, true, true, false, address(relayerFactory));
    emit RelayerDeployed(expectedAddress, aRateFeed, mockAggregators[1]);
    relayerFactory.redeployRelayer(aRateFeed, mockAggregators[1]);
  }

  function test_remembersTheNewRelayerAddress() public {
    address relayer = relayerFactory.redeployRelayer(aRateFeed, mockAggregators[1]);
    address storedAddress = relayerFactory.getRelayer(aRateFeed);
    assertEq(storedAddress, relayer);
  }

  function test_revertsWhenDeployingTheSameExactRelayer() public {
    vm.expectRevert(relayerExistsError(oldAddress, aRateFeed, mockAggregator));
    relayerFactory.redeployRelayer(aRateFeed, mockAggregator);
  }
}
