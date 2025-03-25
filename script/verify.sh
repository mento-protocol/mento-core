# GoodDollarExchangeProvider impl
source .env.dev
forge verify-contract --verifier etherscan --verifier-url https://api.celoscan.io/api --etherscan-api-key $CELOSCAN_KEY  $EXCHANGEPROVIDER_IMPL GoodDollarExchangeProvider --chain 42220 --constructor-args 0000000000000000000000000000000000000000000000000000000000000000 --optimizer-runs 200 --retries 1
forge verify-contract --verifier sourcify $EXCHANGEPROVIDER_IMPL GoodDollarExchangeProvider --chain 42220 --constructor-args 0000000000000000000000000000000000000000000000000000000000000000 --optimizer-runs 200 --retries 1

# GoodDollarExpansionController impl 
forge verify-contract --verifier etherscan --verifier-url https://api.celoscan.io/api --etherscan-api-key $CELOSCAN_KEY  $EXPANSIONCONTROLLER_IMPL GoodDollarExpansionController --chain 42220 --constructor-args 0000000000000000000000000000000000000000000000000000000000000000 --optimizer-runs 200 --retries 1
forge verify-contract --verifier sourcify $EXPANSIONCONTROLLER_IMPL GoodDollarExpansionController --chain 42220 --constructor-args 0000000000000000000000000000000000000000000000000000000000000000 --optimizer-runs 200 --retries 1

#reserve impl
forge verify-contract --verifier etherscan --verifier-url https://api.celoscan.io/api --etherscan-api-key $CELOSCAN_KEY  $RESERVE_IMPL Reserve --chain 42220 --constructor-args 0000000000000000000000000000000000000000000000000000000000000000 --optimizer-runs 200 --retries 1
forge verify-contract --verifier sourcify $RESERVE_IMPL Reserve --chain 42220 --constructor-args 0000000000000000000000000000000000000000000000000000000000000000 --optimizer-runs 200 --retries 1

# broker impl
forge verify-contract --verifier etherscan --verifier-url https://api.celoscan.io/api --etherscan-api-key $CELOSCAN_KEY  $BROKER_IMPL Broker --chain 42220 --constructor-args 0000000000000000000000000000000000000000000000000000000000000000 --optimizer-runs 200 --retries 1
forge verify-contract --verifier sourcify $BROKER_IMPL Broker --chain 42220 --constructor-args 0000000000000000000000000000000000000000000000000000000000000000 --optimizer-runs 200 --retries 1

# proxy admin
forge verify-contract --verifier etherscan --verifier-url https://api.celoscan.io/api --etherscan-api-key $CELOSCAN_KEY  0x8855a8e5b6717FE834ce673D110Bcf4f52B03aea ProxyAdmin --chain 42220 --optimizer-runs 200 --retries 1 --compiler-version 0.8.18
forge verify-contract --verifier sourcify 0x8855a8e5b6717FE834ce673D110Bcf4f52B03aea ProxyAdmin --chain 42220 --optimizer-runs 200 --retries 1 --compiler-version 0.8.18

# # this will verify all transparentupgradeable proxies
forge verify-contract --verifier etherscan --verifier-url https://api.celoscan.io/api --etherscan-api-key $CELOSCAN_KEY  0x558ec7e55855fac9403de3adb3aa1e588234a92c TransparentUpgradeableProxy --chain 42220 --optimizer-runs 200 --retries 1 --compiler-version 0.8.18 --constructor-args 000000000000000000000000fb1cf4e85d82c4c90e33e5173d26ce558cb9de8e0000000000000000000000008855a8e5b6717fe834ce673d110bcf4f52b03aea00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000
forge verify-contract --verifier sourcify 0x558ec7e55855fac9403de3adb3aa1e588234a92c TransparentUpgradeableProxy --chain 42220 --optimizer-runs 200 --retries 1 --compiler-version 0.8.18 --constructor-args 000000000000000000000000fb1cf4e85d82c4c90e33e5173d26ce558cb9de8e0000000000000000000000008855a8e5b6717fe834ce673d110bcf4f52b03aea00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000
