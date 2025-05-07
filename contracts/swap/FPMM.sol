// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { IFPMM } from "../interfaces/IFPMM.sol";
import { ERC20Upgradeable } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { ReentrancyGuard } from "openzeppelin-contracts-next/contracts/security/ReentrancyGuard.sol";
import { Math } from "openzeppelin-contracts-next/contracts/utils/math/Math.sol";
import { SafeERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20MintableBurnable as IERC20 } from "contracts/common/IERC20MintableBurnable.sol";
import { ISortedOracles } from "../interfaces/ISortedOracles.sol";
import { IFPMMCallee } from "../interfaces/IFPMMCallee.sol";
import "forge-std/console.sol";
contract FPMM is IFPMM, ReentrancyGuard, ERC20Upgradeable, OwnableUpgradeable {
  using SafeERC20 for IERC20;

  uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

  address public token0;
  address public token1;
  uint256 public decimals0;
  uint256 public decimals1;

  uint256 public reserve0;
  uint256 public reserve1;
  uint256 public blockTimestampLast;

  ISortedOracles public sortedOracles;
  address public referenceRateFeedID;

  // Fee in basis points
  uint256 public protocolFee;

  // Slippage allowed for rebalance in basis points
  uint256 public rebalanceIncentivePercentage;

  // Threshold for rebalance in basis points
  uint256 public rebalanceThreshold;

  // Mapping to track trusted contracts that can use the rebalance function
  mapping(address => bool) public liquidityStrategy;

  constructor(bool disable) {
    if (disable) {
      _disableInitializers();
    }
  }

  function initialize(address _token0, address _token1, address _sortedOracles) external initializer {
    (token0, token1) = (_token0, _token1);

    string memory symbol0 = ERC20Upgradeable(_token0).symbol();
    string memory symbol1 = ERC20Upgradeable(_token1).symbol();

    string memory name_ = string(abi.encodePacked("Mento Fixed Price MM - ", symbol0, "/", symbol1));
    string memory symbol_ = string(abi.encodePacked("FPMM-", symbol0, "/", symbol1));

    __ERC20_init(name_, symbol_);
    __Ownable_init();

    decimals0 = 10 ** ERC20Upgradeable(_token0).decimals();
    decimals1 = 10 ** ERC20Upgradeable(_token1).decimals();

    protocolFee = 30; // 0.3% fee (30 basis points)
    rebalanceIncentivePercentage = 10; // Default 0.1% slippage tolerance (10 basis points)
    rebalanceThreshold = 500; // Default 1% rebalance threshold (100 basis points)

    setSortedOracles(_sortedOracles);
  }

  function metadata()
    external
    view
    returns (uint256 dec0, uint256 dec1, uint256 r0, uint256 r1, address t0, address t1)
  {
    return (decimals0, decimals1, reserve0, reserve1, token0, token1);
  }

  function tokens() external view returns (address, address) {
    return (token0, token1);
  }

  function getReserves() public view returns (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast) {
    _reserve0 = reserve0;
    _reserve1 = reserve1;
    _blockTimestampLast = blockTimestampLast;
  }

  function totalValueInToken1(
    uint256 amount0,
    uint256 amount1,
    uint256 rateNumerator,
    uint256 rateDenominator
  ) public view returns (uint256) {
    uint256 token0ValueInToken1 = convertWithRate(amount0, decimals0, decimals1, rateNumerator, rateDenominator);
    return token0ValueInToken1 + amount1;
  }

  function getPrices()
    public
    view
    returns (uint256 oraclePrice, uint256 reservePrice, uint256 _decimals0, uint256 _decimals1)
  {
    require(referenceRateFeedID != address(0), "FPMM: REFERENCE_RATE_NOT_SET");
    require(reserve0 > 0 && reserve1 > 0, "FPMM: RESERVES_EMPTY");

    _decimals0 = decimals0;
    _decimals1 = decimals1;

    (uint256 rateNumerator, uint256 rateDenominator) = sortedOracles.medianRate(referenceRateFeedID);

    oraclePrice = (rateNumerator * 1e18) / (rateDenominator);
    reservePrice = (reserve1 * _decimals0 * 1e18) / (reserve0 * _decimals1);
  }

  function getAmountOut(uint256 amountIn, address tokenIn) public view returns (uint256 amountOut) {
    require(tokenIn == token0 || tokenIn == token1, "FPMM: INVALID_TOKEN");

    if (amountIn == 0) return 0;

    (uint256 rateNumerator, uint256 rateDenominator) = sortedOracles.medianRate(referenceRateFeedID);

    uint256 amountInAfterFee = amountIn - ((amountIn * protocolFee) / 10000);

    if (tokenIn == token0) {
      return convertWithRate(amountInAfterFee, decimals0, decimals1, rateNumerator, rateDenominator);
    } else {
      return convertWithRate(amountInAfterFee, decimals1, decimals0, rateDenominator, rateNumerator);
    }
  }

  function setProtocolFee(uint256 _protocolFee) external onlyOwner {
    // not taken for rebalances
    require(_protocolFee <= 100, "FPMM: FEE_TOO_HIGH"); // Max 2 3
    protocolFee = _protocolFee;
  }

  function setRebalanceIncentivePercentage(uint256 _rebalanceIncentivePercentage) external onlyOwner {
    // for cdp it is going to be positive but for reserve liq strategy it is going to be 0
    require(_rebalanceIncentivePercentage <= 100, "FPMM: REBALANCE_INCENTIVE_TOO_HIGH"); // Max 1%
    rebalanceIncentivePercentage = _rebalanceIncentivePercentage;
  }

  function setRebalanceThreshold(uint256 _rebalanceThreshold) external onlyOwner {
    // 5-10 %
    require(_rebalanceThreshold <= 1000, "FPMM: REBALANCE_THRESHOLD_TOO_HIGH"); // Max 10%
    rebalanceThreshold = _rebalanceThreshold;
  }

  function setLiquidityStrategy(address strategy, bool state) external onlyOwner {
    liquidityStrategy[strategy] = state;
  }

  // first version will use 1-1 pricing together with the circuit breaker
  function setSortedOracles(address _sortedOracles) public onlyOwner {
    require(_sortedOracles != address(0), "SortedOracles address must be set");
    sortedOracles = ISortedOracles(_sortedOracles);
  }

  function setReferenceRateFeedID(address _referenceRateFeedID) public onlyOwner {
    require(_referenceRateFeedID != address(0), "Reference rate feed ID must be set");
    referenceRateFeedID = _referenceRateFeedID;
  }

  function mint(address to) external nonReentrant returns (uint256 liquidity) {
    (uint256 _reserve0, uint256 _reserve1) = (reserve0, reserve1);

    uint256 balance0 = IERC20(token0).balanceOf(address(this));
    uint256 balance1 = IERC20(token1).balanceOf(address(this));

    uint256 amount0 = balance0 - _reserve0;
    uint256 amount1 = balance1 - _reserve1;

    uint256 _totalSupply = totalSupply();

    if (_totalSupply == 0) {
      liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
      _mint(address(1), MINIMUM_LIQUIDITY);
    } else {
      liquidity = Math.min((amount0 * _totalSupply) / _reserve0, (amount1 * _totalSupply) / _reserve1);
    }

    require(liquidity > MINIMUM_LIQUIDITY, "FPMM: INSUFFICIENT_LIQUIDITY_MINTED");
    _mint(to, liquidity);

    _update();
  }

  function burn(address to) external nonReentrant returns (uint256 amount0, uint256 amount1) {
    (address _token0, address _token1) = (token0, token1);

    uint256 balance0 = IERC20(_token0).balanceOf(address(this));
    uint256 balance1 = IERC20(_token1).balanceOf(address(this));

    uint256 liquidity = balanceOf(address(this));

    uint256 _totalSupply = totalSupply();

    amount0 = (liquidity * balance0) / _totalSupply;
    amount1 = (liquidity * balance1) / _totalSupply;

    require(amount0 > 0 && amount1 > 0, "FPMM: INSUFFICIENT_LIQUIDITY_BURNED");

    _burn(address(this), liquidity);

    IERC20(_token0).safeTransfer(to, amount0);
    IERC20(_token1).safeTransfer(to, amount1);

    _update();
  }

  function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external nonReentrant {
    require(amount0Out > 0 || amount1Out > 0, "FPMM: INSUFFICIENT_OUTPUT_AMOUNT");
    (uint256 _reserve0, uint256 _reserve1) = (reserve0, reserve1);
    require(amount0Out < _reserve0 && amount1Out < _reserve1, "FPMM: INSUFFICIENT_LIQUIDITY");
    require(to != token0 && to != token1, "FPMM: INVALID_TO_ADDRESS");

    _swap(amount0Out, amount1Out, to, data, false);
  }

  function rebalance(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external nonReentrant {
    require(liquidityStrategy[msg.sender], "FPMM: NOT_LIQUIDITY_STRATEGY");
    require(amount0Out > 0 || amount1Out > 0, "FPMM: INSUFFICIENT_OUTPUT_AMOUNT");
    (uint256 _reserve0, uint256 _reserve1) = (reserve0, reserve1);
    require(amount0Out < _reserve0 && amount1Out < _reserve1, "FPMM: INSUFFICIENT_LIQUIDITY");
    require(to != token0 && to != token1, "FPMM: INVALID_TO_ADDRESS");

    _swap(amount0Out, amount1Out, to, data, true);
  }

  function _swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data, bool isRebalance) private {
    (uint256 _reserve0, uint256 _reserve1) = (reserve0, reserve1);
    console.log("reserve0", _reserve0);
    console.log("reserve1", _reserve1);
    (uint256 rateNumerator, uint256 rateDenominator) = sortedOracles.medianRate(referenceRateFeedID);
    uint256 initialReserveValue = totalValueInToken1(_reserve0, _reserve1, rateNumerator, rateDenominator);
    uint256 initialPriceDifference = _calculatePriceDifference(_reserve0, _reserve1, rateNumerator, rateDenominator);

    if (isRebalance) {
      require(initialPriceDifference >= rebalanceThreshold, "FPMM: PRICE_DIFFERENCE_TOO_SMALL");
    }

    if (amount0Out > 0) IERC20(token0).safeTransfer(to, amount0Out);
    if (amount1Out > 0) IERC20(token1).safeTransfer(to, amount1Out);

    if (data.length > 0) IFPMMCallee(to).hook(msg.sender, amount0Out, amount1Out, data);

    uint256 balance0 = IERC20(token0).balanceOf(address(this));
    uint256 balance1 = IERC20(token1).balanceOf(address(this));

    uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
    uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
    require(amount0In > 0 || amount1In > 0, "FPMM: INSUFFICIENT_INPUT_AMOUNT");

    _update();

    uint256 newReserveValue = totalValueInToken1(reserve0, reserve1, rateNumerator, rateDenominator);
    if (isRebalance) {
      uint256 newPriceDifference = _calculatePriceDifference(reserve0, reserve1, rateNumerator, rateDenominator);

      // Ensure price difference is smaller than before
      require(newPriceDifference < initialPriceDifference, "FPMM: PRICE_DIFFERENCE_NOT_IMPROVED");
      console.log("newPriceDifference", newPriceDifference);
      console.log("initialPriceDifference", initialPriceDifference);
      console.log("rebalanceThreshold", rebalanceThreshold);
      console.log("reserve0", reserve0);
      console.log("reserve1", reserve1);
      require(newPriceDifference < rebalanceThreshold, "FPMM: POOL_NOT_REBALANCED");

      // Check for excessive value loss
      uint256 rebalanceIncentive = (initialReserveValue * rebalanceIncentivePercentage) / 10000;
      uint256 minAcceptableValue = initialReserveValue - rebalanceIncentive;
      require(newReserveValue >= minAcceptableValue, "FPMM: EXCESSIVE_VALUE_LOSS");
    } else {
      uint256 fee0 = (amount0In * protocolFee) / 10000;
      uint256 fee1 = (amount1In * protocolFee) / 10000;

      uint256 fee0InToken1 = convertWithRate(fee0, decimals0, decimals1, rateNumerator, rateDenominator);
      uint256 totalFeeInToken1 = fee0InToken1 + fee1;

      uint256 expectedReserveValue = initialReserveValue + totalFeeInToken1;
      require(newReserveValue >= expectedReserveValue, "FPMM: RESERVE_VALUE_DECREASED");
    }
  }

  function _update() private {
    reserve0 = IERC20(token0).balanceOf(address(this));
    reserve1 = IERC20(token1).balanceOf(address(this));
    blockTimestampLast = block.timestamp;
  }

  function convertWithRate(
    uint256 amount,
    uint256 fromDecimals,
    uint256 toDecimals,
    uint256 numerator,
    uint256 denominator
  ) public pure returns (uint256) {
    if (fromDecimals > toDecimals) {
      uint256 decimalAdjustment = fromDecimals / toDecimals;
      return (amount * numerator) / (denominator * decimalAdjustment);
    } else if (fromDecimals < toDecimals) {
      uint256 decimalAdjustment = toDecimals / fromDecimals;
      return (amount * numerator * decimalAdjustment) / denominator;
    } else {
      return (amount * numerator) / denominator;
    }
  }

  function _calculatePriceDifference(
    uint256 _reserve0,
    uint256 _reserve1,
    uint256 rateNumerator,
    uint256 rateDenominator
  ) internal view returns (uint256 priceDifference) {
    (uint256 oraclePrice, uint256 reservePrice, , ) = getPrices();

    if (oraclePrice > reservePrice) {
      priceDifference = ((oraclePrice - reservePrice) * 10000) / oraclePrice;
    } else {
      priceDifference = ((reservePrice - oraclePrice) * 10000) / oraclePrice;
    }
  }
}
