## Magical binary fixtures

`SortedOracles` is a contract that was developed initially in cLabs, temporarily take over 
forcefully by Mento Labs, and ultimate returned to cLabs for long term maintenance. We will not 
maintain in the context of this repo, any changes will need to happen in `celo-monorepo`.
We've moved away from having in-repo copies of `celo-monorepo` contracts, and instead utilize the
`@celo/contracts` npm package which exposes the needed contracts.

However, because of some limitations in Foundry it's impossible (at least from what I can tell) to
deploy contracts with linked libraries when they're not somewhere in the current project.
I managed to get that working when both SortedOracles and the library where in `mento-core`,
but I can't make it work with based off of the `@celo/contracts` npm package. So I took another route.

What's better than deploying code from Foundry artifacts? Deploying code from binary fixtures.

### How

There's a script in the repo `script/UpdateSortedOraclesFixture.sol` which is a `solc-0.5` script that:
1. Deploys SortedOracles (initializable).
2. Saves the deployed bytecode into a binary file.
3. Looks through the code for the library address, and logs it.
4. Saves the library deployed bytecode into a binary file.

And we have a test helper `test/utils/Fixtures.sol` that:
1. Reads the binary files.
2. Etches the library bytecode at the harcoded address from (3) above.
3. Etches the SortedOracles bytecode to a new address.

### How to update the fixtures

1. Update the `@celo/contracts` to the target version.
2. `forge clean && forge build` to make sure the SortedOracles artifact is up to date.
3. `cat out/SortedOracles.sol/SortedOracles.json | jq '.deployedBytecode.linkReferences'`
   Look through the output. There should be a single library `AddressSortedLinkedListWithMedian.sol`.
   The list of objects with `start` and `length` are positions in the SortedOracles bytecode where
   the library address will be linked. See the `start` value of the first offset.
4. Compare that with the constant in `UpdateSortedOraclesFixture`, and if needed update it.
5. `forge script UpdateSortedOraclesFixtures`
   It will log an address at the end, that is the linked library address.
6. Update the hardcoded `ASLLWMAddress` in `test/utils/Fixtures.sol`, with the address from (5).

!! DONE, YEY !! 

This shouldn't need to happen very often. There are ways to make this process nicer, but 
not warranted for how often SortedOracles will update in the future.
   










 
