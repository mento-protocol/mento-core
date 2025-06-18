import React, { useState } from "react";
import { useWeb3 } from "../context/Web3Context";

export const RedeemCollateral: React.FC = () => {
  const [boldAmount, setBoldAmount] = useState("");
  const [maxFeePercentage, setMaxFeePercentage] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState(false);

  return (
    <div className="p-4 bg-white rounded-lg shadow">
      <h2 className="text-xl font-bold mb-4">Redeem Collateral</h2>
      <div className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-700">BOLD Amount</label>
          <input
            type="number"
            value={boldAmount}
            onChange={e => setBoldAmount(e.target.value)}
            className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
            placeholder="Enter BOLD amount"
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700">Max Fee Percentage (e.g., 0.1 for 10%)</label>
          <input
            type="number"
            value={maxFeePercentage}
            onChange={e => setMaxFeePercentage(e.target.value)}
            className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
            placeholder="Enter max fee percentage"
            min="0"
            max="1"
            step="0.01"
          />
        </div>
        {error && <div className="text-red-500 text-sm">{error}</div>}
        {success && <div className="text-green-500 text-sm">Collateral redeemed successfully!</div>}
        <button
          className="w-full bg-indigo-600 text-white py-2 px-4 rounded-md hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"
          disabled={loading}
        >
          {loading ? "Redeeming..." : "Redeem Collateral"}
        </button>
      </div>
    </div>
  );
};
