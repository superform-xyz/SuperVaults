// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { Script } from "forge-std/Script.sol";
import { ISuperRegistry } from "superform-core/src/interfaces/ISuperRegistry.sol";
import { SuperVaultFactory } from "src/SuperVaultFactory.sol";
import "forge-std/console2.sol";
import { CREATE3Script } from "../base/CREATE3Script.sol";

contract MainnetDeploySuperVaultFactory is CREATE3Script {
    constructor() CREATE3Script("V1") { }

    function deploySuperVaultFactory(bool isStaging, uint256 chainId) external {
        vm.startBroadcast();

        address superRegistry;

        if (isStaging) {
            if (chainId == 250) {
                superRegistry = 0x7B8d68f90dAaC67C577936d3Ce451801864EF189;
            } else {
                superRegistry = 0xB2C097ac459aFAc892ae5b35f6bd6a9Dd3071F47;
            }
        } else {
            if (chainId == 250) {
                superRegistry = 0x7feB31d18E43E2faeC718EEd2D7f34402c3e27b4;
            } else {
                superRegistry = 0x17A332dC7B40aE701485023b219E9D6f493a2514;
            }
        }

        assert(superRegistry != address(0));
        /// @dev VAULT MANAGER is EMERGENCY ADMIN FOR NOW
        address VAULT_MANAGER = isStaging ? 0x6A5DD913fE3CB5193E09D1810a3b9ff1C0f9c0D6 : address(0);
        assert(VAULT_MANAGER != address(0));

        console2.log("SuperRegistry:", superRegistry);
        console2.log("Vault Manager:", VAULT_MANAGER);
        /// @notice Deploy SuperVaultFactory

        address superVaultFactory = create3.deploy(
            getCreate3ContractSalt("SuperVaultFactory"),
            abi.encodePacked(type(SuperVaultFactory).creationCode, abi.encode(superRegistry, VAULT_MANAGER))
        );

        console2.log("SuperVaultFactory deployed to:", superVaultFactory);

        vm.stopBroadcast();
    }
}
