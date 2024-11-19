# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env


# only export these env vars if ENVIRONMENT = local
ifeq ($(ENVIRONMENT), local)
	export ETHEREUM_RPC_URL = $(shell op read op://5ylebqljbh3x6zomdxi3qd7tsa/ETHEREUM_RPC_URL/credential)
	export BSC_RPC_URL := $(shell op read op://5ylebqljbh3x6zomdxi3qd7tsa/BSC_RPC_URL/credential)
	export AVALANCHE_RPC_URL := $(shell op read op://5ylebqljbh3x6zomdxi3qd7tsa/AVALANCHE_RPC_URL/credential)
	export POLYGON_RPC_URL := $(shell op read op://5ylebqljbh3x6zomdxi3qd7tsa/POLYGON_RPC_URL/credential)
	export ARBITRUM_RPC_URL := $(shell op read op://5ylebqljbh3x6zomdxi3qd7tsa/ARBITRUM_RPC_URL/credential)
	export OPTIMISM_RPC_URL := $(shell op read op://5ylebqljbh3x6zomdxi3qd7tsa/OPTIMISM_RPC_URL/credential)
	export BASE_RPC_URL := $(shell op read op://5ylebqljbh3x6zomdxi3qd7tsa/BASE_RPC_URL/credential)
	export FANTOM_RPC_URL := $(shell op read op://5ylebqljbh3x6zomdxi3qd7tsa/FANTOM_RPC_URL/credential)
	export LINEA_RPC_URL := $(shell op read op://5ylebqljbh3x6zomdxi3qd7tsa/LINEA_RPC_URL/credential)
	export BLAST_RPC_URL := $(shell op read op://5ylebqljbh3x6zomdxi3qd7tsa/BLAST_RPC_URL/credential)
	export BARTIO_RPC_URL := $(shell op read op://5ylebqljbh3x6zomdxi3qd7tsa/BARTIO_RPC_URL/credential)
	export ETHEREUM_RPC_URL_QN := $(shell op read op://5ylebqljbh3x6zomdxi3qd7tsa/ETHEREUM_RPC_URL/credential)
	export BSC_RPC_URL_QN := $(shell op read op://5ylebqljbh3x6zomdxi3qd7tsa/BSC_RPC_URL/credential)
	export AVALANCHE_RPC_URL_QN := $(shell op read op://5ylebqljbh3x6zomdxi3qd7tsa/AVALANCHE_RPC_URL/credential)
	export POLYGON_RPC_URL_QN := $(shell op read op://5ylebqljbh3x6zomdxi3qd7tsa/POLYGON_RPC_URL/credential)
	export ARBITRUM_RPC_URL_QN := $(shell op read op://5ylebqljbh3x6zomdxi3qd7tsa/ARBITRUM_RPC_URL/credential)
	export OPTIMISM_RPC_URL_QN := $(shell op read op://5ylebqljbh3x6zomdxi3qd7tsa/OPTIMISM_RPC_URL/credential)
	export BASE_RPC_URL_QN := $(shell op read op://5ylebqljbh3x6zomdxi3qd7tsa/BASE_RPC_URL/credential)
	export FANTOM_RPC_URL_QN := $(shell op read op://5ylebqljbh3x6zomdxi3qd7tsa/FANTOM_RPC_URL/credential)
	export SEPOLIA_RPC_URL_QN := $(shell op read op://5ylebqljbh3x6zomdxi3qd7tsa/SEPOLIA_RPC_URL/credential)
	export BSC_TESTNET_RPC_URL_QN := $(shell op read op://5ylebqljbh3x6zomdxi3qd7tsa/BSC_TESTNET_RPC_URL/credential)
	export LINEA_RPC_URL_QN := $(shell op read op://5ylebqljbh3x6zomdxi3qd7tsa/LINEA_RPC_URL/credential)
	export BLAST_RPC_URL_QN := $(shell op read op://5ylebqljbh3x6zomdxi3qd7tsa/BLAST_RPC_URL/credential)
	export BARTIO_RPC_URL_QN := $(shell op read op://5ylebqljbh3x6zomdxi3qd7tsa/BARTIO_RPC_URL/credential)

endif

# deps
install:; forge install
update:; forge update

# Build & test
build :; FOUNDRY_PROFILE=production forge build
build-sizes :; FOUNDRY_PROFILE=production forge build --sizes
test-vvv   :; forge test --match-test test_superVault_rebalance_5115 --evm-version cancun -vvv
ftest   :; forge test --evm-version cancun
coverage :; forge coverage  --evm-version cancun --report lcov
clean  :; forge clean
snapshot :; forge snapshot
fmt    :; forge fmt && forge fmt test/
