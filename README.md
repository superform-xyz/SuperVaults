# SuperVaults

SuperVaults is a smart contract project for managing and optimizing decentralized finance (DeFi) positions across multiple protocols.

The SuperVault contract adheres to the `ERC-4626` standard, with additional functions to support dynamic rebalancing and other operational activities.

## Overview

SuperVaults allow users to deposit assets and automatically distribute them across various DeFi protocols (Superforms) to optimize yield and manage risk. The project includes features such as:

- Deposit and withdrawal of assets
- Automatic rebalancing of positions
- Yield optimization across multiple protocols
- Risk management through diversification

**Note:** SuperVaults only operates with underlying Superforms that are on the same chain and have the same underlying asset.

## Key Components
- `SuperVaultFactory.sol`: Factory contract for creating and managing SuperVaults
- `SuperVault.sol`: Main contract for managing user deposits and interactions with Superforms

## Getting Started

1. Clone the repository
2. Install dependencies: `forge install`
3. Compile contracts: `make build`

## Tests

Step by step instructions on setting up the project and running it

1. Make sure Foundry is installed with the following temporary workarounds (see: https://github.com/foundry-rs/foundry/issues/8014)

- For minimal ram usage, do `foundryup -v  nightly-f625d0fa7c51e65b4bf1e8f7931cd1c6e2e285e9`
- For compatibility with safe signing operations do `foundryup -v  nightly-ea2eff95b5c17edd3ffbdfc6daab5ce5cc80afc0`

2. Set the rpc variables in the makefile using your own nodes and disable any instances that run off 1password

```
POLYGON_RPC_URL=
AVALANCHE_RPC_URL=
FANTOM_RPC_URL=
BSC_RPC_URL=
ARBITRUM_RPC_URL=
OPTIMISM_RPC_URL=
ETHEREUM_RPC_URL=
BASE_RPC_URL=
FANTOM_RPC_URL=
```

## Project structure

    .
    ├── script
    ├── security-review
    ├── src
      ├── interfaces
        ├── ISuperVault.sol
        ├── ISuperVaultFactory.sol
      ├── SuperVault.sol
      ├── SuperVaultFactory.sol
    ├── test
    ├── foundry.toml
    ├── Makefile
    └── README.md

- `script` contains deployment and utility scripts and outputs [`/script`](./script)
- `security-review` contains information relevant to prior security reviews[`/security-review`](./security-review)
- `src` is the source folder for all smart contract code[`/src`](./src)
  - `interfaces` define interactions with other contracts [`/src/interfaces`](./src/interfaces)
  - `SuperVault.sol` and `SuperVaultFactory.sol` define the core functionality of the SuperVaults [`/src/SuperVault.sol`](./src/SuperVault.sol) and [`/src/SuperVaultFactory.sol`](./src/SuperVaultFactory.sol)
- `test` contains tests for contracts in src [`/test`](./test)

## Usage

### Deposit Flow

1. Users can view the available deposit limit for a SuperVault by calling the `availableDepositLimit()` function
2. A user sends `ERC20` tokens (e.g., USDC) to the SuperformRouter contract.
3. The `SuperformRouter` contract deposits these tokens into the SuperVault via its Superform contract.
4. The `SuperVault` contract makes a multi-deposit into its underlying vaults through the `SuperformRouter` contract.
5. The `SuperVault` mints shares based on the received `SuperPositions` (SPs) and sends them to its `Superform` contract.
    - The `Superform` contract mints SPs at a 1:1 ratio corresponding to the received `SuperVault` shares.
    - The user receives the `SuperVault` SPs in their wallet or smart wallet.

### Withdrawal Flow

1. A user initiates the withdrawal process by sending a transaction to the `SuperformRouter` contract with a specified amount of SPs.
2. The `SuperformRouter` contract burns the given amount of SPs and initiates the withdrawal from the `SuperVault` via its `Superform` contract.
3. The `SuperVault` withdraws the corresponding funds from its underlying vaults and sends the funds back to the user.

### Rebalance Flow

1. The Keeper obtains the total value of the `SuperVault`’s underlying vaults.
2. The Keeper calculates the current share prices based on the assets in the underlying vaults and their current APYs.
3. The Keeper determines the amounts to be deposited into and withdrawn from the underlying vaults, based on share prices, predefined coefficients in the `SuperVault`, and current allocations.
4. The Keeper sends a transaction to the `SuperVault` to initiate the rebalancing process, including all necessary data for the rebalance.
5. The `SuperVault` executes the rebalancing using the `SuperformRouterWrapper` contract.

## Resources

- [Twitter](https://twitter.com/superformxyz)
- [Website](https://www.superform.xyz/)
- [Technical Documentation](https://docs.superform.xyz)

## Contributing

Contributions are welcome! Please fork the repository and submit a pull request with your changes.

## License
MIT License
