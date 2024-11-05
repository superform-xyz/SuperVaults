// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ISuperVault } from "./ISuperVault.sol";

/// @title ISuperVaultFactory Interface
/// @notice Interface for the SuperVaultFactory contract
/// @author SuperForm Labs
interface ISuperVaultFactory {
    //////////////////////////////////////////////////////////////
    //                          ERRORS                          //
    //////////////////////////////////////////////////////////////

    /// @notice Error thrown when the caller is not the management role
    error NOT_MANAGEMENT();

    /// @notice Error thrown when the pending management is not set
    error FAILED_TO_SET_PENDING_MANAGEMENT();

    /// @notice Error thrown when duplicate final superform IDs are provided
    error DUPLICATE_FINAL_SUPERFORM_IDS();

    /// @notice Error thrown when array lengths do not match
    error ARRAY_LENGTH_MISMATCH();

    /// @notice Error thrown when the number of superforms is zero
    error ZERO_SUPERFORMS();

    /// @notice Error thrown when the caller is not the Super Vaults strategist
    error NOT_SUPER_VAULTS_STRATEGIST();

    /// @notice Error thrown when a zero address is provided
    error ZERO_ADDRESS();

    /// @notice Error thrown when the final superform IDs array is empty
    error EMPTY_FINAL_SUPERFORM_IDS();

    /// @notice Error thrown when the block chain ID is out of bounds
    error BLOCK_CHAIN_ID_OUT_OF_BOUNDS();

    //////////////////////////////////////////////////////////////
    //                          EVENTS                          //
    //////////////////////////////////////////////////////////////

    /// @notice Emitted when a new SuperVault is created
    /// @param superVault Address of the SuperVault
    event SuperVaultCreated(address indexed superVault);

    /// @notice Emitted when the strategist for a SuperVault is updated
    /// @param superVault Address of the SuperVault
    /// @param strategist Address of the strategist
    event VaultStrategistUpdated(address indexed superVault, address indexed strategist);

    /// @dev emitted when a new SuperRegistry is set
    /// @param superRegistry is the address of the super registry
    event SuperRegistrySet(address indexed superRegistry);

    //////////////////////////////////////////////////////////////
    //              EXTERNAL VIEW FUNCTIONS                     //
    //////////////////////////////////////////////////////////////

    /// @notice Returns whether a SuperVault exists
    /// @param superVault_ Address of the SuperVault
    /// @return Whether the SuperVault exists
    function isSuperVault(address superVault_) external view returns (bool);

    /// @notice Returns all SuperVaults
    /// @return Array of SuperVault addresses
    //function getSuperVaults() external view returns (address[] memory);

    /// @notice Returns the number of SuperVaults
    /// @return Number of SuperVaults
    function getSuperVaultCount() external view returns (uint256);

    //////////////////////////////////////////////////////////////
    //              EXTERNAL WRITE FUNCTIONS                    //
    //////////////////////////////////////////////////////////////

    /// @notice Creates a new SuperVault
    /// @dev Sets pending management to deployer, deployer will have to accept management in SuperVault
    /// @param asset_ Address of the asset token
    /// @param strategist_ Address of the strategist
    /// @param vaultManager_ Address of the vault manager
    /// @param name_ Name of the strategy
    /// @param depositLimit_ Maximum deposit limit
    /// @param superformIds_ Array of Superform IDs
    /// @param startingWeights_ Array of starting weights for each Superform
    function createSuperVault(
        address asset_,
        address strategist_,
        address vaultManager_,
        string memory name_,
        uint256 depositLimit_,
        uint256[] memory superformIds_,
        uint256[] memory startingWeights_
    )
        external
        returns (address);
}
