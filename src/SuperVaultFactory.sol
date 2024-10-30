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
}