// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import { TransparentUpgradeableProxy } from "openzeppelin-contracts-next/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "openzeppelin-contracts-next/contracts/proxy/transparent/ProxyAdmin.sol";
import { Ownable } from "openzeppelin-contracts-next/contracts/access/Ownable.sol";

import { GoodDollarExchangeProvider } from "contracts/goodDollar/GoodDollarExchangeProvider.sol";
import { GoodDollarExpansionController } from "contracts/goodDollar/GoodDollarExpansionController.sol";
import { IRegistry } from "contracts/goodDollar/interfaces/IRegistry.sol";
import { Broker } from "contracts/swap/Broker.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";
import { ITradingLimits } from "contracts/interfaces/ITradingLimits.sol";
import { IBancorExchangeProvider } from "contracts/interfaces/IBancorExchangeProvider.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

interface IController {
  function genericCall(
    address _contract,
    bytes calldata _data,
    address _avatar,
    uint256 _value
  ) external returns (bool, bytes memory);
}

contract DeployMento is Script {
  // Deployment addresses to be populated
  ProxyAdmin public proxyAdmin;
  address public exchangeProvider = vm.envAddress("EXCHANGEPROVIDER");
  address public expansionController = vm.envAddress("EXPANSIONCONTROLLER");
  uint256 public gdSupply = vm.envUint("GOODDOLLAR_SUPPLY");
  uint256 public reserveSupply = vm.envUint("RESERVE_SUPPLY");
  uint32 public exitContribution = uint32(vm.envUint("EXIT_CONTRIBUTION"));
  uint256 public gdTargetPrice = vm.envUint("GOODDOLLAR_TARGET_PRICE");
  // given price calculate the reserve ratio
  uint32 reserveRatio = uint32((reserveSupply * 1e18 * 1e8) / (gdTargetPrice * gdSupply));

  uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
  address avatar = vm.envAddress("AVATAR");
  address cUSD = vm.envAddress("CUSD");
  address goodDollar = vm.envAddress("GOODDOLLAR");
  IController controller = IController(0x36B0273c0537D73265Ae2607a3E9Be949Bff97c8);
  string env = vm.envString("ENV");
  address signer = vm.addr(deployerPrivateKey);

  function run() public {
    vm.startBroadcast(deployerPrivateKey);

    // Get proxy-as-implementation contracts for initialization
    GoodDollarExchangeProvider exchangeProviderProxied = GoodDollarExchangeProvider(exchangeProvider);
    GoodDollarExpansionController expansionControllerProxied = GoodDollarExpansionController(expansionController);

    // bytes32 exchangeId = keccak256(abi.encodePacked(IERC20(cUSD).symbol(), IERC20(goodDollar).symbol()));

    IBancorExchangeProvider.PoolExchange memory exchange = IBancorExchangeProvider.PoolExchange({
      reserveAsset: cUSD,
      tokenAddress: goodDollar,
      tokenSupply: gdSupply,
      reserveBalance: reserveSupply,
      reserveRatio: reserveRatio,
      exitContribution: exitContribution
    });

    (bool ok, bytes memory result) = controller.genericCall(
      exchangeProvider,
      abi.encodeCall(IBancorExchangeProvider.createExchange, exchange),
      address(avatar),
      0
    );

    console.log("createExchange %s", ok);
    require(ok, "createExchange failed");
    bytes32 exchangeId = abi.decode(result, (bytes32));
    // console.logBytes32(exchangeId);
    (bool ok2, ) = controller.genericCall(
      expansionController,
      abi.encodeCall(
        GoodDollarExpansionController.setExpansionConfig,
        (exchangeId, 288617289021952, 1 days) //10% a year = ((1e18 - expansionRate)/1e18)^365=0.9 frequency 1 day
      ),
      address(avatar),
      0
    );
    console.log("setExpansionConfig %s", ok2);
    require(ok2, "setExpansionConfig failed");

    console.log("current price:", exchangeProviderProxied.currentPrice(exchangeId));
    vm.stopBroadcast();

    // Log deployed addresses
    console.log("Deployer:", signer);
    console.log("Exchange Id:");
    console.logBytes32(exchangeId);
  }
}
