#!/usr/bin/env bash
# For accessing the secrets please create them in .env file as we use 1password

export ETHEREUM_RPC_URL=$(op read op://5ylebqljbh3x6zomdxi3qd7tsa/ETHEREUM_RPC_URL/credential)
export BSC_RPC_URL=$(op read op://5ylebqljbh3x6zomdxi3qd7tsa/BSC_RPC_URL/credential)
export AVALANCHE_RPC_URL=$(op read op://5ylebqljbh3x6zomdxi3qd7tsa/AVALANCHE_RPC_URL/credential)
export POLYGON_RPC_URL=$(op read op://5ylebqljbh3x6zomdxi3qd7tsa/POLYGON_RPC_URL/credential)
export ARBITRUM_RPC_URL=$(op read op://5ylebqljbh3x6zomdxi3qd7tsa/ARBITRUM_RPC_URL/credential)
export OPTIMISM_RPC_URL=$(op read op://5ylebqljbh3x6zomdxi3qd7tsa/OPTIMISM_RPC_URL/credential)
export BASE_RPC_URL=$(op read op://5ylebqljbh3x6zomdxi3qd7tsa/BASE_RPC_URL/credential)
export FANTOM_RPC_URL=$(op read op://5ylebqljbh3x6zomdxi3qd7tsa/FANTOM_RPC_URL/credential)
export SV_TENDERLY_VIRTUAL_MAINNET=$(op read op://5ylebqljbh3x6zomdxi3qd7tsa/SV_TENDERLY_VIRTUAL_MAINNET/credential)

# Run the script
echo Deploying super vault factory: ...

forge script script/forge-scripts/Deploy.SuperVaultFactory.s.sol:MainnetDeploySuperVaultFactory --sig "deploySuperVaultFactory(uint256,uint256)" 2 1 --rpc-url $SV_TENDERLY_VIRTUAL_MAINNET --account default --sender 0x48aB8AdF869Ba9902Ad483FB1Ca2eFDAb6eabe92  --unlocked


