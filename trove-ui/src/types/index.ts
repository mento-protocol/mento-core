import { ethers } from "ethers";

export interface Trove {
  id: string;
  debt: string;
  coll: string;
  status: number;
  currentICR: string;
  annualInterestRate: string;
}

export interface TroveManager {
  getTroveIdsCount: () => Promise<number>;
  getTroveFromTroveIdsArray: (index: number) => Promise<number>;
  getCurrentICR: (troveId: number, price: string) => Promise<string>;
  getTroveStatus: (troveId: number) => Promise<number>;
  getTroveAnnualInterestRate: (troveId: number) => Promise<string>;
  Troves: (id: number) => Promise<{
    debt: string;
    coll: string;
    status: number;
    annualInterestRate: string;
  }>;
}

export interface BorrowerOperations {
  openTrove(
    owner: string,
    ownerIndex: number,
    ETHAmount: ethers.BigNumber,
    boldAmount: ethers.BigNumber,
    upperHint: number,
    lowerHint: number,
    annualInterestRate: ethers.BigNumber,
    maxUpfrontFee: ethers.BigNumber,
    addManager: string,
    removeManager: string,
    receiver: string,
  ): Promise<number>;
  closeTrove(troveId: number): Promise<void>;
}

export interface CollateralRegistry {
  redeemCollateral: (boldAmount: string, maxIterations: number, maxFeePercentage: string) => Promise<void>;
}

export interface PriceFeed {
  getPrice: () => Promise<string>;
  setPrice: (price: string) => Promise<void>;
}
