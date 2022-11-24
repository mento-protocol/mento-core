const {runTypeChain,glob} = require('typechain')

async function main() {
  const cwd = process.cwd()
  // Files for which types are supposed to be created
  const allFiles = glob(cwd+"/out",["IBiPoolManager.sol/IBiPoolManager.json",
                                    "IBroker.sol/IBroker.json",
                                    "IBrokerAdmin.sol/IBrokerAdmin.json",
                                    "ICeloToken.sol/ICeloToken.json",
                                    "IExchange.sol/IExchange.json",
                                    "IExchangeProvider.sol/IExchangeProvider.json",
                                    "IPricingModule.sol/IPricingModule.json",
                                    "IReserve.sol/IReserve.json",
                                    "ISortedOracles.sol/ISortedOracles.json",
                                    "IStableToken.sol/IStableToken.json"])

  const result = await runTypeChain({
    cwd,
    filesToProcess: allFiles,
    allFiles,
    outDir: 'types',
    target: 'ethers-v5',
  })
}

main().catch(console.error)