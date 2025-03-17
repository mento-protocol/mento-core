# GoodDollarExchangeProvider impl
forge verify-contract --verifier etherscan --verifier-url https://api.celoscan.io/api --etherscan-api-key $CELOSCAN_KEY  0xfb1Cf4E85D82C4C90e33E5173d26cE558cB9de8e GoodDollarExchangeProvider --chain 42220 --constructor-args 0000000000000000000000000000000000000000000000000000000000000001 --optimizer-runs 200 --retries 1
forge verify-contract --verifier sourcify 0xfb1Cf4E85D82C4C90e33E5173d26cE558cB9de8e GoodDollarExchangeProvider --chain 42220 --constructor-args 0000000000000000000000000000000000000000000000000000000000000001 --optimizer-runs 200 --retries 1

# GoodDollarExpansionController impl 
forge verify-contract --verifier etherscan --verifier-url https://api.celoscan.io/api --etherscan-api-key $CELOSCAN_KEY  0xa42b24B3aAd1df1b4c5af3052ad1Ae8A3a2D1795 GoodDollarExpansionController --chain 42220 --constructor-args 0000000000000000000000000000000000000000000000000000000000000001 --optimizer-runs 200 --retries 1
forge verify-contract --verifier sourcify 0xa42b24B3aAd1df1b4c5af3052ad1Ae8A3a2D1795 GoodDollarExpansionController --chain 42220 --constructor-args 0000000000000000000000000000000000000000000000000000000000000001 --optimizer-runs 200 --retries 1

#reserve impl
forge verify-contract --verifier etherscan --verifier-url https://api.celoscan.io/api --etherscan-api-key $CELOSCAN_KEY  0xf78c12e6d3971cfc325a3b150fa4bb5ab8660c3f Reserve --chain 42220 --constructor-args 0000000000000000000000000000000000000000000000000000000000000001 --optimizer-runs 200 --retries 1
forge verify-contract --verifier sourcify 0xf78c12e6d3971cfc325a3b150fa4bb5ab8660c3f Reserve --chain 42220 --constructor-args 0000000000000000000000000000000000000000000000000000000000000001 --optimizer-runs 200 --retries 1

# broker impl
forge verify-contract --verifier etherscan --verifier-url https://api.celoscan.io/api --etherscan-api-key $CELOSCAN_KEY  0xa92Fb401f6aFBBF27338d4cE20322b102b35c51A Broker --chain 42220 --constructor-args 0000000000000000000000000000000000000000000000000000000000000001 --optimizer-runs 200 --retries 1
forge verify-contract --verifier sourcify 0xa92Fb401f6aFBBF27338d4cE20322b102b35c51A Broker --chain 42220 --constructor-args 0000000000000000000000000000000000000000000000000000000000000001 --optimizer-runs 200 --retries 1

# proxy admin
forge verify-contract --verifier etherscan --verifier-url https://api.celoscan.io/api --etherscan-api-key $CELOSCAN_KEY  0x8855a8e5b6717FE834ce673D110Bcf4f52B03aea ProxyAdmin --chain 42220 --optimizer-runs 200 --retries 1 --compiler-version 0.8.18
forge verify-contract --verifier sourcify 0x8855a8e5b6717FE834ce673D110Bcf4f52B03aea ProxyAdmin --chain 42220 --optimizer-runs 200 --retries 1 --compiler-version 0.8.18

# this will verify all transparentupgradeable proxies
forge verify-contract --verifier etherscan --verifier-url https://api.celoscan.io/api --etherscan-api-key $CELOSCAN_KEY  0x558ec7e55855fac9403de3adb3aa1e588234a92c TransparentUpgradeableProxy --chain 42220 --optimizer-runs 200 --retries 1 --compiler-version 0.8.18 --constructor-args 000000000000000000000000fb1cf4e85d82c4c90e33e5173d26ce558cb9de8e0000000000000000000000008855a8e5b6717fe834ce673d110bcf4f52b03aea00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000
forge verify-contract --verifier sourcify 0x558ec7e55855fac9403de3adb3aa1e588234a92c TransparentUpgradeableProxy --chain 42220 --optimizer-runs 200 --retries 1 --compiler-version 0.8.18 --constructor-args 000000000000000000000000fb1cf4e85d82c4c90e33e5173d26ce558cb9de8e0000000000000000000000008855a8e5b6717fe834ce673d110bcf4f52b03aea00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000

