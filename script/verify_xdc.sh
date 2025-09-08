# GoodDollarExchangeProvider impl
source .env
forge verify-contract --verifier etherscan --verifier-url https://rpc.xinfin.network --etherscan-api-key $CELOSCAN_KEY  $EXCHANGEPROVIDER_IMPL GoodDollarExchangeProvider --chain 50 --constructor-args 0000000000000000000000000000000000000000000000000000000000000000 --optimizer-runs 200 --retries 1
forge verify-contract --verifier sourcify $EXCHANGEPROVIDER_IMPL GoodDollarExchangeProvider --chain 50 --constructor-args 0000000000000000000000000000000000000000000000000000000000000000 --optimizer-runs 200 --retries 1

# GoodDollarExpansionController impl 
forge verify-contract --verifier etherscan --verifier-url https://rpc.xinfin.network --etherscan-api-key $CELOSCAN_KEY  $EXPANSIONCONTROLLER_IMPL GoodDollarExpansionController --chain 50 --constructor-args 0000000000000000000000000000000000000000000000000000000000000000 --optimizer-runs 200 --retries 1
forge verify-contract --verifier sourcify $EXPANSIONCONTROLLER_IMPL GoodDollarExpansionController --chain 50 --constructor-args 0000000000000000000000000000000000000000000000000000000000000000 --optimizer-runs 200 --retries 1

#registry impl
forge verify-contract --verifier etherscan --verifier-url https://rpc.xinfin.network --etherscan-api-key $CELOSCAN_KEY  $RESERVE_IMPL Reserve --chain 50 --constructor-args 0000000000000000000000000000000000000000000000000000000000000000 --optimizer-runs 200 --retries 1
forge verify-contract --verifier sourcify $REGISTRY_IMPL Reserve --chain 50 --constructor-args 0000000000000000000000000000000000000000000000000000000000000000 --optimizer-runs 200 --retries 1

#reserve impl
forge verify-contract --verifier etherscan --verifier-url https://rpc.xinfin.network --etherscan-api-key $CELOSCAN_KEY  $RESERVE_IMPL Reserve --chain 50 --constructor-args 0000000000000000000000000000000000000000000000000000000000000000 --optimizer-runs 200 --retries 1
forge verify-contract --verifier sourcify $RESERVE_IMPL Reserve --chain 50 --constructor-args 0000000000000000000000000000000000000000000000000000000000000000 --optimizer-runs 200 --retries 1

# broker impl
forge verify-contract --verifier etherscan --verifier-url https://rpc.xinfin.network --etherscan-api-key $CELOSCAN_KEY  $BROKER_IMPL Broker --chain 50 --constructor-args 0000000000000000000000000000000000000000000000000000000000000000 --optimizer-runs 200 --retries 1
forge verify-contract --verifier sourcify $BROKER_IMPL Broker --chain 50 --constructor-args 0000000000000000000000000000000000000000000000000000000000000000 --optimizer-runs 200 --retries 1

# proxy admin
forge verify-contract --verifier etherscan --verifier-url https://rpc.xinfin.network --etherscan-api-key $CELOSCAN_KEY  0x54f44fBE2943c2196D94831288E716cdeAF56579 ProxyAdmin --chain 50 --optimizer-runs 200 --retries 1 --compiler-version 0.8.18
forge verify-contract --verifier sourcify 0x54f44fBE2943c2196D94831288E716cdeAF56579 ProxyAdmin --chain 50 --optimizer-runs 200 --retries 1 --compiler-version 0.8.18

# # this will verify all transparentupgradeable proxies
forge verify-contract --verifier etherscan --verifier-url https://rpc.xinfin.network --etherscan-api-key $CELOSCAN_KEY  0x34f260FcCe222afF0DA07ED12E239af38A144682 TransparentUpgradeableProxy --chain 50 --optimizer-runs 200 --retries 1 --compiler-version 0.8.18 --constructor-args 000000000000000000000000fb1cf4e85d82c4c90e33e5173d26ce558cb9de8e0000000000000000000000008855a8e5b6717fe834ce673d110bcf4f52b03aea00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000
forge verify-contract --verifier sourcify 0x34f260FcCe222afF0DA07ED12E239af38A144682 TransparentUpgradeableProxy --chain 50 --optimizer-runs 200 --retries 1 --compiler-version 0.8.18 --constructor-args 000000000000000000000000fb1cf4e85d82c4c90e33e5173d26ce558cb9de8e0000000000000000000000008855a8e5b6717fe834ce673d110bcf4f52b03aea00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000
