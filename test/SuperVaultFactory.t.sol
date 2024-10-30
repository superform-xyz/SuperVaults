// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import { SuperVault } from "../src/SuperVault.sol";
import { SuperVaultFactory } from "../src/SuperVaultFactory.sol";

import "superform-core/test/utils/ProtocolActions.sol";
import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract SuperVaultFactoryTest is ProtocolActions {
    SuperVaultFactory public factory;
    SuperVault public superVault;

    uint64 SOURCE_CHAIN;

    uint256[] underlyingSuperformIds;
    uint256[] allSuperformIds;
    uint256[] weights;

    function sortAllSuperformIds() internal {
        uint256 n = allSuperformIds.length;
        for (uint256 i = 0; i < n - 1; i++) {
            for (uint256 j = 0; j < n - i - 1; j++) {
                if (allSuperformIds[j] > allSuperformIds[j + 1]) {
                    // Swap
                    uint256 temp = allSuperformIds[j];
                    allSuperformIds[j] = allSuperformIds[j + 1];
                    allSuperformIds[j + 1] = temp;
                }
            }
        }
    }

    function setUp() public {
        SOURCE_CHAIN = ETH;

        // Setup
        vm.selectFork(FORKS[SOURCE_CHAIN]);
        vm.startPrank(deployer);
        factory = new SuperVaultFactory(
            getContract(SOURCE_CHAIN, "SuperRegistry")
        );

        address morphoVault = 0x8eB67A509616cd6A7c1B3c8C21D48FF57df3d458;
        address aaveUsdcVault = 0x73edDFa87C71ADdC275c2b9890f5c3a8480bC9E6;
        address eulerUsdcVault = 0x797DD80692c3b2dAdabCe8e30C07fDE5307D48a9;
        address sandclockUSDCVault = 0x096697720056886b905D0DEB0f06AfFB8e4665E5;

        address[] memory vaultAddresses = new address[](4);
        vaultAddresses[0] = morphoVault;
        vaultAddresses[1] = aaveUsdcVault;
        vaultAddresses[2] = eulerUsdcVault;
        vaultAddresses[3] = sandclockUSDCVault;

        // Get the SuperformFactory
        SuperformFactory superformFactory = SuperformFactory(getContract(SOURCE_CHAIN, "SuperformFactory"));
        underlyingSuperformIds = new uint256[](vaultAddresses.length - 1);
        allSuperformIds = new uint256[](vaultAddresses.length);
        address superformAddress;
        for (uint256 i = 0; i < vaultAddresses.length; i++) {
            (allSuperformIds[i], superformAddress) = superformFactory.createSuperform(1, vaultAddresses[i]);
        }

        sortAllSuperformIds();

        for (uint256 i = 0; i < vaultAddresses.length - 1; i++) {
            underlyingSuperformIds[i] = allSuperformIds[i];
        }

       weights = new uint256[](vaultAddresses.length - 1);
        for (uint256 i = 0; i < vaultAddresses.length - 1; i++) {
            weights[i] = uint256(10_000) / 3;
            if (i == 2) {
                weights[i] += 1;
            }
        }
        
    }

    function test_createSuperVault() public {
        superVault = new SuperVault(
            getContract(SOURCE_CHAIN, "SuperRegistry"),
            getContract(ETH, "USDC"),
            "USDCSuperVaultMorphoEulerAave",
            type(uint256).max,
            underlyingSuperformIds,
            weights
        );
        assertEq(superVault.name(), "USDCSuperVaultMorphoEulerAave");
        assertTrue(factory.isSuperVault(address(superVault)));
        assertEq(factory.superVaultCount, 1);
        assert(address(superVault) != address(0));
    }
}
