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

    /// @notice The SuperformFactory contract
    ISuperformFactory public immutable superformFactory;

    /// @notice The SuperRegistry contract
    ISuperRegistry public immutable superRegistry;

    /// @notice The number of SuperVaults created
    uint256 public superVaultCount;

    /// @notice The mapping of registered SuperVaults
    mapping(address superVault => bool registered) public registeredSuperVaults;

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
        if (superformFactory_ == address(0) || superRegistry_ == address(0)) {
            revert ZERO_ADDRESS();
        }
        superformFactory = ISuperformFactory(superformFactory_);
        superRegistry = ISuperRegistry(superRegistry_);
    }

    //////////////////////////////////////////////////////////////
    //                     EXTERNAL WRITE FUNCTIONS              //
    //////////////////////////////////////////////////////////////

    /// @inheritdoc ISuperVaultFactory
    function createSuperVault(
        address asset_,
        uint64 chainId_,
        string memory name_,
        uint256 depositLimit_,
        uint256[] memory superformIds_,
        uint256[] memory startingWeights_
    ) external onlySuperVaultsManager returns (address) {
        uint256 numberOfSuperforms = superformIds_.length;
        if (numberOfSuperforms == 0) {
            revert ZERO_SUPERFORMS();
        }

        if (numberOfSuperforms != startingWeights_.length) {
            revert ARRAY_LENGTH_MISMATCH();
        }

        if (superRegistry_ == address(0)) {
            revert ZERO_ADDRESS();
        }

        if (block.chainid > type(uint64).max) {
            revert BLOCK_CHAIN_ID_OUT_OF_BOUNDS();
        }

        // uint256 totalWeight;
        // address superform;

        // for (uint256 i; i < numberOfSuperforms; ++i) {
        //     /// @dev this superVault only supports superforms that have the same asset as the vault
        //     (superform,,) = superformIds_[i].getSuperform();

        //     if (!factory.isSuperform(superformIds_[i])) {
        //         revert SUPERFORM_DOES_NOT_EXIST(superformIds_[i]);
        //     }

        //     if (IBaseForm(superform).getVaultAsset() != asset_) {
        //         revert SUPERFORM_DOES_NOT_SUPPORT_ASSET();
        //     }

        //     totalWeight += startingWeights_[i];
        // }

        // if (totalWeight != TOTAL_WEIGHT) revert INVALID_WEIGHTS();

        superVaultCount++;
        registeredSuperVaults[address(superVault)] = true;

        //SuperVault superVault = new SuperVault(superRegistry_, asset_, chainId_, name_, depositLimit_, superformIds_, startingWeights_);

        superVault.CHAIN_ID = uint64(block.chainid);

        // SV.numberOfSuperforms = numberOfSuperforms;
        // SV.superformIds = superformIds_;
        // SV.weights = startingWeights_;
        // SV.depositLimit = depositLimit_;

        return address(superVault);
    }

    //////////////////////////////////////////////////////////////
    //                  EXTERNAL VIEW FUNCTIONS                 //
    //////////////////////////////////////////////////////////////

    /// @inheritdoc ISuperVaultFactory
    function isSuperVault(address superVault_) external view returns (bool) {
        return registeredSuperVaults[superVault_];
    }

    /// @inheritdoc ISuperVaultFactory
    function getSuperVault(uint256 superformId_) external view returns (address) {
        // TODO: Implement
    }

    function getSuperVaultData(address superVault_) external view returns (ISuperVault.SuperVaultStrategyData memory) {
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

    /// @inheritdoc ISuperVaultFactor
    function getSuperVaultCount() external view returns (uint256) {
        return superVaultCount;
    }

    /// @inheritdoc ISuperVaultFactory
    // function getSuperVaultDepositLimit(address superVault_) external view returns (uint256) {
    //     // TODO: Implement
    // }

    // /// @inheritdoc ISuperVaultFactory
    // function getSuperVaultName(address superVault_) external view returns (string memory) {
    //     // TODO: Implement
    // }

    //////////////////////////////////////////////////////////////
    //                      INTERNAL FUNCTIONS                  //
    //////////////////////////////////////////////////////////////

    /// @dev returns the address for id_ from super registry
    function _getAddress(bytes32 id_) internal view returns (address) {
        return superRegistry.getAddress(id_);
    }
}
