// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { SuperVault } from "./SuperVault.sol";
import { ISuperVault } from "./ISuperVault.sol";
import { ISuperVaultFactory } from "./ISuperVaultFactory.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { DataLib } from "superform-core/src/libraries/DataLib.sol";
import { IBaseForm } from "superform-core/src/interfaces/IBaseForm.sol";
import { ITokenizedStrategy } from "tokenized-strategy/interfaces/ITokenizedStrategy.sol";
import { ISuperRegistry } from "superform-core/src/interfaces/ISuperRegistry.sol";

/// @title SuperVaultFactory
/// @notice Factory for creating SuperVaults
/// @dev Implements the ISuperVaultFactory interface
/// @author SuperForm Labs
contract SuperVaultFactory is ISuperVaultFactory {
    using Math for uint256;
    using DataLib for uint256;

    //////////////////////////////////////////////////////////////
    //                     STATE VARIABLES                      //
    //////////////////////////////////////////////////////////////

    /// @notice The SuperRegistry contract
    ISuperRegistry public immutable superRegistry;

    /// @notice The TokenizedStrategy contract
    ITokenizedStrategy public immutable tokenizedStrategy;
    /// @notice The number of SuperVaults created
    uint256 public superVaultCount;

    /// @notice The total weight used for calculating proportions (10000 = 100%)
    uint256 public constant TOTAL_WEIGHT = 10_000;

    /// @notice The mapping of registered SuperVaults
    mapping(address superVault => bool registered) public registeredSuperVaults;

    //////////////////////////////////////////////////////////////
    //                       MODIFIERS                          //
    //////////////////////////////////////////////////////////////

    modifier onlyManagement() {
        tokenizedStrategy.requireManagement(msg.sender);
        _;
    }

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
        tokenizedStrategy = ITokenizedStrategy(0xBB51273D6c746910C7C06fe718f30c936170feD0);
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

    function getSuperVaultData(address superVault_) external view returns (uint256 numberOfSuperforms, uint256[] memory superformIds, uint256[] memory weights) {
        return ISuperVault(superVault_).getSuperVaultData();
    }

    /// @inheritdoc ISuperVaultFactory
    function getSuperformIds(address superVault_) external view returns (uint256[] memory) {
        (,, uint256[] memory superformIds) = ISuperVault(superVault_).getSuperVaultData();
        return superformIds;
    }

    /// @inheritdoc ISuperVaultFactory
    function getSuperVaultCount() external view returns (uint256) {
        return superVaultCount;
    }

    //////////////////////////////////////////////////////////////
    //                    PUBLIC FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    function updateSuperVaultStrategist(address superVault_, address strategist_) public onlyManagement {
        // TODO: Implement
        //ISuperVault(superVault_).strategist() = strategist_;
    }

    //////////////////////////////////////////////////////////////
    //                      INTERNAL FUNCTIONS                  //
    //////////////////////////////////////////////////////////////

    /// @dev returns the address for id_ from super registry
    function _getAddress(bytes32 id_) internal view returns (address) {
        return superRegistry.getAddress(id_);
    }
}
