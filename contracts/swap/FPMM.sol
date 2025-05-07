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

  address public oracle;
  // Fee in basis points
  uint256 public protocolFee; // TODO: should be moved to the factory

  ISortedOracles public sortedOracles;
  address public referenceRateFeedID;

  // Slippage allowed for rebalance (in basis points)
  uint256 public allowedSlippage;

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
    allowedSlippage = 10; // Default 0.1% slippage tolerance (10 basis points)
    rebalanceThreshold = 100; // Default 1% rebalance threshold (100 basis points)

    setSortedOracles(_sortedOracles);
  }

  function setProtocolFee(uint256 _protocolFee) external onlyOwner {
    require(_protocolFee <= 100, "FPMM: FEE_TOO_HIGH"); // Max 1%
    protocolFee = _protocolFee;
  }

  function setAllowedSlippage(uint256 _allowedSlippage) external onlyOwner {
    require(_allowedSlippage <= 100, "FPMM: SLIPPAGE_TOO_HIGH"); // Max 1%
    allowedSlippage = _allowedSlippage;
  }

  function setRebalanceThreshold(uint256 _rebalanceThreshold) external onlyOwner {
    require(_rebalanceThreshold <= 1000, "FPMM: SLIPPAGE_TOO_HIGH"); // Max 10%
    rebalanceThreshold = _rebalanceThreshold;
  }

  function setLiquidityStrategy(address strategy, bool state) external onlyOwner {
    liquidityStrategy[strategy] = state;
  }

  function setSortedOracles(address _sortedOracles) public onlyOwner {
    require(_sortedOracles != address(0), "SortedOracles address must be set");
    sortedOracles = ISortedOracles(_sortedOracles);
  }

  function setReferenceRateFeedID(address _referenceRateFeedID) public onlyOwner {
    require(_referenceRateFeedID != address(0), "Reference rate feed ID must be set");
    referenceRateFeedID = _referenceRateFeedID;
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

  function getAmountOut(uint256 amountIn, address tokenIn) public view returns (uint256 amountOut) {
    require(tokenIn == token0 || tokenIn == token1, "FPMM: INVALID_TOKEN");

    if (amountIn == 0) return 0;

    (uint256 rateNumerator, uint256 rateDenominator) = sortedOracles.medianRate(referenceRateFeedID);

    uint256 amountInAfterFee = amountIn - ((amountIn * protocolFee) / 10000);

    if (tokenIn == token0) {
      return _convertWithRate(amountInAfterFee, decimals0, decimals1, rateNumerator, rateDenominator);
    } else {
      return _convertWithRate(amountInAfterFee, decimals1, decimals0, rateDenominator, rateNumerator);
    }
  }

  function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external nonReentrant {
    require(amount0Out > 0 || amount1Out > 0, "FPMM: INSUFFICIENT_OUTPUT_AMOUNT");
    (uint256 _reserve0, uint256 _reserve1) = (reserve0, reserve1);
    require(amount0Out < _reserve0 && amount1Out < _reserve1, "FPMM: INSUFFICIENT_LIQUIDITY");
    require(to != token0 && to != token1, "FPMM: INVALID_TO_ADDRESS");

    _swap(amount0Out, amount1Out, to, data, false);
  }

  function rebalance(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external nonReentrant {
    require(liquidityStrategy[msg.sender], "FPMM: NOT_TRUSTED");
    require(amount0Out > 0 || amount1Out > 0, "FPMM: INSUFFICIENT_OUTPUT_AMOUNT");
    (uint256 _reserve0, uint256 _reserve1) = (reserve0, reserve1);
    require(amount0Out < _reserve0 && amount1Out < _reserve1, "FPMM: INSUFFICIENT_LIQUIDITY");
    require(to != token0 && to != token1, "FPMM: INVALID_TO_ADDRESS");

    _swap(amount0Out, amount1Out, to, data, true);
  }

  function _swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data, bool isRebalance) private {
    (uint256 _reserve0, uint256 _reserve1) = (reserve0, reserve1);
    (uint256 rateNumerator, uint256 rateDenominator) = sortedOracles.medianRate(referenceRateFeedID);
    uint256 initialReserveValue = totalValueInToken1(_reserve0, _reserve1, rateNumerator, rateDenominator);

    if (isRebalance) {
      uint256 priceDifference = _calculatePriceDifference(_reserve0, _reserve1, rateNumerator, rateDenominator);
      require(priceDifference >= rebalanceThreshold, "FPMM: PRICE_DIFFERENCE_TOO_SMALL");
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

    uint256 fee0InToken1 = _convertWithRate(
      (amount0In * protocolFee) / 10000, // fee on token0
      decimals0,
      decimals1,
      rateNumerator,
      rateDenominator
    );
    uint256 totalFeeInToken1 = fee0InToken1 + (amount1In * protocolFee) / 10000;

    uint256 expectedReserveValue = initialReserveValue + totalFeeInToken1;

    if (isRebalance) {
      uint256 newPriceDifference = _calculatePriceDifference(reserve0, reserve1, rateNumerator, rateDenominator);

      uint256 initialPriceDifference = _calculatePriceDifference(_reserve0, _reserve1, rateNumerator, rateDenominator);

      // Ensure price difference is smaller than before
      require(newPriceDifference < initialPriceDifference, "FPMM: PRICE_DIFFERENCE_NOT_IMPROVED");

      // Check for excessive value loss
      uint256 rebalanceIncentive = (expectedReserveValue * allowedSlippage) / 10000;
      uint256 minAcceptableValue = expectedReserveValue - rebalanceIncentive;
      require(newReserveValue >= minAcceptableValue, "FPMM: EXCESSIVE_VALUE_LOSS");
    } else {
      require(newReserveValue >= expectedReserveValue, "FPMM: RESERVE_VALUE_DECREASED");
    }
  }

  function totalValueInToken1(
    uint256 amount0,
    uint256 amount1,
    uint256 rateNumerator,
    uint256 rateDenominator
  ) public view returns (uint256) {
    uint256 token0ValueInToken1 = _convertWithRate(amount0, decimals0, decimals1, rateNumerator, rateDenominator);
    return token0ValueInToken1 + amount1;
  }

  function getPrices()
    external
    view
    returns (uint256 oraclePrice, uint256 reserveRatio, uint256 _decimals0, uint256 _decimals1)
  {
    require(referenceRateFeedID != address(0), "FPMM: REFERENCE_RATE_NOT_SET");
    require(reserve0 > 0 && reserve1 > 0, "FPMM: RESERVES_EMPTY");

    _decimals0 = decimals0;
    _decimals1 = decimals1;

    (uint256 rateNumerator, uint256 rateDenominator) = sortedOracles.medianRate(referenceRateFeedID);

    oraclePrice = (rateNumerator) / (rateDenominator);
    reserveRatio = (reserve0 * _decimals1) / (reserve1 * _decimals0);
  }

  function _update() private {
    reserve0 = IERC20(token0).balanceOf(address(this));
    reserve1 = IERC20(token1).balanceOf(address(this));
    blockTimestampLast = block.timestamp;
  }

  function _convertWithRate(
    uint256 amount,
    uint256 fromDecimals,
    uint256 toDecimals,
    uint256 numerator,
    uint256 denominator
  ) private pure returns (uint256) {
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
    uint256 oraclePrice = rateNumerator / rateDenominator;
    uint256 reserveRatio = (_reserve0 * decimals1) / (_reserve1 * decimals0);

    if (oraclePrice > reserveRatio) {
      priceDifference = ((oraclePrice - reserveRatio) * 10000) / oraclePrice;
    } else {
      priceDifference = ((reserveRatio - oraclePrice) * 10000) / oraclePrice;
    }
  }
}
