// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { Script } from "forge-std/Script.sol";
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
        superformIds[0] = 53_060_340_969_226_234_633_364_492_417_650_658_771_681_951_352_098_198_744_034_590;

        uint256[] memory startingWeights = new uint256[](1);
        startingWeights[0] = 10_000;

        /// TODO WARNING!: Change this before making it the oficial SuperVault
        address refundsReceiver = 0x48aB8AdF869Ba9902Ad483FB1Ca2eFDAb6eabe92;
        new SuperVault(
            superRegistry,
            0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, // USDC
            0x48aB8AdF869Ba9902Ad483FB1Ca2eFDAb6eabe92, // deployer
            "USDCSuperVaultMoonwellFlagship",
            type(uint256).max,
            superformIds,
            startingWeights
        );

        vm.stopBroadcast();
    }
}
