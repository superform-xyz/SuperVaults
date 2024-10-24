#!/usr/bin/env bash

export ETHEREUM_RPC_URL=$(op read op://5ylebqljbh3x6zomdxi3qd7tsa/ETHEREUM_RPC_URL/credential)
export BSC_RPC_URL=$(op read op://5ylebqljbh3x6zomdxi3qd7tsa/BSC_RPC_URL/credential)
export AVALANCHE_RPC_URL=$(op read op://5ylebqljbh3x6zomdxi3qd7tsa/AVALANCHE_RPC_URL/credential)
export POLYGON_RPC_URL=$(op read op://5ylebqljbh3x6zomdxi3qd7tsa/POLYGON_RPC_URL/credential)
export ARBITRUM_RPC_URL=$(op read op://5ylebqljbh3x6zomdxi3qd7tsa/ARBITRUM_RPC_URL/credential)
export OPTIMISM_RPC_URL=$(op read op://5ylebqljbh3x6zomdxi3qd7tsa/OPTIMISM_RPC_URL/credential)
export BASE_RPC_URL=$(op read op://5ylebqljbh3x6zomdxi3qd7tsa/BASE_RPC_URL/credential)
export FANTOM_RPC_URL=$(op read op://5ylebqljbh3x6zomdxi3qd7tsa/FANTOM_RPC_URL/credential)
<<c
Run the script
echo Deploying super vault: ...

forge script script/forge-scripts/Deploy.SuperVault.s.sol:MainnetDeploySuperVault --sig "deploySuperVault(bool,uint256)" true 8453 --rpc-url $BASE_RPC_URL --legacy --account default --sender 0x48aB8AdF869Ba9902Ad483FB1Ca2eFDAb6eabe92 --broadcast
c

forge script script/forge-scripts/Deploy.SuperVault.s.sol:MainnetDeploySuperVault --sig "setStrategist(bool,uint256)" true 8453 --rpc-url $BASE_RPC_URL --legacy --account default --sender 0x48aB8AdF869Ba9902Ad483FB1Ca2eFDAb6eabe92 --broadcast
