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

// import { console } from "forge-std/console.sol";

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

  constructor(bool disable) {
    if (disable) {
      _disableInitializers();
    }
  }

  function initialize(address _token0, address _token1, address _sortedOracles) external initializer {
    (token0, token1) = (_token0, _token1);

    decimals0 = 10 ** ERC20Upgradeable(_token0).decimals();
    decimals1 = 10 ** ERC20Upgradeable(_token1).decimals();

    string memory symbol0 = ERC20Upgradeable(_token0).symbol();
    string memory symbol1 = ERC20Upgradeable(_token1).symbol();

    string memory name_ = string(abi.encodePacked("Mento Fixed Price MM - ", symbol0, "/", symbol1));
    string memory symbol_ = string(abi.encodePacked("FPMM-", symbol0, "/", symbol1));

    __ERC20_init(name_, symbol_);
    __Ownable_init();

    protocolFee = 30; // 0.3% fee (30 basis points)

    setSortedOracles(_sortedOracles);
  }

  function setProtocolFee(uint256 _protocolFee) external onlyOwner {
    require(_protocolFee <= 1000, "FPMM: FEE_TOO_HIGH"); // Max 10%
    protocolFee = _protocolFee;
    emit ProtocolFeeUpdated(_protocolFee);
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
    require(amountIn > 0, "FPMM: INSUFFICIENT_INPUT_AMOUNT");
    require(tokenIn == token0 || tokenIn == token1, "FPMM: INVALID_TOKEN");

    (uint256 rateNumerator, uint256 rateDenominator) = sortedOracles.medianRate(referenceRateFeedID);

    uint256 amountInAfterFee = amountIn - ((amountIn * protocolFee) / 10000);

    if (tokenIn == token0) {
      return _convertWithRate(amountInAfterFee, decimals0, decimals1, rateNumerator, rateDenominator);
    } else {
      return _convertWithRate(amountInAfterFee, decimals1, decimals0, rateDenominator, rateNumerator);
    }
  }

  function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata) external nonReentrant {
    require(amount0Out > 0 || amount1Out > 0, "FPMM: INSUFFICIENT_OUTPUT_AMOUNT");
    (uint256 _reserve0, uint256 _reserve1) = (reserve0, reserve1);
    require(amount0Out < _reserve0 && amount1Out < _reserve1, "FPMM: INSUFFICIENT_LIQUIDITY");

    uint256 balance0 = IERC20(token0).balanceOf(address(this));
    uint256 balance1 = IERC20(token1).balanceOf(address(this));

    uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
    uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;

    require(amount0In > 0 || amount1In > 0, "FPMM: INSUFFICIENT_INPUT_AMOUNT");

    if (amount0In > 0 && amount1Out > 0) {
      uint256 amount1OutCalculated = getAmountOut(amount0In, token0);
      require(amount1Out <= amount1OutCalculated, "FPMM: INSUFFICIENT_OUTPUT_BASED_ON_ORACLE");
    } else if (amount1In > 0 && amount0Out > 0) {
      uint256 amount0OutCalculated = getAmountOut(amount1In, token1);
      require(amount0Out <= amount0OutCalculated, "FPMM: INSUFFICIENT_OUTPUT_BASED_ON_ORACLE");
    } else {
      revert("FPMM: INVALID_SWAP_DIRECTION");
    }

    if (amount0Out > 0) IERC20(token0).safeTransfer(to, amount0Out);
    if (amount1Out > 0) IERC20(token1).safeTransfer(to, amount1Out);

    _update();
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

  // Events
  event OracleUpdated(address indexed oracle);
  event ProtocolFeeUpdated(uint256 protocolFee);
  event Swap(
    address indexed sender,
    uint256 amount0In,
    uint256 amount1In,
    uint256 amount0Out,
    uint256 amount1Out,
    address indexed to
  );
}
