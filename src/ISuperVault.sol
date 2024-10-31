// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IERC1155Receiver } from "openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol";

/// @title ISuperVault Interface
/// @notice Interface for the SuperVault contract
interface ISuperVault is IERC1155Receiver {
    //////////////////////////////////////////////////////////////
    //                  STRUCTS                                   //
    //////////////////////////////////////////////////////////////

    /// @notice Struct to hold SuperVault strategy data
    struct SuperVaultStrategyData {
        uint256 numberOfSuperforms;
        uint256 depositLimit;
        uint256[] superformIds;
        uint256[] weights;
    }

    /// @notice Struct to hold rebalance arguments
    /// @notice superformIdsRebalanceFrom must be an ordered array of superform IDs with no duplicates
    /// @param superformIdsRebalanceFrom Array of superform IDs to rebalance from
    /// @param amountsRebalanceFrom Array of amounts to rebalance from each superform
    /// @param finalSuperformIds Array of final superform IDs
    /// @param weightsOfRedestribution Array of weights for redistribution
    /// @param slippage Slippage tolerance for the rebalance
    struct RebalanceArgs {
        uint256[] superformIdsRebalanceFrom;
        uint256[] amountsRebalanceFrom;
        uint256[] finalSuperformIds;
        uint256[] weightsOfRedestribution;
        uint256 slippage;
    }

    //////////////////////////////////////////////////////////////
    //                  ERRORS                                   //
    //////////////////////////////////////////////////////////////

    /// @notice Error thrown when no superforms are provided in constructor
    error ZERO_SUPERFORMS();

    /// @notice Error thrown when duplicate superform IDs to rebalance from are provided
    error DUPLICATE_SUPERFORM_IDS_REBALANCE_FROM();

    /// @notice Error thrown when duplicate final superform IDs are provided
    error DUPLICATE_FINAL_SUPERFORM_IDS();

    /// @notice Error thrown when array lengths do not match
    error ARRAY_LENGTH_MISMATCH();

    /// @notice Error thrown when invalid weights are provided
    error INVALID_WEIGHTS();

    /// @notice Error thrown when the caller is not the Super Vaults strategist
    error NOT_SUPER_VAULTS_STRATEGIST();

    /// @notice Error thrown when the amounts to rebalance from array is empty
    error EMPTY_AMOUNTS_REBALANCE_FROM();

    /// @notice Error thrown when the final superform IDs array is empty
    error EMPTY_FINAL_SUPERFORM_IDS();

    /// @notice Error thrown when a superform does not support the asset
    error SUPERFORM_DOES_NOT_SUPPORT_ASSET();

    /// @notice Error thrown when the block chain ID is out of bounds
    error BLOCK_CHAIN_ID_OUT_OF_BOUNDS();

    /// @notice Error thrown when a superform does not exist
    error SUPERFORM_DOES_NOT_EXIST(uint256 superformId);

    /// @notice Error thrown when a superform ID is invalid
    error INVALID_SUPERFORM_ID_REBALANCE_FROM();

    /// @notice Error thrown when a superform ID is not found in the final superform IDs
    error REBALANCE_FROM_ID_NOT_FOUND_IN_FINAL_IDS();

    /// @notice Error thrown when the caller is not the pending management
    error NOT_PENDING_MANAGEMENT();

    //////////////////////////////////////////////////////////////
    //                  EVENTS                                   //
    //////////////////////////////////////////////////////////////

    /// @notice Emitted when the SuperVault is rebalanced
    /// @param finalSuperformIds Array of final superform IDs of the SuperVault
    /// @param finalWeights Array of final weights of the SuperVault
    event RebalanceComplete(uint256[] finalSuperformIds, uint256[] finalWeights);

    /// @notice Emitted when the deposit limit is set
    /// @param depositLimit The new deposit limit
    event DepositLimitSet(uint256 depositLimit);

    /// @notice Emitted when dust is forwarded to the paymaster
    /// @param dust The amount of dust forwarded
    event DustForwardedToPaymaster(uint256 dust);

    /// @notice Emitted when the strategist is set
    /// @param strategist The new strategist
    event StrategistSet(address strategist);

    /// @notice Emitted when the management is updated
    /// @param management The new management
    event ManagementUpdated(address management);

    //////////////////////////////////////////////////////////////
    //                 EXTERNAL VIEW/PURE FUNCTIONS             //
    //////////////////////////////////////////////////////////////

    /// @notice Returns the SuperVault data
    /// @return numberOfSuperforms The number of Superforms
    /// @return superformIds Array of Superform IDs
    /// @return weights Array of weights for each Superform
    function getSuperVaultData()
        external
        view
        returns (uint256 numberOfSuperforms, uint256[] memory superformIds, uint256[] memory weights);

    //////////////////////////////////////////////////////////////
    //                  EXTERNAL  FUNCTIONS                     //
    //////////////////////////////////////////////////////////////

    /// @notice Rebalances the SuperVault
    /// @notice rebalanceArgs_.superformIdsRebalanceFrom must be an ordered array of superform IDs with no duplicates
    /// @notice the logic is as follows:
    /// select the ids to rebalance from
    /// send an amount to take from those ids
    /// the total underlying asset amount is redestributed according to the desired weights
    function rebalance(RebalanceArgs memory rebalanceArgs_) external payable;

    /// @notice Forwards dust to the paymaster
    function forwardDustToPaymaster() external;
}
