// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ISuperformFactoryMinimal {
    function vaultFormImplCombinationToSuperforms(bytes32 vaultFormImplementationCombination)
        external
        view
        returns (uint256 superformId);

    function getFormImplementation(uint32 formImplementationId_) external view returns (address);
}