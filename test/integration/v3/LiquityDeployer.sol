// SPDX-License-Identifier: MIT
// solhint-disable max-line-length, function-max-lines

pragma solidity 0.8.24;

import { AddressesRegistry } from "bold/src/AddressesRegistry.sol";
import { ActivePool } from "bold/src/ActivePool.sol";
import { BoldToken } from "bold/src/BoldToken.sol";
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

uint256 constant _24_HOURS = 86400;
uint256 constant _48_HOURS = 172800;

contract LiquityDeployer is TestStorage {
  IBoldToken public _debtToken;
  IERC20Metadata public _collateralToken;

  function deploy() public returns (LiquityContractsDev memory) {
    LiquityContractsDev memory contracts;

    _debtToken = $tokens.debtToken;
    _collateralToken = IERC20Metadata(address($tokens.collateralToken));

    (contracts, , , , ) = deployAndConnectContracts(_debtToken, _collateralToken);

    return contracts;
    // return deployAndConnectContracts(_debtToken, _collateralToken);
  }

  // function test_openTrove() public {
  //   LiquityContractsDev memory contracts;
  //   ICollateralRegistry collateralRegistry;
  //   IBoldToken boldToken;
  //   HintHelpers hintHelpers;
  //   MultiTroveGetter multiTroveGetter;

  //   (contracts, collateralRegistry, boldToken, hintHelpers, multiTroveGetter) = deployAndConnectContracts(
  //     _debtToken,
  //     _collateralToken
  //   );

  //   // console.
  //   console2.log("contracts.systemParams", address(contracts.systemParams));
  //   console2.log("contracts.addressesRegistry", address(contracts.addressesRegistry));
  //   console2.log("contracts.priceFeed", address(contracts.priceFeed));
  //   console2.log("contracts.interestRouter", address(contracts.interestRouter));
  //   console2.log("contracts.borrowerOperations", address(contracts.borrowerOperations));
  //   console2.log("contracts.troveManager", address(contracts.troveManager));
  //   console2.log("contracts.troveNFT", address(contracts.troveNFT));
  //   console2.log("contracts.stabilityPool", address(contracts.stabilityPool));
  //   console2.log("contracts.activePool", address(contracts.activePool));
  //   // console2.log("contracts.defaultPool", address(contracts.defaultPool));
  //   // console2.log("contracts.gasPool", address(contracts.gasPool));
  //   // console2.log("contracts.collSurplusPool", address(contracts.collSurplusPool));
  //   console2.log("contracts.sortedTroves", address(contracts.sortedTroves));
  // console2.log("contracts.hintHelpers", address(contracts.hintHelpers));
  // console2.log("contracts.multiTroveGetter", address(contracts.multiTroveGetter));

  /*
          LiquityContractsDev memory contracts,
      ICollateralRegistry collateralRegistry,
      IBoldToken boldToken,
      HintHelpers hintHelpers,
      MultiTroveGetter multiTroveGetter,
      MockERC20 WETH // for gas compensation
      */

  // TestDeployer deployer = new TestDeployer();
  // TestDeployer.LiquityContractsDev memory contracts;
  // (contracts, collateralRegistry, boldToken, hintHelpers,, WETH) = deployer.deployAndConnectContracts();
  // (contracts, collateralRegistry, boldToken, hintHelpers, , WETH) = deployer.deployAndConnectContracts();

  // deployAndConnectContracts(_debtToken, _collateralToken);

  // _openTrove(contracts);
  // }

  // function _openTrove(LiquityContractsDev memory contracts) public {
  //   IMockFXPriceFeed feed = IMockFXPriceFeed(address(contracts.priceFeed));
  //   ITroveManager troveManager = ITroveManager(address(contracts.troveManager));

  //   feed.setPrice(2000e18);
  //   uint256 trovesCount = troveManager.getTroveIdsCount();
  //   assertEq(trovesCount, 0);

  //   address A = makeAddr("A");
  //   MockERC20(address(_collateralToken)).mint(A, 10_000e18);

  //   assertEq(MockERC20(address(_collateralToken)).balanceOf(A), 10_000e18);

  //   IBorrowerOperations borrowerOperations = IBorrowerOperations(address(contracts.borrowerOperations));
  //   ISystemParams systemParams = ISystemParams(address(contracts.systemParams));

  //   console2.log("\n");
  //   console2.log("-- trying to open trove --");

  //   vm.startPrank(A);
  //   MockERC20(address(_collateralToken)).approve(address(borrowerOperations), 10_000e18);
  //   borrowerOperations.openTrove(
  //     A,
  //     0,
  //     2e18,
  //     2000e18,
  //     0,
  //     0,
  //     systemParams.MIN_ANNUAL_INTEREST_RATE(),
  //     1000e18,
  //     address(0),
  //     address(0),
  //     address(0)
  //   );
  //   vm.stopPrank();

  //   trovesCount = troveManager.getTroveIdsCount();
  //   assertEq(trovesCount, 1);

  //   console2.log("# of troves", trovesCount);
  //   console2.log("eur.M A", MockERC20(address(_debtToken)).balanceOf(A));
  //   console2.log("gas pool balance", MockERC20(address(_collateralToken)).balanceOf(address(contracts.pools.gasPool)));

  //   assertEq(MockERC20(address(_debtToken)).balanceOf(A), 2000e18);
  // }

  bytes32 constant SALT = keccak256("LiquityV2");
  struct LiquityContractsDevPools {
    IDefaultPool defaultPool;
    ICollSurplusPool collSurplusPool;
    GasPool gasPool;
  }
  struct LiquityContractsDev {
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
    LiquityContractsDevPools pools;
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
    bytes bytecode;
    address boldTokenAddress;
    uint256 i;
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
    IBoldToken debtToken,
    IERC20Metadata collateralToken
  )
    public
    returns (
      LiquityContractsDev memory contracts,
      ICollateralRegistry collateralRegistry,
      IBoldToken boldToken,
      HintHelpers hintHelpers,
      MultiTroveGetter multiTroveGetter
    )
  {
    return
      deployAndConnectContracts(
        debtToken,
        collateralToken,
        TroveManagerParams(150e16, 110e16, 10e16, 110e16, 5e16, 10e16)
      );
  }
  function deployAndConnectContracts(
    IBoldToken debtToken,
    IERC20Metadata collateralToken,
    TroveManagerParams memory troveManagerParams
  )
    public
    returns (
      LiquityContractsDev memory contracts,
      ICollateralRegistry collateralRegistry,
      IBoldToken boldToken,
      HintHelpers hintHelpers,
      MultiTroveGetter multiTroveGetter
    )
  {
    LiquityContractsDev[] memory contractsArray;
    TroveManagerParams[] memory troveManagerParamsArray = new TroveManagerParams[](1);
    troveManagerParamsArray[0] = troveManagerParams;
    (contractsArray, collateralRegistry, boldToken, hintHelpers, multiTroveGetter) = deployAndConnectContractsMultiColl(
      debtToken,
      collateralToken,
      troveManagerParamsArray
    );
    contracts = contractsArray[0];
  }
  function deployAndConnectContractsMultiColl(
    IBoldToken debtToken,
    IERC20Metadata collateralToken,
    TroveManagerParams[] memory troveManagerParamsArray
  )
    public
    returns (
      LiquityContractsDev[] memory contractsArray,
      ICollateralRegistry collateralRegistry,
      IBoldToken boldToken, // TODO: rename to debtToken
      HintHelpers hintHelpers,
      MultiTroveGetter multiTroveGetter
    )
  {
    (contractsArray, collateralRegistry, boldToken, hintHelpers, multiTroveGetter) = deployAndConnectContracts(
      debtToken,
      troveManagerParamsArray,
      collateralToken
    );
  }

  function deployAndConnectContracts(
    IBoldToken debtToken,
    TroveManagerParams[] memory troveManagerParamsArray,
    IERC20Metadata collateralToken
  )
    public
    returns (
      LiquityContractsDev[] memory contractsArray,
      ICollateralRegistry collateralRegistry,
      IBoldToken boldToken, // TODO: rename to debtToken
      HintHelpers hintHelpers,
      MultiTroveGetter multiTroveGetter
    )
  {
    DeploymentVarsDev memory vars;
    vars.numCollaterals = troveManagerParamsArray.length;
    // Deploy Bold
    vars.bytecode = abi.encodePacked(type(BoldToken).creationCode, abi.encode(address(this)));

    vars.boldTokenAddress = address(debtToken);
    // vars.boldTokenAddress = getAddress(address(this), vars.bytecode, SALT);
    // boldToken = new BoldToken{ salt: SALT }(address(this));
    // assert(address(boldToken) == vars.boldTokenAddress);

    contractsArray = new LiquityContractsDev[](vars.numCollaterals);
    vars.collaterals = new IERC20Metadata[](vars.numCollaterals);
    vars.addressesRegistries = new IAddressesRegistry[](vars.numCollaterals);
    vars.troveManagers = new ITroveManager[](vars.numCollaterals);
    ISystemParams[] memory systemParamsArray = new ISystemParams[](vars.numCollaterals);
    for (vars.i = 0; vars.i < vars.numCollaterals; vars.i++) {
      systemParamsArray[vars.i] = deploySystemParamsDev(troveManagerParamsArray[vars.i], vars.i);
    }
    // Deploy the first branch with WETH collateral
    vars.collaterals[0] = collateralToken;
    (IAddressesRegistry addressesRegistry, address troveManagerAddress) = _deployAddressesRegistryDev(
      systemParamsArray[0]
    );
    vars.addressesRegistries[0] = addressesRegistry;
    vars.troveManagers[0] = ITroveManager(troveManagerAddress);

    collateralRegistry = new CollateralRegistry(boldToken, vars.collaterals, vars.troveManagers, systemParamsArray[0]);
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
    IBoldToken _boldToken,
    ICollateralRegistry _collateralRegistry,
    IERC20Metadata _gasToken,
    IAddressesRegistry _addressesRegistry,
    address _troveManagerAddress,
    IHintHelpers _hintHelpers,
    IMultiTroveGetter _multiTroveGetter,
    ISystemParams _systemParams
  ) internal returns (LiquityContractsDev memory contracts) {
    LiquityContractAddresses memory addresses;
    contracts.collToken = _collToken;
    contracts.systemParams = _systemParams;
    // Deploy all contracts, using testers for TM and PriceFeed
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
      boldToken: _boldToken,
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

    // TODO: remove
    // Connect contracts
    // _boldToken.setBranchAddresses(
    //   address(contracts.troveManager),
    //   address(contracts.stabilityPool),
    //   address(contracts.borrowerOperations),
    //   address(contracts.activePool)
    // );

    address stableOwner = Ownable(address(_boldToken)).owner();
    // console.log("stableOwner", stableOwner);

    vm.startPrank(stableOwner);
    IStableTokenV3(address(_boldToken)).setMinter(address(contracts.borrowerOperations), true);
    IStableTokenV3(address(_boldToken)).setMinter(address(contracts.activePool), true);

    IStableTokenV3(address(_boldToken)).setBurner(address(addressVars.collateralRegistry), true);
    IStableTokenV3(address(_boldToken)).setBurner(address(contracts.borrowerOperations), true);
    IStableTokenV3(address(_boldToken)).setBurner(address(contracts.troveManager), true);
    IStableTokenV3(address(_boldToken)).setBurner(address(contracts.stabilityPool), true);

    IStableTokenV3(address(_boldToken)).setOperator(address(contracts.stabilityPool), true);
    vm.stopPrank();
  }
}
