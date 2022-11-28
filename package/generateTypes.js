const {runTypeChain,glob} = require('typechain')
const fs = require('fs');

async function main() {
  let cwd = process.cwd()
  cwd = cwd.replace("/package","")

  const interfacesPath = cwd + "/contracts/interfaces"

  let files = await fs.readdirSync(interfacesPath)
  files = files.map(file => { return file + "/" + file.replace("sol","json")})
  const allFiles = glob(cwd+"/out",files)

  const result = runTypeChain({
   cwd,
   filesToProcess: allFiles,
   allFiles,
   outDir: 'package/src',
   target: 'ethers-v5',
})
}
main().catch(console.error)