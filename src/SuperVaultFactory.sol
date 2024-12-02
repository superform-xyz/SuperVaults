// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ITokenizedStrategy } from "tokenized-strategy/interfaces/ITokenizedStrategy.sol";
import { SuperVault } from "./SuperVault.sol";
import { ISuperVault } from "./interfaces/ISuperVault.sol";
import { ISuperVaultFactory } from "./interfaces/ISuperVaultFactory.sol";

/// @title SuperVaultFactory
/// @notice Factory for creating SuperVaults
/// @dev Implements the ISuperVaultFactory interface
/// @author SuperForm Labs
contract SuperVaultFactory is ISuperVaultFactory, Ownable {
    //////////////////////////////////////////////////////////////
    //                     STATE VARIABLES                      //
    //////////////////////////////////////////////////////////////

    /// @notice The SuperRegistry contract
    address private immutable superRegistry;

    /// @notice The array of registered SuperVaults
    address[] public superVaults;

    //////////////////////////////////////////////////////////////
    //                       CONSTRUCTOR                        //
    //////////////////////////////////////////////////////////////

    /// @param superRegistry_ Address of the SuperRegistry
    constructor(address superRegistry_, address vaultManager_) Ownable(vaultManager_) {
        if (superRegistry_ == address(0) || vaultManager_ == address(0)) {
            revert ZERO_ADDRESS();
        }
        superRegistry = superRegistry_;
    }

    //////////////////////////////////////////////////////////////
    //                    EXTERNAL WRITE FUNCTIONS              //
    //////////////////////////////////////////////////////////////

    /// @inheritdoc ISuperVaultFactory
    /// @dev after deploying superVault, deployer needs to accept management
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
        onlyOwner
        returns (address superVault)
    {
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

        bytes32 salt = keccak256(abi.encodePacked(asset_, name_, superformIds_, startingWeights_, "SuperVault"));
        superVault = address(
            new SuperVault{ salt: salt }(
                superRegistry, asset_, strategist_, vaultManager_, name_, depositLimit_, superformIds_, startingWeights_
            )
        );

        ISuperVault(superVault).setValid5115FormImplementationId(formImplementationId5115_);

        /// @dev set performance fee to 0
        (bool success,) = address(superVault).call(abi.encodeCall(ITokenizedStrategy.setPerformanceFee, (0)));
        if (!success) {
            revert FAILED_TO_SET_PERFORMANCE_FEE();
        }

        /// @dev set pending management to deployer
        /// @dev deployer will have to accept management in SuperVault
        (success,) = address(superVault).call(abi.encodeCall(ITokenizedStrategy.setPendingManagement, (msg.sender)));
        if (!success) {
            revert FAILED_TO_SET_PENDING_MANAGEMENT();
        }

        superVaults.push(superVault);

        emit SuperVaultCreated(superVault);
    }

    //////////////////////////////////////////////////////////////
    //                  EXTERNAL VIEW FUNCTIONS                 //
    //////////////////////////////////////////////////////////////

    /// @inheritdoc ISuperVaultFactory
    function getNumberOfSuperVaults() external view override returns (uint256) {
        return superVaults.length;
    }
}
