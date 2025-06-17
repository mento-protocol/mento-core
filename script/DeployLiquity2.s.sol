// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { StdCheats } from "forge-std/StdCheats.sol";
import { IERC20Metadata } from "openzeppelin-contracts-v4.9.5/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Strings } from "openzeppelin-contracts-v4.9.5/contracts/utils/Strings.sol";
import { IERC20 as IERC20_GOV } from "openzeppelin-contracts-v4.9.5/contracts/token/ERC20/IERC20.sol";
import { ProxyAdmin } from "openzeppelin-contracts-v4.9.5/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "openzeppelin-contracts-v4.9.5/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { ETH_GAS_COMPENSATION } from "contracts/v3/Dependencies/Constants.sol";
import { IBorrowerOperations } from "contracts/v3/Interfaces/IBorrowerOperations.sol";
import { StringFormatting } from "test/v3/Utils/StringFormatting.sol";
import { Accounts } from "test/v3/TestContracts/Accounts.sol";
import { ERC20Faucet } from "test/v3/TestContracts/ERC20Faucet.sol";
import { WETHTester } from "test/v3/TestContracts/WETHTester.sol";
import "contracts/v3/AddressesRegistry.sol";
import "contracts/v3/ActivePool.sol";
import "contracts/v3/BoldToken.sol";
import "contracts/v3/BorrowerOperations.sol";
import "contracts/v3/TroveManager.sol";
import "contracts/v3/TroveNFT.sol";
import "contracts/v3/CollSurplusPool.sol";
import "contracts/v3/DefaultPool.sol";
import "contracts/v3/GasPool.sol";
import "contracts/v3/HintHelpers.sol";
import "contracts/v3/MultiTroveGetter.sol";
import "contracts/v3/SortedTroves.sol";
import "contracts/v3/StabilityPool.sol";

import "contracts/v3/CollateralRegistry.sol";
import "contracts/v3/StableTokenV3.sol";
import "contracts/v3/Interfaces/IStableTokenV3.sol";
import "test/v3/TestContracts/PriceFeedTestnet.sol";
import "test/v3/TestContracts/MetadataDeployment.sol";
import "test/v3/Utils/Logging.sol";
import "test/v3/Utils/StringEquality.sol";
import "forge-std/console2.sol";

contract DeployLiquity2Script is StdCheats, MetadataDeployment, Logging {
  using Strings for *;
  using StringFormatting for *;
  using StringEquality for string;

  bytes32 SALT;
  address deployer;

  struct LiquityContracts {
    IAddressesRegistry addressesRegistry;
    IActivePool activePool;
    IBorrowerOperations borrowerOperations;
    ICollSurplusPool collSurplusPool;
    IDefaultPool defaultPool;
    ISortedTroves sortedTroves;
    IStabilityPool stabilityPool;
    ITroveManager troveManager;
    ITroveNFT troveNFT;
    MetadataNFT metadataNFT;
    IPriceFeed priceFeed;
    GasPool gasPool;
    IInterestRouter interestRouter;
    IERC20Metadata collToken;
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
    uint256 SCR;
    uint256 BCR;
    uint256 LIQUIDATION_PENALTY_SP;
    uint256 LIQUIDATION_PENALTY_REDISTRIBUTION;
  }

  struct DeploymentVars {
    uint256 numCollaterals;
    IERC20Metadata[] collaterals;
    IAddressesRegistry[] addressesRegistries;
    ITroveManager[] troveManagers;
    LiquityContracts contracts;
    bytes bytecode;
    address boldTokenAddress;
    uint256 i;
  }

  struct DemoTroveParams {
    uint256 collIndex;
    uint256 owner;
    uint256 ownerIndex;
    uint256 coll;
    uint256 debt;
    uint256 annualInterestRate;
  }

  struct DeploymentResult {
    LiquityContracts contracts;
    ICollateralRegistry collateralRegistry;
    HintHelpers hintHelpers;
    MultiTroveGetter multiTroveGetter;
    ProxyAdmin proxyAdmin;
    IStableTokenV3 stableToken;
    address stabilityPoolImpl;
    address stableTokenV3Impl;
  }

  struct DeploymentConfig {
    address USDC_ALFAJORES_ADDRESS;
    string stableTokenName;
    string stableTokenSymbol;
    // Parameters for the TroveManager
    uint256 CCR;
    uint256 MCR;
    uint256 SCR;
    uint256 BCR;
    uint256 LIQUIDATION_PENALTY_SP;
    uint256 LIQUIDATION_PENALTY_REDISTRIBUTION;
  }

  DeploymentConfig internal CONFIG =
    DeploymentConfig({
      USDC_ALFAJORES_ADDRESS: 0x2F25deB3848C207fc8E0c34035B3Ba7fC157602B,
      stableTokenName: "mUSD Test",
      stableTokenSymbol: "mUSD",
      // TODO: reconsider these values
      CCR: 150e16,
      MCR: 110e16,
      SCR: 110e16,
      BCR: 40e16,
      LIQUIDATION_PENALTY_SP: 5e16,
      LIQUIDATION_PENALTY_REDISTRIBUTION: 10e16
    });

  function run() external {
    string memory saltStr = vm.envOr("SALT", block.timestamp.toString());
    SALT = keccak256(bytes(saltStr));

    uint256 privateKey = vm.envUint("DEPLOYER");
    deployer = vm.addr(privateKey);
    vm.startBroadcast(privateKey);

    _log("Deployer:               ", deployer.toHexString());
    _log("Deployer balance:       ", deployer.balance.decimal());
    _log("CREATE2 salt:           ", 'keccak256(bytes("', saltStr, '")) = ', uint256(SALT).toHexString());
    _log("Chain ID:               ", block.chainid.toString());

    DeploymentResult memory deployed = _deployAndConnectContracts();

    vm.stopBroadcast();

    vm.writeFile("script/deployment-manifest.json", _getManifestJson(deployed));
  }

  // See: https://solidity-by-example.org/app/create2/
  function getBytecode(bytes memory _creationCode, address _addressesRegistry) public pure returns (bytes memory) {
    return abi.encodePacked(_creationCode, abi.encode(_addressesRegistry));
  }

  function _deployAndConnectContracts() internal returns (DeploymentResult memory r) {
    _deployProxyInfrastructure(r);
    _deployAndInitializeStableToken(r);

    TroveManagerParams memory troveManagerParams = TroveManagerParams({
      CCR: CONFIG.CCR,
      MCR: CONFIG.MCR,
      SCR: CONFIG.SCR,
      BCR: CONFIG.BCR,
      LIQUIDATION_PENALTY_SP: CONFIG.LIQUIDATION_PENALTY_SP,
      LIQUIDATION_PENALTY_REDISTRIBUTION: CONFIG.LIQUIDATION_PENALTY_REDISTRIBUTION
    });

    IAddressesRegistry addressesRegistry = new AddressesRegistry(
      deployer,
      troveManagerParams.CCR,
      troveManagerParams.MCR,
      troveManagerParams.BCR,
      troveManagerParams.SCR,
      troveManagerParams.LIQUIDATION_PENALTY_SP,
      troveManagerParams.LIQUIDATION_PENALTY_REDISTRIBUTION
    );

    address troveManagerAddress = vm.computeCreate2Address(
      SALT,
      keccak256(getBytecode(type(TroveManager).creationCode, address(addressesRegistry)))
    );

    IERC20Metadata collToken = IERC20Metadata(CONFIG.USDC_ALFAJORES_ADDRESS);

    IERC20Metadata[] memory collaterals = new IERC20Metadata[](1);
    collaterals[0] = collToken;

    ITroveManager[] memory troveManagers = new ITroveManager[](1);
    troveManagers[0] = ITroveManager(troveManagerAddress);

    r.collateralRegistry = new CollateralRegistry(IBoldToken(address(r.stableToken)), collaterals, troveManagers);
    r.hintHelpers = new HintHelpers(r.collateralRegistry);
    r.multiTroveGetter = new MultiTroveGetter(r.collateralRegistry);

    IPriceFeed priceFeed = new PriceFeedTestnet();

    r.contracts = _deployAndConnectCollateralContracts(collToken, priceFeed, addressesRegistry, troveManagerAddress, r);
  }

  function _deployProxyInfrastructure(DeploymentResult memory r) internal {
    r.proxyAdmin = new ProxyAdmin{ salt: SALT }();
    r.stableTokenV3Impl = address(new StableTokenV3{ salt: SALT }(true));
    r.stabilityPoolImpl = address(new StabilityPool{ salt: SALT }(true));

    assert(
      address(r.proxyAdmin) == vm.computeCreate2Address(SALT, keccak256(bytes.concat(type(ProxyAdmin).creationCode)))
    );
    assert(
      address(r.stableTokenV3Impl) ==
        vm.computeCreate2Address(SALT, keccak256(bytes.concat(type(StableTokenV3).creationCode, abi.encode(true))))
    );
    assert(
      address(r.stabilityPoolImpl) ==
        vm.computeCreate2Address(SALT, keccak256(bytes.concat(type(StabilityPool).creationCode, abi.encode(true))))
    );
  }

  function _deployAndInitializeStableToken(DeploymentResult memory r) internal {
    r.stableToken = IStableTokenV3(
      address(new TransparentUpgradeableProxy(address(r.stableTokenV3Impl), address(r.proxyAdmin), ""))
    );

    r.stableToken.initialize(CONFIG.stableTokenName, CONFIG.stableTokenSymbol, new address[](0), new uint256[](0));
    // TODO: run initialize with correct addresses
    r.stableToken.initializeV2(address(deployer), address(deployer));
  }

  function _deployAndConnectCollateralContracts(
    IERC20Metadata _collToken,
    IPriceFeed _priceFeed,
    IAddressesRegistry _addressesRegistry,
    address _troveManagerAddress,
    DeploymentResult memory r
  ) internal returns (LiquityContracts memory contracts) {
    LiquityContractAddresses memory addresses;
    contracts.collToken = _collToken;
    contracts.addressesRegistry = _addressesRegistry;
    contracts.priceFeed = _priceFeed;
    // TODO: replace with governance timelock on mainnet
    contracts.interestRouter = IInterestRouter(0x56fD3F2bEE130e9867942D0F463a16fBE49B8d81);

    addresses.troveManager = _troveManagerAddress;

    contracts.metadataNFT = deployMetadata(SALT);
    addresses.metadataNFT = vm.computeCreate2Address(
      SALT,
      keccak256(getBytecode(type(MetadataNFT).creationCode, address(initializedFixedAssetReader)))
    );
    assert(address(contracts.metadataNFT) == addresses.metadataNFT);

    addresses.borrowerOperations = _computeCreate2Address(
      type(BorrowerOperations).creationCode,
      address(contracts.addressesRegistry)
    );
    addresses.troveNFT = _computeCreate2Address(type(TroveNFT).creationCode, address(contracts.addressesRegistry));
    addresses.activePool = _computeCreate2Address(type(ActivePool).creationCode, address(contracts.addressesRegistry));
    addresses.defaultPool = _computeCreate2Address(
      type(DefaultPool).creationCode,
      address(contracts.addressesRegistry)
    );
    addresses.gasPool = _computeCreate2Address(type(GasPool).creationCode, address(contracts.addressesRegistry));
    addresses.collSurplusPool = _computeCreate2Address(
      type(CollSurplusPool).creationCode,
      address(contracts.addressesRegistry)
    );
    addresses.sortedTroves = _computeCreate2Address(
      type(SortedTroves).creationCode,
      address(contracts.addressesRegistry)
    );

    // Deploy StabilityPool proxy
    address stabilityPool = address(
      new TransparentUpgradeableProxy(address(r.stabilityPoolImpl), address(r.proxyAdmin), "")
    );

    contracts.stabilityPool = IStabilityPool(stabilityPool);
    // Set up addresses in registry
    _setupAddressesRegistry(contracts, addresses, r);

    // Deploy core protocol contracts
    _deployProtocolContracts(contracts, addresses);

    IStabilityPool(stabilityPool).initialize(contracts.addressesRegistry);

    // Configure StableToken branches
    _configureStableToken(r, contracts);
  }

  function _setupAddressesRegistry(
    LiquityContracts memory contracts,
    LiquityContractAddresses memory addresses,
    DeploymentResult memory r
  ) internal {
    IAddressesRegistry.AddressVars memory addressVars = IAddressesRegistry.AddressVars({
      collToken: contracts.collToken,
      borrowerOperations: IBorrowerOperations(addresses.borrowerOperations),
      troveManager: ITroveManager(addresses.troveManager),
      troveNFT: ITroveNFT(addresses.troveNFT),
      metadataNFT: IMetadataNFT(addresses.metadataNFT),
      stabilityPool: contracts.stabilityPool,
      priceFeed: contracts.priceFeed,
      activePool: IActivePool(addresses.activePool),
      defaultPool: IDefaultPool(addresses.defaultPool),
      gasPoolAddress: addresses.gasPool,
      collSurplusPool: ICollSurplusPool(addresses.collSurplusPool),
      sortedTroves: ISortedTroves(addresses.sortedTroves),
      interestRouter: contracts.interestRouter,
      hintHelpers: r.hintHelpers,
      multiTroveGetter: r.multiTroveGetter,
      collateralRegistry: r.collateralRegistry,
      boldToken: IBoldToken(address(r.stableToken)),
      gasToken: IERC20Metadata(CONFIG.USDC_ALFAJORES_ADDRESS)
    });
    contracts.addressesRegistry.setAddresses(addressVars);
  }

  function _deployProtocolContracts(
    LiquityContracts memory contracts,
    LiquityContractAddresses memory addresses
  ) internal {
    contracts.borrowerOperations = new BorrowerOperations{ salt: SALT }(contracts.addressesRegistry);
    contracts.troveManager = new TroveManager{ salt: SALT }(contracts.addressesRegistry);
    contracts.troveNFT = new TroveNFT{ salt: SALT }(contracts.addressesRegistry);
    contracts.activePool = new ActivePool{ salt: SALT }(contracts.addressesRegistry);
    contracts.defaultPool = new DefaultPool{ salt: SALT }(contracts.addressesRegistry);
    contracts.gasPool = new GasPool{ salt: SALT }(contracts.addressesRegistry);
    contracts.collSurplusPool = new CollSurplusPool{ salt: SALT }(contracts.addressesRegistry);
    contracts.sortedTroves = new SortedTroves{ salt: SALT }(contracts.addressesRegistry);

    assert(address(contracts.borrowerOperations) == addresses.borrowerOperations);
    assert(address(contracts.troveManager) == addresses.troveManager);
    assert(address(contracts.troveNFT) == addresses.troveNFT);
    assert(address(contracts.activePool) == addresses.activePool);
    assert(address(contracts.defaultPool) == addresses.defaultPool);
    assert(address(contracts.gasPool) == addresses.gasPool);
    assert(address(contracts.collSurplusPool) == addresses.collSurplusPool);
    assert(address(contracts.sortedTroves) == addresses.sortedTroves);
  }

  function _computeCreate2Address(
    bytes memory creationCode,
    address _addressesRegistry
  ) internal view returns (address) {
    return vm.computeCreate2Address(SALT, keccak256(getBytecode(creationCode, _addressesRegistry)));
  }

  function _configureStableToken(DeploymentResult memory r, LiquityContracts memory contracts) internal {
    r.stableToken.setBranchAddresses(
      address(contracts.troveManager),
      address(contracts.stabilityPool),
      address(contracts.borrowerOperations),
      address(contracts.activePool)
    );

    r.stableToken.setCollateralRegistry(address(r.collateralRegistry));
  }

  function _getBranchContractsJson(LiquityContracts memory c) internal view returns (string memory) {
    return
      string.concat(
        "{",
        string.concat(
          // Avoid stack too deep by chunking concats
          string.concat(
            string.concat('"collSymbol":"', c.collToken.symbol(), '",'), // purely for human-readability
            string.concat('"collToken":"', address(c.collToken).toHexString(), '",'),
            string.concat('"addressesRegistry":"', address(c.addressesRegistry).toHexString(), '",'),
            string.concat('"activePool":"', address(c.activePool).toHexString(), '",'),
            string.concat('"borrowerOperations":"', address(c.borrowerOperations).toHexString(), '",'),
            string.concat('"collSurplusPool":"', address(c.collSurplusPool).toHexString(), '",'),
            string.concat('"defaultPool":"', address(c.defaultPool).toHexString(), '",'),
            string.concat('"sortedTroves":"', address(c.sortedTroves).toHexString(), '",')
          ),
          string.concat(
            string.concat('"stabilityPool":"', address(c.stabilityPool).toHexString(), '",'),
            string.concat('"troveManager":"', address(c.troveManager).toHexString(), '",'),
            string.concat('"troveNFT":"', address(c.troveNFT).toHexString(), '",'),
            string.concat('"metadataNFT":"', address(c.metadataNFT).toHexString(), '",'),
            string.concat('"priceFeed":"', address(c.priceFeed).toHexString(), '",'),
            string.concat('"gasPool":"', address(c.gasPool).toHexString(), '",'),
            string.concat('"interestRouter":"', address(c.interestRouter).toHexString(), '",')
          )
        ),
        "}"
      );
  }

  function _getDeploymentConstants() internal pure returns (string memory) {
    return
      string.concat(
        "{",
        string.concat(
          string.concat('"ETH_GAS_COMPENSATION":"', ETH_GAS_COMPENSATION.toString(), '",'),
          string.concat('"INTEREST_RATE_ADJ_COOLDOWN":"', INTEREST_RATE_ADJ_COOLDOWN.toString(), '",'),
          string.concat('"MAX_ANNUAL_INTEREST_RATE":"', MAX_ANNUAL_INTEREST_RATE.toString(), '",'),
          string.concat('"MIN_ANNUAL_INTEREST_RATE":"', MIN_ANNUAL_INTEREST_RATE.toString(), '",'),
          string.concat('"MIN_DEBT":"', MIN_DEBT.toString(), '",'),
          string.concat('"SP_YIELD_SPLIT":"', SP_YIELD_SPLIT.toString(), '",'),
          string.concat('"UPFRONT_INTEREST_PERIOD":"', UPFRONT_INTEREST_PERIOD.toString(), '"') // no comma
        ),
        "}"
      );
  }

  function _getManifestJson(DeploymentResult memory deployed) internal view returns (string memory) {
    string[] memory branches = new string[](1);

    branches[0] = _getBranchContractsJson(deployed.contracts);

    return
      string.concat(
        "{",
        string.concat('"constants":', _getDeploymentConstants(), ","),
        string.concat('"collateralRegistry":"', address(deployed.collateralRegistry).toHexString(), '",'),
        string.concat('"boldToken":"', address(deployed.stableToken).toHexString(), '",'),
        string.concat('"hintHelpers":"', address(deployed.hintHelpers).toHexString(), '",'),
        string.concat('"proxyAdmin":"', address(deployed.proxyAdmin).toHexString(), '",'),
        string.concat('"stableTokenV3Impl":"', address(deployed.stableTokenV3Impl).toHexString(), '",'),
        string.concat('"stabilityPoolImpl":"', address(deployed.stabilityPoolImpl).toHexString(), '",'),
        string.concat('"multiTroveGetter":"', address(deployed.multiTroveGetter).toHexString(), '",'),
        string.concat('"branches":[', branches.join(","), "]"),
        "}"
      );
  }
}
