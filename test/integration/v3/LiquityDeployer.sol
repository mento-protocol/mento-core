// SPDX-License-Identifier: MIT
// solhint-disable max-line-length, function-max-lines

pragma solidity 0.8.24;

import { AddressesRegistry } from "bold/src/AddressesRegistry.sol";
import { ActivePool } from "bold/src/ActivePool.sol";
import { IBoldToken, IERC20Metadata } from "bold/src/Interfaces/IBoldToken.sol";
import { BorrowerOperations } from "bold/src/BorrowerOperations.sol";
import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { CollSurplusPool } from "bold/src/CollSurplusPool.sol";
import { DefaultPool } from "bold/src/DefaultPool.sol";
import { GasPool } from "bold/src/GasPool.sol";
import { HintHelpers } from "bold/src/HintHelpers.sol";
import { MultiTroveGetter } from "bold/src/MultiTroveGetter.sol";
import { SortedTroves } from "bold/src/SortedTroves.sol";
import { StabilityPool } from "bold/src/StabilityPool.sol";
import { TroveManager } from "bold/src/TroveManager.sol";
import { ICollSurplusPool } from "bold/src/Interfaces/ICollSurplusPool.sol";
import { IDefaultPool } from "bold/src/Interfaces/IDefaultPool.sol";
import { IHintHelpers } from "bold/src/Interfaces/IHintHelpers.sol";
import { IMultiTroveGetter } from "bold/src/Interfaces/IMultiTroveGetter.sol";
import { ISortedTroves } from "bold/src/Interfaces/ISortedTroves.sol";
import { IStabilityPool } from "bold/src/Interfaces/IStabilityPool.sol";
import { ITroveManager } from "bold/src/Interfaces/ITroveManager.sol";
import { IBorrowerOperations } from "bold/src/Interfaces/IBorrowerOperations.sol";
import { IAddressesRegistry } from "bold/src/Interfaces/IAddressesRegistry.sol";
import { IActivePool } from "bold/src/Interfaces/IActivePool.sol";
import { ITroveNFT } from "bold/src/Interfaces/ITroveNFT.sol";
import { ISystemParams } from "bold/src/Interfaces/ISystemParams.sol";
import { ICollateralRegistry } from "bold/src/Interfaces/ICollateralRegistry.sol";
import { IMetadataNFT } from "bold/src/NFTMetadata/MetadataNFT.sol";

import { IPriceFeed } from "bold/src/Interfaces/IPriceFeed.sol";
import { TroveNFT } from "bold/src/TroveNFT.sol";
import { CollateralRegistry } from "bold/src/CollateralRegistry.sol";
import { IInterestRouter } from "bold/src/Interfaces/IInterestRouter.sol";

import { SystemParams } from "bold/src/SystemParams.sol";

import { IStableTokenV3 } from "contracts/interfaces/IStableTokenV3.sol";
import { MockFXPriceFeed } from "bold/test/TestContracts/MockFXPriceFeed.sol";
import { MockInterestRouter } from "bold/test/TestContracts/MockInterestRouter.sol";

import { TestStorage } from "./TestStorage.sol";
import "bold/src/Dependencies/Constants.sol";

contract LiquityDeployer is TestStorage {
  bytes32 constant SALT = keccak256("LiquityV2");

  struct LiquityPools {
    IDefaultPool defaultPool;
    ICollSurplusPool collSurplusPool;
    GasPool gasPool;
  }

  struct LiquityContracts {
    IAddressesRegistry addressesRegistry;
    IBorrowerOperations borrowerOperations;
    ISortedTroves sortedTroves;
    IActivePool activePool;
    IStabilityPool stabilityPool;
    ITroveManager troveManager;
    ITroveNFT troveNFT;
    IPriceFeed priceFeed;
    IInterestRouter interestRouter;
    IERC20Metadata collToken;
    LiquityPools pools;
    ISystemParams systemParams;
  }

  struct LiquityContractAddresses {
    address activePool;
    address borrowerOperations;
    address collSurplusPool;
    address defaultPool;
    address sortedTroves;
    address stabilityPool;
    address troveManager;
    address troveNFT;
    address metadataNFT;
    address priceFeed;
    address gasPool;
    address interestRouter;
  }

  struct TroveManagerParams {
    uint256 CCR;
    uint256 MCR;
    uint256 BCR;
    uint256 SCR;
    uint256 LIQUIDATION_PENALTY_SP;
    uint256 LIQUIDATION_PENALTY_REDISTRIBUTION;
  }

  struct DeploymentVarsDev {
    uint256 numCollaterals;
    IERC20Metadata[] collaterals;
    IAddressesRegistry[] addressesRegistries;
    ITroveManager[] troveManagers;
    uint256 i;
  }

  function _deployLiquity() internal {
    require($tokens.deployed, "LIQUITY_DEPLOYER: tokens not deployed");

    LiquityContracts memory contracts;
    ICollateralRegistry collateralRegistry;

    // (contracts, collateralRegistry, hintHelpers, multiTroveGetter) = deployer.deployAndConnectContracts();
    (contracts, collateralRegistry, , ) = deployAndConnectContracts(
      $tokens.debtToken,
      IERC20Metadata(address($tokens.collateralToken))
    );

    $liquity.addressesRegistry = contracts.addressesRegistry;
    $liquity.borrowerOperations = contracts.borrowerOperations;
    $liquity.sortedTroves = contracts.sortedTroves;
    $liquity.activePool = contracts.activePool;
    $liquity.stabilityPool = contracts.stabilityPool;
    $liquity.troveManager = contracts.troveManager;
    $liquity.troveNFT = contracts.troveNFT;
    $liquity.priceFeed = contracts.priceFeed;
    $liquity.interestRouter = contracts.interestRouter;
    $liquity.collToken = contracts.collToken;
    $liquity.systemParams = contracts.systemParams;

    $liquityInternalPools.defaultPool = contracts.pools.defaultPool;
    $liquityInternalPools.collSurplusPool = contracts.pools.collSurplusPool;
    $liquityInternalPools.gasPool = contracts.pools.gasPool;

    _configureDebtToken(contracts, collateralRegistry);

    $liquity.deployed = true;
  }

  // See: https://solidity-by-example.org/app/create2/
  function getBytecode(bytes memory _creationCode, address _addressesRegistry) public pure returns (bytes memory) {
    return abi.encodePacked(_creationCode, abi.encode(_addressesRegistry));
  }
  function getBytecode(
    bytes memory _creationCode,
    address _addressesRegistry,
    address _systemParams
  ) public pure returns (bytes memory) {
    return abi.encodePacked(_creationCode, abi.encode(_addressesRegistry, _systemParams));
  }
  function getBytecode(bytes memory _creationCode, bool _disable) public pure returns (bytes memory) {
    return abi.encodePacked(_creationCode, abi.encode(_disable));
  }
  function getBytecode(
    bytes memory _creationCode,
    bool _disable,
    address _systemParams
  ) public pure returns (bytes memory) {
    return abi.encodePacked(_creationCode, abi.encode(_disable, _systemParams));
  }
  function getAddress(address _deployer, bytes memory _bytecode, bytes32 _salt) public pure returns (address) {
    bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), _deployer, _salt, keccak256(_bytecode)));
    // NOTE: cast last 20 bytes of hash to address
    return address(uint160(uint256(hash)));
  }
  function deployAndConnectContracts(
    IStableTokenV3 debtToken,
    IERC20Metadata collateralToken
  )
    public
    returns (
      LiquityContracts memory contracts,
      ICollateralRegistry collateralRegistry,
      HintHelpers hintHelpers,
      MultiTroveGetter multiTroveGetter
    )
  {
    return
      deployAndConnectContracts(
        debtToken,
        collateralToken,
        TroveManagerParams({
          CCR: 150e16,
          MCR: 110e16,
          BCR: 10e16,
          SCR: 110e16,
          LIQUIDATION_PENALTY_SP: 5e16,
          LIQUIDATION_PENALTY_REDISTRIBUTION: 10e16
        })
      );
  }
  function deployAndConnectContracts(
    IStableTokenV3 debtToken,
    IERC20Metadata collateralToken,
    TroveManagerParams memory troveManagerParams
  )
    public
    returns (
      LiquityContracts memory contracts,
      ICollateralRegistry collateralRegistry,
      HintHelpers hintHelpers,
      MultiTroveGetter multiTroveGetter
    )
  {
    LiquityContracts[] memory contractsArray;
    TroveManagerParams[] memory troveManagerParamsArray = new TroveManagerParams[](1);
    troveManagerParamsArray[0] = troveManagerParams;
    (contractsArray, collateralRegistry, hintHelpers, multiTroveGetter) = deployAndConnectContractsMultiColl(
      debtToken,
      collateralToken,
      troveManagerParamsArray
    );
    contracts = contractsArray[0];
  }
  function deployAndConnectContractsMultiColl(
    IStableTokenV3 debtToken,
    IERC20Metadata collateralToken,
    TroveManagerParams[] memory troveManagerParamsArray
  )
    public
    returns (
      LiquityContracts[] memory contractsArray,
      ICollateralRegistry collateralRegistry,
      HintHelpers hintHelpers,
      MultiTroveGetter multiTroveGetter
    )
  {
    (contractsArray, collateralRegistry, hintHelpers, multiTroveGetter) = deployAndConnectContracts(
      debtToken,
      troveManagerParamsArray,
      collateralToken
    );
  }

  function deployAndConnectContracts(
    IStableTokenV3 debtToken,
    TroveManagerParams[] memory troveManagerParamsArray,
    IERC20Metadata collateralToken
  )
    public
    returns (
      LiquityContracts[] memory contractsArray,
      ICollateralRegistry collateralRegistry,
      HintHelpers hintHelpers,
      MultiTroveGetter multiTroveGetter
    )
  {
    DeploymentVarsDev memory vars;
    vars.numCollaterals = troveManagerParamsArray.length;

    contractsArray = new LiquityContracts[](vars.numCollaterals);
    vars.collaterals = new IERC20Metadata[](vars.numCollaterals);
    vars.addressesRegistries = new IAddressesRegistry[](vars.numCollaterals);
    vars.troveManagers = new ITroveManager[](vars.numCollaterals);
    ISystemParams[] memory systemParamsArray = new ISystemParams[](vars.numCollaterals);
    for (vars.i = 0; vars.i < vars.numCollaterals; vars.i++) {
      systemParamsArray[vars.i] = deploySystemParamsDev(troveManagerParamsArray[vars.i], vars.i);
    }

    vars.collaterals[0] = collateralToken;
    (IAddressesRegistry addressesRegistry, address troveManagerAddress) = _deployAddressesRegistryDev(
      systemParamsArray[0]
    );
    vars.addressesRegistries[0] = addressesRegistry;
    vars.troveManagers[0] = ITroveManager(troveManagerAddress);

    collateralRegistry = new CollateralRegistry(
      IBoldToken(address(debtToken)),
      vars.collaterals,
      vars.troveManagers,
      systemParamsArray[0]
    );
    hintHelpers = new HintHelpers(collateralRegistry, systemParamsArray[0]);
    multiTroveGetter = new MultiTroveGetter(collateralRegistry);
    contractsArray[0] = _deployAndConnectCollateralContractsDev(
      collateralToken,
      debtToken,
      collateralRegistry,
      collateralToken,
      vars.addressesRegistries[0],
      address(vars.troveManagers[0]),
      hintHelpers,
      multiTroveGetter,
      systemParamsArray[0]
    );
  }

  function _deployAddressesRegistryDev(ISystemParams _systemParams) internal returns (IAddressesRegistry, address) {
    IAddressesRegistry addressesRegistry = new AddressesRegistry(address(this));
    address troveManagerAddress = getAddress(
      address(this),
      getBytecode(type(TroveManager).creationCode, address(addressesRegistry), address(_systemParams)),
      SALT
    );
    return (addressesRegistry, troveManagerAddress);
  }

  function deploySystemParamsDev(TroveManagerParams memory params, uint256 index) public returns (ISystemParams) {
    bytes32 uniqueSalt = keccak256(abi.encodePacked(SALT, index));
    // Create parameter structs based on constants
    ISystemParams.DebtParams memory debtParams = ISystemParams.DebtParams({
      minDebt: 2000e18 // MIN_DEBT
    });
    ISystemParams.LiquidationParams memory liquidationParams = ISystemParams.LiquidationParams({
      liquidationPenaltySP: params.LIQUIDATION_PENALTY_SP,
      liquidationPenaltyRedistribution: params.LIQUIDATION_PENALTY_REDISTRIBUTION
    });
    ISystemParams.GasCompParams memory gasCompParams = ISystemParams.GasCompParams({
      collGasCompensationDivisor: 200, // COLL_GAS_COMPENSATION_DIVISOR
      collGasCompensationCap: 2 ether, // COLL_GAS_COMPENSATION_CAP
      ethGasCompensation: 0.0375 ether // ETH_GAS_COMPENSATION
    });
    ISystemParams.CollateralParams memory collateralParams = ISystemParams.CollateralParams({
      ccr: params.CCR,
      scr: params.SCR,
      mcr: params.MCR,
      bcr: params.BCR
    });
    ISystemParams.InterestParams memory interestParams = ISystemParams.InterestParams({
      minAnnualInterestRate: DECIMAL_PRECISION / 200 // MIN_ANNUAL_INTEREST_RATE (0.5%)
    });
    ISystemParams.RedemptionParams memory redemptionParams = ISystemParams.RedemptionParams({
      redemptionFeeFloor: DECIMAL_PRECISION / 200, // REDEMPTION_FEE_FLOOR (0.5%)
      initialBaseRate: DECIMAL_PRECISION, // INITIAL_BASE_RATE (100%)
      redemptionMinuteDecayFactor: 998076443575628800, // REDEMPTION_MINUTE_DECAY_FACTOR
      redemptionBeta: 1 // REDEMPTION_BETA
    });
    ISystemParams.StabilityPoolParams memory poolParams = ISystemParams.StabilityPoolParams({
      spYieldSplit: 75 * (DECIMAL_PRECISION / 100), // SP_YIELD_SPLIT (75%)
      minBoldInSP: 1e18 // MIN_BOLD_IN_SP
    });
    SystemParams systemParams = new SystemParams{ salt: uniqueSalt }(
      false,
      debtParams,
      liquidationParams,
      gasCompParams,
      collateralParams,
      interestParams,
      redemptionParams,
      poolParams
    );
    systemParams.initialize();
    return ISystemParams(systemParams);
  }

  function _deployAndConnectCollateralContractsDev(
    IERC20Metadata _collToken,
    IStableTokenV3 _debtToken,
    ICollateralRegistry _collateralRegistry,
    IERC20Metadata _gasToken,
    IAddressesRegistry _addressesRegistry,
    address _troveManagerAddress,
    IHintHelpers _hintHelpers,
    IMultiTroveGetter _multiTroveGetter,
    ISystemParams _systemParams
  ) internal returns (LiquityContracts memory contracts) {
    LiquityContractAddresses memory addresses;
    contracts.collToken = _collToken;
    contracts.systemParams = _systemParams;
    contracts.addressesRegistry = _addressesRegistry;
    contracts.priceFeed = IPriceFeed(address(new MockFXPriceFeed()));
    contracts.interestRouter = IInterestRouter(address(new MockInterestRouter()));

    // Pre-calc addresses
    addresses.borrowerOperations = getAddress(
      address(this),
      getBytecode(type(BorrowerOperations).creationCode, address(contracts.addressesRegistry), address(_systemParams)),
      SALT
    );
    addresses.troveManager = _troveManagerAddress;
    addresses.troveNFT = getAddress(
      address(this),
      getBytecode(type(TroveNFT).creationCode, address(contracts.addressesRegistry)),
      SALT
    );
    bytes32 stabilityPoolSalt = keccak256(abi.encodePacked(address(contracts.addressesRegistry)));
    addresses.stabilityPool = getAddress(
      address(this),
      getBytecode(type(StabilityPool).creationCode, bool(false), address(_systemParams)),
      stabilityPoolSalt
    );
    addresses.activePool = getAddress(
      address(this),
      getBytecode(type(ActivePool).creationCode, address(contracts.addressesRegistry), address(_systemParams)),
      SALT
    );
    addresses.defaultPool = getAddress(
      address(this),
      getBytecode(type(DefaultPool).creationCode, address(contracts.addressesRegistry)),
      SALT
    );
    addresses.gasPool = getAddress(
      address(this),
      getBytecode(type(GasPool).creationCode, address(contracts.addressesRegistry)),
      SALT
    );
    addresses.collSurplusPool = getAddress(
      address(this),
      getBytecode(type(CollSurplusPool).creationCode, address(contracts.addressesRegistry)),
      SALT
    );
    addresses.sortedTroves = getAddress(
      address(this),
      getBytecode(type(SortedTroves).creationCode, address(contracts.addressesRegistry)),
      SALT
    );
    // Deploy contracts
    IAddressesRegistry.AddressVars memory addressVars = IAddressesRegistry.AddressVars({
      borrowerOperations: IBorrowerOperations(addresses.borrowerOperations),
      troveManager: ITroveManager(addresses.troveManager),
      troveNFT: ITroveNFT(addresses.troveNFT),
      metadataNFT: IMetadataNFT(address(0)),
      stabilityPool: IStabilityPool(addresses.stabilityPool),
      priceFeed: contracts.priceFeed,
      activePool: IActivePool(addresses.activePool),
      defaultPool: IDefaultPool(addresses.defaultPool),
      gasPoolAddress: addresses.gasPool,
      collSurplusPool: ICollSurplusPool(addresses.collSurplusPool),
      sortedTroves: ISortedTroves(addresses.sortedTroves),
      interestRouter: contracts.interestRouter,
      hintHelpers: _hintHelpers,
      multiTroveGetter: _multiTroveGetter,
      collateralRegistry: _collateralRegistry,
      boldToken: IBoldToken(address(_debtToken)),
      collToken: _collToken,
      gasToken: _gasToken,
      liquidityStrategy: address(123) // TODO: add LiquidityStrategy address
    });
    contracts.addressesRegistry.setAddresses(addressVars);
    contracts.borrowerOperations = new BorrowerOperations{ salt: SALT }(contracts.addressesRegistry, _systemParams);
    contracts.troveManager = new TroveManager{ salt: SALT }(contracts.addressesRegistry, _systemParams);
    contracts.troveNFT = new TroveNFT{ salt: SALT }(contracts.addressesRegistry);
    contracts.stabilityPool = new StabilityPool{ salt: stabilityPoolSalt }(false, _systemParams);
    contracts.activePool = new ActivePool{ salt: SALT }(contracts.addressesRegistry, _systemParams);
    contracts.pools.defaultPool = new DefaultPool{ salt: SALT }(contracts.addressesRegistry);
    contracts.pools.gasPool = new GasPool{ salt: SALT }(contracts.addressesRegistry);
    contracts.pools.collSurplusPool = new CollSurplusPool{ salt: SALT }(contracts.addressesRegistry);
    contracts.sortedTroves = new SortedTroves{ salt: SALT }(contracts.addressesRegistry);
    assert(address(contracts.borrowerOperations) == addresses.borrowerOperations);
    assert(address(contracts.troveManager) == addresses.troveManager);
    assert(address(contracts.troveNFT) == addresses.troveNFT);
    assert(address(contracts.stabilityPool) == addresses.stabilityPool);
    assert(address(contracts.activePool) == addresses.activePool);
    assert(address(contracts.pools.defaultPool) == addresses.defaultPool);
    assert(address(contracts.pools.gasPool) == addresses.gasPool);
    assert(address(contracts.pools.collSurplusPool) == addresses.collSurplusPool);
    assert(address(contracts.sortedTroves) == addresses.sortedTroves);

    contracts.stabilityPool.initialize(contracts.addressesRegistry);
  }

  function _configureDebtToken(LiquityContracts memory contracts, ICollateralRegistry collateralRegistry) private {
    address stableOwner = Ownable(address($tokens.debtToken)).owner();

    vm.startPrank(stableOwner);
    IStableTokenV3(address($tokens.debtToken)).setMinter(address(contracts.borrowerOperations), true);
    IStableTokenV3(address($tokens.debtToken)).setMinter(address(contracts.activePool), true);

    IStableTokenV3(address($tokens.debtToken)).setBurner(address(collateralRegistry), true);
    IStableTokenV3(address($tokens.debtToken)).setBurner(address(contracts.borrowerOperations), true);
    IStableTokenV3(address($tokens.debtToken)).setBurner(address(contracts.troveManager), true);
    IStableTokenV3(address($tokens.debtToken)).setBurner(address(contracts.stabilityPool), true);

    IStableTokenV3(address($tokens.debtToken)).setOperator(address(contracts.stabilityPool), true);
    vm.stopPrank();
  }
}
