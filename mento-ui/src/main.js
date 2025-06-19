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

    // Button elements
    this.openTroveBtn = document.getElementById("openTroveBtn");
    this.redeemBtn = document.getElementById("redeemBtn");
    this.refreshTrovesBtn = document.getElementById("refreshTrovesBtn");
    this.swapBtn = document.getElementById("swapBtn");

    // List elements
    this.troveList = document.getElementById("troveList");
  }

  bindEvents() {
    this.connectBtn.addEventListener("click", () => this.connectWallet());
    this.openTroveBtn.addEventListener("click", () => this.openTrove());
    this.redeemBtn.addEventListener("click", () => this.redeemCollateral());
    this.refreshTrovesBtn.addEventListener("click", () => this.loadTroves());
    this.swapBtn.addEventListener("click", () => this.swapTokens());
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
      this.contracts.fpmm = new ethers.Contract(CONFIG.CONTRACTS.FPMM, ABIS.FPMM, this.signer);
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
    await Promise.all([this.loadPrice(), this.loadTroves()]);
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
