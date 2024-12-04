#!/usr/bin/env bash
# For accessing the secrets please create them in .env file as we use 1password

export ETHEREUM_RPC_URL=$(op read op://5ylebqljbh3x6zomdxi3qd7tsa/ETHEREUM_RPC_URL/credential)
export BASE_RPC_URL=$(op read op://5ylebqljbh3x6zomdxi3qd7tsa/BASE_RPC_URL/credential)
export SV_TENDERLY_VIRTUAL_MAINNET=$(op read op://5ylebqljbh3x6zomdxi3qd7tsa/SV_TENDERLY_VIRTUAL_MAINNET/credential)

export TENDERLY_VERIFIER_URL_VNET=$SV_TENDERLY_VIRTUAL_MAINNET/verify/etherscan
export TENDERLY_ACCESS_TOKEN=$(op read op://5ylebqljbh3x6zomdxi3qd7tsa/TENDERLY_SUPER_THAI_PROJ_API_KEY/credential)
export BASESCAN_API_KEY=$(op read op://5ylebqljbh3x6zomdxi3qd7tsa/BASESCAN_API_KEY/credential)

constructor_arg_vnet="$(cast abi-encode 'constructor((address,address,address,address,string,uint256,uint256[],uint256[]))' '(0x17A332dC7B40aE701485023b219E9D6f493a2514,0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,0xde587D0C7773BD239fF1bE87d32C876dEd4f7879,0xde587D0C7773BD239fF1bE87d32C876dEd4f7879,SuperUSDC,1000000000000,[6277101738094410093849154803755231404199879241263958603447],[10000])')"


forge verify-contract 0xeaebe7eaec84585cfd1b38cc6c5b74fc0de74af1 "src/SuperVault.sol:SuperVault" --chain-id 95 \
    --num-of-optimizations 200 \
    --watch \
    --compiler-version v0.8.23 \
    --constructor-args "$constructor_arg_vnet" \
    --rpc-url $SV_TENDERLY_VIRTUAL_MAINNET \
    --verifier-url $TENDERLY_VERIFIER_URL_VNET \
    --etherscan-api-key $TENDERLY_ACCESS_TOKEN

# constructor_arg_prod="$(cast abi-encode 'constructor((address,address,address,address,string,uint256,uint256[],uint256[]))' '(0x17A332dC7B40aE701485023b219E9D6f493a2514,0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,0x01d9944787045A431DA61F3be137Ba07b5dd8d6C,0x01d9944787045A431DA61F3be137Ba07b5dd8d6C,SuperUSDC,1000000000000,[53060340969226327679691964126799737454608928190443144923035525],[10000])')"

# export NETWORK_ID=95
# export TENDERLY_VERIFIER_URL_PROD=https://api.tenderly.co/api/v1/account/superform/project/v1/etherscan/verify/network/$NETWORK_ID

# forge verify-contract 0x369b2d0c701f791645ECF40F14d390F69A6023E3 "src/SuperVault.sol:SuperVault" --chain-id $NETWORK_ID \
#     --num-of-optimizations 200 \
#     --watch \
#     --rpc-url $SV_TENDERLY_VIRTUAL_MAINNET \
#     --verifier-url $TENDERLY_VERIFIER_URL_VNET \
#     --etherscan-api-key $TENDERLY_ACCESS_TOKEN
