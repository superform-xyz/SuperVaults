// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { SuperVault } from "../../src/SuperVault.sol";
import { ITokenizedStrategy } from "tokenized-strategy/interfaces/ITokenizedStrategy.sol";
import { ISuperRegistry } from "superform-core/src/interfaces/ISuperRegistry.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "forge-std/console2.sol";

contract MainnetDeploySuperVault is Script {
    function deploySuperVault(uint256 env, uint256 chainId) external {
        vm.startBroadcast();

        address superRegistry;

        if (env == 1) {
            if (chainId == 250) {
                superRegistry = 0x7B8d68f90dAaC67C577936d3Ce451801864EF189;
            } else {
                superRegistry = 0xB2C097ac459aFAc892ae5b35f6bd6a9Dd3071F47;
            }
        } else if (env == 0 || env == 2) {
            if (chainId == 250) {
                superRegistry = 0x7feB31d18E43E2faeC718EEd2D7f34402c3e27b4;
            } else {
                superRegistry = 0x17A332dC7B40aE701485023b219E9D6f493a2514;
            }
        }

        assert(superRegistry != address(0));

        /// @notice Deploy SuperVault
        uint256[] memory superformIds = new uint256[](1);
        superformIds[0] = chainId == 1
            ? 6_277_101_738_094_410_093_849_154_803_755_231_404_199_879_241_263_958_603_447 // (Euler USDC)
            : 53_060_340_969_225_424_123_272_122_895_191_053_251_498_236_784_870_936_252_229_868;

        uint256[] memory startingWeights = new uint256[](1);
        startingWeights[0] = 10_000;

        /// @dev STRATEGIST is REWARDS ADMIN FOR NOW
        /// @dev VAULT MANAGER is EMERGENCY ADMIN FOR NOW
        /// @dev MANAGEMENT is PAYMENT ADMIN FOR NOW, will be EMERGENCY ADMIN ON PROD
        address STRATEGIST;
        address VAULT_MANAGER;
        address MANAGEMENT;
        if (env == 1) {
            STRATEGIST = 0x1F05a8Ff6d895Ba04C84c5031c5d63FA1afCDA6F;
            VAULT_MANAGER = 0x6A5DD913fE3CB5193E09D1810a3b9ff1C0f9c0D6;
            MANAGEMENT = 0xc5c971e6B9F01dcf06bda896AEA3648eD6e3EFb3;
        } else if (env == 0) {
            STRATEGIST = 0x01d9944787045A431DA61F3be137Ba07b5dd8d6C;
            VAULT_MANAGER = 0x01d9944787045A431DA61F3be137Ba07b5dd8d6C;
            MANAGEMENT = 0x73009CE7cFFc6C4c5363734d1b429f0b848e0490;
        } else if (env == 2) {
            STRATEGIST = 0xde587D0C7773BD239fF1bE87d32C876dEd4f7879;
            VAULT_MANAGER = 0xde587D0C7773BD239fF1bE87d32C876dEd4f7879;
            MANAGEMENT = 0xde587D0C7773BD239fF1bE87d32C876dEd4f7879;
        }
        // USDC on mainnet
        address ASSET =
            chainId == 1 ? 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 : 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

        assert(STRATEGIST != address(0));
        assert(VAULT_MANAGER != address(0));
        assert(MANAGEMENT != address(0));
        assert(ASSET != address(0));

        /// @dev deposit limit is 1 million USDC
        uint256 depositLimit = 1_000_000 * 10 ** IERC20Metadata(ASSET).decimals();

        address superVault = address(
            new SuperVault(
                superRegistry,
                ASSET, // USDC
                STRATEGIST,
                VAULT_MANAGER,
                "SuperUSDC",
                depositLimit,
                superformIds,
                startingWeights
            )
        );
        console2.log("SuperVault deployed at:", superVault);

        /// @dev set valid 5115 form implementation ID
        SuperVault(superVault).setValid5115FormImplementationId(env == 1 ? 5 : 3);

        /// @dev set performance fee to 0
        (bool success,) =
            address(superVault).call(abi.encodeWithSelector(ITokenizedStrategy.setPerformanceFee.selector, 0));
        if (!success) {
            revert("Set performance fee failed");
        }

        /// @dev set pending management to PAYMENT ADMIN
        (success,) = address(superVault).call(
            abi.encodeWithSelector(ITokenizedStrategy.setPendingManagement.selector, MANAGEMENT)
        );
        if (!success) {
            revert("Set pending management failed");
        }

        vm.stopBroadcast();
    }
}
