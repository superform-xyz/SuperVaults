// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { Script } from "forge-std/Script.sol";
import { ISuperRegistry } from "superform-core/src/interfaces/ISuperRegistry.sol";
import { SuperRBAC } from "superform-core/src/settings/SuperRBAC.sol";
import { SuperVault } from "src/SuperVault.sol";

contract MainnetDeploySuperVault is Script {
    function deploySuperVault(bool isStaging, uint256 chainId) external {
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

        /// @notice Deploy SuperVault
        /// FIXME: change the parameters

        /// 100% in the morpho moonwell USDC
        uint256[] memory superformIds = new uint256[](1);
        superformIds[0] = 53_060_340_969_225_424_123_272_122_895_191_053_251_498_236_784_870_936_252_229_868;

        uint256[] memory startingWeights = new uint256[](1);
        startingWeights[0] = 10_000;

        new SuperVault(
            superRegistry,
            0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, // USDC
            "USDCSuperVaultMoonwellFlagship",
            type(uint256).max,
            superformIds,
            startingWeights
        );

        /// @dev TODO set later the correct address, as this is currently rewards admin
        address REWARDS_ADMIN =
            isStaging ? 0x1F05a8Ff6d895Ba04C84c5031c5d63FA1afCDA6F : 0xf82F3D7Df94FC2994315c32322DA6238cA2A2f7f;

        address superRBAC = ISuperRegistry(superRegistry).getAddress(keccak256("SUPER_RBAC"));

        assert(superRBAC != address(0));

        SuperRBAC superRBACC = SuperRBAC(superRBAC);
        superRBACC.setRoleAdmin(keccak256("SUPER_VAULTS_STRATEGIST"), superRBACC.PROTOCOL_ADMIN_ROLE());
        superRBACC.grantRole(keccak256("SUPER_VAULTS_STRATEGIST"), REWARDS_ADMIN);
        vm.stopBroadcast();
    }
}
