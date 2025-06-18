import React from "react";
import { Web3Provider } from "./context/Web3Context";
import { OpenTrove } from "./components/OpenTrove";
import { RedeemCollateral } from "./components/RedeemCollateral";
import { TroveList } from "./components/TroveList";
import { PriceFeedManager } from "./components/PriceFeedManager";

function App() {
  return (
    <Web3Provider>
      <div className="min-h-screen bg-gray-100">
        <header className="bg-white shadow">
          <div className="max-w-7xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
            <h1 className="text-3xl font-bold text-gray-900">Trove Management System</h1>
          </div>
        </header>

        <main className="max-w-7xl mx-auto py-6 sm:px-6 lg:px-8">
          <div className="px-4 py-6 sm:px-0">
            <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
              <div className="space-y-6">
                <OpenTrove />
                <RedeemCollateral />
              </div>
              <div className="space-y-6">
                <TroveList />
                <PriceFeedManager />
              </div>
            </div>
          </div>
        </main>
      </div>
    </Web3Provider>
  );
}

export default App;
