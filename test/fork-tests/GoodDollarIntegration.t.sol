// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Test, console2 as console } from "celo-foundry/Test.sol";

import { IGoodDollarExchangeProvider } from "contracts/goodDollar/interfaces/IGoodDollarExchangeProvider.sol";
import { IGoodDollarExpansionController } from "contracts/goodDollar/interfaces/IGoodDollarExpansionController.sol";
import { IBancorExchangeProvider } from "contracts/goodDollar/interfaces/IBancorExchangeProvider.sol";
import { IStableTokenV2 } from "contracts/interfaces/IStableTokenV2.sol";
import { IGoodDollar } from "contracts/goodDollar/interfaces/IGoodDollar.sol";
import { IBroker } from "contracts/interfaces/IBroker.sol";
import { IDistributionHelper } from "contracts/goodDollar/interfaces/IDistributionHelper.sol";
import { IRegistry } from "contracts/common/interfaces/IRegistry.sol";
import { SafeERC20 } from "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";
import { IERC20 } from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

import { Reserve } from "contracts/swap/Reserve.sol";

import { FixidityLib } from "contracts/common/FixidityLib.sol";
import { Chain } from "test/utils/Chain.sol";
import { Factory } from "test/utils/Factory.sol";
import { GetCode } from "test/utils/GetCode.sol";

contract GoodDollarIntegrationTest is Test {
  using SafeERC20 for IERC20;
  using FixidityLib for FixidityLib.Fraction;
  address public trader;
  address public interestCollector;

  address public avatar;
  address public distributionHelper;

  IBroker public broker;
  Reserve public reserve;
  IStableTokenV2 public reserveToken;
  IGoodDollar public gdToken;

  IGoodDollarExchangeProvider public exchangeProvider;
  IGoodDollarExpansionController public expansionController;

  IBancorExchangeProvider.PoolExchange public poolExchange1;
  bytes32 public exchangeId;

  address public constant REGISTRY_ADDRESS = 0x000000000000000000000000000000000000ce10;
  IRegistry public registry = IRegistry(REGISTRY_ADDRESS);
  address public constant deployer = address(0x31337);
  Factory public factory;

  function setUp() public {
    Chain.fork(42220);
    vm.allowCheatcodes(deployer);
    address _factory = address(new Factory());
    vm.etch(deployer, GetCode.at(_factory));
    factory = Factory(deployer);

    reserve = new Reserve(true);
    gdToken = IGoodDollar(0x62B8B11039FcfE5aB0C56E502b1C372A3d2a9c7A);
    reserveToken = IStableTokenV2(0x765DE816845861e75A25fCA122bb6898B8B1282a);
    broker = IBroker(factory.createContract("BrokerV2", abi.encode(true)));
    exchangeProvider = IGoodDollarExchangeProvider(
      factory.createContract("GoodDollarExchangeProvider", abi.encode(false))
    );
    expansionController = IGoodDollarExpansionController(
      factory.createContract("GoodDollarExpansionController", abi.encode(false))
    );

    avatar = actor("avatar");
    distributionHelper = actor("distributionHelper");
    trader = actor("trader");

    configureReserve();
    configureTokens();
    configureBroker();
    configureExchangeProvider();
    configureExpansionController();
  }

  function configureReserve() public {
    bytes32[] memory initialAssetAllocationSymbols = new bytes32[](2);
    initialAssetAllocationSymbols[0] = bytes32("cGLD");
    initialAssetAllocationSymbols[1] = bytes32("cUSD");

    uint256[] memory initialAssetAllocationWeights = new uint256[](2);
    initialAssetAllocationWeights[0] = FixidityLib.newFixedFraction(1, 2).unwrap();
    initialAssetAllocationWeights[1] = FixidityLib.newFixedFraction(1, 2).unwrap();

    uint256 tobinTax = FixidityLib.newFixedFraction(5, 1000).unwrap();
    uint256 tobinTaxReserveRatio = FixidityLib.newFixedFraction(2, 1).unwrap();

    address[] memory collateralAssets = new address[](1);
    collateralAssets[0] = address(reserveToken);

    uint256[] memory collateralAssetDailySpendingRatios = new uint256[](1);
    collateralAssetDailySpendingRatios[0] = 1e24;

    reserve.initialize(
      actor("registry"),
      600, // deprecated
      1000000000000000000000000,
      0,
      0,
      initialAssetAllocationSymbols,
      initialAssetAllocationWeights,
      tobinTax,
      tobinTaxReserveRatio,
      collateralAssets,
      collateralAssetDailySpendingRatios
    );

    reserve.addToken(address(gdToken));
    reserve.addExchangeSpender(address(broker));
    require(reserve.isStableAsset(address(gdToken)), "GoodDollar is not a stable token in the reserve");
    require(reserve.isCollateralAsset(address(reserveToken)), "ReserveToken is not a collateral asset in the reserve");
  }

  function configureTokens() public {
    vm.startPrank(0x495d133B938596C9984d462F007B676bDc57eCEC);
    gdToken.addMinter(address(broker));
    gdToken.addMinter(address(expansionController));
    vm.stopPrank();
    require(gdToken.isMinter(address(broker)), "Broker is not a minter");
    require(gdToken.isMinter(address(expansionController)), "ExpansionController is not a minter");
    deal(address(reserveToken), address(reserve), 60_000 * 1e18);
  }

  function configureBroker() public {
    address[] memory exchangeProviders = new address[](1);
    address[] memory reserves = new address[](1);
    exchangeProviders[0] = address(exchangeProvider);
    reserves[0] = address(reserve);
    broker.initialize(exchangeProviders, reserves);
    require(broker.isExchangeProvider(address(exchangeProvider)), "ExchangeProvider is not registered in the broker");
    require(
      broker.exchangeReserve(address(exchangeProvider)) == address(reserve),
      "Reserve is not registered in the broker"
    );
  }

  function configureExchangeProvider() public {
    exchangeProvider.initialize(address(broker), address(reserve), address(expansionController), avatar);

    poolExchange1 = IBancorExchangeProvider.PoolExchange({
      reserveAsset: address(reserveToken),
      tokenAddress: address(gdToken),
      tokenSupply: 300_000 * 1e18,
      reserveBalance: 60_000 * 1e18,
      reserveRatio: 0.2 * 1e8,
      exitConribution: 0.01 * 1e8
    });

    exchangeId = IBancorExchangeProvider(address(exchangeProvider)).createExchange(poolExchange1);
  }

  function configureExpansionController() public {
    uint64 expansionRate = uint64(1e18 * 0.001);
    uint32 expansionFrequency = uint32(1 days);

    expansionController.initialize(address(exchangeProvider), distributionHelper, address(reserve), avatar);
    vm.prank(avatar);
    expansionController.setExpansionConfig(exchangeId, expansionRate, expansionFrequency);
  }

  function test_SwapIn_reserveTokenToGDollar() public {
    uint256 amountIn = 1000 * 1e18;

    uint256 reserveBalanceBefore = reserveToken.balanceOf(address(reserve));
    uint256 priceBefore = IBancorExchangeProvider(address(exchangeProvider)).currentPrice(exchangeId);
    uint256 expectedAmountOut = broker.getAmountOut(
      address(exchangeProvider),
      exchangeId,
      address(reserveToken),
      address(gdToken),
      amountIn
    );

    deal(address(reserveToken), trader, amountIn);

    vm.startPrank(trader);
    reserveToken.approve(address(broker), amountIn);
    broker.swapIn(
      address(exchangeProvider),
      exchangeId,
      address(reserveToken),
      address(gdToken),
      amountIn,
      expectedAmountOut
    );
    uint256 priceAfter = IBancorExchangeProvider(address(exchangeProvider)).currentPrice(exchangeId);
    uint256 reserveBalanceAfter = reserveToken.balanceOf(address(reserve));

    assertEq(expectedAmountOut, gdToken.balanceOf(trader));
    assertEq(reserveBalanceBefore + amountIn, reserveBalanceAfter);
    assertTrue(priceBefore < priceAfter);
  }

  function test_SwapIn_gDollarToReserveToken() public {
    uint256 amountIn = 1000 * 1e18;

    uint256 reserveBalanceBefore = reserveToken.balanceOf(address(reserve));
    uint256 priceBefore = IBancorExchangeProvider(address(exchangeProvider)).currentPrice(exchangeId);
    uint256 expectedAmountOut = broker.getAmountOut(
      address(exchangeProvider),
      exchangeId,
      address(gdToken),
      address(reserveToken),
      amountIn
    );

    deal(address(gdToken), trader, amountIn);

    vm.startPrank(trader);
    gdToken.approve(address(broker), amountIn);
    broker.swapIn(
      address(exchangeProvider),
      exchangeId,
      address(gdToken),
      address(reserveToken),
      amountIn,
      expectedAmountOut
    );
    uint256 priceAfter = IBancorExchangeProvider(address(exchangeProvider)).currentPrice(exchangeId);
    uint256 reserveBalanceAfter = reserveToken.balanceOf(address(reserve));

    assertEq(expectedAmountOut, reserveToken.balanceOf(trader));
    assertEq(reserveBalanceBefore - expectedAmountOut, reserveBalanceAfter);
    assertTrue(priceAfter < priceBefore);
  }

  function test_SwapOut_reserveTokenToGDollar() public {
    uint256 amountOut = 1000 * 1e18;
    uint256 reserveBalanceBefore = reserveToken.balanceOf(address(reserve));
    uint256 priceBefore = IBancorExchangeProvider(address(exchangeProvider)).currentPrice(exchangeId);
    uint256 expectedAmountIn = broker.getAmountIn(
      address(exchangeProvider),
      exchangeId,
      address(reserveToken),
      address(gdToken),
      amountOut
    );

    deal(address(reserveToken), trader, expectedAmountIn);

    vm.startPrank(trader);
    reserveToken.approve(address(broker), expectedAmountIn);
    broker.swapOut(
      address(exchangeProvider),
      exchangeId,
      address(reserveToken),
      address(gdToken),
      amountOut,
      expectedAmountIn
    );
    uint256 priceAfter = IBancorExchangeProvider(address(exchangeProvider)).currentPrice(exchangeId);
    uint256 reserveBalanceAfter = reserveToken.balanceOf(address(reserve));

    assertEq(amountOut, gdToken.balanceOf(trader));
    assertEq(reserveBalanceBefore + expectedAmountIn, reserveBalanceAfter);
    assertTrue(priceBefore < priceAfter);
  }

  function test_SwapOut_gDollarToReserveToken() public {
    uint256 amountOut = 1000 * 1e18;

    uint256 reserveBalanceBefore = reserveToken.balanceOf(address(reserve));
    uint256 priceBefore = IBancorExchangeProvider(address(exchangeProvider)).currentPrice(exchangeId);
    uint256 expectedAmountIn = broker.getAmountIn(
      address(exchangeProvider),
      exchangeId,
      address(gdToken),
      address(reserveToken),
      amountOut
    );

    deal(address(gdToken), trader, expectedAmountIn);

    vm.startPrank(trader);
    gdToken.approve(address(broker), expectedAmountIn);
    broker.swapOut(
      address(exchangeProvider),
      exchangeId,
      address(gdToken),
      address(reserveToken),
      amountOut,
      expectedAmountIn
    );
    uint256 priceAfter = IBancorExchangeProvider(address(exchangeProvider)).currentPrice(exchangeId);
    uint256 reserveBalanceAfter = reserveToken.balanceOf(address(reserve));

    assertEq(amountOut, reserveToken.balanceOf(trader));
    assertEq(reserveBalanceBefore - amountOut, reserveBalanceAfter);
    assertTrue(priceAfter < priceBefore);
  }

  function test_expansion() public {
    uint256 priceBefore = IBancorExchangeProvider(address(exchangeProvider)).currentPrice(exchangeId);
    uint256 distributionHelperBalanceBefore = gdToken.balanceOf(distributionHelper);

    vm.mockCall(
      distributionHelper,
      abi.encodeWithSelector(IDistributionHelper(distributionHelper).onDistribution.selector),
      abi.encode(true)
    );

    skip(2 days + 1 seconds);

    uint256 amountMinted = expansionController.mintUBIFromExpansion(exchangeId);
    uint256 priceAfter = IBancorExchangeProvider(address(exchangeProvider)).currentPrice(exchangeId);
    assertEq(priceBefore, priceAfter);
    assertEq(gdToken.balanceOf(distributionHelper), amountMinted + distributionHelperBalanceBefore);
  }

  function test_interest() public {
    uint256 priceBefore = IBancorExchangeProvider(address(exchangeProvider)).currentPrice(exchangeId);
    address reserveInterestCollector = actor("reserveInterestCollector");
    uint256 reserveInterest = 1000 * 1e18;
    deal(address(reserveToken), reserveInterestCollector, reserveInterest);

    uint256 reserveBalanceBefore = reserveToken.balanceOf(address(reserve));
    uint256 interestCollectorBalanceBefore = reserveToken.balanceOf(reserveInterestCollector);
    uint256 distributionHelperBalanceBefore = gdToken.balanceOf(distributionHelper);

    vm.startPrank(reserveInterestCollector);
    reserveToken.approve(address(expansionController), reserveInterest);
    expansionController.mintUBIFromInterest(exchangeId, reserveInterest);
    vm.stopPrank();

    uint256 priceAfter = IBancorExchangeProvider(address(exchangeProvider)).currentPrice(exchangeId);
    uint256 reserveBalanceAfter = reserveToken.balanceOf(address(reserve));
    uint256 interestCollectorBalanceAfter = reserveToken.balanceOf(reserveInterestCollector);
    uint256 distributionHelperBalanceAfter = gdToken.balanceOf(distributionHelper);

    assertEq(reserveBalanceAfter, reserveBalanceBefore + reserveInterest);
    assertEq(interestCollectorBalanceAfter, interestCollectorBalanceBefore - reserveInterest);
    assertTrue(distributionHelperBalanceBefore < distributionHelperBalanceAfter);
    assertEq(priceBefore, priceAfter);
  }
}
