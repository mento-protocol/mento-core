import React, { createContext, useContext, useState, useEffect } from "react";
import { ethers } from "ethers";
import detectEthereumProvider from "@metamask/detect-provider";
import { TroveManager, BorrowerOperations, CollateralRegistry, PriceFeed } from "../types";

import BorrowerOperationsABI from "../abi/out/BorrowerOperations.sol/BorrowerOperations.json";
import CollateralRegistryABI from "../abi/out/CollateralRegistry.sol/CollateralRegistry.json";
import PriceFeedABI from "../abi/out/PriceFeedMock.sol/PriceFeedMock.json";
import TroveManagerABI from "../abi/out/TroveManager.sol/TroveManager.json";

const ALFAJORES_CHAIN_ID = "0xaef3"; // 44787 in hex
const ALFAJORES_RPC_URL = "https://alfajores-forno.celo-testnet.org";

interface Web3ContextType {
  account: string | null;
  connect: () => Promise<void>;
  disconnect: () => void;
  provider: ethers.providers.Web3Provider | null;
  signer: ethers.Signer | null;
  troveManager: TroveManager | null;
  borrowerOperations: BorrowerOperations | null;
  collateralRegistry: CollateralRegistry | null;
  priceFeed: PriceFeed | null;
  isAlfajores: boolean;
  isCorrectNetwork: boolean;
  switchToAlfajores: () => Promise<void>;
}

const Web3Context = createContext<Web3ContextType>({
  account: null,
  connect: async () => {},
  disconnect: () => {},
  provider: null,
  signer: null,
  troveManager: null,
  borrowerOperations: null,
  collateralRegistry: null,
  priceFeed: null,
  isAlfajores: false,
  isCorrectNetwork: false,
  switchToAlfajores: async () => {},
});

export const useWeb3 = () => useContext(Web3Context);

export const Web3Provider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [account, setAccount] = useState<string | null>(null);
  const [provider, setProvider] = useState<ethers.providers.Web3Provider | null>(null);
  const [signer, setSigner] = useState<ethers.Signer | null>(null);
  const [troveManager, setTroveManager] = useState<TroveManager | null>(null);
  const [borrowerOperations, setBorrowerOperations] = useState<BorrowerOperations | null>(null);
  const [collateralRegistry, setCollateralRegistry] = useState<CollateralRegistry | null>(null);
  const [priceFeed, setPriceFeed] = useState<PriceFeed | null>(null);
  const [isAlfajores, setIsAlfajores] = useState(false);
  const [isCorrectNetwork, setIsCorrectNetwork] = useState(false);

  const switchToAlfajores = async () => {
    if (!window.ethereum) {
      console.error("MetaMask is not installed");
      return;
    }

    try {
      // Try to switch to Alfajores network
      await window.ethereum.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: "0xAEF3" }], // 44787 in hex
      });
    } catch (switchError: any) {
      // This error code indicates that the chain has not been added to MetaMask
      if (switchError.code === 4902) {
        try {
          await window.ethereum.request({
            method: "wallet_addEthereumChain",
            params: [
              {
                chainId: "0xAEF3", // 44787 in hex
                chainName: "Alfajores Testnet",
                nativeCurrency: {
                  name: "CELO",
                  symbol: "CELO",
                  decimals: 18,
                },
                rpcUrls: [ALFAJORES_RPC_URL],
                blockExplorerUrls: ["https://alfajores-blockscout.celo-testnet.org"],
              },
            ],
          });
        } catch (addError) {
          console.error("Error adding Alfajores network:", addError);
        }
      } else {
        console.error("Error switching to Alfajores network:", switchError);
      }
    }
  };

  const connect = async () => {
    try {
      debugger;
      const ethereumProvider = await detectEthereumProvider();
      if (!ethereumProvider) {
        throw new Error("Please install MetaMask!");
      }

      console.log("Ethereum provider detected:", ethereumProvider);

      // Request account access
      await window.ethereum.request({ method: "eth_requestAccounts" });

      // Create provider and signer
      const provider = new ethers.providers.Web3Provider(window.ethereum);
      const signer = provider.getSigner();

      // Wait for the signer to be ready
      await signer.getAddress();

      const account = await signer.getAddress();

      console.log("Provider:", provider);
      console.log("Signer:", signer);
      console.log("Account:", account);

      setProvider(provider);
      setSigner(signer);
      setAccount(account);

      const network = await provider.getNetwork();
      const isAlfajoresNetwork = network.chainId === 44787; // Alfajores chainId
      setIsAlfajores(isAlfajoresNetwork);
      setIsCorrectNetwork(isAlfajoresNetwork);

      // Initialize contract instances
      const troveManagerAddress = "0x03671705ce98a50fec58f78abcd915a046d1ace9"; // Replace with actual address
      const borrowerOperationsAddress = "0xcda088ac6226d71bafd885321b77ff2f50fb0709"; // Replace with actual address
      const collateralRegistryAddress = "0x1b686eda0d819e8b280add42a2c849b448484698"; // Replace with actual address
      const priceFeedAddress = "0x00a7234b1e6d098689bbad3e94319b2bbb9de449"; // Replace with actual address

      console.log("Initializing contracts with signer:", signer);

      // Create contract instances with the signer
      const troveManagerContract = new ethers.Contract(
        troveManagerAddress,
        TroveManagerABI.abi,
        signer,
      ) as unknown as TroveManager;

      const borrowerOperationsContract = new ethers.Contract(
        borrowerOperationsAddress,
        BorrowerOperationsABI.abi,
        signer,
      ) as unknown as BorrowerOperations;

      const collateralRegistryContract = new ethers.Contract(
        collateralRegistryAddress,
        CollateralRegistryABI.abi,
        signer,
      ) as unknown as CollateralRegistry;

      const priceFeedContract = new ethers.Contract(priceFeedAddress, PriceFeedABI.abi, signer) as unknown as PriceFeed;

      // Verify contract connections
      console.log("Verifying contract connections...");
      try {
        await borrowerOperationsContract.openTrove(
          account,
          Math.floor(Date.now() / 1000),
          ethers.utils.parseEther("1"),
          ethers.utils.parseEther("1"),
          0,
          0,
          ethers.utils.parseEther("0.1"),
          ethers.utils.parseEther("0.1"),
          ethers.constants.AddressZero,
          ethers.constants.AddressZero,
          account,
        );
        console.log("BorrowerOperations contract is connected");
      } catch (error) {
        console.error("Error connecting to BorrowerOperations:", error);
      }

      setTroveManager(troveManagerContract);
      setBorrowerOperations(borrowerOperationsContract);
      setCollateralRegistry(collateralRegistryContract);
      setPriceFeed(priceFeedContract);
    } catch (error) {
      console.error("Error connecting to MetaMask:", error);
    }
  };

  const disconnect = () => {
    setProvider(null);
    setSigner(null);
    setAccount(null);
    setTroveManager(null);
    setBorrowerOperations(null);
    setCollateralRegistry(null);
    setPriceFeed(null);
    setIsAlfajores(false);
  };

  useEffect(() => {
    const init = async () => {
      if (window.ethereum) {
        const provider = new ethers.providers.Web3Provider(window.ethereum);
        setProvider(provider);

        const accounts = await provider.listAccounts();
        if (accounts.length > 0) {
          const signer = provider.getSigner();
          setSigner(signer);
          const account = await signer.getAddress();
          setAccount(account);
          console.log("Account:", account);

          const network = await provider.getNetwork();
          const isAlfajoresNetwork = network.chainId === 44787; // Alfajores chainId

          if (!isAlfajoresNetwork) {
            await switchToAlfajores();
            setIsCorrectNetwork(true);
          }
        }
      }
    };

    init();
  }, []);

  const value: Web3ContextType = {
    account,
    connect,
    disconnect,
    provider,
    signer,
    troveManager,
    borrowerOperations,
    collateralRegistry,
    priceFeed,
    isAlfajores,
    isCorrectNetwork,
    switchToAlfajores,
  };

  return <Web3Context.Provider value={value}>{children}</Web3Context.Provider>;
};
