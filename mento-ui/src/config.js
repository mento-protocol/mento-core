// Configuration for Mento Protocol contracts on Alfajores testnet
export const CONFIG = {
  // Alfajores testnet configuration
  CHAIN_ID: 44787,
  RPC_URL: "https://alfajores-forno.celo-testnet.org",
  EXPLORER_URL: "https://alfajores.celoscan.io",

  // Contract addresses (to be updated with actual deployed addresses)
  CONTRACTS: {
    // Main registry contract
    ADDRESSES_REGISTRY: "0xd39c90bb4c1e5d63f83a9fe52359897bb1068ed3",

    // Token addresses
    CUSD: "0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1", // cUSD on Alfajores
    CELO: "0xF194afDf50B03e69Bd7D057c1Aa9e10c9954E4C9", // CELO on Alfajores

    // FPMM contract for swaps
    FPMM: "0x8d5671f4a37a6ff95cafb7c26faf1d5db6129fa9", // TODO: Add actual FPMM address
    // FPMM: "0x7DBA083Db8303416D858cbF6282698F90f375Aec",

    // Liquidity Strategy contract
    LIQUIDITY_STRATEGY: "0x3dD78d0b0805dcf9E798Bc89c186d5d0a5ffDBda", // For testing only - replace with actual Liquidity Strategy address
  },

  // Default values
  DEFAULTS: {
    MIN_DEBT: "2000", // Minimum debt in BOLD
    MCR: "110", // Minimum Collateral Ratio (110%)
    MAX_ITERATIONS: 20,
    GAS_LIMIT: 500000,
  },
};

// ABI fragments for contract interactions
export const ABIS = {
  // ERC20 token ABI
  ERC20: [
    "function name() view returns (string)",
    "function symbol() view returns (string)",
    "function decimals() view returns (uint8)",
    "function totalSupply() view returns (uint256)",
    "function balanceOf(address) view returns (uint256)",
    "function transfer(address to, uint256 amount) returns (bool)",
    "function allowance(address owner, address spender) view returns (uint256)",
    "function approve(address spender, uint256 amount) returns (bool)",
    "function transferFrom(address from, address to, uint256 amount) returns (bool)",
    "event Transfer(address indexed from, address indexed to, uint256 value)",
    "event Approval(address indexed owner, address indexed spender, uint256 value)",
  ],

  // AddressesRegistry ABI
  ADDRESSES_REGISTRY: [
    "function borrowerOperations() view returns (address)",
    "function troveManager() view returns (address)",
    "function boldToken() view returns (address)",
    "function collToken() view returns (address)",
    "function priceFeed() view returns (address)",
    "function collateralRegistry() view returns (address)",
    "function stabilityPool() view returns (address)",
    "function activePool() view returns (address)",
    "function CCR() view returns (uint256)",
    "function MCR() view returns (uint256)",
    "function SCR() view returns (uint256)",
  ],

  // BorrowerOperations ABI
  BORROWER_OPERATIONS: [
    "function openTrove(address _owner, uint256 _ownerIndex, uint256 _collAmount, uint256 _boldAmount, uint256 _upperHint, uint256 _lowerHint, uint256 _annualInterestRate, uint256 _maxUpfrontFee, address _addManager, address _removeManager, address _receiver) returns (uint256)",
    "function closeTrove(uint256 _troveId)",
    "function addColl(uint256 _troveId, uint256 _collAmount)",
    "function withdrawColl(uint256 _troveId, uint256 _amount)",
    "function withdrawBold(uint256 _troveId, uint256 _amount, uint256 _maxUpfrontFee)",
    "function repayBold(uint256 _troveId, uint256 _amount)",
    "function adjustTrove(uint256 _troveId, uint256 _collChange, bool _isCollIncrease, uint256 _boldChange, bool _isDebtIncrease, uint256 _maxUpfrontFee)",
  ],

  // TroveManager ABI
  TROVE_MANAGER: [
    "function getTroveIdsCount() view returns (uint256)",
    "function getTroveFromTroveIdsArray(uint256 _index) view returns (uint256)",
    "function getCurrentICR(uint256 _troveId, uint256 _price) view returns (uint256)",
    "function getTroveStatus(uint256 _troveId) view returns (uint8)",
    "function Troves(uint256 _id) view returns (uint256 debt, uint256 coll, uint256 stake, uint8 status, uint64 arrayIndex, uint64 lastDebtUpdateTime, uint64 lastInterestRateAdjTime, uint256 annualInterestRate, address interestBatchManager, uint256 batchDebtShares)",
    "function batchLiquidateTroves(uint256[] calldata _troveArray)",
  ],

  // CollateralRegistry ABI
  COLLATERAL_REGISTRY: [
    "function redeemCollateral(uint256 _boldAmount, uint256 _maxIterations, uint256 _maxFeePercentage)",
    "function getRedemptionRate() view returns (uint256)",
    "function getRedemptionRateWithDecay() view returns (uint256)",
  ],

  // PriceFeed ABI
  PRICE_FEED: [
    "function getPrice() view returns (uint256)",
    "function fetchPrice() returns (uint256, bool)",
    "function lastGoodPrice() view returns (uint256)",
  ],

  // FPMM ABI
  FPMM: [
    "function getAmountOut(uint256 amountIn, address tokenIn) view returns (uint256 amountOut)",
    "function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data)",
    "function token0() view returns (address)",
    "function token1() view returns (address)",
    "function getReserves() view returns (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast)",
    "function metadata() view returns (uint256 decimal0, uint256 decimal1, uint256 reserve0, uint256 reserve1, uint256 blockTimestampLast, uint256 oraclePrice)",
    "function getPrices() view returns (uint256 oraclePrice, uint256 poolPrice, uint256 timestamp, uint256 blockNumber)",
    "function rebalanceIncentive() view returns (uint256)",
    "function rebalanceThresholdAbove() view returns (uint256)",
    "function rebalanceThresholdBelow() view returns (uint256)",
    "function rebalance(uint256 amount0Out, uint256 amount1Out, bytes calldata data)",
  ],
  
  // LiquidityStrategy ABI
  LIQUIDITY_STRATEGY: [
    "function rebalance(address pool) external",
    "function isPoolRegistered(address pool) view returns (bool)",
    "function getPools() view returns (address[])",
    "function fpmmPoolConfigs(address) view returns (uint256 lastRebalance, uint256 rebalanceCooldown, uint256 rebalanceIncentive)",
  ],
};

// Network configuration for MetaMask
export const NETWORKS = {
  ALFAJORES: {
    chainId: "0xaeef", // 44787 in hex
    chainName: "Alfajores Testnet",
    nativeCurrency: {
      name: "CELO",
      symbol: "CELO",
      decimals: 18,
    },
    rpcUrls: ["https://alfajores-forno.celo-testnet.org"],
    blockExplorerUrls: ["https://alfajores.celoscan.io"],
  },
};
