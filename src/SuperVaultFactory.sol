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
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title SuperVaultFactory
/// @notice Factory for creating SuperVaults
/// @dev Implements the ISuperVaultFactory interface
/// @author SuperForm Labs
contract SuperVaultFactory is ISuperVaultFactory, AccessControl {
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

    /// @notice The array of registered SuperVaults
    address[] public superVaults;

    /// @notice The mapping of registered SuperVaults
    mapping(address superVault => bool registered) public registeredSuperVaults;

    //////////////////////////////////////////////////////////////
    //                       MODIFIERS                          //
    //////////////////////////////////////////////////////////////

    modifier onlyManagement() {
        if (!hasRole(keccak256("MANAGEMENT_ROLE"), msg.sender)) {
            revert NOT_MANAGEMENT();
        }
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
        _grantRole(keccak256("MANAGEMENT_ROLE"), msg.sender);
    }

    //////////////////////////////////////////////////////////////
    //                    EXTERNAL WRITE FUNCTIONS              //
    //////////////////////////////////////////////////////////////

    /// @inheritdoc ISuperVaultFactory
    /// @dev after deploying superVault, deployer needs to accept management
    function createSuperVault(
        address asset_,
        address strategist_,
        string memory name_,
        uint256 depositLimit_,
        uint256[] memory superformIds_,
        uint256[] memory startingWeights_
    ) external onlyManagement returns (address) {
        if (asset_ == address(0) || strategist_ == address(0)) {
            revert ZERO_ADDRESS();
        }

        uint256 numberOfSuperforms = superformIds_.length;

        if (numberOfSuperforms == 0) {
            revert ZERO_SUPERFORMS();
        }

        if (numberOfSuperforms != startingWeights_.length) {
            revert ARRAY_LENGTH_MISMATCH();
        }

        //bytes32
        address superVault = address(new SuperVault(
            address(superRegistry),
            asset_,
            strategist_,
            name_,
            depositLimit_,
            superformIds_,
            startingWeights_
        ));

        /// @dev set pending management to deployer
        /// @dev deployer will have to accept management in SuperVault
        (bool success,) =
            address(superVault).call(abi.encodeWithSelector(ITokenizedStrategy.setPendingManagement.selector, msg.sender));
        if (!success) {
            revert FAILED_TO_SET_PENDING_MANAGEMENT();
        }

        superVaults.push(superVault);
        registeredSuperVaults[superVault] = true;

        return superVault;
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
        (,uint256[] memory superformIds,) = ISuperVault(superVault_).getSuperVaultData();
        return superformIds;
    }

    /// @inheritdoc ISuperVaultFactory
    function getSuperVaultCount() external view returns (uint256) {
        return superVaults.length;
    }

    //////////////////////////////////////////////////////////////
    //                      INTERNAL FUNCTIONS                  //
    //////////////////////////////////////////////////////////////

    /// @dev returns the address for id_ from super registry
    function _getAddress(bytes32 id_) internal view returns (address) {
        return superRegistry.getAddress(id_);
    }
}
