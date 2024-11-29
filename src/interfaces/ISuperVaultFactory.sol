// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title ISuperVaultFactory Interface
/// @notice Interface for the SuperVaultFactory contract
/// @author SuperForm Labs
interface ISuperVaultFactory {
    //////////////////////////////////////////////////////////////
    //                          ERRORS                          //
    //////////////////////////////////////////////////////////////

    /// @notice Error thrown when the pending management is not set
    error FAILED_TO_SET_PENDING_MANAGEMENT();

    /// @notice Error thrown when the performance fee is not set
    error FAILED_TO_SET_PERFORMANCE_FEE();

    /// @notice Error thrown when array lengths do not match
    error ARRAY_LENGTH_MISMATCH();

    /// @notice Error thrown when the number of superforms is zero
    error ZERO_SUPERFORMS();

    /// @notice Error thrown when the form implementation ID is zero
    error ZERO_FORM_IMPLEMENTATION_ID();

    /// @notice Error thrown when a zero address is provided
    error ZERO_ADDRESS();

    /// @notice Error thrown when the final superform IDs array is empty
    error EMPTY_FINAL_SUPERFORM_IDS();

    //////////////////////////////////////////////////////////////
    //                          EVENTS                          //
    //////////////////////////////////////////////////////////////

    /// @notice Emitted when a SuperVault is created
    /// @param superVault The address of the created SuperVault
    event SuperVaultCreated(address indexed superVault);

    //////////////////////////////////////////////////////////////
    //              EXTERNAL VIEW FUNCTIONS                     //
    //////////////////////////////////////////////////////////////

    /// @notice Returns all SuperVaults
    /// @return Number of SuperVaults
    function getNumberOfSuperVaults() external view returns (uint256);

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
    /// @param formImplementationId5115_ Form implementation ID for 5115
    function createSuperVault(
        address asset_,
        address strategist_,
        address vaultManager_,
        string memory name_,
        uint256 depositLimit_,
        uint256[] memory superformIds_,
        uint256[] memory startingWeights_,
        uint32 formImplementationId5115_
    )
        external
        returns (address superVault);
}
