// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import { BaseSetup } from "./BaseSetup.sol";
import { SuperVault } from "../src/SuperVault.sol";
import { SuperVaultFactory } from "../src/SuperVaultFactory.sol";
import { ISuperVaultFactory } from "../src/ISuperVaultFactory.sol";

import { ITokenizedStrategy } from "tokenized-strategy/interfaces/ITokenizedStrategy.sol";

contract SuperVaultFactoryTest is BaseSetup {
    SuperVaultFactory public factory;
    SuperVault public superVault;

    function setUp() public override {
        super.setUp();

        // Setup
        vm.startPrank(deployer);

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
