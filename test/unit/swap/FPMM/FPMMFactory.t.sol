// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { FPMMFactory } from "contracts/swap/FPMMFactory.sol";
import { FPMM } from "contracts/swap/FPMM.sol";
// solhint-disable-next-line max-line-length
import { ITransparentUpgradeableProxy } from "openzeppelin-contracts-next/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { IFPMM } from "contracts/interfaces/IFPMM.sol";
import { IFPMMFactory } from "contracts/interfaces/IFPMMFactory.sol";

contract FPMMFactoryTest is Test {
  /* ------- Events from FPMMFactory ------- */
  event FPMMDeployed(address indexed token0, address indexed token1, address fpmmProxy, address fpmmImplementation);
  event FPMMImplementationRegistered(address indexed fpmmImplementation);
  event FPMMImplementationUnregistered(address indexed fpmmImplementation);
  event ProxyAdminSet(address indexed proxyAdmin);
  event OracleAdapterSet(address indexed oracleAdapter);
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
  event DefaultParamsSet(IFPMM.FPMMParams defaultParams);
  event Initialized(uint8 version);
  /* --------------------------------------- */

  address public deployer;
  address public createX;
  address public referenceRateFeedID;

  // Celo
  uint256 public celoFork;
  address public token0Celo;
  address public token1Celo;
  address public oracleAdapterCelo;
  address public proxyAdminCelo;
  address public governanceCelo;
  FPMMFactory public factoryCelo;
  FPMM public fpmmImplementationCelo;
  address public fpmmImplementationCeloAddress;
  IFPMM.FPMMParams public defaultFpmmParamsCelo;

  // Optimism
  uint256 public opFork;
  address public token0Op;
  address public token1Op;
  address public oracleAdapterOp;
  address public proxyAdminOp;
  address public governanceOp;
  FPMMFactory public factoryOp;
  FPMM public fpmmImplementationOp;
  address public fpmmImplementationOpAddress;
  IFPMM.FPMMParams public defaultFpmmParamsOp;

  function setUp() public virtual {
    createX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
    deployer = makeAddr("Deployer");
    referenceRateFeedID = makeAddr("token0/token1");

    celoFork = vm.createFork("https://forno.celo.org");
    token0Celo = 0x0000000000000000000000000000000000000c31;
    token1Celo = 0x0000000000000000000000000000000000000c32;
    oracleAdapterCelo = makeAddr("OracleAdapter Celo");
    proxyAdminCelo = makeAddr("ProxyAdmin Celo");
    governanceCelo = makeAddr("Governance Celo");
    fpmmImplementationCelo = new FPMM(true);
    fpmmImplementationCeloAddress = address(fpmmImplementationCelo);
    vm.makePersistent(address(fpmmImplementationCelo));
    defaultFpmmParamsCelo = IFPMM.FPMMParams({
      lpFee: 30,
      protocolFee: 0,
      protocolFeeRecipient: makeAddr("protocolFeeRecipientCelo"),
      feeSetter: address(0),
      rebalanceIncentive: 50,
      rebalanceThresholdAbove: 500,
      rebalanceThresholdBelow: 500
    });

    opFork = vm.createFork("https://mainnet.optimism.io");
    token0Op = 0x0000000000000000000000000000000000000c39;
    token1Op = 0x0000000000000000000000000000000000000C3a;
    oracleAdapterOp = makeAddr("OracleAdapter Optimism");
    proxyAdminOp = makeAddr("ProxyAdmin Optimism");
    governanceOp = makeAddr("Governance Optimism");
    fpmmImplementationOp = new FPMM(true);
    fpmmImplementationOpAddress = address(fpmmImplementationOp);
    vm.makePersistent(address(fpmmImplementationOp));
    defaultFpmmParamsOp = IFPMM.FPMMParams({
      lpFee: 50,
      protocolFee: 0,
      protocolFeeRecipient: makeAddr("protocolFeeRecipientOp"),
      feeSetter: address(0),
      rebalanceIncentive: 25,
      rebalanceThresholdAbove: 250,
      rebalanceThresholdBelow: 250
    });
  }

  function assertEqFPMMParams(IFPMM.FPMMParams memory expected, IFPMM.FPMMParams memory actual) internal pure {
    assertEq(expected.lpFee, actual.lpFee);
    assertEq(expected.protocolFee, actual.protocolFee);
    assertEq(expected.protocolFeeRecipient, actual.protocolFeeRecipient);
    assertEq(expected.feeSetter, actual.feeSetter);
    assertEq(expected.rebalanceIncentive, actual.rebalanceIncentive);
    assertEq(expected.rebalanceThresholdAbove, actual.rebalanceThresholdAbove);
    assertEq(expected.rebalanceThresholdBelow, actual.rebalanceThresholdBelow);
  }
}

contract FPMMFactoryTest_InitializerSettersGetters is FPMMFactoryTest {
  function setUp() public override {
    super.setUp();
  }

  function test_constructor_whenDisableTrue_shouldDisableInitializers() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(true);
    vm.expectRevert("Initializable: contract is already initialized");
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );
  }
  function test_constructor_whenDisableFalse_shouldNotDisableInitializers() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );
  }

  function test_constructor_whenCreateXNotDeployed_shouldRevert() public {
    vm.expectRevert(IFPMMFactory.CreateXBytecodeHashMismatch.selector);
    factoryCelo = new FPMMFactory(false);
  }

  function test_constructor_whenDifferentContractIsDeployedToCreateXAddress_shouldRevert() public {
    deployCodeTo("ERC20", abi.encode("Token 0", "T0"), createX);
    vm.expectRevert(IFPMMFactory.CreateXBytecodeHashMismatch.selector);
    factoryCelo = new FPMMFactory(false);
  }

  function test_initialize_shouldSetOwnerToGovernance() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    vm.prank(deployer);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );
    assertEq(factoryCelo.owner(), governanceCelo);
  }

  function test_initialize_whenOracleAdapterIsZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    vm.expectRevert(IFPMMFactory.ZeroAddress.selector);
    factoryCelo.initialize(
      address(0),
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );
  }

  function test_initialize_whenProxyAdminIsZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    vm.expectRevert(IFPMMFactory.ZeroAddress.selector);
    factoryCelo.initialize(
      oracleAdapterCelo,
      address(0),
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );
  }

  function test_initialize_whenFPMMImplementationIsZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    vm.expectRevert(IFPMMFactory.ZeroAddress.selector);
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(0), defaultFpmmParamsCelo);
  }

  function test_initialize_whenInitialOwnerIsZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    vm.expectRevert("Ownable: new owner is the zero address");
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      address(0),
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );
  }

  function test_initialize_whenDefaultParamsIsInvalid_shouldRevert() public {
    IFPMM.FPMMParams memory invalidDefaultFpmmParams = defaultFpmmParamsCelo;
    invalidDefaultFpmmParams.lpFee = 201;

    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    vm.expectRevert(IFPMMFactory.FeeTooHigh.selector);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      invalidDefaultFpmmParams
    );
  }

  function test_initialized_shouldSetVariablesAndEmitEvents() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);

    vm.expectEmit();
    emit OwnershipTransferred(address(0), address(this));
    vm.expectEmit();
    emit ProxyAdminSet(proxyAdminCelo);
    vm.expectEmit();
    emit OracleAdapterSet(oracleAdapterCelo);
    vm.expectEmit();
    emit FPMMImplementationRegistered(address(fpmmImplementationCelo));
    vm.expectEmit();
    emit DefaultParamsSet(defaultFpmmParamsCelo);
    vm.expectEmit();
    emit OwnershipTransferred(address(this), governanceCelo);
    vm.expectEmit();
    emit Initialized(1);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );

    assertEq(factoryCelo.oracleAdapter(), oracleAdapterCelo);
    assertEq(factoryCelo.proxyAdmin(), proxyAdminCelo);
    assertEq(factoryCelo.isRegisteredImplementation(address(fpmmImplementationCelo)), true);
    address[] memory registeredImplementations = factoryCelo.registeredImplementations();
    assertEq(registeredImplementations.length, 1);
    assertEq(registeredImplementations[0], address(fpmmImplementationCelo));
    assertEq(factoryCelo.owner(), governanceCelo);
    assertEqFPMMParams(defaultFpmmParamsCelo, factoryCelo.defaultParams());
  }

  function test_setOracleAdapter_whenCallerIsNotOwner_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );

    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("Not Owner"));
    factoryCelo.setOracleAdapter(makeAddr("New OracleAdapter"));
  }

  function test_setOracleAdapter_whenZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );

    vm.expectRevert(IFPMMFactory.ZeroAddress.selector);
    vm.prank(governanceCelo);
    factoryCelo.setOracleAdapter(address(0));
  }

  function test_setOracleAdapter_shouldSetOracleAdapterAndEmitEvent() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );

    address newOracleAdapter = makeAddr("New OracleAdapter");
    vm.expectEmit();
    emit OracleAdapterSet(newOracleAdapter);
    vm.prank(governanceCelo);
    factoryCelo.setOracleAdapter(newOracleAdapter);

    assertEq(factoryCelo.oracleAdapter(), newOracleAdapter);
  }

  function test_setProxyAdmin_whenCallerIsNotOwner_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );

    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("Not Owner"));
    factoryCelo.setProxyAdmin(makeAddr("New ProxyAdmin"));
  }

  function test_setProxyAdmin_whenZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );

    vm.expectRevert(IFPMMFactory.ZeroAddress.selector);
    vm.prank(governanceCelo);
    factoryCelo.setProxyAdmin(address(0));
  }

  function test_setProxyAdmin_shouldSetProxyAdminAndEmitEvent() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );

    address newProxyAdmin = makeAddr("New ProxyAdmin");
    vm.expectEmit();
    emit ProxyAdminSet(newProxyAdmin);
    vm.prank(governanceCelo);
    factoryCelo.setProxyAdmin(newProxyAdmin);

    assertEq(factoryCelo.proxyAdmin(), newProxyAdmin);
  }

  function test_transferOwnership_whenCallerIsNotOwner_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );

    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("Not Owner"));
    factoryCelo.transferOwnership(makeAddr("New Owner"));
  }

  function test_setOwner_whenZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );

    vm.expectRevert("Ownable: new owner is the zero address");
    vm.prank(governanceCelo);
    factoryCelo.transferOwnership(address(0));
  }

  function test_transferOwnership_shouldSetOwnerAndEmitEvent() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );

    address newOwner = makeAddr("New Owner");
    vm.expectEmit();
    emit OwnershipTransferred(governanceCelo, newOwner);
    vm.prank(governanceCelo);
    factoryCelo.transferOwnership(newOwner);

    assertEq(factoryCelo.owner(), newOwner);
  }

  function test_setDefaultParams_whenCallerIsNotOwner_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );

    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("Not Owner"));
    factoryCelo.setDefaultParams(defaultFpmmParamsCelo);
  }

  function test_setDefaultParams_whenLpFeeIsTooHigh_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );

    IFPMM.FPMMParams memory invalidDefaultFpmmParams = defaultFpmmParamsCelo;
    invalidDefaultFpmmParams.lpFee = 201;

    vm.expectRevert(IFPMMFactory.FeeTooHigh.selector);
    vm.prank(governanceCelo);
    factoryCelo.setDefaultParams(invalidDefaultFpmmParams);
  }

  function test_setDefaultParams_whenProtocolFeeIsTooHigh_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );

    IFPMM.FPMMParams memory invalidDefaultFpmmParams = defaultFpmmParamsCelo;
    invalidDefaultFpmmParams.protocolFee = 201;

    vm.expectRevert(IFPMMFactory.FeeTooHigh.selector);
    vm.prank(governanceCelo);
    factoryCelo.setDefaultParams(invalidDefaultFpmmParams);
  }

  function test_setDefaultParams_whenCombinedFeeIsTooHigh_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );

    IFPMM.FPMMParams memory invalidDefaultFpmmParams = defaultFpmmParamsCelo;
    invalidDefaultFpmmParams.lpFee = 100;
    invalidDefaultFpmmParams.protocolFee = 101;

    vm.expectRevert(IFPMMFactory.FeeTooHigh.selector);
    vm.prank(governanceCelo);
    factoryCelo.setDefaultParams(invalidDefaultFpmmParams);
  }

  function test_setDefaultParams_whenProtocolFeeRecipientIsZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );

    IFPMM.FPMMParams memory invalidDefaultFpmmParams = defaultFpmmParamsCelo;
    invalidDefaultFpmmParams.protocolFeeRecipient = address(0);

    vm.expectRevert(IFPMMFactory.ZeroAddress.selector);
    vm.prank(governanceCelo);
    factoryCelo.setDefaultParams(invalidDefaultFpmmParams);
  }

  function test_setDefaultParams_whenRebalanceIncentiveIsTooHigh_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );

    IFPMM.FPMMParams memory invalidDefaultFpmmParams = defaultFpmmParamsCelo;
    invalidDefaultFpmmParams.rebalanceIncentive = 101;

    vm.expectRevert(IFPMMFactory.RebalanceIncentiveTooHigh.selector);
    vm.prank(governanceCelo);
    factoryCelo.setDefaultParams(invalidDefaultFpmmParams);
  }

  function test_setDefaultParams_whenRebalanceThresholdAboveIsTooHigh_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );

    IFPMM.FPMMParams memory invalidDefaultFpmmParams = defaultFpmmParamsCelo;
    invalidDefaultFpmmParams.rebalanceThresholdAbove = 1001;

    vm.expectRevert(IFPMMFactory.RebalanceThresholdTooHigh.selector);
    vm.prank(governanceCelo);
    factoryCelo.setDefaultParams(invalidDefaultFpmmParams);
  }

  function test_setDefaultParams_whenRebalanceThresholdBelowIsTooHigh_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );

    IFPMM.FPMMParams memory invalidDefaultFpmmParams = defaultFpmmParamsCelo;
    invalidDefaultFpmmParams.rebalanceThresholdBelow = 1001;

    vm.expectRevert(IFPMMFactory.RebalanceThresholdTooHigh.selector);
    vm.prank(governanceCelo);
    factoryCelo.setDefaultParams(invalidDefaultFpmmParams);
  }

  function test_setDefaultParams_shouldSetDefaultParamsAndEmitEvent() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );

    IFPMM.FPMMParams memory newDefaultFpmmParams = IFPMM.FPMMParams({
      lpFee: 10,
      protocolFee: 20,
      protocolFeeRecipient: makeAddr("New Protocol Fee Recipient"),
      feeSetter: address(0),
      rebalanceIncentive: 30,
      rebalanceThresholdAbove: 250,
      rebalanceThresholdBelow: 250
    });

    vm.expectEmit();
    emit DefaultParamsSet(newDefaultFpmmParams);
    vm.prank(governanceCelo);
    factoryCelo.setDefaultParams(newDefaultFpmmParams);

    assertEqFPMMParams(newDefaultFpmmParams, factoryCelo.defaultParams());
  }

  function test_registerImplementation_whenCallerIsNotOwner_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("Not Owner"));
    factoryCelo.registerFPMMImplementation(address(fpmmImplementationCelo));
  }

  function test_registerImplementation_whenImplementationIsZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );
    vm.expectRevert(IFPMMFactory.ZeroAddress.selector);
    vm.prank(governanceCelo);
    factoryCelo.registerFPMMImplementation(address(0));
  }

  function test_registerImplementation_whenImplementationIsAlreadyRegistered_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );
    vm.startPrank(governanceCelo);
    factoryCelo.registerFPMMImplementation(makeAddr("Implementation2"));
    vm.expectRevert(IFPMMFactory.ImplementationAlreadyRegistered.selector);
    factoryCelo.registerFPMMImplementation(makeAddr("Implementation2"));
    vm.stopPrank();
  }

  function test_registerImplementation_whenImplementationIsNotRegistered_shouldRegisterImplementationAndEmitEvent()
    public
  {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );
    vm.prank(governanceCelo);
    vm.expectEmit();
    emit FPMMImplementationRegistered(makeAddr("Implementation2"));
    factoryCelo.registerFPMMImplementation(makeAddr("Implementation2"));
    vm.stopPrank();
  }

  function test_unregisterImplementation_whenCallerIsNotOwner_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("Not Owner"));
    factoryCelo.unregisterFPMMImplementation(address(fpmmImplementationCelo), 0);
  }

  function test_unregisterImplementation_whenImplementationIsNotRegistered_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );
    vm.expectRevert(IFPMMFactory.ImplementationNotRegistered.selector);
    vm.prank(governanceCelo);
    factoryCelo.unregisterFPMMImplementation(makeAddr("Implementation2"), 0);
  }

  function test_unregisterImplemenattion_whenIndexIsOutOfBounds_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );
    vm.expectRevert(IFPMMFactory.IndexOutOfBounds.selector);
    vm.prank(governanceCelo);
    factoryCelo.unregisterFPMMImplementation(address(fpmmImplementationCelo), 1);
  }

  function test_unregisterImplementation_whenImplementationAddressAndIndexDoNotMatch_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );
    vm.startPrank(governanceCelo);
    factoryCelo.registerFPMMImplementation(makeAddr("Implementation2"));
    vm.expectRevert(IFPMMFactory.ImplementationIndexMismatch.selector);
    factoryCelo.unregisterFPMMImplementation(makeAddr("Implementation2"), 0);
    vm.stopPrank();
  }

  function test_unregisterImplementation_shouldUnregisterImplementationAndEmitEvent() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );
    vm.prank(governanceCelo);
    vm.expectEmit();
    emit FPMMImplementationUnregistered(address(fpmmImplementationCelo));
    factoryCelo.unregisterFPMMImplementation(address(fpmmImplementationCelo), 0);

    assertEq(factoryCelo.registeredImplementations().length, 0);
    assertEq(factoryCelo.isRegisteredImplementation(address(fpmmImplementationCelo)), false);
  }

  function test_unregisterImplementation_whenMultipleImplementations_shouldUnregisterImplementationAndEmitEvent()
    public
  {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );
    vm.prank(governanceCelo);
    factoryCelo.registerFPMMImplementation(makeAddr("Implementation2"));
    vm.prank(governanceCelo);
    vm.expectEmit();
    emit FPMMImplementationUnregistered(address(fpmmImplementationCelo));
    factoryCelo.unregisterFPMMImplementation(address(fpmmImplementationCelo), 0);

    assertEq(factoryCelo.registeredImplementations().length, 1);
    assertEq(factoryCelo.isRegisteredImplementation(address(fpmmImplementationCelo)), false);
    assertEq(factoryCelo.isRegisteredImplementation(makeAddr("Implementation2")), true);
    assertEq(factoryCelo.registeredImplementations()[0], makeAddr("Implementation2"));
  }

  function test_getOrPrecomputeProxyAddress_whenContractIsNotDeployed_shouldReturnCorrectPrecomputedAddress() public {
    vm.selectFork(celoFork);
    deployCodeTo("ERC20", abi.encode("Token 0", "T0"), token0Celo);
    deployCodeTo("ERC20", abi.encode("Token 1", "T1"), token1Celo);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );

    address precomputedProxy = factoryCelo.getOrPrecomputeProxyAddress(token0Celo, token1Celo);

    vm.prank(governanceCelo);
    address deployedProxy = factoryCelo.deployFPMM(
      address(fpmmImplementationCelo),
      token0Celo,
      token1Celo,
      referenceRateFeedID,
      false
    );

    assertEq(deployedProxy, precomputedProxy);
  }
}

abstract contract FPMMFactoryTest_DeployFPMM is FPMMFactoryTest {
  address public expectedImplementation;
  address public expectedProxy;
  address public expectedOracleAdapter;
  address public expectedProxyAdmin;
  address public expectedGovernance;
  address public expectedToken0;
  address public expectedToken1;
  address public expectedReferenceRateFeedID;
  IFPMM.FPMMParams public expectedDefaultFpmmParams;

  function deploy(string memory chain) internal virtual returns (address);

  function setUp() public virtual override {
    super.setUp();
    vm.selectFork(celoFork);
    vm.prank(deployer);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      fpmmImplementationCeloAddress,
      defaultFpmmParamsCelo
    );
    deployCodeTo("ERC20", abi.encode("Token 0", "T0"), token0Celo);
    deployCodeTo("ERC20", abi.encode("Token 1", "T1"), token1Celo);
  }

  function test_deployFPMM_whenCallerIsNotOwner_shouldRevert() public {
    vm.prank(makeAddr("Not Owner"));
    vm.expectRevert("Ownable: caller is not the owner");
    deploy("celo");
  }

  function test_deployFPMM_whenImplementationIsNotRegistered_shouldRevert() public {
    fpmmImplementationCeloAddress = makeAddr("Not Registered Implementation");
    vm.prank(governanceCelo);
    vm.expectRevert(IFPMMFactory.ImplementationNotRegistered.selector);
    deploy("celo");
  }

  function test_deployFPMM_whenToken0OrToken1IsZeroAddress_shouldRevert() public {
    token0Celo = address(0);
    vm.prank(governanceCelo);
    vm.expectRevert(IFPMMFactory.SortTokensZeroAddress.selector);
    deploy("celo");

    token0Celo = makeAddr("Token 0 Celo");
    token1Celo = address(0);
    vm.prank(governanceCelo);
    vm.expectRevert(IFPMMFactory.SortTokensZeroAddress.selector);
    deploy("celo");
  }

  function test_deployFPMM_whenToken0AndToken1AreSame_shouldRevert() public {
    token0Celo = token1Celo;
    vm.prank(governanceCelo);
    vm.expectRevert(IFPMMFactory.IdenticalTokenAddresses.selector);
    deploy("celo");
  }

  function test_deployFPMM_whenPairAlreadyExists_shouldRevert() public {
    vm.prank(governanceCelo);
    deploy("celo");
    vm.expectRevert(IFPMMFactory.PairAlreadyExists.selector);
    vm.prank(governanceCelo);
    deploy("celo");
  }

  function test_deployFPMM_whenReferenceRateFeedIDIsZeroAddress_shouldRevert() public {
    referenceRateFeedID = address(0);
    vm.prank(governanceCelo);
    vm.expectRevert(IFPMMFactory.InvalidReferenceRateFeedID.selector);
    deploy("celo");
  }

  function testdeployFPMM_shouldUpdateAndEmit() public {
    vm.prank(governanceCelo);
    vm.expectEmit();
    emit FPMMDeployed(expectedToken0, expectedToken1, expectedProxy, expectedImplementation);
    address deployedProxy = deploy("celo");

    assertEq(deployedProxy, expectedProxy);
    assertEq(factoryCelo.getPool(expectedToken0, expectedToken1), deployedProxy);
    assertEq(factoryCelo.deployedFPMMAddresses().length, 1);
    assertEq(factoryCelo.deployedFPMMAddresses()[0], deployedProxy);

    // if not pranked, the proxy will revert
    vm.prank(expectedProxyAdmin);
    address proxyAdmin = ITransparentUpgradeableProxy(deployedProxy).admin();
    assertEq(proxyAdmin, expectedProxyAdmin);

    FPMM fpmm = FPMM(deployedProxy);

    // test that the proxy is initialized correctly
    assertEq(fpmm.owner(), expectedGovernance);
    assertEq(fpmm.token0(), expectedToken0);
    assertEq(fpmm.token1(), expectedToken1);
    assertEq(fpmm.referenceRateFeedID(), expectedReferenceRateFeedID);
    assertEq(address(fpmm.oracleAdapter()), expectedOracleAdapter);
    assertEq(fpmm.lpFee(), expectedDefaultFpmmParams.lpFee);
    assertEq(fpmm.protocolFee(), expectedDefaultFpmmParams.protocolFee);
    assertEq(fpmm.protocolFeeRecipient(), expectedDefaultFpmmParams.protocolFeeRecipient);
    assertEq(fpmm.rebalanceIncentive(), expectedDefaultFpmmParams.rebalanceIncentive);
    assertEq(fpmm.rebalanceThresholdAbove(), expectedDefaultFpmmParams.rebalanceThresholdAbove);
    assertEq(fpmm.rebalanceThresholdBelow(), expectedDefaultFpmmParams.rebalanceThresholdBelow);
  }

  function test_deployFPMM_shouldRevertForSamePairInDifferentOrder() public {
    vm.prank(governanceCelo);
    deploy("celo");
    address[] memory deployedFPMMAddresses = factoryCelo.deployedFPMMAddresses();
    assertEq(deployedFPMMAddresses.length, 1);

    // deploy second pair with switched token0,token1
    token0Celo = expectedToken1;
    token1Celo = expectedToken0;
    vm.prank(governanceCelo);
    vm.expectRevert(IFPMMFactory.PairAlreadyExists.selector);
    deploy("celo");
  }

  function test_deployFPMM_shouldDeploySameFPMMToSameAddressOnDifferentChains() public {
    vm.selectFork(celoFork);
    vm.prank(governanceCelo);
    address celoFPMMProxy = deploy("celo");
    assertEq(celoFPMMProxy, factoryCelo.getPool(token0Celo, token1Celo));

    vm.selectFork(opFork);
    vm.prank(deployer);
    factoryOp = new FPMMFactory(false);
    factoryOp.initialize(oracleAdapterOp, proxyAdminOp, governanceOp, fpmmImplementationOpAddress, defaultFpmmParamsOp);
    deployCodeTo("ERC20", abi.encode("Token 0", "T0"), token0Op);
    deployCodeTo("ERC20", abi.encode("Token 1", "T1"), token1Op);

    assertEq(address(factoryOp), address(factoryCelo));

    vm.prank(governanceOp);
    address opFPMMProxy = deploy("op");
    assertEq(opFPMMProxy, factoryOp.getPool(token0Op, token1Op));

    assertEq(opFPMMProxy, celoFPMMProxy);
  }
}

contract FPMMFactoryTest_DeployFPMMStandard is FPMMFactoryTest_DeployFPMM {
  function setUp() public override {
    super.setUp();
    expectedImplementation = fpmmImplementationCeloAddress;
    expectedProxy = factoryCelo.getOrPrecomputeProxyAddress(token0Celo, token1Celo);
    expectedToken0 = token0Celo;
    expectedToken1 = token1Celo;
    expectedOracleAdapter = oracleAdapterCelo;
    expectedProxyAdmin = proxyAdminCelo;
    expectedGovernance = governanceCelo;
    expectedReferenceRateFeedID = referenceRateFeedID;
    expectedDefaultFpmmParams = defaultFpmmParamsCelo;
  }

  function deploy(string memory chain) internal override returns (address) {
    if (keccak256(abi.encode(chain)) == keccak256(abi.encode("celo"))) {
      return factoryCelo.deployFPMM(fpmmImplementationCeloAddress, token0Celo, token1Celo, referenceRateFeedID, false);
    } else if (keccak256(abi.encode(chain)) == keccak256(abi.encode("op"))) {
      return factoryOp.deployFPMM(fpmmImplementationOpAddress, token0Op, token1Op, referenceRateFeedID, false);
    } else {
      return address(0);
    }
  }
}

contract FPMMFactoryTest_DeployFPMMCustom is FPMMFactoryTest_DeployFPMM {
  function setUp() public override {
    super.setUp();
    expectedImplementation = fpmmImplementationCeloAddress;
    expectedProxy = factoryCelo.getOrPrecomputeProxyAddress(token0Celo, token1Celo);
    expectedToken0 = token0Celo;
    expectedToken1 = token1Celo;
    expectedOracleAdapter = makeAddr("Custom OracleAdapter");
    expectedProxyAdmin = makeAddr("Custom Proxy Admin");
    expectedGovernance = makeAddr("Custom Governance");
    expectedReferenceRateFeedID = referenceRateFeedID;

    expectedDefaultFpmmParams = IFPMM.FPMMParams({
      lpFee: 39,
      protocolFee: 22,
      protocolFeeRecipient: makeAddr("Custom Protocol Fee Recipient"),
      feeSetter: address(0),
      rebalanceIncentive: 30,
      rebalanceThresholdAbove: 123,
      rebalanceThresholdBelow: 456
    });
  }

  function deploy(string memory chain) internal override returns (address) {
    if (keccak256(abi.encode(chain)) == keccak256(abi.encode("celo"))) {
      return
        factoryCelo.deployFPMM(
          fpmmImplementationCeloAddress,
          expectedOracleAdapter,
          expectedProxyAdmin,
          expectedGovernance,
          token0Celo,
          token1Celo,
          referenceRateFeedID,
          false,
          expectedDefaultFpmmParams
        );
    } else if (keccak256(abi.encode(chain)) == keccak256(abi.encode("op"))) {
      return
        factoryOp.deployFPMM(
          fpmmImplementationOpAddress,
          expectedOracleAdapter,
          expectedProxyAdmin,
          expectedGovernance,
          token0Op,
          token1Op,
          referenceRateFeedID,
          false,
          expectedDefaultFpmmParams
        );
    } else {
      return address(0);
    }
  }

  function test_deployFPMM_whenCustomOracleAdapterIsZeroAddress_shouldRevert() public {
    expectedOracleAdapter = address(0);
    vm.prank(governanceCelo);
    vm.expectRevert(IFPMMFactory.InvalidOracleAdapter.selector);
    deploy("celo");
  }

  function test_deployFPMM_whenCustomProxyAdminIsZeroAddress_shouldRevert() public {
    expectedProxyAdmin = address(0);
    vm.prank(governanceCelo);
    vm.expectRevert(IFPMMFactory.InvalidProxyAdmin.selector);
    deploy("celo");
  }

  function test_deployFPMM_whenCustomGovernanceIsZeroAddress_shouldRevert() public {
    expectedGovernance = address(0);
    vm.prank(governanceCelo);
    vm.expectRevert(IFPMMFactory.InvalidOwner.selector);
    deploy("celo");
  }
}

contract FPMMFactoryTest_SortTokens is FPMMFactoryTest {
  function setUp() public override {
    super.setUp();
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      oracleAdapterCelo,
      proxyAdminCelo,
      governanceCelo,
      address(fpmmImplementationCelo),
      defaultFpmmParamsCelo
    );
  }

  function testSortTokens_whenTokenAIsLessThanTokenB_shouldReturnTokensInOrder() public view {
    address tokenA = address(0x1000);
    address tokenB = address(0x2000);

    (address token0, address token1) = factoryCelo.sortTokens(tokenA, tokenB);

    assertEq(token0, tokenA);
    assertEq(token1, tokenB);
  }

  function testSortTokens_whenTokenBIsLessThanTokenA_shouldReturnTokensInOrder() public view {
    address tokenA = address(0x2000);
    address tokenB = address(0x1000);

    (address token0, address token1) = factoryCelo.sortTokens(tokenA, tokenB);

    assertEq(token0, tokenB);
    assertEq(token1, tokenA);
  }

  function testSortTokens_whenTokensAreEqual_shouldRevert() public {
    address tokenA = address(0x1000);
    address tokenB = address(0x1000);

    vm.expectRevert(IFPMMFactory.IdenticalTokenAddresses.selector);
    factoryCelo.sortTokens(tokenA, tokenB);
  }

  function testSortTokens_whenTokenAIsZeroAddress_shouldRevert() public {
    address tokenA = address(0);
    address tokenB = address(0x1000);

    vm.expectRevert(IFPMMFactory.SortTokensZeroAddress.selector);
    factoryCelo.sortTokens(tokenA, tokenB);
  }

  function testSortTokens_whenTokenBIsZeroAddress_shouldRevert() public {
    address tokenA = address(0x1000);
    address tokenB = address(0);

    vm.expectRevert(IFPMMFactory.SortTokensZeroAddress.selector);
    factoryCelo.sortTokens(tokenA, tokenB);
  }

  function testSortTokens_integrationWithDeployFPMM_shouldUseSortedTokens() public {
    // Deploy tokens with specific addresses
    address lowerToken = address(0x1000);
    address higherToken = address(0x2000);

    deployCodeTo("ERC20", abi.encode("Lower Token", "LOW"), lowerToken);
    deployCodeTo("ERC20", abi.encode("Higher Token", "HIGH"), higherToken);

    // Deploy with tokens in reverse order
    vm.prank(governanceCelo);
    address deployedProxy = factoryCelo.deployFPMM(
      address(fpmmImplementationCelo),
      higherToken, // token0 (higher address)
      lowerToken, // token1 (lower address)
      referenceRateFeedID,
      false
    );

    // Verify the FPMM was deployed with sorted tokens
    FPMM fpmm = FPMM(deployedProxy);
    assertEq(fpmm.token0(), lowerToken); // Should be sorted to lower address
    assertEq(fpmm.token1(), higherToken); // Should be sorted to higher address

    // Verify the factory mapping uses sorted tokens
    assertEq(factoryCelo.getPool(lowerToken, higherToken), deployedProxy);
    assertEq(factoryCelo.getPool(higherToken, lowerToken), deployedProxy); // Should not exist
  }

  function testSortTokens_integrationWithGetOrPrecomputeProxyAddress_shouldUseSortedTokens() public {
    address lowerToken = address(0x1000);
    address higherToken = address(0x2000);

    deployCodeTo("ERC20", abi.encode("Lower Token", "LOW"), lowerToken);
    deployCodeTo("ERC20", abi.encode("Higher Token", "HIGH"), higherToken);

    // Get precomputed address with tokens in reverse order
    address precomputedAddress = factoryCelo.getOrPrecomputeProxyAddress(higherToken, lowerToken);

    // Deploy with tokens in correct order
    vm.prank(governanceCelo);
    address deployedProxy = factoryCelo.deployFPMM(
      address(fpmmImplementationCelo),
      lowerToken,
      higherToken,
      referenceRateFeedID,
      false
    );

    // Verify both addresses match
    assertEq(deployedProxy, precomputedAddress);

    // Verify the factory mapping uses sorted tokens
    assertEq(factoryCelo.getPool(lowerToken, higherToken), deployedProxy);
  }

  function testSortTokens_deploymentMappingConsistency_shouldUseSortedTokensInMapping() public {
    address lowerToken = address(0x1000);
    address higherToken = address(0x2000);

    deployCodeTo("ERC20", abi.encode("Lower Token", "LOW"), lowerToken);
    deployCodeTo("ERC20", abi.encode("Higher Token", "HIGH"), higherToken);

    // Deploy with tokens in reverse order
    vm.prank(governanceCelo);
    address deployedProxy = factoryCelo.deployFPMM(
      address(fpmmImplementationCelo),
      higherToken, // token0 (higher address)
      lowerToken, // token1 (lower address)
      referenceRateFeedID,
      false
    );

    assertEq(factoryCelo.getPool(lowerToken, higherToken), deployedProxy);
    assertEq(factoryCelo.getPool(higherToken, lowerToken), deployedProxy);

    // Verify deployedFPMMAddresses contains the deployed proxy
    address[] memory deployedAddresses = factoryCelo.deployedFPMMAddresses();
    assertEq(deployedAddresses.length, 1);
    assertEq(deployedAddresses[0], deployedProxy);
  }

  function testSortTokens_multipleDeploymentsWithDifferentOrders_shouldMaintainConsistency() public {
    address tokenA = address(0x1000);
    address tokenB = address(0x2000);
    address tokenC = address(0x3000);

    deployCodeTo("ERC20", abi.encode("Token A", "TKA"), tokenA);
    deployCodeTo("ERC20", abi.encode("Token B", "TKB"), tokenB);
    deployCodeTo("ERC20", abi.encode("Token C", "TKC"), tokenC);

    // Deploy pair A-B with A first
    vm.prank(governanceCelo);
    address proxyAB1 = factoryCelo.deployFPMM(
      address(fpmmImplementationCelo),
      tokenA,
      tokenB,
      referenceRateFeedID,
      false
    );

    // Deploy pair B-C with B first
    vm.prank(governanceCelo);
    address proxyBC1 = factoryCelo.deployFPMM(
      address(fpmmImplementationCelo),
      tokenB,
      tokenC,
      referenceRateFeedID,
      false
    );

    // Verify mappings use sorted tokens
    assertEq(factoryCelo.getPool(tokenA, tokenB), proxyAB1);
    assertEq(factoryCelo.getPool(tokenB, tokenC), proxyBC1);

    // Verify reverse mappings exist
    assertEq(factoryCelo.getPool(tokenB, tokenA), proxyAB1);
    assertEq(factoryCelo.getPool(tokenC, tokenB), proxyBC1);

    // Verify deployed addresses list
    address[] memory deployedAddresses = factoryCelo.deployedFPMMAddresses();
    assertEq(deployedAddresses.length, 2);
    assertEq(deployedAddresses[0], proxyAB1);
    assertEq(deployedAddresses[1], proxyBC1);
  }

  function testSortTokens_getOrPrecomputeProxyAddress_shouldReturnSameAddressForDifferentOrders() public {
    address lowerToken = address(0x1000);
    address higherToken = address(0x2000);

    deployCodeTo("ERC20", abi.encode("Lower Token", "LOW"), lowerToken);
    deployCodeTo("ERC20", abi.encode("Higher Token", "HIGH"), higherToken);

    // Get precomputed addresses with different token orders
    address precomputedAddress1 = factoryCelo.getOrPrecomputeProxyAddress(lowerToken, higherToken);
    address precomputedAddress2 = factoryCelo.getOrPrecomputeProxyAddress(higherToken, lowerToken);

    // Both should return the same address
    assertEq(precomputedAddress1, precomputedAddress2);

    // Deploy the actual contract
    vm.prank(governanceCelo);
    address deployedProxy = factoryCelo.deployFPMM(
      address(fpmmImplementationCelo),
      higherToken, // Deploy with reverse order
      lowerToken,
      referenceRateFeedID,
      false
    );

    // Verify the deployed address matches both precomputed addresses
    assertEq(deployedProxy, precomputedAddress1);
    assertEq(deployedProxy, precomputedAddress2);
  }
}
