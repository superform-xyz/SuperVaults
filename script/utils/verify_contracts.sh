#!/usr/bin/env bash
# For accessing the secrets please create them in .env file as we use 1password
export SV_TENDERLY_VIRTUAL_MAINNET=$(op read op://5ylebqljbh3x6zomdxi3qd7tsa/SV_TENDERLY_VIRTUAL_MAINNET/credential)
export TENDERLY_VERIFIER_URL=$SV_TENDERLY_VIRTUAL_MAINNET/verify/etherscan
export TENDERLY_ACCESS_TOKEN=$(op read op://5ylebqljbh3x6zomdxi3qd7tsa/TENDERLY_SUPER_THAI_PROJ_API_KEY/credential)

forge verify-contract 0x241C5B23374E01Ef5C55b1B0405C09c9d25Ce75e "src/SuperVault.sol:SuperVault" --chain-id 1 \
    --num-of-optimizations 200 \
    --watch \
    --compiler-version v0.8.23+commit.f704f362 \
    --guess-constructor-args \
    --rpc-url $SV_TENDERLY_VIRTUAL_MAINNET \
    --verifier-url $TENDERLY_VERIFIER_URL \
    --etherscan-api-key $TENDERLY_ACCESS_TOKEN
