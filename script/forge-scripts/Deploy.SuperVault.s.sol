// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { Script } from "forge-std/Script.sol";
import { SuperVault } from "src/SuperVault.sol";
import { ITokenizedStrategy } from "tokenized-strategy/interfaces/ITokenizedStrategy.sol";
import { ISuperRegistry } from "superform-core/src/interfaces/ISuperRegistry.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "forge-std/console2.sol";

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

        /// @dev STRATEGIST is REWARDS ADMIN FOR NOW
        address STRATEGIST = isStaging ? 0x1F05a8Ff6d895Ba04C84c5031c5d63FA1afCDA6F : address(0);
        /// @dev VAULT MANAGER is EMERGENCY ADMIN FOR NOW
        address VAULT_MANAGER = isStaging ? 0x6A5DD913fE3CB5193E09D1810a3b9ff1C0f9c0D6 : address(0);
        /// @dev ASSET is USDC on BASE
        address ASSET = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        uint256 depositLimit = 1_000_000 * 10 ** IERC20Metadata(ASSET).decimals();

        assert(STRATEGIST != address(0));
        assert(VAULT_MANAGER != address(0));
        assert(ASSET != address(0));

        address superVault = address(
            new SuperVault(
                superRegistry,
                ASSET, // USDC
                STRATEGIST,
                VAULT_MANAGER,
                "SuperUSDCBaseVault",
                depositLimit,
                superformIds,
                startingWeights
            )
        );
        /// @dev set valid 5115 form implementation ID
        SuperVault(superVault).setValid5115FormImplementationId(isStaging ? 5 : 3);

        /// @dev set performance fee to 0
        (bool success,) =
            address(superVault).call(abi.encodeWithSelector(ITokenizedStrategy.setPerformanceFee.selector, 0));
        if (!success) {
            revert("Set performance fee failed");
        }

        /// @dev MANAGEMENT is PAYMENT ADMIN FOR NOW, will be EMERGENCY ADMIN ON PROD
        address MANAGEMENT = isStaging ? 0xc5c971e6B9F01dcf06bda896AEA3648eD6e3EFb3 : address(0);

        assert(MANAGEMENT != address(0));
        /// @dev set pending management to PAYMENT ADMIN
        (success,) = address(superVault).call(
            abi.encodeWithSelector(ITokenizedStrategy.setPendingManagement.selector, MANAGEMENT)
        );
        if (!success) {
            revert("Set pending management failed");
        }

        console2.log("SuperVault deployed at: %s", superVault);

        vm.stopBroadcast();
    }
}
