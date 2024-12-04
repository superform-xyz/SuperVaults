#!/usr/bin/env bash
# For accessing the secrets please create them in .env file as we use 1password
export SV_TENDERLY_VIRTUAL_MAINNET=$(op read op://5ylebqljbh3x6zomdxi3qd7tsa/SV_TENDERLY_VIRTUAL_MAINNET/credential)
export TENDERLY_VERIFIER_URL=$SV_TENDERLY_VIRTUAL_MAINNET/verify/etherscan
export TENDERLY_ACCESS_TOKEN=$(op read op://5ylebqljbh3x6zomdxi3qd7tsa/TENDERLY_SUPER_THAI_PROJ_API_KEY/credential)

constructor_arg="$(cast abi-encode 'constructor((address,address,address,address,string,uint256,uint256[],uint256[]))' '(0x17A332dC7B40aE701485023b219E9D6f493a2514,0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,0xde587D0C7773BD239fF1bE87d32C876dEd4f7879,0xde587D0C7773BD239fF1bE87d32C876dEd4f7879,SuperUSDC,1000000000000,[6277101738094410093849154803755231404199879241263958603447],[10000])')"


forge verify-contract 0x6515fCbB29891d7C62E0a83AD99C563d9e503114 "src/SuperVault.sol:SuperVault" --chain-id 1 \
    --num-of-optimizations 200 \
    --watch \
    --compiler-version v0.8.23+commit.f704f362 \
    --constructor-args "$constructor_arg" \
    --rpc-url $SV_TENDERLY_VIRTUAL_MAINNET \
    --verifier-url $TENDERLY_VERIFIER_URL \
    --etherscan-api-key $TENDERLY_ACCESS_TOKEN
