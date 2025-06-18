import React, { useState, useEffect } from "react";
import { useWeb3 } from "../context/Web3Context";
import { ethers } from "ethers";
import { Trove } from "../types";

export const TroveList: React.FC = () => {
  const { troveManager, borrowerOperations, priceFeed } = useWeb3();
  const [troves, setTroves] = useState<Trove[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [selectedTroveId, setSelectedTroveId] = useState<string | null>(null);

  const fetchTroves = async () => {
    if (!troveManager || !priceFeed) return;

    try {
      setLoading(true);
      setError("");

      const count = await troveManager.getTroveIdsCount();
      const currentPrice = await priceFeed.getPrice();
      const troveList: Trove[] = [];

      for (let i = 0; i < count; i++) {
        const troveId = await troveManager.getTroveFromTroveIdsArray(i);
        const troveData = await troveManager.Troves(troveId);
        const currentICR = await troveManager.getCurrentICR(troveId, currentPrice);
        const status = await troveManager.getTroveStatus(troveId);
        const annualInterestRate = await troveManager.getTroveAnnualInterestRate(troveId);

        troveList.push({
          id: troveId.toString(),
          debt: ethers.utils.formatEther(troveData.debt),
          coll: ethers.utils.formatEther(troveData.coll),
          status,
          currentICR: ethers.utils.formatEther(currentICR),
          annualInterestRate: ethers.utils.formatEther(annualInterestRate),
        });
      }

      setTroves(troveList);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to fetch troves");
    } finally {
      setLoading(false);
    }
  };

  const handleCloseTrove = async (troveId: string) => {
    if (!borrowerOperations) return;

    try {
      setLoading(true);
      setError("");

      await borrowerOperations.closeTrove(parseInt(troveId));
      await fetchTroves();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to close trove");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchTroves();
  }, [troveManager, priceFeed]);

  const getStatusText = (status: number) => {
    switch (status) {
      case 0:
        return "Non-existent";
      case 1:
        return "Active";
      case 2:
        return "Closed by Owner";
      case 3:
        return "Closed by Liquidation";
      case 4:
        return "Zombie";
      default:
        return "Unknown";
    }
  };

  return (
    <div className="p-4 bg-white rounded-lg shadow">
      <div className="flex justify-between items-center mb-4">
        <h2 className="text-2xl font-bold">Trove List</h2>
        <button
          onClick={fetchTroves}
          disabled={loading}
          className="bg-indigo-600 text-white py-2 px-4 rounded-md hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 disabled:opacity-50"
        >
          Refresh
        </button>
      </div>

      {error && <p className="text-red-500 text-sm mb-4">{error}</p>}

      <div className="overflow-x-auto">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">ID</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Collateral
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Debt</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">ICR</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Interest Rate
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {troves.map(trove => (
              <tr key={trove.id}>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{trove.id}</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{trove.coll} ETH</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{trove.debt} BOLD</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{trove.currentICR}%</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{getStatusText(trove.status)}</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{trove.annualInterestRate}%</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {trove.status === 1 && (
                    <button
                      onClick={() => handleCloseTrove(trove.id)}
                      disabled={loading}
                      className="text-indigo-600 hover:text-indigo-900"
                    >
                      Close
                    </button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
};
