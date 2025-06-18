import React, { useState } from "react";
import { useWeb3 } from "../context/Web3Context";

export const OpenTrove: React.FC = () => {
  const [collateralAmount, setCollateralAmount] = useState("");
  const [debtAmount, setDebtAmount] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState(false);

  return (
    <div className="p-4 bg-white rounded-lg shadow">
      <h2 className="text-xl font-bold mb-4">Open Trove</h2>
      <div className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-700">Collateral Amount (cUSD)</label>
          <input
            type="number"
            value={collateralAmount}
            onChange={e => setCollateralAmount(e.target.value)}
            className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
            placeholder="Enter collateral amount"
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700">Debt Amount (cKES)</label>
          <input
            type="number"
            value={debtAmount}
            onChange={e => setDebtAmount(e.target.value)}
            className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
            placeholder="Enter debt amount"
          />
        </div>
        {error && <div className="text-red-500 text-sm">{error}</div>}
        {success && <div className="text-green-500 text-sm">Trove opened successfully!</div>}
        <button
          className="w-full bg-indigo-600 text-white py-2 px-4 rounded-md hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"
          disabled={loading}
        >
          {loading ? "Opening..." : "Open Trove"}
        </button>
      </div>
    </div>
  );
};
