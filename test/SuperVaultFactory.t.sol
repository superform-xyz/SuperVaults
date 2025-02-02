// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { SuperVault } from "../src/SuperVault.sol";
import { SuperVaultFactory } from "../src/SuperVaultFactory.sol";
import { ISuperVaultFactory } from "../src/interfaces/ISuperVaultFactory.sol";

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

        // Test zero address for superRegistry
        vm.expectRevert(ISuperVaultFactory.ZERO_ADDRESS.selector);
        factory = new SuperVaultFactory(address(0), deployer);

        // Deploy the factory
        factory = new SuperVaultFactory(getContract(SOURCE_CHAIN, "SuperRegistry"), deployer);

        vm.stopPrank();
    }

    function test_createSuperVault() public {
        vm.prank(deployer);
        address superVaultTest = factory.createSuperVault(
            getContract(ETH, "USDC"),
            deployer,
            deployer,
            "USDCSuperVaultMorphoEulerAave",
            type(uint256).max,
            underlyingSuperformIds,
            weights,
            4
        );
        assertEq(factory.getNumberOfSuperVaults(), 1);
        assert(superVaultTest != address(0));
    }

    function test_createSuperVault_reverts() public {
        vm.startPrank(deployer);

        /// Test zero address for asset
        vm.expectRevert(ISuperVaultFactory.ZERO_ADDRESS.selector);
        factory.createSuperVault(
            address(0),
            deployer,
            deployer,
            "USDCSuperVaultMorphoEulerAave",
            type(uint256).max,
            underlyingSuperformIds,
            weights,
            4
        );

        /// Test zero address for strategist
        vm.expectRevert(ISuperVaultFactory.ZERO_ADDRESS.selector);
        factory.createSuperVault(
            getContract(ETH, "USDC"),
            address(0),
            deployer,
            "USDCSuperVaultMorphoEulerAave",
            type(uint256).max,
            underlyingSuperformIds,
            weights,
            4
        );

        /// Test superform ids and weights length mismatch
        vm.expectRevert(ISuperVaultFactory.ARRAY_LENGTH_MISMATCH.selector);
        factory.createSuperVault(
            getContract(ETH, "USDC"),
            deployer,
            deployer,
            "USDCSuperVaultMorphoEulerAave",
            type(uint256).max,
            underlyingSuperformIds,
            new uint256[](underlyingSuperformIds.length - 1),
            4
        );

        /// Test no superforms
        vm.expectRevert(ISuperVaultFactory.ZERO_SUPERFORMS.selector);
        factory.createSuperVault(
            getContract(ETH, "USDC"),
            deployer,
            deployer,
            "USDCSuperVaultMorphoEulerAave",
            type(uint256).max,
            new uint256[](0),
            new uint256[](0),
            4
        );

        vm.stopPrank();
    }

    function test_getSuperVaultCount() public {
        vm.startPrank(deployer);
        factory.createSuperVault(
            getContract(ETH, "USDC"),
            deployer,
            deployer,
            "USDCSuperVaultMorphoEulerAave",
            type(uint256).max,
            underlyingSuperformIds,
            weights,
            4
        );
        factory.createSuperVault(
            getContract(ETH, "USDC"),
            address(12_345),
            address(12_345),
            "TestSuperVault",
            100e18,
            underlyingSuperformIds,
            weights,
            4
        );
        vm.stopPrank();
        assertEq(factory.getNumberOfSuperVaults(), 2);
    }

    function test_deployerIsPendingVaultManagement() public {
        vm.startPrank(deployer);
        address superVaultTest = factory.createSuperVault(
            getContract(ETH, "USDC"),
            deployer,
            deployer,
            "USDCSuperVaultMorphoEulerAave",
            type(uint256).max,
            underlyingSuperformIds,
            weights,
            4
        );
        (bool success,) =
            address(superVaultTest).call(abi.encodeWithSelector(ITokenizedStrategy.acceptManagement.selector));
        assertTrue(success);
        SuperVault(superVaultTest).setStrategist(address(0xdead));
        vm.stopPrank();
        assertEq(SuperVault(superVaultTest).strategist(), address(0xdead));
    }

    function test_cannotCreateSameSuperVaultTwice() public {
        vm.startPrank(deployer);
        factory.createSuperVault(
            getContract(ETH, "USDC"),
            deployer,
            deployer,
            "USDCSuperVaultMorphoEulerAave",
            type(uint256).max,
            underlyingSuperformIds,
            weights,
            4
        );
        vm.expectRevert();
        factory.createSuperVault(
            getContract(ETH, "USDC"),
            deployer,
            deployer,
            "USDCSuperVaultMorphoEulerAave",
            type(uint256).max,
            underlyingSuperformIds,
            weights,
            4
        );
        vm.stopPrank();
    }

    function test_transferOwnership() public {
        address newOwner = address(0xBEEF);

        address USDC = getContract(ETH, "USDC");

        vm.startPrank(deployer);

        console.log("current owner", factory.owner());
        // Transfer ownership to new address
        factory.transferOwnership(newOwner);

        // New owner should be able to create vault
        vm.startPrank(newOwner);
        factory.createSuperVault(
            USDC, deployer, deployer, "TestVault", type(uint256).max, underlyingSuperformIds, weights, 4
        );
        vm.stopPrank();
    }
}
