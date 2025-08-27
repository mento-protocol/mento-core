import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";

import { CDPPolicy } from "contracts/v3/CDPPolicy.sol";
import { LiquidityTypes as LQ } from "contracts/v3/libraries/LiquidityTypes.sol";

import { Test } from "forge-std/Test.sol";

contract CDPPolicyTest is Test {
  CDPPolicy public policy;

  function setUp() public {
    policy = new CDPPolicy();
  }

  function test_whenPoolPriceAbove() public {
    /*
      struct Context {
        address pool;
        Reserves reserves;
        Prices prices;
        address token0;
        address token1;
        uint128 incentiveBps;
        uint64 token0Dec;
        uint64 token1Dec;
        bool isToken0Debt;
    }
  */
    LQ.Context memory ctx;
  }
}
