// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, private-vars-leading-underscore
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase, one-contract-per-file
pragma solidity ^0.8.18;

import { Ownable } from "openzeppelin-contracts-next/contracts/access/Ownable.sol";
import { BaseTest } from "../utils/BaseTest.next.sol";
import { IChainlinkRelayerFactory } from "contracts/interfaces/IChainlinkRelayerFactory.sol";
import { IChainlinkRelayer } from "contracts/interfaces/IChainlinkRelayer.sol";
import { ChainlinkRelayerFactory } from "contracts/oracles/ChainlinkRelayerFactory.sol";

contract ChainlinkRelayerFactoryTest is BaseTest {
  IChainlinkRelayerFactory relayerFactory;
  address owner = makeAddr("owner");
  address nonOwner = makeAddr("nonOwner");
  address mockSortedOracles = makeAddr("sortedOracles");
  address[4] mockAggregators = [
    makeAddr("aggregator1"),
    makeAddr("aggregator2"),
    makeAddr("aggregator3"),
    makeAddr("aggregator4")
  ];
  address[3] rateFeeds = [makeAddr("rateFeed1"), makeAddr("rateFeed2"), makeAddr("rateFeed3")];
  address aRateFeed = rateFeeds[0];

  IChainlinkRelayer.Config relayerConfig0 =
    IChainlinkRelayer.Config(0, mockAggregators[0], address(0), address(0), address(0), false, false, false, false);
  IChainlinkRelayer.Config relayerConfig1 =
    IChainlinkRelayer.Config(0, mockAggregators[1], address(0), address(0), address(0), false, false, false, false);
  IChainlinkRelayer.Config relayerConfig2 =
    IChainlinkRelayer.Config(0, mockAggregators[2], address(0), address(0), address(0), false, false, false, false);
  IChainlinkRelayer.Config relayerConfigComplex =
    IChainlinkRelayer.Config(
      1024,
      mockAggregators[0],
      mockAggregators[1],
      mockAggregators[2],
      mockAggregators[3],
      false,
      true,
      false,
      true
    );

  event RelayerDeployed(
    address indexed relayerAddress,
    address indexed rateFeedId,
    IChainlinkRelayer.Config relayerConfig
  );
  event RelayerRemoved(address indexed relayerAddress, address indexed rateFeedId);

  function setUp() public virtual {
    relayerFactory = IChainlinkRelayerFactory(new ChainlinkRelayerFactory(false));
    vm.prank(owner);
    relayerFactory.initialize(mockSortedOracles);
  }

  function assertRelayerMatchesConfig(IChainlinkRelayer relayer, IChainlinkRelayer.Config memory expected) internal {
    IChainlinkRelayer.Config memory actual = relayer.getConfig();
    assertEq(keccak256(abi.encode(expected)), keccak256(abi.encode(actual)));
  }

  function expectedRelayerAddress(
    address rateFeedId,
    address sortedOracles,
    IChainlinkRelayer.Config memory relayerConfig,
    address relayerFactoryAddress
  ) internal view returns (address expectedAddress) {
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
                    abi.encode(
                      rateFeedId,
                      sortedOracles,
                      relayerConfig.maxTimestampSpread,
                      relayerConfig.chainlinkAggregator0,
                      relayerConfig.chainlinkAggregator1,
                      relayerConfig.chainlinkAggregator2,
                      relayerConfig.chainlinkAggregator3,
                      relayerConfig.invertAggregator0,
                      relayerConfig.invertAggregator1,
                      relayerConfig.invertAggregator2,
                      relayerConfig.invertAggregator3
                    )
                  )
                )
              )
            )
          )
        )
      );
  }

  function contractAlreadyExistsError(address relayerAddress, address rateFeedId)
    public
    pure
    returns (bytes memory ContractAlreadyExistsError)
  {
    return abi.encodeWithSignature("ContractAlreadyExists(address,address)", relayerAddress, rateFeedId);
  }

  function relayerForFeedExistsError(address rateFeedId) public pure returns (bytes memory RelayerForFeedExistsError) {
    return abi.encodeWithSignature("RelayerForFeedExists(address)", rateFeedId);
  }

  function noRelayerForRateFeedId(address rateFeedId) public pure returns (bytes memory NoRelayerForRateFeedIdError) {
    return abi.encodeWithSignature("NoRelayerForRateFeedId(address)", rateFeedId);
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
    vm.prank(owner);
    IChainlinkRelayer relayer = IChainlinkRelayer(relayerFactory.deployRelayer(aRateFeed, relayerConfig0));

    address rateFeed = relayer.rateFeedId();
    assertEq(rateFeed, aRateFeed);
  }

  function test_setsConfig() public {
    vm.prank(owner);
    IChainlinkRelayer relayer = IChainlinkRelayer(relayerFactory.deployRelayer(aRateFeed, relayerConfigComplex));
    assertRelayerMatchesConfig(relayer, relayerConfigComplex);
  }

  function test_setsSortedOracles() public {
    vm.prank(owner);
    IChainlinkRelayer relayer = IChainlinkRelayer(relayerFactory.deployRelayer(aRateFeed, relayerConfig0));

    address sortedOracles = relayer.sortedOracles();
    assertEq(sortedOracles, mockSortedOracles);
  }

  function test_deploysToTheCorrectAddress() public {
    vm.prank(owner);
    address relayer = relayerFactory.deployRelayer(aRateFeed, relayerConfig0);

    address expectedAddress = expectedRelayerAddress({
      rateFeedId: aRateFeed,
      sortedOracles: mockSortedOracles,
      relayerConfig: relayerConfig0,
      relayerFactoryAddress: address(relayerFactory)
    });

    assertEq(relayer, expectedAddress);
  }

  function test_emitsRelayerDeployedEvent() public {
    address expectedAddress = expectedRelayerAddress(
      aRateFeed,
      mockSortedOracles,
      relayerConfig0,
      address(relayerFactory)
    );
    // solhint-disable-next-line func-named-parameters
    vm.expectEmit(true, true, true, false, address(relayerFactory));
    emit RelayerDeployed({ relayerAddress: expectedAddress, rateFeedId: aRateFeed, relayerConfig: relayerConfig0 });
    vm.prank(owner);
    relayerFactory.deployRelayer(aRateFeed, relayerConfig0);
  }

  function test_remembersTheRelayerAddress() public {
    vm.prank(owner);
    address relayer = relayerFactory.deployRelayer(aRateFeed, relayerConfig0);
    address storedAddress = relayerFactory.getRelayer(aRateFeed);
    assertEq(storedAddress, relayer);
  }

  function test_revertsWhenDeployingTheSameRelayer() public {
    vm.prank(owner);
    address relayer = relayerFactory.deployRelayer(aRateFeed, relayerConfig0);
    vm.expectRevert(contractAlreadyExistsError(relayer, aRateFeed));
    vm.prank(owner);
    relayerFactory.deployRelayer(aRateFeed, relayerConfig0);
  }

  function test_revertsWhenDeployingForTheSameRateFeed() public {
    vm.prank(owner);
    relayerFactory.deployRelayer(aRateFeed, relayerConfig0);
    vm.expectRevert(relayerForFeedExistsError(aRateFeed));
    vm.prank(owner);
    relayerFactory.deployRelayer(aRateFeed, relayerConfig1);
  }

  function test_revertsWhenCalledByNonOwner() public {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(nonOwner);
    relayerFactory.deployRelayer(aRateFeed, relayerConfig0);
  }
}

contract ChainlinkRelayerFactoryTest_getRelayers is ChainlinkRelayerFactoryTest {
  function test_emptyWhenNoRelayers() public {
    address[] memory relayers = relayerFactory.getRelayers();
    assertEq(relayers.length, 0);
  }

  function test_returnsRelayerWhenThereIsOne() public {
    vm.prank(owner);
    address relayerAddress = relayerFactory.deployRelayer(aRateFeed, relayerConfig0);
    address[] memory relayers = relayerFactory.getRelayers();
    assertEq(relayers.length, 1);
    assertEq(relayers[0], relayerAddress);
  }

  function test_returnsMultipleRelayersWhenThereAreMore() public {
    vm.prank(owner);
    address relayerAddress1 = relayerFactory.deployRelayer(rateFeeds[0], relayerConfig0);
    vm.prank(owner);
    address relayerAddress2 = relayerFactory.deployRelayer(rateFeeds[1], relayerConfig1);
    vm.prank(owner);
    address relayerAddress3 = relayerFactory.deployRelayer(rateFeeds[2], relayerConfig2);
    address[] memory relayers = relayerFactory.getRelayers();
    assertEq(relayers.length, 3);
    assertEq(relayers[0], relayerAddress1);
    assertEq(relayers[1], relayerAddress2);
    assertEq(relayers[2], relayerAddress3);
  }

  function test_returnsADifferentRelayerAfterRedeployment() public {
    vm.prank(owner);
    address relayerAddress1 = relayerFactory.deployRelayer(rateFeeds[0], relayerConfig0);
    vm.prank(owner);
    relayerFactory.deployRelayer(rateFeeds[1], relayerConfig1);
    vm.prank(owner);
    address relayerAddress2 = relayerFactory.redeployRelayer(rateFeeds[1], relayerConfig2);
    address[] memory relayers = relayerFactory.getRelayers();
    assertEq(relayers.length, 2);
    assertEq(relayers[0], relayerAddress1);
    assertEq(relayers[1], relayerAddress2);
  }

  function test_doesntReturnARemovedRelayer() public {
    vm.prank(owner);
    address relayerAddress1 = relayerFactory.deployRelayer(rateFeeds[0], relayerConfig0);
    vm.prank(owner);
    address relayerAddress2 = relayerFactory.deployRelayer(rateFeeds[1], relayerConfig1);
    vm.prank(owner);
    relayerFactory.deployRelayer(rateFeeds[2], relayerConfig2);
    vm.prank(owner);
    relayerFactory.removeRelayer(rateFeeds[2]);
    address[] memory relayers = relayerFactory.getRelayers();
    assertEq(relayers.length, 2);
    assertEq(relayers[0], relayerAddress1);
    assertEq(relayers[1], relayerAddress2);
  }
}

contract ChainlinkRelayerFactoryTest_removeRelayer is ChainlinkRelayerFactoryTest {
  address relayerAddress;

  function setUp() public override {
    super.setUp();

    vm.prank(owner);
    relayerAddress = relayerFactory.deployRelayer(aRateFeed, relayerConfig0);
  }

  function test_removesTheRelayer() public {
    vm.prank(owner);
    relayerFactory.removeRelayer(aRateFeed);
    vm.prank(owner);
    address relayer = relayerFactory.getRelayer(aRateFeed);
    assertEq(relayer, address(0));
  }

  function test_emitsRelayerRemovedEvent() public {
    // solhint-disable-next-line func-named-parameters
    vm.expectEmit(true, true, true, false, address(relayerFactory));
    emit RelayerRemoved({ relayerAddress: relayerAddress, rateFeedId: aRateFeed });
    vm.prank(owner);
    relayerFactory.removeRelayer(aRateFeed);
  }

  function test_doesntRemoveOtherRelayers() public {
    vm.prank(owner);
    address newRelayerAddress = relayerFactory.deployRelayer(rateFeeds[1], relayerConfig1);
    vm.prank(owner);
    relayerFactory.removeRelayer(aRateFeed);
    address[] memory relayers = relayerFactory.getRelayers();

    assertEq(relayers.length, 1);
    assertEq(relayers[0], newRelayerAddress);
  }

  function test_revertsOnNonexistentRelayer() public {
    vm.expectRevert(noRelayerForRateFeedId(rateFeeds[1]));
    vm.prank(owner);
    relayerFactory.removeRelayer(rateFeeds[1]);
  }

  function test_revertsWhenCalledByNonOwner() public {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(nonOwner);
    relayerFactory.removeRelayer(aRateFeed);
  }
}

contract ChainlinkRelayerFactoryTest_redeployRelayer is ChainlinkRelayerFactoryTest {
  address oldAddress;

  function setUp() public override {
    super.setUp();
    vm.prank(owner);
    oldAddress = relayerFactory.deployRelayer(aRateFeed, relayerConfig0);
  }

  function test_setsRateFeedOnNewRelayer() public {
    vm.prank(owner);
    IChainlinkRelayer relayer = IChainlinkRelayer(relayerFactory.redeployRelayer(aRateFeed, relayerConfig1));

    address rateFeed = relayer.rateFeedId();
    assertEq(rateFeed, aRateFeed);
  }

  function test_setsAggregatorOnNewRelayer() public {
    vm.prank(owner);
    IChainlinkRelayer relayer = IChainlinkRelayer(relayerFactory.redeployRelayer(aRateFeed, relayerConfig1));

    assertRelayerMatchesConfig(relayer, relayerConfig1);
  }

  function test_setsSortedOraclesOnNewRelayer() public {
    vm.prank(owner);
    IChainlinkRelayer relayer = IChainlinkRelayer(relayerFactory.redeployRelayer(aRateFeed, relayerConfig1));

    address sortedOracles = relayer.sortedOracles();
    assertEq(sortedOracles, mockSortedOracles);
  }

  function test_deploysToTheCorrectNewAddress() public {
    vm.prank(owner);
    address relayer = relayerFactory.redeployRelayer(aRateFeed, relayerConfig1);

    address expectedAddress = expectedRelayerAddress(
      aRateFeed,
      mockSortedOracles,
      relayerConfig1,
      address(relayerFactory)
    );

    assertEq(relayer, expectedAddress);
  }

  function test_emitsRelayerRemovedAndDeployedEvents() public {
    address expectedAddress = expectedRelayerAddress({
      rateFeedId: aRateFeed,
      sortedOracles: mockSortedOracles,
      relayerConfig: relayerConfig1,
      relayerFactoryAddress: address(relayerFactory)
    });
    // solhint-disable-next-line func-named-parameters
    vm.expectEmit(true, true, true, false, address(relayerFactory));
    emit RelayerRemoved({ relayerAddress: oldAddress, rateFeedId: aRateFeed });
    // solhint-disable-next-line func-named-parameters
    vm.expectEmit(true, true, true, false, address(relayerFactory));
    emit RelayerDeployed({ relayerAddress: expectedAddress, rateFeedId: aRateFeed, relayerConfig: relayerConfig1 });
    vm.prank(owner);
    relayerFactory.redeployRelayer(aRateFeed, relayerConfig1);
  }

  function test_remembersTheNewRelayerAddress() public {
    vm.prank(owner);
    address relayer = relayerFactory.redeployRelayer(aRateFeed, relayerConfig1);
    address storedAddress = relayerFactory.getRelayer(aRateFeed);
    assertEq(storedAddress, relayer);
  }

  function test_revertsWhenDeployingTheSameExactRelayer() public {
    vm.expectRevert(contractAlreadyExistsError(oldAddress, aRateFeed));
    vm.prank(owner);
    relayerFactory.redeployRelayer(aRateFeed, relayerConfig0);
  }

  function test_revertsWhenCalledByNonOwner() public {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(nonOwner);
    relayerFactory.redeployRelayer(aRateFeed, relayerConfig1);
  }
}
