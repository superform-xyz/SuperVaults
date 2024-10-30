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
    constructor(address superformFactory_) {
        superformFactory = superformFactory_;
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
}
