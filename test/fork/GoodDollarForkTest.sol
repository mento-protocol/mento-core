// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

// Libraries
import { FixidityLib } from "celo/contracts/common/FixidityLib.sol";

// Interfaces
import { IBancorExchangeProvider } from "contracts/interfaces/IBancorExchangeProvider.sol";
import { IDistributionHelper } from "contracts/goodDollar/interfaces/IGoodProtocol.sol";
import { IGoodDollar } from "contracts/goodDollar/interfaces/IGoodProtocol.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";
import { IStableTokenV2 } from "contracts/interfaces/IStableTokenV2.sol";

// Contracts
import { BaseForkTest } from "./BaseForkTest.sol";
import { Broker } from "contracts/swap/Broker.sol";
import { GoodDollarExchangeProvider } from "contracts/goodDollar/GoodDollarExchangeProvider.sol";
import { GoodDollarExpansionController } from "contracts/goodDollar/GoodDollarExpansionController.sol";

contract GoodDollarForkTest is BaseForkTest {
  using FixidityLib for FixidityLib.Fraction;

  address constant AVATAR_ADDRESS = 0x495d133B938596C9984d462F007B676bDc57eCEC;
  address constant CUSD_ADDRESS = 0x765DE816845861e75A25fCA122bb6898B8B1282a;
  address constant GOOD_DOLLAR_ADDRESS = 0x62B8B11039FcfE5aB0C56E502b1C372A3d2a9c7A;
  address constant REGISTRY_ADDRESS = 0x000000000000000000000000000000000000ce10;

  // Addresses
  address ownerAddress;
  address brokerAddress;
  address distributionHelperAddress = makeAddr("distributionHelper");

  // Tokens
  IStableTokenV2 reserveToken;
  IGoodDollar goodDollarToken;

  // Contracts
  IReserve public goodDollarReserve;
  GoodDollarExchangeProvider goodDollarExchangeProvider;
  GoodDollarExpansionController expansionController;

  IBancorExchangeProvider.PoolExchange public poolExchange;
  bytes32 exchangeId;

  constructor(uint256 _chainId) BaseForkTest(_chainId) {}

  /* ======================================== */
  /* ================ Set Up ================ */
  /* ======================================== */

  function setUp() public override {
    super.setUp();
    // Tokens
    reserveToken = IStableTokenV2(CUSD_ADDRESS);
    goodDollarToken = IGoodDollar(GOOD_DOLLAR_ADDRESS);

    // Contracts
    goodDollarExchangeProvider = new GoodDollarExchangeProvider(false);
    expansionController = new GoodDollarExpansionController(false);
    // deployCode() hack to deploy solidity v0.5 reserve contract from a v0.8 contract
    goodDollarReserve = IReserve(deployCode("Reserve", abi.encode(true)));

    // Addresses
    ownerAddress = makeAddr("owner");
    brokerAddress = address(this.broker());

    // Initialize GoodDollarExchangeProvider
    configureReserve();
    configureTokens();
    configureBroker();
    configureGoodDollarExchangeProvider();
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

    vm.startPrank(ownerAddress);
    goodDollarReserve.initialize({
      registryAddress: REGISTRY_ADDRESS,
      _tobinTaxStalenessThreshold: 600, // deprecated
      _spendingRatioForCelo: 1000000000000000000000000,
      _frozenGold: 0,
      _frozenDays: 0,
      _assetAllocationSymbols: initialAssetAllocationSymbols,
      _assetAllocationWeights: initialAssetAllocationWeights,
      _tobinTax: tobinTax,
      _tobinTaxReserveRatio: tobinTaxReserveRatio,
      _collateralAssets: collateralAssets,
      _collateralAssetDailySpendingRatios: collateralAssetDailySpendingRatios
    });

    goodDollarReserve.addToken(address(goodDollarToken));
    goodDollarReserve.addExchangeSpender(address(this.broker()));
    vm.stopPrank();
    require(
      goodDollarReserve.isStableAsset(address(goodDollarToken)),
      "GoodDollar is not a stable token in the reserve"
    );
    require(
      goodDollarReserve.isCollateralAsset(address(reserveToken)),
      "ReserveToken is not a collateral asset in the reserve"
    );
  }

  function configureTokens() public {
    vm.startPrank(AVATAR_ADDRESS);
    goodDollarToken.addMinter(address(broker));
    goodDollarToken.addMinter(address(expansionController));
    vm.stopPrank();

    require(goodDollarToken.isMinter(address(broker)), "Broker is not a minter");
    require(goodDollarToken.isMinter(address(expansionController)), "ExpansionController is not a minter");
    deal(address(reserveToken), address(goodDollarReserve), 60_000 * 1e18);
  }

  function configureBroker() public {
    vm.prank(Broker(address(broker)).owner());
    broker.addExchangeProvider(address(goodDollarExchangeProvider), address(goodDollarReserve));

    require(
      broker.isExchangeProvider(address(goodDollarExchangeProvider)),
      "ExchangeProvider is not registered in the broker"
    );
    require(
      Broker(address(broker)).exchangeReserve(address(goodDollarExchangeProvider)) == address(goodDollarReserve),
      "Reserve is not registered in the broker"
    );
  }

  function configureGoodDollarExchangeProvider() public {
    vm.prank(ownerAddress);
    goodDollarExchangeProvider.initialize(
      brokerAddress,
      address(goodDollarReserve),
      address(expansionController),
      AVATAR_ADDRESS
    );

    poolExchange = IBancorExchangeProvider.PoolExchange({
      reserveAsset: address(reserveToken),
      tokenAddress: address(goodDollarToken),
      tokenSupply: 7_000_000_000 * 1e18,
      reserveBalance: 200_000 * 1e18,
      reserveRatio: 0.28571428 * 1e8,
      exitContribution: 0.1 * 1e8
    });

    vm.prank(AVATAR_ADDRESS);
    exchangeId = IBancorExchangeProvider(address(goodDollarExchangeProvider)).createExchange(poolExchange);
  }

  function configureExpansionController() public {
    uint64 expansionRatePerYear = uint64(1e18 * 0.1); // 10% per year
    uint32 expansionFrequency = uint32(1 days);

    vm.prank(ownerAddress);
    expansionController.initialize({
      _goodDollarExchangeProvider: address(goodDollarExchangeProvider),
      _distributionHelper: distributionHelperAddress,
      _reserve: address(goodDollarReserve),
      _avatar: AVATAR_ADDRESS
    });

    vm.prank(AVATAR_ADDRESS);
    expansionController.setExpansionConfig({
      exchangeId: exchangeId,
      expansionRate: expansionRatePerYear,
      expansionFrequency: expansionFrequency
    });
  }

  /**
   * @notice Manual deal helper because foundry's vm.deal() crashes
   * on the GoodDollar contract with "panic: assertion failed (0x01)"
   */
  function mintGoodDollar(uint256 amount, address to) public {
    vm.prank(AVATAR_ADDRESS);
    goodDollarToken.mint(to, amount);
  }

  /**
   * TODO: Do a few swaps
   * TODO: Make sure TradingLimits are enforced
   * TODO: Make sure CircuitBreaker is enforced
   */

  /* ======================================== */
  /* ================ Tests ================ */
  /* ======================================== */
  function test_init_isDeployedAndInitializedCorrectly() public view {
    assertEq(goodDollarExchangeProvider.owner(), ownerAddress);
    assertEq(goodDollarExchangeProvider.broker(), brokerAddress);
    assertEq(address(goodDollarExchangeProvider.reserve()), address(goodDollarReserve));

    IBancorExchangeProvider.PoolExchange memory _poolExchange = goodDollarExchangeProvider.getPoolExchange(exchangeId);
    assertEq(_poolExchange.reserveAsset, _poolExchange.reserveAsset);
    assertEq(_poolExchange.tokenAddress, _poolExchange.tokenAddress);
    assertEq(_poolExchange.tokenSupply, _poolExchange.tokenSupply);
    assertEq(_poolExchange.reserveBalance, _poolExchange.reserveBalance);
    assertEq(_poolExchange.reserveRatio, _poolExchange.reserveRatio);
    assertEq(_poolExchange.exitContribution, _poolExchange.exitContribution);
  }

  function test_swapIn_reserveTokenToGoodDollar() public {
    uint256 amountIn = 1000 * 1e18;

    uint256 reserveBalanceBefore = reserveToken.balanceOf(address(goodDollarReserve));
    uint256 priceBefore = IBancorExchangeProvider(address(goodDollarExchangeProvider)).currentPrice(exchangeId);
    uint256 expectedAmountOut = broker.getAmountOut(
      address(goodDollarExchangeProvider),
      exchangeId,
      address(reserveToken),
      address(goodDollarToken),
      amountIn
    );

    deal(address(reserveToken), trader, amountIn);

    vm.startPrank(trader);
    reserveToken.approve(address(broker), amountIn);
    broker.swapIn(
      address(goodDollarExchangeProvider),
      exchangeId,
      address(reserveToken),
      address(goodDollarToken),
      amountIn,
      expectedAmountOut
    );
    uint256 priceAfter = IBancorExchangeProvider(address(goodDollarExchangeProvider)).currentPrice(exchangeId);
    uint256 reserveBalanceAfter = reserveToken.balanceOf(address(goodDollarReserve));

    assertEq(expectedAmountOut, goodDollarToken.balanceOf(trader));
    assertEq(reserveBalanceBefore + amountIn, reserveBalanceAfter);
    assertTrue(priceBefore < priceAfter);
  }

  function test_swapIn_goodDollarToReserveToken() public {
    uint256 amountIn = 1000 * 1e18;

    uint256 reserveBalanceBefore = reserveToken.balanceOf(address(goodDollarReserve));
    uint256 priceBefore = IBancorExchangeProvider(address(goodDollarExchangeProvider)).currentPrice(exchangeId);
    uint256 expectedAmountOut = broker.getAmountOut(
      address(goodDollarExchangeProvider),
      exchangeId,
      address(goodDollarToken),
      address(reserveToken),
      amountIn
    );

    mintGoodDollar(amountIn, trader);

    vm.startPrank(trader);
    goodDollarToken.approve(address(broker), amountIn);
    broker.swapIn(
      address(goodDollarExchangeProvider),
      exchangeId,
      address(goodDollarToken),
      address(reserveToken),
      amountIn,
      expectedAmountOut
    );
    uint256 priceAfter = IBancorExchangeProvider(address(goodDollarExchangeProvider)).currentPrice(exchangeId);
    uint256 reserveBalanceAfter = reserveToken.balanceOf(address(goodDollarReserve));

    assertEq(expectedAmountOut, reserveToken.balanceOf(trader));
    assertEq(reserveBalanceBefore - expectedAmountOut, reserveBalanceAfter);
    assertTrue(priceAfter < priceBefore);
  }

  function test_swapOut_reserveTokenToGDollar() public {
    uint256 amountOut = 1000 * 1e18;
    uint256 reserveBalanceBefore = reserveToken.balanceOf(address(goodDollarReserve));
    uint256 priceBefore = IBancorExchangeProvider(address(goodDollarExchangeProvider)).currentPrice(exchangeId);
    uint256 expectedAmountIn = broker.getAmountIn(
      address(goodDollarExchangeProvider),
      exchangeId,
      address(reserveToken),
      address(goodDollarToken),
      amountOut
    );

    deal(address(reserveToken), trader, expectedAmountIn);

    vm.startPrank(trader);
    reserveToken.approve(address(broker), expectedAmountIn);
    broker.swapOut(
      address(goodDollarExchangeProvider),
      exchangeId,
      address(reserveToken),
      address(goodDollarToken),
      amountOut,
      expectedAmountIn
    );
    uint256 priceAfter = IBancorExchangeProvider(address(goodDollarExchangeProvider)).currentPrice(exchangeId);
    uint256 reserveBalanceAfter = reserveToken.balanceOf(address(goodDollarReserve));

    assertEq(amountOut, goodDollarToken.balanceOf(trader));
    assertEq(reserveBalanceBefore + expectedAmountIn, reserveBalanceAfter);
    assertTrue(priceBefore < priceAfter);
  }

  function test_swapOut_goodDollarToReserveToken() public {
    uint256 amountOut = 1000 * 1e18;

    uint256 reserveBalanceBefore = reserveToken.balanceOf(address(goodDollarReserve));
    uint256 priceBefore = IBancorExchangeProvider(address(goodDollarExchangeProvider)).currentPrice(exchangeId);
    uint256 expectedAmountIn = broker.getAmountIn(
      address(goodDollarExchangeProvider),
      exchangeId,
      address(goodDollarToken),
      address(reserveToken),
      amountOut
    );

    mintGoodDollar(expectedAmountIn, trader);

    vm.startPrank(trader);
    goodDollarToken.approve(address(broker), expectedAmountIn);
    broker.swapOut(
      address(goodDollarExchangeProvider),
      exchangeId,
      address(goodDollarToken),
      address(reserveToken),
      amountOut,
      expectedAmountIn
    );
    uint256 priceAfter = IBancorExchangeProvider(address(goodDollarExchangeProvider)).currentPrice(exchangeId);
    uint256 reserveBalanceAfter = reserveToken.balanceOf(address(goodDollarReserve));

    assertEq(amountOut, reserveToken.balanceOf(trader));
    assertEq(reserveBalanceBefore - amountOut, reserveBalanceAfter);
    assertTrue(priceAfter < priceBefore);
  }

  function test_mintFromExpansion() public {
    uint256 priceBefore = IBancorExchangeProvider(address(goodDollarExchangeProvider)).currentPrice(exchangeId);
    uint256 distributionHelperBalanceBefore = goodDollarToken.balanceOf(distributionHelperAddress);

    vm.mockCall(
      distributionHelperAddress,
      abi.encodeWithSelector(IDistributionHelper(distributionHelperAddress).onDistribution.selector),
      abi.encode(true)
    );

    skip(2 days + 1 seconds);

    uint256 amountMinted = expansionController.mintUBIFromExpansion(exchangeId);
    uint256 priceAfter = IBancorExchangeProvider(address(goodDollarExchangeProvider)).currentPrice(exchangeId);
    assertApproxEqAbs(priceBefore, priceAfter, 1e11);
    assertEq(goodDollarToken.balanceOf(distributionHelperAddress), amountMinted + distributionHelperBalanceBefore);
  }

  function test_mintFromInterest() public {
    uint256 priceBefore = IBancorExchangeProvider(address(goodDollarExchangeProvider)).currentPrice(exchangeId);
    address reserveInterestCollector = makeAddr("reserveInterestCollector");
    uint256 reserveInterest = 1000 * 1e18;
    deal(address(reserveToken), reserveInterestCollector, reserveInterest);

    uint256 reserveBalanceBefore = reserveToken.balanceOf(address(goodDollarReserve));
    uint256 interestCollectorBalanceBefore = reserveToken.balanceOf(reserveInterestCollector);
    uint256 distributionHelperBalanceBefore = goodDollarToken.balanceOf(distributionHelperAddress);

    vm.startPrank(reserveInterestCollector);
    reserveToken.approve(address(expansionController), reserveInterest);
    expansionController.mintUBIFromInterest(exchangeId, reserveInterest);
    vm.stopPrank();

    uint256 priceAfter = IBancorExchangeProvider(address(goodDollarExchangeProvider)).currentPrice(exchangeId);
    uint256 reserveBalanceAfter = reserveToken.balanceOf(address(goodDollarReserve));
    uint256 interestCollectorBalanceAfter = reserveToken.balanceOf(reserveInterestCollector);
    uint256 distributionHelperBalanceAfter = goodDollarToken.balanceOf(distributionHelperAddress);

    assertEq(reserveBalanceAfter, reserveBalanceBefore + reserveInterest);
    assertEq(interestCollectorBalanceAfter, interestCollectorBalanceBefore - reserveInterest);
    assertTrue(distributionHelperBalanceBefore < distributionHelperBalanceAfter);
    assertEq(priceBefore, priceAfter);
  }
}
