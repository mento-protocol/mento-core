import { ethers } from "ethers";
import { CONFIG, ABIS, NETWORKS } from "./config.js";

class MentoUI {
  constructor() {
    this.provider = null;
    this.signer = null;
    this.address = null;
    this.contracts = {};
    this.troves = [];

    this.initializeElements();
    this.bindEvents();
    this.checkConnection();
  }

  initializeElements() {
    // Connect elements
    this.connectBtn = document.getElementById("connectBtn");
    this.connectSection = document.getElementById("connectSection");
    this.walletInfo = document.getElementById("walletInfo");
    this.walletAddress = document.getElementById("walletAddress");
    this.networkInfo = document.getElementById("networkInfo");
    this.walletBalance = document.getElementById("walletBalance");
    this.mainContent = document.getElementById("mainContent");

    // Price elements
    this.collateralPrice = document.getElementById("collateralPrice");

    // Form elements
    this.collateralAmount = document.getElementById("collateralAmount");
    this.boldAmount = document.getElementById("boldAmount");
    this.interestRate = document.getElementById("interestRate");
    this.redeemAmount = document.getElementById("redeemAmount");
    this.maxIterations = document.getElementById("maxIterations");
    this.swapAmount = document.getElementById("swapAmount");
    this.swapFrom = document.getElementById("swapFrom");
    this.swapTo = document.getElementById("swapTo");
    this.rebalancePoolSelect = document.getElementById("rebalancePoolSelect");

    // Button elements
    this.openTroveBtn = document.getElementById("openTroveBtn");
    this.redeemBtn = document.getElementById("redeemBtn");
    this.refreshTrovesBtn = document.getElementById("refreshTrovesBtn");
    this.swapBtn = document.getElementById("swapBtn");
    this.rebalanceBtn = document.getElementById("rebalanceBtn");
    this.refreshPoolsBtn = document.getElementById("refreshPoolsBtn");

    // List elements
    this.troveList = document.getElementById("troveList");
    this.poolsList = document.getElementById("poolsList");
  }

  bindEvents() {
    this.connectBtn.addEventListener("click", () => this.connectWallet());
    this.openTroveBtn.addEventListener("click", () => this.openTrove());
    this.redeemBtn.addEventListener("click", () => this.redeemCollateral());
    this.refreshTrovesBtn.addEventListener("click", () => this.loadTroves());
    this.swapBtn.addEventListener("click", () => this.swapTokens());
    
    // Rebalance related events
    if (this.rebalanceBtn) {
      this.rebalanceBtn.addEventListener("click", () => this.rebalancePool());
    }
    if (this.refreshPoolsBtn) {
      this.refreshPoolsBtn.addEventListener("click", () => this.loadPools());
    }
  }

  async checkConnection() {
    if (typeof window.ethereum !== "undefined") {
      try {
        const accounts = await window.ethereum.request({ method: "eth_accounts" });
        if (accounts.length > 0) {
          await this.setupProvider();
          await this.updateWalletInfo();
          this.showMainContent();
        }
      } catch (error) {
        console.error("Error checking connection:", error);
      }
    }
  }

  async connectWallet() {
    if (typeof window.ethereum === "undefined") {
      this.showError("MetaMask is not installed. Please install MetaMask to use this app.");
      return;
    }

    try {
      this.connectBtn.disabled = true;
      this.connectBtn.textContent = "Connecting...";

      // Request account access
      const accounts = await window.ethereum.request({ method: "eth_requestAccounts" });

      if (accounts.length === 0) {
        throw new Error("No accounts found");
      }

      await this.setupProvider();
      await this.switchToAlfajores();
      await this.updateWalletInfo();
      this.showMainContent();
      this.loadInitialData();
    } catch (error) {
      console.error("Error connecting wallet:", error);
      this.showError("Failed to connect wallet: " + error.message);
    } finally {
      this.connectBtn.disabled = false;
      this.connectBtn.textContent = "Connect Wallet";
    }
  }

  async setupProvider() {
    this.provider = new ethers.BrowserProvider(window.ethereum);
    this.signer = await this.provider.getSigner();
    this.address = await this.signer.getAddress();

    // Initialize contracts
    await this.initializeContracts();
  }

  async switchToAlfajores() {
    if (window.ethereum.networkVersion === "44787") {
      return;
    }

    try {
      await window.ethereum.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: NETWORKS.ALFAJORES.chainId }],
      });
    } catch (switchError) {
      // This error code indicates that the chain has not been added to MetaMask
      if (switchError.code === 4902) {
        try {
          await window.ethereum.request({
            method: "wallet_addEthereumChain",
            params: [NETWORKS.ALFAJORES],
          });
        } catch (addError) {
          throw new Error("Failed to add Alfajores network to MetaMask");
        }
      } else {
        throw switchError;
      }
    }
  }

  async initializeContracts() {
    // Initialize registry contract
    this.contracts.registry = new ethers.Contract(
      CONFIG.CONTRACTS.ADDRESSES_REGISTRY,
      ABIS.ADDRESSES_REGISTRY,
      this.signer,
    );

    // Get contract addresses from registry
    const [
      borrowerOperationsAddr,
      troveManagerAddr,
      boldTokenAddr,
      collTokenAddr,
      priceFeedAddr,
      collateralRegistryAddr,
    ] = await Promise.all([
      this.contracts.registry.borrowerOperations(),
      this.contracts.registry.troveManager(),
      this.contracts.registry.boldToken(),
      this.contracts.registry.collToken(),
      this.contracts.registry.priceFeed(),
      this.contracts.registry.collateralRegistry(),
    ]);
    console.log(
      { borrowerOperationsAddr },
      { troveManagerAddr },
      { boldTokenAddr },
      { collTokenAddr },
      { priceFeedAddr },
      { collateralRegistryAddr },
    );

    // Initialize other contracts
    this.contracts.borrowerOperations = new ethers.Contract(
      borrowerOperationsAddr,
      ABIS.BORROWER_OPERATIONS,
      this.signer,
    );

    this.contracts.troveManager = new ethers.Contract(troveManagerAddr, ABIS.TROVE_MANAGER, this.signer);

    this.contracts.boldToken = new ethers.Contract(boldTokenAddr, ABIS.ERC20, this.signer);

    this.contracts.collToken = new ethers.Contract(collTokenAddr, ABIS.ERC20, this.signer);

    this.contracts.priceFeed = new ethers.Contract(priceFeedAddr, ABIS.PRICE_FEED, this.signer);

    this.contracts.collateralRegistry = new ethers.Contract(
      collateralRegistryAddr,
      ABIS.COLLATERAL_REGISTRY,
      this.signer,
    );

    // Initialize FPMM if address is available
    if (CONFIG.CONTRACTS.FPMM !== "0x0000000000000000000000000000000000000000") {
      try {
        this.contracts.fpmm = new ethers.Contract(CONFIG.CONTRACTS.FPMM, ABIS.FPMM, this.signer);
        console.log("FPMM contract initialized at:", CONFIG.CONTRACTS.FPMM);
      } catch (error) {
        console.error("Error initializing FPMM contract:", error);
      }
    }
    
    // Initialize LiquidityStrategy if address is available
    if (CONFIG.CONTRACTS.LIQUIDITY_STRATEGY !== "0x0000000000000000000000000000000000000000") {
      try {
        this.contracts.liquidityStrategy = new ethers.Contract(
          CONFIG.CONTRACTS.LIQUIDITY_STRATEGY,
          ABIS.LIQUIDITY_STRATEGY,
          this.signer
        );
        console.log("Liquidity Strategy contract initialized at:", CONFIG.CONTRACTS.LIQUIDITY_STRATEGY);
      } catch (error) {
        console.error("Error initializing Liquidity Strategy contract:", error);
      }
    } else {
      console.warn("Liquidity Strategy contract address not configured");
    }
  }

  async updateWalletInfo() {
    if (!this.address) return;

    try {
      const balance = await this.provider.getBalance(this.address);
      const network = await this.provider.getNetwork();

      this.walletAddress.textContent = this.address;
      this.networkInfo.textContent = `Chain ID: ${network.chainId}`;
      this.walletBalance.textContent = `${ethers.formatEther(balance)} CELO`;

      this.walletInfo.style.display = "block";
    } catch (error) {
      console.error("Error updating wallet info:", error);
    }
  }

  showMainContent() {
    this.mainContent.classList.add("active");
  }

  async loadInitialData() {
    await Promise.all([this.loadPrice(), this.loadTroves(), this.loadPools()]);
  }

  async loadPrice() {
    try {
      const price = await this.contracts.priceFeed.getPrice();
      const priceFormatted = ethers.formatUnits(price, 18);
      this.collateralPrice.textContent = `$${parseFloat(priceFormatted).toFixed(2)}`;
    } catch (error) {
      console.error("Error loading price:", error);
      this.collateralPrice.textContent = "Error loading price";
    }
  }

  async loadTroves() {
    try {
      this.troveList.innerHTML = '<div class="loading">Loading your troves...</div>';

      const troveCount = await this.contracts.troveManager.getTroveIdsCount();
      console.log({ troveCount });
      this.troves = [];

      for (let i = 0; i < troveCount; i++) {
        try {
          const troveId = await this.contracts.troveManager.getTroveFromTroveIdsArray(i);
          console.log({ troveId });
          const troveData = await this.contracts.troveManager.Troves(troveId);
          console.log({ troveData });

          // Check if trove belongs to current user
          // Active status
          this.troves.push({
            id: troveId.toString(),
            debt: ethers.formatUnits(troveData.debt, 18),
            coll: ethers.formatUnits(troveData.coll, 18),
            interestRate: ethers.formatUnits(troveData.annualInterestRate, 16), // Convert from basis points
          });
        } catch (error) {
          console.error(`Error loading trove ${i}:`, error);
        }
      }

      this.renderTroves();
    } catch (error) {
      console.error("Error loading troves:", error);
      this.troveList.innerHTML = '<div class="error">Error loading troves</div>';
    }
  }

  renderTroves() {
    if (this.troves.length === 0) {
      this.troveList.innerHTML = '<div class="loading">No troves found</div>';
      return;
    }

    this.troveList.innerHTML = this.troves
      .map(
        trove => `
      <div class="trove-item">
        <h4>Trove #${trove.id}</h4>
        <p><strong>Collateral:</strong> ${parseFloat(trove.coll).toFixed(2)} USD.m</p>
        <p><strong>Debt:</strong> ${parseFloat(trove.debt).toFixed(2)} EUR.m</p>
        <p><strong>Interest Rate:</strong> ${parseFloat(trove.interestRate).toFixed(2)}%</p>
        <button class="btn btn-danger" onclick="mentoUI.closeTrove('${trove.id}')">Close Trove</button>
      </div>
    `,
      )
      .join("");
  }

  async openTrove() {
    try {
      this.openTroveBtn.disabled = true;
      this.openTroveBtn.textContent = "Opening Trove...";

      const collAmount = ethers.parseUnits(this.collateralAmount.value, 18);
      const boldAmount = ethers.parseUnits(this.boldAmount.value, 18);
      const interestRate = ethers.parseUnits(this.interestRate.value, 16); // Convert to basis points
      const ownerIndex = Math.floor(Date.now() / 1000);

      // Approve collateral token
      const allowance = await this.contracts.collToken.allowance(
        this.address,
        this.contracts.borrowerOperations.target,
      );
      console.log({ allowance });
      if (allowance < collAmount) {
        const approveTx = await this.contracts.collToken.approve(
          this.contracts.borrowerOperations.target,
          ethers.MaxUint256,
        );
        await approveTx.wait();
      }

      // Open trove
      const tx = await this.contracts.borrowerOperations.openTrove(
        this.address,
        ownerIndex,
        collAmount,
        boldAmount,
        0, // upperHint
        0, // lowerHint
        interestRate,
        ethers.MaxUint256, // maxUpfrontFee
        ethers.ZeroAddress, // addManager
        ethers.ZeroAddress, // removeManager
        ethers.ZeroAddress, // receiver
      );

      await tx.wait();
      this.showSuccess("Trove opened successfully!");
      await this.loadTroves();
    } catch (error) {
      console.error("Error opening trove:", error);
      this.showError("Failed to open trove: " + error.message);
    } finally {
      this.openTroveBtn.disabled = false;
      this.openTroveBtn.textContent = "Open Trove";
    }
  }

  async closeTrove(troveId) {
    try {
      // Get trove data to know how much debt to repay
      const troveData = await this.contracts.troveManager.Troves(troveId);
      const debtAmount = troveData.debt;

      // Approve BOLD token
      const allowance = await this.contracts.boldToken.allowance(
        this.address,
        this.contracts.borrowerOperations.target,
      );
      if (allowance < debtAmount) {
        const approveTx = await this.contracts.boldToken.approve(
          this.contracts.borrowerOperations.target,
          ethers.MaxUint256,
        );
        await approveTx.wait();
      }

      // Close trove
      const tx = await this.contracts.borrowerOperations.closeTrove(troveId);
      await tx.wait();

      this.showSuccess("Trove closed successfully!");
      await this.loadTroves();
    } catch (error) {
      console.error("Error closing trove:", error);
      this.showError("Failed to close trove: " + error.message);
    }
  }

  async redeemCollateral() {
    try {
      this.redeemBtn.disabled = true;
      this.redeemBtn.textContent = "Redeeming...";

      const boldAmount = ethers.parseUnits(this.redeemAmount.value, 18);
      const maxIterations = parseInt(this.maxIterations.value);
      const maxFeePercentage = ethers.parseUnits("1", 18); // 100% max fee

      // Approve BOLD token
      const allowance = await this.contracts.boldToken.allowance(
        this.address,
        this.contracts.collateralRegistry.target,
      );
      if (allowance < boldAmount) {
        const approveTx = await this.contracts.boldToken.approve(
          this.contracts.collateralRegistry.target,
          ethers.MaxUint256,
        );
        await approveTx.wait();
      }

      // Redeem collateral
      const tx = await this.contracts.collateralRegistry.redeemCollateral(boldAmount, maxIterations, maxFeePercentage);

      await tx.wait();
      this.showSuccess("Collateral redeemed successfully!");
    } catch (error) {
      console.error("Error redeeming collateral:", error);
      this.showError("Failed to redeem collateral: " + error.message);
    } finally {
      this.redeemBtn.disabled = false;
      this.redeemBtn.textContent = "Redeem Collateral";
    }
  }

  async swapTokens() {
    if (!this.contracts.fpmm) {
      this.showError("FPMM contract not configured");
      return;
    }

    try {
      this.swapBtn.disabled = true;
      this.swapBtn.textContent = "Swapping...";

      const amount = ethers.parseUnits(this.swapAmount.value, 18);
      const fromToken = this.swapFrom.value;

      const fromTokenContract = fromToken === "USD.m" ? this.contracts.collToken : this.contracts.boldToken;
      const fromTokenAddr = fromToken === "USD.m" ? this.contracts.collToken.target : this.contracts.boldToken.target;
      const sendTx = await fromTokenContract.transfer(this.contracts.fpmm.target, amount);
      await sendTx.wait();

      debugger;

      // Calculate output amount
      const amountOut = await this.contracts.fpmm.getAmountOut(amount, fromTokenAddr);

      // Execute swap
      const tx = await this.contracts.fpmm.swap(
        fromToken === "USD.m" ? amountOut : 0,
        fromToken === "USD.m" ? 0 : amountOut,
        this.address,
        "0x",
      );

      await tx.wait();
      this.showSuccess("Swap completed successfully!");
    } catch (error) {
      console.error("Error swapping tokens:", error);
      this.showError("Failed to swap tokens: " + error.message);
    } finally {
      this.swapBtn.disabled = false;
      this.swapBtn.textContent = "Swap Tokens";
    }
  }
  
  async loadPools() {
    console.log("Loading pools...");
    
    if (!this.contracts.liquidityStrategy) {
      console.error("Liquidity strategy not configured:", this.contracts.liquidityStrategy);
      if (this.poolsList) {
        this.poolsList.innerHTML = '<div class="error">Liquidity strategy contract not configured</div>';
      }
      return;
    }
    
    if (!this.poolsList) {
      console.error("Pools list element not found");
      return;
    }
    
    console.log("Liquidity strategy initialized:", this.contracts.liquidityStrategy.target);
    
    try {
      this.poolsList.innerHTML = '<div class="loading">Loading pools...</div>';
      
      // Get all registered pools
      console.log("Fetching registered pools...");
      const pools = await this.contracts.liquidityStrategy.getPools();
      console.log("Pools found:", pools);
      
      if (pools.length === 0) {
        this.poolsList.innerHTML = '<div class="loading">No pools registered in the liquidity strategy. Please add pools to the strategy first.</div>';
        
        // Add a sample test pool for UI testing if needed
        if (window.location.search.includes('addTestPool=true')) {
          this.poolsList.innerHTML += '<div class="pool-item test-pool">' +
            '<h4>Test Pool (UI Testing Only)</h4>' +
            '<div class="pool-data">' +
            '<div class="pool-column">' +
            '<p><strong>Tokens:</strong> USD.m/EUR.m</p>' +
            '<p><strong>Reserves:</strong> 1000.00/1000.00</p>' +
            '<p><strong>Oracle Price:</strong> $1.0000</p>' +
            '<p><strong>Pool Price:</strong> $1.0000</p>' +
            '</div>' +
            '<div class="pool-column">' +
            '<p><strong>Last Rebalance:</strong> Never</p>' +
            '<p><strong>Cooldown Ends:</strong> N/A</p>' +
            '<p><strong>Rebalance Incentive:</strong> 0.25%</p>' +
            '<p><strong>Thresholds:</strong> +0.5% / -0.5%</p>' +
            '</div>' +
            '</div>' +
            '<button class="btn btn-primary" disabled>Rebalance Unavailable (Test)</button>' +
            '</div>';
        }
        
        // Clear the dropdown options except the first default option
        if (this.rebalancePoolSelect) {
          this.rebalancePoolSelect.innerHTML = '<option value="">Select a pool</option>';
        }
        return;
      }
      
      // Store pools data
      this.pools = [];
      
      // Fetch data for each pool
      for (const poolAddress of pools) {
        try {
          const fpmmContract = new ethers.Contract(poolAddress, ABIS.FPMM, this.signer);
          
          // Get pool configuration from liquidity strategy
          const poolConfig = await this.contracts.liquidityStrategy.fpmmPoolConfigs(poolAddress);
          
          // Get token information
          const token0Address = await fpmmContract.token0();
          const token1Address = await fpmmContract.token1();
          
          // Get token symbols
          const token0Contract = new ethers.Contract(token0Address, ABIS.ERC20, this.signer);
          const token1Contract = new ethers.Contract(token1Address, ABIS.ERC20, this.signer);
          
          let token0Symbol = "Unknown";
          let token1Symbol = "Unknown";
          
          try {
            token0Symbol = await token0Contract.symbol();
            console.log(`Token 0 (${token0Address}) symbol:`, token0Symbol);
          } catch (error) {
            console.error(`Error getting symbol for token 0 (${token0Address}):`, error);
            token0Symbol = token0Address.substring(0, 6) + "...";
          }
          
          try {
            token1Symbol = await token1Contract.symbol();
            console.log(`Token 1 (${token1Address}) symbol:`, token1Symbol);
          } catch (error) {
            console.error(`Error getting symbol for token 1 (${token1Address}):`, error);
            token1Symbol = token1Address.substring(0, 6) + "...";
          }
          
          // Get metadata
          const metadata = await fpmmContract.metadata();
          
          // Get prices
          const prices = await fpmmContract.getPrices();
          
          // Get rebalance thresholds
          const thresholdAbove = await fpmmContract.rebalanceThresholdAbove();
          const thresholdBelow = await fpmmContract.rebalanceThresholdBelow();
          
          // Calculate if rebalance is possible (cooldown check)
          const now = Math.floor(Date.now() / 1000);
          const cooldownEnds = Number(poolConfig.lastRebalance) + Number(poolConfig.rebalanceCooldown);
          const canRebalance = now > cooldownEnds;
          
          this.pools.push({
            address: poolAddress,
            token0Address: token0Address,
            token1Address: token1Address,
            token0Symbol: token0Symbol,
            token1Symbol: token1Symbol,
            reserve0: metadata.reserve0,
            reserve1: metadata.reserve1,
            oraclePrice: prices.oraclePrice,
            poolPrice: prices.poolPrice,
            lastRebalance: poolConfig.lastRebalance,
            rebalanceCooldown: poolConfig.rebalanceCooldown,
            rebalanceIncentive: poolConfig.rebalanceIncentive,
            thresholdAbove,
            thresholdBelow,
            canRebalance
          });
        } catch (error) {
          console.error(`Error loading pool ${poolAddress}:`, error);
        }
      }
      
      this.renderPools();
      this.updatePoolsDropdown();
      
    } catch (error) {
      console.error("Error loading pools:", error);
      this.poolsList.innerHTML = '<div class="error">Error loading pools</div>';
    }
  }
  
  renderPools() {
    if (!this.poolsList || this.pools.length === 0) {
      return;
    }
    
    this.poolsList.innerHTML = this.pools
      .map(pool => {
        try {
          // Convert BigInt values to Numbers safely
          const lastRebalanceNum = BigInt(pool.lastRebalance.toString());
          const rebalanceCooldownNum = BigInt(pool.rebalanceCooldown.toString());
          
          const lastRebalanceDate = new Date(Number(lastRebalanceNum) * 1000).toLocaleString();
          const cooldownEnds = new Date(Number(lastRebalanceNum + rebalanceCooldownNum) * 1000).toLocaleString();
          
          // Format numbers properly
          const oraclePriceFormatted = ethers.formatUnits(pool.oraclePrice, 18);
          const poolPriceFormatted = ethers.formatUnits(pool.poolPrice, 18);
          const reserve0Formatted = ethers.formatUnits(pool.reserve0, 18);
          const reserve1Formatted = ethers.formatUnits(pool.reserve1, 6);
          
          // Convert thresholds (which could be BigInt) to Numbers safely
          const thresholdAboveNum = Number(BigInt(pool.thresholdAbove.toString())) / 100;
          const thresholdBelowNum = Number(BigInt(pool.thresholdBelow.toString())) / 100;
          const rebalanceIncentiveNum = Number(BigInt(pool.rebalanceIncentive.toString())) / 100;
          
          return `
          <div class="pool-item">
            <h4>Pool ${pool.address.substring(0, 6)}...${pool.address.substring(38)}</h4>
            <div class="pool-data">
              <div class="pool-column">
                <p><strong>Tokens:</strong> ${pool.token0Symbol}/${pool.token1Symbol}</p>
                <p><strong>Reserves:</strong> ${parseFloat(reserve0Formatted).toFixed(2)} ${pool.token0Symbol} / ${parseFloat(reserve1Formatted).toFixed(2)} ${pool.token1Symbol}</p>
                <p><strong>Oracle Price:</strong> $${parseFloat(oraclePriceFormatted).toFixed(4)}</p>
                <p><strong>Pool Price:</strong> $${parseFloat(poolPriceFormatted).toFixed(4)}</p>
              </div>
              <div class="pool-column">
                <p><strong>Last Rebalance:</strong> ${lastRebalanceDate}</p>
                <p><strong>Cooldown Ends:</strong> ${cooldownEnds}</p>
                <p><strong>Rebalance Incentive:</strong> ${rebalanceIncentiveNum.toFixed(2)}%</p>
                <p><strong>Thresholds:</strong> +${thresholdAboveNum.toFixed(2)}% / -${thresholdBelowNum.toFixed(2)}%</p>
              </div>
            </div>
            <button class="btn ${pool.canRebalance ? 'btn-primary' : 'btn-secondary'}" 
              onclick="mentoUI.rebalancePool('${pool.address}')" 
              ${!pool.canRebalance ? 'disabled' : ''}>
              ${pool.canRebalance ? 'Rebalance Pool' : 'Cooldown Active'}
            </button>
          </div>
        `;
        } catch (error) {
          console.error("Error rendering pool:", error, pool);
          return `
          <div class="pool-item error-pool">
            <h4>Error displaying pool ${pool.address ? (pool.address.substring(0, 6) + '...' + pool.address.substring(38)) : 'unknown'}</h4>
            <p>Error: ${error.message}</p>
          </div>
          `;
        }
      })
      .join("");
  }
  
  updatePoolsDropdown() {
    if (!this.rebalancePoolSelect || this.pools.length === 0) {
      return;
    }
    
    // Clear existing options
    this.rebalancePoolSelect.innerHTML = '<option value="">Select a pool</option>';
    
    // Add options for each pool
    this.pools.forEach(pool => {
      const option = document.createElement('option');
      option.value = pool.address;
      option.textContent = `${pool.address.substring(0, 6)}...${pool.address.substring(38)}`;
      this.rebalancePoolSelect.appendChild(option);
    });
  }
  
  async rebalancePool(poolAddress) {
    if (!this.contracts.liquidityStrategy) {
      this.showError("Liquidity strategy not configured");
      return;
    }
    
    // If no poolAddress provided, get it from the dropdown
    if (!poolAddress && this.rebalancePoolSelect) {
      poolAddress = this.rebalancePoolSelect.value;
    }
    
    if (!poolAddress) {
      this.showError("Please select a pool to rebalance");
      return;
    }
    
    try {
      // Disable all rebalance buttons
      const rebalanceButtons = document.querySelectorAll('.pool-item button');
      rebalanceButtons.forEach(button => {
        button.disabled = true;
        button.textContent = "Rebalancing...";
      });
      
      // Execute rebalance
      const tx = await this.contracts.liquidityStrategy.rebalance(poolAddress);
      await tx.wait();
      
      this.showSuccess("Pool rebalanced successfully!");
      
      // Reload pools data
      await this.loadPools();
    } catch (error) {
      console.error("Error rebalancing pool:", error);
      this.showError("Failed to rebalance pool: " + error.message);
      
      // Re-enable buttons
      const rebalanceButtons = document.querySelectorAll('.pool-item button');
      rebalanceButtons.forEach(button => {
        button.disabled = false;
        button.textContent = "Rebalance Pool";
      });
    }
  }

  showError(message) {
    const errorDiv = document.createElement("div");
    errorDiv.className = "error";
    errorDiv.textContent = message;
    document.querySelector(".container").insertBefore(errorDiv, document.querySelector(".header").nextSibling);

    setTimeout(() => {
      errorDiv.remove();
    }, 5000);
  }

  showSuccess(message) {
    const successDiv = document.createElement("div");
    successDiv.className = "success";
    successDiv.textContent = message;
    document.querySelector(".container").insertBefore(successDiv, document.querySelector(".header").nextSibling);

    setTimeout(() => {
      successDiv.remove();
    }, 5000);
  }
}

// Initialize the app when DOM is loaded
document.addEventListener("DOMContentLoaded", () => {
  window.mentoUI = new MentoUI();
});

// Handle MetaMask account changes
if (typeof window.ethereum !== "undefined") {
  window.ethereum.on("accountsChanged", accounts => {
    if (accounts.length === 0) {
      // User disconnected
      location.reload();
    } else {
      // Account changed
      location.reload();
    }
  });

  window.ethereum.on("chainChanged", () => {
    location.reload();
  });
}
