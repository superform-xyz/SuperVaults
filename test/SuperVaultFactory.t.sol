// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import { SuperVault } from "../src/SuperVault.sol";
import { SuperVaultFactory } from "../src/SuperVaultFactory.sol";
import { ISuperVaultFactory } from "../src/ISuperVaultFactory.sol";

import "superform-core/test/utils/ProtocolActions.sol";
import { Math } from "openzeppelin/contracts/utils/math/Math.sol";
import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { ITokenizedStrategy } from "tokenized-strategy/interfaces/ITokenizedStrategy.sol";

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

    function setUp() public override {
        super.setUp();
        SOURCE_CHAIN = ETH;

        // Setup
        vm.selectFork(FORKS[SOURCE_CHAIN]);
        vm.startPrank(deployer);

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

        factory = new SuperVaultFactory(
            getContract(SOURCE_CHAIN, "SuperRegistry")
        );

        vm.stopPrank();
    }

    function test_createSuperVault() public {
        vm.prank(deployer);
        address superVault = factory.createSuperVault(
            getContract(ETH, "USDC"),
            address(deployer),
            "USDCSuperVaultMorphoEulerAave",
            type(uint256).max,
            underlyingSuperformIds,
            weights
        );
        assertTrue(factory.isSuperVault(superVault));
        assertEq(factory.getSuperVaultCount(), 1);
        assert(superVault != address(0));
    }

    function test_createSuperVault_reverts() public {
        vm.startPrank(deployer);

        /// Test zero address for asset
        vm.expectRevert(ISuperVaultFactory.ZERO_ADDRESS.selector);
        factory.createSuperVault(
            address(0),
            address(deployer),
            "USDCSuperVaultMorphoEulerAave",
            type(uint256).max,
            underlyingSuperformIds,
            weights
        );

        /// Test zero address for strategist
        vm.expectRevert(ISuperVaultFactory.ZERO_ADDRESS.selector);
        factory.createSuperVault(
            getContract(ETH, "USDC"),
            address(0),
            "USDCSuperVaultMorphoEulerAave",
            type(uint256).max,
            underlyingSuperformIds,
            weights
        );

        /// Test superform ids and weights length mismatch
        vm.expectRevert(ISuperVaultFactory.ARRAY_LENGTH_MISMATCH.selector);
        factory.createSuperVault(
            getContract(ETH, "USDC"),
            address(deployer),
            "USDCSuperVaultMorphoEulerAave",
            type(uint256).max,
            underlyingSuperformIds,
            new uint256[](underlyingSuperformIds.length - 1)
        );

        /// Test no superforms
        vm.expectRevert(ISuperVaultFactory.ZERO_SUPERFORMS.selector);
        factory.createSuperVault(
            getContract(ETH, "USDC"),
            address(deployer),
            "USDCSuperVaultMorphoEulerAave",
            type(uint256).max,
            new uint256[](0),
            new uint256[](0)
        );
        vm.stopPrank();
    }

    function test_getSuperVaultData() public {
        vm.prank(deployer);
        address superVault = factory.createSuperVault(
            getContract(ETH, "USDC"),
            address(deployer),
            "USDCSuperVaultMorphoEulerAave",
            type(uint256).max,
            underlyingSuperformIds,
            weights
        );
        (uint256 numberOfSuperforms, uint256[] memory superformIds, uint256[] memory weightsReceived) = factory.getSuperVaultData(address(superVault));
        assertEq(numberOfSuperforms, underlyingSuperformIds.length);
        assertEq(superformIds.length, underlyingSuperformIds.length);
        assertEq(weightsReceived.length, underlyingSuperformIds.length);
        for (uint256 i = 0; i < underlyingSuperformIds.length; i++) {
            assertEq(superformIds[i], underlyingSuperformIds[i]);
            assertEq(weightsReceived[i], weights[i]);
        }
    }

    function test_getSuperformIds() public {
        vm.prank(deployer);
        address superVault = factory.createSuperVault(
            getContract(ETH, "USDC"),
            address(deployer),
            "USDCSuperVaultMorphoEulerAave",
            type(uint256).max,
            underlyingSuperformIds,
            weights
        );
        uint256[] memory superformIds = factory.getSuperformIds(address(superVault));
        assertEq(superformIds.length, underlyingSuperformIds.length);
        for (uint256 i = 0; i < underlyingSuperformIds.length; i++) {
            assertEq(superformIds[i], underlyingSuperformIds[i]);
        }
    }

    function test_getSuperVaultCount() public {
        vm.startPrank(deployer);
        factory.createSuperVault(
            getContract(ETH, "USDC"),
            address(deployer),
            "USDCSuperVaultMorphoEulerAave",
            type(uint256).max,
            underlyingSuperformIds,
            weights
        );
        factory.createSuperVault(
            getContract(ETH, "USDC"),
            address(12345),
            "TestSuperVault",
            100e18,
            underlyingSuperformIds,
            weights
        );
        vm.stopPrank();
        assertEq(factory.getSuperVaultCount(), 2);
    }

    function test_deployerIsPendingVaultManagement() public {
        vm.startPrank(deployer);
        address superVault = factory.createSuperVault(
            getContract(ETH, "USDC"),
            deployer,
            "USDCSuperVaultMorphoEulerAave",
            type(uint256).max,
            underlyingSuperformIds,
            weights
        );
        address(superVault).call(abi.encodeWithSelector(ITokenizedStrategy.acceptManagement.selector));
        SuperVault(superVault).setStrategist(address(0xdead));
        vm.stopPrank();
        assertEq(SuperVault(superVault).strategist(), address(0xdead));
    }
}
