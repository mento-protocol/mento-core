import React, { useState } from "react";
import { useWeb3 } from "../context/Web3Context";

export const PriceFeedManager: React.FC = () => {
  const [currentPrice, setCurrentPrice] = useState("");
  const [newPrice, setNewPrice] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState(false);

  return (
    <div className="p-4 bg-white rounded-lg shadow">
      <h2 className="text-xl font-bold mb-4">Price Feed Manager</h2>
      <div className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-700">Current Price</label>
          <input
            type="text"
            value={currentPrice}
            readOnly
            className="mt-1 block w-full rounded-md border-gray-300 bg-gray-50 shadow-sm"
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700">New Price</label>
          <input
            type="number"
            value={newPrice}
            onChange={e => setNewPrice(e.target.value)}
            className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
            placeholder="Enter new price"
          />
        </div>
        {error && <div className="text-red-500 text-sm">{error}</div>}
        {success && <div className="text-green-500 text-sm">Price updated successfully!</div>}
        <button
          className="w-full bg-indigo-600 text-white py-2 px-4 rounded-md hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"
          disabled={loading}
        >
          {loading ? "Updating..." : "Update Price"}
        </button>
      </div>
    </div>
  );
};
