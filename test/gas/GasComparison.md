##### Gas Comparison

`/test/gas/BrokerGas.t.sol` contains simple swap tests to estimate gas usage. You can get an overview with

`forge test --match-contract BrokerGasTest` and
`forge test --match-contract BrokerGasTest --gas-report`

or a more detailed view of gas usage by function call with

`forge test --match-contract BrokerGasTest -vvvv` or for single tests
`forge test --match-test ${TEST_NAME} -vvvvv`.

##### How to compare gas usage

To compare feature additions and code changes, you can run `/test/gas/BrokerGas.t.sol` on different branches and compare the gas estimates manually.

##### Historical Exchange Gas usage

Mento V1 contracts take around 25% more gas for simple swaps from a Stable to CELO. You can run the gas estimation by
`forge test --match-contract ExchangeGasTest -vvvv` or for single tests
`forge test --match-test ${TEST_NAME} -vvvvv`.

###### 2022/11/21 gas report

Broker.sol
[PASS] test_gas_swapIn_CELOTocEUR() (gas: 170792)
[PASS] test_gas_swapIn_CELOTocUSD() (gas: 170790)
[PASS] test_gas_swapIn_CEURToCelo() (gas: 229310)
[PASS] test_gas_swapIn_CUSDToCelo() (gas: 229311)
[PASS] test_gas_swapIn_cUSDTocEUR() (gas: 200882)
[PASS] test_gas_swapIn_cEURTocUSD() (gas: 200965)
[PASS] test_gas_swapIn_cUSDToUSDCet() (gas: 246431)
[PASS] test_gas_swapIn_cEURToUSDCet() (gas: 246410)

- test_gas_swapIn_CELOTocUSD: [112366] Broker::swapIn

Exchange.sol
[PASS] test_gas_sell_CELO_for_cEUR() (gas: 207711)
[PASS] test_gas_sell_CELO_for_cUSD() (gas: 207752)
[PASS] test_gas_sell_cEUR_for_CELO() (gas: 257494)
[PASS] test_gas_sell_cUSD_for_CELO() (gas: 261958)

- test_gas_sell_CELO_for_cUSD: [140569] 0x67316300f17f063085Ca8bCa4bd3f7a5a3C66275::sell
