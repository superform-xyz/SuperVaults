// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { SuperVault } from "./SuperVault.sol";
import { ISuperVault } from "./ISuperVault.sol";
import { ISuperVaultFactory } from "./ISuperVaultFactory.sol";
import { BaseStrategy } from "tokenized-strategy/BaseStrategy.sol";
import { IBaseForm } from "superform-core/src/interfaces/IBaseForm.sol";
import { ISuperformFactory } from "superform-core/src/interfaces/ISuperformFactory.sol";
import { ISuperRegistry } from "superform-core/src/interfaces/ISuperRegistry.sol";

/// @title SuperVaultFactory
/// @notice Factory for creating SuperVaults
/// @author SuperForm Labs
contract SuperVaultFactory is BaseStrategy, ISuperVaultFactory {
    //////////////////////////////////////////////////////////////
    //                     STATE VARIABLES                      //
    //////////////////////////////////////////////////////////////

    /// @notice The SuperRegistry contract
    ISuperRegistry public immutable superRegistry;

    /// @notice The SuperformFactory contract
    ISuperformFactory public immutable superformFactory;

    /// @notice The number of SuperVaults created
    uint256 public superVaultCount;

    /// @notice The total weight used for calculating proportions (10000 = 100%)
    uint256 public constant TOTAL_WEIGHT = 10_000;

    /// @notice The mapping of registered SuperVaults
    mapping(address superVault => bool registered) public registeredSuperVaults;

    //////////////////////////////////////////////////////////////
    //                       CONSTRUCTOR                        //
    //////////////////////////////////////////////////////////////

    /// @param superRegistry_ Address of the SuperRegistry
    constructor(
        address superRegistry_
    ) {
        if (superRegistry_ == address(0)) {
            revert ZERO_ADDRESS();
        }
        superRegistry = ISuperRegistry(superRegistry_);
        superformFactory = superRegistry.getAddress(keccak256("SUPERFORM_FACTORY"));
    }

    //////////////////////////////////////////////////////////////
    //                    EXTERNAL WRITE FUNCTIONS              //
    //////////////////////////////////////////////////////////////

    /// @inheritdoc ISuperVaultFactory
    function createSuperVault(
        address asset_,
        address strategist_,
        string memory name_,
        uint256 depositLimit_,
        uint256[] memory superformIds_,
        uint256[] memory startingWeights_
    ) external onlyManagement returns (address) {
        uint256 numberOfSuperforms = superformIds_.length;

        if (numberOfSuperforms == 0) {
            revert ZERO_SUPERFORMS();
        }

        if (numberOfSuperforms != startingWeights_.length) {
            revert ARRAY_LENGTH_MISMATCH();
        }

        if (block.chainid > type(uint64).max) {
            revert BLOCK_CHAIN_ID_OUT_OF_BOUNDS();
        }

        uint256 totalWeight;
        address superform;

        for (uint256 i; i < numberOfSuperforms; ++i) {
            /// @dev this superVault only supports superforms that have the same asset as the vault
            (superform,,) = superformIds_[i].getSuperform();

            if (!superformFactory.isSuperform(superformIds_[i])) {
                revert SUPERFORM_DOES_NOT_EXIST(superformIds_[i]);
            }

            if (IBaseForm(superform).getVaultAsset() != asset_) {
                revert SUPERFORM_DOES_NOT_SUPPORT_ASSET();
            }

            totalWeight += startingWeights_[i];
        }

        if (totalWeight != TOTAL_WEIGHT) revert INVALID_WEIGHTS();

        superVaultCount++;

        SuperVault superVault = new SuperVault(
          address(superRegistry),
            asset_,
            name_,
            depositLimit_,
            superformIds_,
            startingWeights_
        );

        registeredSuperVaults[address(superVault)] = true;
        updateSuperVaultStrategist(address(superVault), strategist_);

        return address(superVault);
    }

    //////////////////////////////////////////////////////////////
    //                  EXTERNAL VIEW FUNCTIONS                 //
    //////////////////////////////////////////////////////////////

    /// @inheritdoc ISuperVaultFactory
    function isSuperVault(address superVault_) external view returns (bool) {
        return registeredSuperVaults[superVault_];
    }

    function getSuperVaultData(address superVault_) external view returns (ISuperVault.SuperVaultStrategyData memory) {
        return ISuperVault(superVault_).getSuperVaultData();
    }

    /// @inheritdoc ISuperVaultFactory
    function getSuperVaultAsset(address superVault_) external view returns (address) {
        return ISuperVault(superVault_).asset();
    }

    /// @inheritdoc ISuperVaultFactory
    function getSuperformIds(address superVault_) external view returns (uint256[] memory) {
        return ISuperVault(superVault_).getSuperVaultData().superformIds;
    }

    /// @inheritdoc ISuperVaultFactory
    function getSuperVaultCount() external view returns (uint256) {
        return superVaultCount;
    }

    //////////////////////////////////////////////////////////////
    //                    PUBLIC FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    function updateSuperVaultStrategist(address superVault_, address strategist_) public onlyManagement {
        ISuperVault(superVault_).strategist() = strategist_;
    }

    //////////////////////////////////////////////////////////////
    //                      INTERNAL FUNCTIONS                  //
    //////////////////////////////////////////////////////////////

    /// @dev returns the address for id_ from super registry
    function _getAddress(bytes32 id_) internal view returns (address) {
        return superRegistry.getAddress(id_);
    }
}
