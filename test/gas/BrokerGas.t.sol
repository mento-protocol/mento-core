// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Test, console2 as console } from "celo-foundry/Test.sol";
import { IERC20 } from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

import { IntegrationSetup } from "../utils/IntegrationSetup.t.sol";
import { TokenHelpers } from "../utils/TokenHelpers.t.sol";

// forge test --match-contract BrokerIntegration -vvv
contract BrokerGasTest is Test, IntegrationSetup, TokenHelpers {
  address trader;

  function setUp() public {
    setUp_mcMint();

    trader = actor("trader");

    mint(cUSDToken, trader, 10**22); // Mint 10k to trader
    mint(cEURToken, trader, 10**22); // Mint 10k to trader

    deal(address(celoToken), trader, 1000 * 10**18); // Gift 10k to trader

    deal(address(celoToken), address(reserve), 10**24); // Gift 1Mil to reserve
    deal(address(usdcToken), address(reserve), 10**24); // Gift 1Mil to reserve
  }

  /**
   * @notice Test helper function to do swap in
   */
  function doSwapIn(
    bytes32 poolId,
    uint256 amountIn,
    address tokenIn,
    address tokenOut
  ) public {
    // Get exchange provider from broker
    address[] memory exchangeProviders = broker.getExchangeProviders();
    assertEq(exchangeProviders.length, 1);
    changePrank(trader);
    IERC20(tokenIn).approve(address(broker), amountIn);

    broker.swapIn(address(exchangeProviders[0]), poolId, tokenIn, tokenOut, 1000 * 10**18, 0);
  }

  function test_gas_swapIn_cUSDToBridgedUSDC() public {
    uint256 amountIn = 1000 * 10**18; // 1k
    IERC20 tokenIn = cUSDToken;
    IERC20 tokenOut = usdcToken;
    bytes32 poolId = pair_cUSD_bridgedUSDC_ID;

    doSwapIn(poolId, amountIn, address(tokenIn), address(tokenOut));
  }

  function test_gas_swapIn_cEURToBridgedUSDC() public {
    uint256 amountIn = 1000 * 10**18; // 1k
    IERC20 tokenIn = cEURToken;
    IERC20 tokenOut = usdcToken;
    bytes32 poolId = pair_cEUR_bridgedUSDC_ID;

    doSwapIn(poolId, amountIn, address(tokenIn), address(tokenOut));
  }

  function test_gas_swapIn_cEURTocUSD() public {
    uint256 amountIn = 1000 * 10**18; // 1k
    IERC20 tokenIn = cEURToken;
    IERC20 tokenOut = cUSDToken;
    bytes32 poolId = pair_cUSD_cEUR_ID;

    doSwapIn(poolId, amountIn, address(tokenIn), address(tokenOut));
  }

  function test_gas_swapIn_cUSDTocEUR() public {
    uint256 amountIn = 1000 * 10**18; // 1k
    IERC20 tokenIn = cUSDToken;
    IERC20 tokenOut = cEURToken;
    bytes32 poolId = pair_cUSD_cEUR_ID;

    doSwapIn(poolId, amountIn, address(tokenIn), address(tokenOut));
  }

  function test_gas_swapIn_CELOTocEUR() public {
    uint256 amountIn = 1000 * 10**18; // 1k
    IERC20 tokenIn = celoToken;
    IERC20 tokenOut = cEURToken;
    bytes32 poolId = pair_cEUR_CELO_ID;

    doSwapIn(poolId, amountIn, address(tokenIn), address(tokenOut));
  }

  function test_gas_swapIn_CELOTocUSD() public {
    uint256 amountIn = 1000 * 10**18; // 1k
    IERC20 tokenIn = celoToken;
    IERC20 tokenOut = cUSDToken;
    bytes32 poolId = pair_cUSD_CELO_ID;

    doSwapIn(poolId, amountIn, address(tokenIn), address(tokenOut));
  }

  function test_gas_swapIn_CUSDToCelo() public {
    uint256 amountIn = 1000 * 10**18; // 1k
    IERC20 tokenIn = cUSDToken;
    IERC20 tokenOut = celoToken;
    bytes32 poolId = pair_cUSD_CELO_ID;

    doSwapIn(poolId, amountIn, address(tokenIn), address(tokenOut));
  }

  function test_gas_swapIn_CEURToCelo() public {
    uint256 amountIn = 1000 * 10**18; // 1k
    IERC20 tokenIn = cEURToken;
    IERC20 tokenOut = celoToken;
    bytes32 poolId = pair_cEUR_CELO_ID;

    doSwapIn(poolId, amountIn, address(tokenIn), address(tokenOut));
  }
}
