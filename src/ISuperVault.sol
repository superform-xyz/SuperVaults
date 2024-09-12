// SPDX-License-Identifier: UNLICENSED
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
        uint256[] superformIds;
        uint256[] weights;
    }

    //////////////////////////////////////////////////////////////
    //                  ERRORS                                   //
    //////////////////////////////////////////////////////////////

    /// @notice Error thrown when array lengths do not match
    error ARRAY_LENGTH_MISMATCH();

    /// @notice Error thrown when invalid weights are provided
    error INVALID_WEIGHTS();

    /// @notice Error thrown when the caller is not the Super Vaults strategist
    error NOT_SUPER_VAULTS_STRATEGIST();

    /// @notice Error thrown when a zero address is provided
    error ZERO_ADDRESS();

    /// @notice Error thrown when a superform does not support the asset
    error SUPERFORM_DOES_NOT_SUPPORT_ASSET();

    /// @notice Error thrown when the block chain ID is out of bounds
    error BLOCK_CHAIN_ID_OUT_OF_BOUNDS();

    /// @notice Error thrown when a duplicate superform ID is provided
    error DUPLICATE_SUPERFORM_ID();

    //////////////////////////////////////////////////////////////
    //                  EVENTS                                   //
    //////////////////////////////////////////////////////////////

    /// @notice Emitted when the refunds receiver is set
    /// @param refundReceiver The address of the refunds receiver
    event RefundsReceiverSet(address refundReceiver);

    /// @notice Emitted when the SuperVault is rebalanced
    /// @param finalWeights Array of final weights of the SuperVault
    event Rebalanced(uint256[] finalWeights);

    //////////////////////////////////////////////////////////////
    //                  EXTERNAL  FUNCTIONS                     //
    //////////////////////////////////////////////////////////////

    /// @notice Rebalances the SuperVault
    /// @dev TODO slippage per vault?
    /// @param superformIdsRebalanceFrom Array of superform IDs to rebalance from
    /// @param amountsRebalanceFrom Array of amounts to rebalance from each superform
    /// @param superformIdsRebalanceTo Array of superform IDs to rebalance to
    /// @param weightsOfRedestribution Array of weights for redistribution
    /// @param rebalanceFromMsgValue Message value for rebalancing from
    /// @param rebalanceToMsgValue Message value for rebalancing to
    /// @param slippage Slippage tolerance for the rebalance
    function rebalance(
        uint256[] memory superformIdsRebalanceFrom,
        uint256[] memory amountsRebalanceFrom,
        uint256[] memory superformIdsRebalanceTo,
        uint256[] memory weightsOfRedestribution,
        uint256 rebalanceFromMsgValue,
        uint256 rebalanceToMsgValue,
        uint256 slippage
    )
        external
        payable;
}
