// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { SuperVault } from "./SuperVault.sol";
import { ISuperVaultFactory } from "./ISuperVaultFactory.sol";
import { BaseStrategy } from "tokenized-strategy/BaseStrategy.sol";
import { ISuperformFactory } from "superform-core/src/interfaces/ISuperformFactory.sol";
import { ISuperRegistry } from "superform-core/src/interfaces/ISuperRegistry.sol";

/// @title SuperVaultFactory
/// @notice Factory for creating SuperVaults
/// @author SuperForm Labs
contract SuperVaultFactory is ISuperVaultFactory {
    //////////////////////////////////////////////////////////////
    //                     STATE VARIABLES                      //
    //////////////////////////////////////////////////////////////

    /// @notice Address of the SuperformFactory
    address public immutable superformFactory;

    //////////////////////////////////////////////////////////////
    //                       MODIFIERS                          //
    //////////////////////////////////////////////////////////////

    /// @notice Ensures that the caller is the SuperVaults Manager
    modifier onlySuperVaultsManager() {
        if (_getAddress(keccak256("SUPER_VAULTS_MANAGER")) != msg.sender) {
            revert NOT_SUPER_VAULTS_MANAGER();
        }
        _;
    }

    //////////////////////////////////////////////////////////////
    //                       CONSTRUCTOR                        //
    //////////////////////////////////////////////////////////////

    /// @param superformFactory_ Address of the SuperformFactory
    constructor(
        address superformFactory_,
        address superRegistry_
    ) {
        superformFactory = superformFactory_;
        superRegistry = superRegistry_;
    }

    //////////////////////////////////////////////////////////////
    //                     EXTERNAL WRITE FUNCTIONS              //
    //////////////////////////////////////////////////////////////

    /// @inheritdoc ISuperVaultFactory
    function createSuperVault(
        address superRegistry_,
        address asset_,
        string memory name_,
        uint256 depositLimit_,
        uint256[] memory superformIds_,
        uint256[] memory startingWeights_
    ) external returns (address) {
        // TODO: Implement
    }

    //////////////////////////////////////////////////////////////
    //                     EXTERNAL VIEW FUNCTIONS              //
    //////////////////////////////////////////////////////////////

    /// @inheritdoc ISuperVaultFactor
    function getSuperVaultCount() external view returns (uint256) {
        // TODO: Implement
    }

    /// @inheritdoc ISuperVaultFactory
    function getSuperVaultAsset(address superVault_) external view returns (address) {
        // TODO: Implement
    }

    /// @inheritdoc ISuperVaultFactory
    function getSuperformIds(address superVault_) external view returns (uint256[] memory) {
        // TODO: Implement
    }

    /// @inheritdoc ISuperVaultFactory
    function getSuperVaultStartingWeights(address superVault_) external view returns (uint256[] memory) {
        // TODO: Implement
    }

    /// @inheritdoc ISuperVaultFactory
    function getSuperVaultDepositLimit(address superVault_) external view returns (uint256) {
        // TODO: Implement
    }

    /// @inheritdoc ISuperVaultFactory
    function getSuperVaultName(address superVault_) external view returns (string memory) {
        // TODO: Implement
    }

    //////////////////////////////////////////////////////////////
    //                       INTERNAL FUNCTIONS                  //
    //////////////////////////////////////////////////////////////

    /// @dev returns the address for id_ from super registry
    function _getAddress(bytes32 id_) internal view returns (address) {
        return superRegistry.getAddress(id_);
    }
}
