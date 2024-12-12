// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "superform-core/test/utils/ProtocolActions.sol";
import { VaultMock } from "superform-core/test/mocks/VaultMock.sol";

import { Math } from "openzeppelin/contracts/utils/math/Math.sol";
import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { SuperVault } from "../src/SuperVault.sol";
import { ISuperVault } from "../src/interfaces/ISuperVault.sol";
import { ITokenizedStrategy } from "tokenized-strategy/interfaces/ITokenizedStrategy.sol";

import { Strings } from "openzeppelin-contracts/contracts/utils/Strings.sol";

contract SuperVaultHarness is SuperVault {
    using Strings for string;

    constructor(
        address superRegistry_,
        address asset_,
        address strategist_,
        address vaultManager_,
        string memory name_,
        uint256 depositLimit_,
        uint256[] memory superformIds_,
        uint256[] memory startingWeights_
    )
        SuperVault(
            superRegistry_,
            asset_,
            strategist_,
            vaultManager_,
            name_,
            depositLimit_,
            superformIds_,
            startingWeights_
        )
    { }

    function updateSVData(address superPositions, uint256[] memory finalSuperformIds) public {
        _updateSVData(superPositions, finalSuperformIds);
    }
}

contract SuperVaultTest is ProtocolActions {
    using Math for uint256;

    using DataLib for uint256;

    address SUPER_POSITIONS_SOURCE;

    uint64 SOURCE_CHAIN;
    uint256 N_UNDERLYING_SFS;
    uint256 SUPER_VAULT_ID1;
    uint256[] underlyingSuperformIds;
    uint256[] allSuperformIds;
    string[] gasTestSuperformNames;
    uint256[] gasTestSuperformIds;

    SuperVault superVault;
    SuperVaultHarness superVaultHarness;

    /// @dev yearn address factory on ETH
    address constant FACTORY = 0x444045c5C13C246e117eD36437303cac8E250aB0;

    address constant KEEPER = address(uint160(uint256(keccak256("KEEPER"))));
    address constant PERFORMANCE_FEE_RECIPIENT = address(uint160(uint256(keccak256("PERFORMANCE_FEE_RECIPIENT"))));

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

    function sortGasTestsArrays() internal {
        uint256 n = gasTestSuperformIds.length;
        for (uint256 i = 0; i < n - 1; i++) {
            for (uint256 j = 0; j < n - i - 1; j++) {
                if (gasTestSuperformIds[j] > gasTestSuperformIds[j + 1]) {
                    // Swap IDs
                    uint256 tempId = gasTestSuperformIds[j];
                    gasTestSuperformIds[j] = gasTestSuperformIds[j + 1];
                    gasTestSuperformIds[j + 1] = tempId;

                    // Swap corresponding names
                    string memory tempName = gasTestSuperformNames[j];
                    gasTestSuperformNames[j] = gasTestSuperformNames[j + 1];
                    gasTestSuperformNames[j + 1] = tempName;
                }
            }
        }
    }

    function setUp() public override {
        chainIds = [ETH, ARBI];
        super.setUp();
        MULTI_TX_SLIPPAGE_SHARE = 0;
        AMBs = [2, 3];
        SOURCE_CHAIN = ETH;

        SUPER_POSITIONS_SOURCE = getContract(SOURCE_CHAIN, "SuperPositions");

        // Setup
        vm.selectFork(FORKS[SOURCE_CHAIN]);
        vm.startPrank(deployer);
        address morphoVault = 0x8eB67A509616cd6A7c1B3c8C21D48FF57df3d458;
        address aaveUsdcVault = 0x73edDFa87C71ADdC275c2b9890f5c3a8480bC9E6;
        address fluidUsdcVault = 0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33;
        address sandclockUSDCVault = 0x096697720056886b905D0DEB0f06AfFB8e4665E5;
        address syFUSDCVault = 0xf94A3798B18140b9Bc322314bbD36BC8e245E29B;
        address eulerUsdcVault = 0x797DD80692c3b2dAdabCe8e30C07fDE5307D48a9;

        address syFUSDCVaultWrapper = ERC5115To4626WrapperFactory(
            getContract(SOURCE_CHAIN, "ERC5115To4626WrapperFactory")
        ).createWrapper(syFUSDCVault, getContract(SOURCE_CHAIN, "USDC"), getContract(SOURCE_CHAIN, "USDC"));

        address[] memory vaultAddresses = new address[](6);
        vaultAddresses[0] = morphoVault;
        vaultAddresses[1] = aaveUsdcVault;
        vaultAddresses[2] = fluidUsdcVault;
        vaultAddresses[3] = sandclockUSDCVault;
        vaultAddresses[4] = syFUSDCVaultWrapper;
        vaultAddresses[5] = eulerUsdcVault;

        N_UNDERLYING_SFS = 3;

        // Get the SuperformFactory
        SuperformFactory superformFactory = SuperformFactory(getContract(SOURCE_CHAIN, "SuperformFactory"));
        underlyingSuperformIds = new uint256[](N_UNDERLYING_SFS);
        gasTestSuperformIds = new uint256[](N_UNDERLYING_SFS);
        allSuperformIds = new uint256[](vaultAddresses.length);
        address superformAddress;
        for (uint256 i = 0; i < vaultAddresses.length; i++) {
            if (i != 4) {
                (allSuperformIds[i], superformAddress) =
                    superformFactory.createSuperform(FORM_IMPLEMENTATION_IDS[0], vaultAddresses[i]);
            } else {
                (allSuperformIds[i], superformAddress) =
                    superformFactory.createSuperform(FORM_IMPLEMENTATION_IDS[1], vaultAddresses[i]);
            }
            if (i < 3) {
                gasTestSuperformIds[i] = allSuperformIds[i];
            }
        }
        gasTestSuperformNames.push("Morpho");
        gasTestSuperformNames.push("Aave");
        gasTestSuperformNames.push("Fluid");

        sortGasTestsArrays();
        sortAllSuperformIds();

        for (uint256 i = 0; i < N_UNDERLYING_SFS; i++) {
            underlyingSuperformIds[i] = allSuperformIds[i];
        }

        uint256[] memory weights = new uint256[](N_UNDERLYING_SFS);
        for (uint256 i = 0; i < N_UNDERLYING_SFS; i++) {
            weights[i] = uint256(10_000) / 3;
            if (i == 2) {
                weights[i] += 1;
            }
        }

        // Deploy SuperVault
        superVault = new SuperVault(
            getContract(ETH, "SuperRegistry"),
            getContract(ETH, "USDC"),
            deployer,
            deployer,
            "USDCSuperVault",
            type(uint256).max,
            underlyingSuperformIds,
            weights
        );
        vm.expectRevert(ISuperVault.ZERO_ID.selector);
        superVault.setValid5115FormImplementationId(0);

        superVault.setValid5115FormImplementationId(FORM_IMPLEMENTATION_IDS[1]);
        uint256[] memory superformIds = new uint256[](3);
        superformIds[0] = allSuperformIds[3];
        superformIds[1] = allSuperformIds[4];
        superformIds[2] = allSuperformIds[5];

        bool[] memory isWhitelisted = new bool[](3);
        isWhitelisted[0] = true;
        isWhitelisted[1] = true;
        isWhitelisted[2] = true;

        ISuperVault(superVault).setWhitelist(superformIds, isWhitelisted);

        uint256[] memory isWhitelistedResult = ISuperVault(superVault).getWhitelist();
        assertEq(isWhitelistedResult[0], allSuperformIds[0], "Whitelist not set correctly");

        /// @dev after deploying superVault, deployer (a FB role) needs to accept management
        /// @dev also needs to be set as keeper (a new FB role)
        /// @dev also we need to have a performance fee recipient (a new FB role)
        (bool success, bytes memory returnValue) =
            address(superVault).call(abi.encodeWithSignature("setKeeper(address)", KEEPER));
        require(success, "Failed to set keeper");
        (success, returnValue) = address(superVault).call(
            abi.encodeWithSignature("setPerformanceFeeRecipient(address)", PERFORMANCE_FEE_RECIPIENT)
        );
        require(success, "Failed to set performance fee recipient");

        superVaultHarness = new SuperVaultHarness(
            getContract(SOURCE_CHAIN, "SuperRegistry"),
            getContract(ETH, "USDC"),
            deployer,
            deployer,
            "USDCSuperVaultMorphoEulerAave",
            type(uint256).max,
            underlyingSuperformIds,
            weights
        );
        superVaultHarness.getSuperVaultData();

        (bool success2,) = address(superVault).call(abi.encodeWithSelector(ITokenizedStrategy.performanceFee.selector));
        require(success2, "Failed to get performance fee");

        address superVaultAddress = address(superVault);

        // Deploy Superform
        (SUPER_VAULT_ID1,) = superformFactory.createSuperform(1, superVaultAddress);

        assertTrue(superformFactory.isSuperform(SUPER_VAULT_ID1), "Superform should be registered");

        SuperRegistry(getContract(ETH, "SuperRegistry")).setAddress(keccak256("SUPER_VAULTS_STRATEGIST"), deployer, ETH);

        SuperRegistry(getContract(ETH, "SuperRegistry")).setAddress(keccak256("VAULT_MANAGER"), deployer, ETH);

        vm.stopPrank();
    }

    function test_RevertWhen_SetWhitelistWithMismatchedArrays() public {
        uint256[] memory superformIds = new uint256[](2);
        superformIds[0] = 1;
        superformIds[1] = 2;

        bool[] memory isWhitelisted = new bool[](1);
        isWhitelisted[0] = true;

        vm.prank(deployer);
        vm.expectRevert(ISuperVault.ARRAY_LENGTH_MISMATCH.selector);
        superVault.setWhitelist(superformIds, isWhitelisted);
    }

    function test_RevertWhen_SetWhitelistWithEmptyArrays() public {
        uint256[] memory superformIds = new uint256[](0);
        bool[] memory isWhitelisted = new bool[](0);

        vm.prank(deployer);
        vm.expectRevert(ISuperVault.ZERO_SUPERFORMS.selector);
        superVault.setWhitelist(superformIds, isWhitelisted);
    }

    function test_setVaultManager() public {
        address newVaultManager = address(0xDEAD);
        // Test successful vault manager update
        vm.prank(deployer);
        superVault.setVaultManager(newVaultManager);
    }

    function test_setVaultManager_zeroAddress() public {
        // Test that zero address is rejected
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSignature("ZERO_ADDRESS()"));
        superVault.setVaultManager(address(0));
    }

    function test_setWhitelist_RemoveElements() public {
        // Setup: First get the initial whitelist
        uint256[] memory initialWhitelist = superVault.getWhitelist();
        assertGt(initialWhitelist.length, 0, "Initial whitelist should not be empty");

        // Select some superformIds to remove (let's remove the first two if they exist)
        uint256 removeCount = initialWhitelist.length >= 2 ? 2 : 1;
        uint256[] memory superformIdsToRemove = new uint256[](removeCount);
        bool[] memory isWhitelisted = new bool[](removeCount);

        // Fill arrays for removal (all false to remove)
        for (uint256 i = 0; i < removeCount; i++) {
            superformIdsToRemove[i] = initialWhitelist[i];
            isWhitelisted[i] = false;
        }

        // Execute removal
        vm.prank(deployer);
        superVault.setWhitelist(superformIdsToRemove, isWhitelisted);

        // Verify removal
        uint256[] memory finalWhitelist = superVault.getWhitelist();
        assertEq(
            finalWhitelist.length,
            initialWhitelist.length - removeCount,
            "Whitelist length should decrease by removal count"
        );

        // Verify removed IDs are no longer whitelisted
        for (uint256 i = 0; i < removeCount; i++) {
            uint256[] memory checkId = new uint256[](1);
            checkId[0] = superformIdsToRemove[i];
            bool[] memory status = superVault.getIsWhitelisted(checkId);
            assertFalse(status[0], "Removed ID should not be whitelisted");
        }

        // Verify remaining IDs are still in order and valid
        for (uint256 i = 0; i < finalWhitelist.length; i++) {
            uint256[] memory checkId = new uint256[](1);
            checkId[0] = finalWhitelist[i];
            bool[] memory status = superVault.getIsWhitelisted(checkId);
            assertTrue(status[0], "Remaining ID should still be whitelisted");
        }
    }

    function test_constructorIsSuperformCheck() public {
        uint256 fakeSuperformId = type(uint256).max;

        uint256[] memory superformIds = new uint256[](1);
        superformIds[0] = fakeSuperformId;

        uint256[] memory weights = new uint256[](1);
        weights[0] = 10_000;

        vm.expectRevert();
        new SuperVault(
            getContract(ETH, "SuperRegistry"),
            getContract(ETH, "USDC"),
            deployer,
            deployer,
            "TestSuperVault",
            type(uint256).max,
            superformIds,
            weights
        );
    }

    function test_onlyVaultManagerCanCall() public {
        vm.startPrank(address(0xdead));
        vm.expectRevert(ISuperVault.NOT_VAULT_MANAGER.selector);
        SuperVault(address(superVault)).setDepositLimit(type(uint256).max);
        vm.stopPrank();
    }

    function test_superVaultConstructorReverts() public {
        address superRegistry = getContract(ETH, "SuperRegistry");
        address asset = getContract(ETH, "USDC");
        string memory name = "TestSuperVault";
        uint256 depositLimit = type(uint256).max;
        uint256[] memory superformIds;
        uint256[] memory startingWeights = new uint256[](3);

        // Setup valid parameters
        startingWeights[0] = 3334;
        startingWeights[1] = 3333;
        startingWeights[2] = 3333;

        // Test 1: ZERO_SUPERFORMS revert
        vm.expectRevert(abi.encodeWithSignature("ZERO_SUPERFORMS()"));
        new SuperVault(superRegistry, asset, deployer, deployer, name, depositLimit, superformIds, startingWeights);
        superformIds = underlyingSuperformIds;

        // Test 2.1: ZERO_ADDRESS revert
        vm.expectRevert(abi.encodeWithSignature("ZERO_ADDRESS()"));
        new SuperVault(address(0), asset, deployer, deployer, name, depositLimit, superformIds, startingWeights);

        // Test 2.2: ZERO_ADDRESS revert
        vm.expectRevert(abi.encodeWithSignature("ZERO_ADDRESS()"));
        new SuperVault(superRegistry, asset, address(0), deployer, name, depositLimit, superformIds, startingWeights);

        // Test 2.3: ZERO_ADDRESS revert
        vm.expectRevert(abi.encodeWithSignature("ZERO_ADDRESS()"));
        new SuperVault(superRegistry, asset, deployer, address(0), name, depositLimit, superformIds, startingWeights);

        // Test 3: ARRAY_LENGTH_MISMATCH revert
        uint256[] memory mismatchedWeights = new uint256[](2);
        mismatchedWeights[0] = 5000;
        mismatchedWeights[1] = 5000;

        vm.expectRevert(abi.encodeWithSignature("ARRAY_LENGTH_MISMATCH()"));
        new SuperVault(superRegistry, asset, deployer, deployer, name, depositLimit, superformIds, mismatchedWeights);

        // Test 4: SUPERFORM_DOES_NOT_SUPPORT_ASSET revert
        vm.expectRevert(abi.encodeWithSignature("SUPERFORM_DOES_NOT_SUPPORT_ASSET()"));
        new SuperVault(
            superRegistry,
            getContract(ETH, "DAI"),
            deployer,
            deployer,
            name,
            depositLimit,
            superformIds,
            startingWeights
        );

        // Test INVALID_WEIGHTS revert
        uint256[] memory invalidWeights = new uint256[](3);
        invalidWeights[0] = 3000;
        invalidWeights[1] = 3000;
        invalidWeights[2] = 3000;

        vm.expectRevert(abi.encodeWithSignature("INVALID_WEIGHTS()"));
        new SuperVault(superRegistry, asset, deployer, deployer, name, depositLimit, superformIds, invalidWeights);
    }

    function test_superVault_assertSuperPositions_splitAccordingToWeights() public {
        vm.startPrank(deployer);
        SOURCE_CHAIN = ETH;
        vm.selectFork(FORKS[SOURCE_CHAIN]);

        uint256 amount = 500e6;
        // Perform a direct deposit to the SuperVault
        _directDeposit(deployer, SUPER_VAULT_ID1, amount, "");

        _assertSuperPositionsSplitAccordingToWeights(ETH);

        _directWithdraw(deployer, SUPER_VAULT_ID1, false);

        _assertUnderlyingBalanceAfterFullWithdraw(ETH);

        vm.stopPrank();
    }

    function test_onERC1155Received() public view {
        // Arrange
        address operator = address(0x1);
        address from = address(0x2);
        uint256 id = 1;
        uint256 value = 100;
        bytes memory data = "";
        (address superFormSuperVault,,) = SUPER_VAULT_ID1.getSuperform();
        address superVaultAddress = IBaseForm(superFormSuperVault).getVaultAddress();

        // Act
        bytes4 result = SuperVault(superVaultAddress).onERC1155Received(operator, from, id, value, data);

        // Assert
        bytes4 expectedSelector = SuperVault.onERC1155Received.selector;
        assertEq(result, expectedSelector, "onERC1155Received should return the correct selector");
    }

    function test_superVault_forwardDustToPaymaster() public {
        deal(getContract(ETH, "USDC"), address(superVault), 1e18);

        vm.startPrank(deployer);
        superVault.forwardDustToPaymaster();
        vm.stopPrank();

        address superRegistry = getContract(ETH, "SuperRegistry");
        assertEq(IERC20(getContract(ETH, "USDC")).balanceOf(address(superVault)), 0);
        address paymaster = ISuperRegistry(superRegistry).getAddress(keccak256("PAYMASTER"));
        assertEq(IERC20(getContract(ETH, "USDC")).balanceOf(paymaster), 1e18);
    }

    function test_superVault_forwardsDustToPaymaster_noDust() public {
        vm.startPrank(deployer);
        superVault.forwardDustToPaymaster();
        vm.stopPrank();
        assertEq(IERC20(getContract(ETH, "USDC")).balanceOf(getContract(ETH, "Paymaster")), 0);
    }

    function test_superVault_xChainDeposit_assertSuperPositions_splitAccordingToWeights() public {
        vm.startPrank(deployer);
        SOURCE_CHAIN = ARBI;

        uint256 amount = 500e18;
        // Perform a xChain deposit to the SuperVault
        _xChainDeposit(SUPER_VAULT_ID1, amount, ETH, 1);

        _assertSuperPositionsSplitAccordingToWeights(ETH);

        vm.startPrank(deployer);

        _xChainWithdraw(SUPER_VAULT_ID1, ETH, 2);

        _assertUnderlyingBalanceAfterFullWithdraw(ETH);

        vm.stopPrank();
    }

    function test_superVault_rebalance_invalidSuperformIdRebalanceFrom() public {
        uint256[] memory superformIdsRebalanceFrom = new uint256[](1);
        superformIdsRebalanceFrom[0] = type(uint256).max;

        uint256[] memory amountsRebalanceFrom = new uint256[](1);
        amountsRebalanceFrom[0] = 1 ether;

        uint256[] memory superformIdsRebalanceTo = new uint256[](1);
        superformIdsRebalanceTo[0] = underlyingSuperformIds[0];

        uint256[] memory weightsOfRedistribution = new uint256[](1);
        weightsOfRedistribution[0] = 10_000;

        ISuperVault.RebalanceArgs memory args = ISuperVault.RebalanceArgs(
            superformIdsRebalanceFrom, amountsRebalanceFrom, superformIdsRebalanceTo, weightsOfRedistribution, 100
        );

        vm.startPrank(deployer);
        vm.expectRevert(ISuperVault.INVALID_SUPERFORM_ID_REBALANCE_FROM.selector);
        SuperVault(address(superVault)).rebalance(args);

        uint256[] memory empty;

        args = ISuperVault.RebalanceArgs(
            superformIdsRebalanceFrom, amountsRebalanceFrom, empty, weightsOfRedistribution, 100
        );
        vm.expectRevert(ISuperVault.EMPTY_FINAL_SUPERFORM_IDS.selector);
        SuperVault(address(superVault)).rebalance(args);

        vm.stopPrank();
    }

    function test_superVault_rebalance_SuperformDoesNotExist() public {
        uint256[] memory finalSuperformIds = new uint256[](1);
        finalSuperformIds[0] = underlyingSuperformIds[0];

        address superPositions = getContract(SOURCE_CHAIN, "SuperPositions");

        vm.mockCall(
            getContract(SOURCE_CHAIN, "SuperformFactory"),
            abi.encodeWithSelector(ISuperformFactory.isSuperform.selector, finalSuperformIds[0]),
            abi.encode(false)
        );

        vm.expectRevert();
        superVaultHarness.updateSVData(superPositions, finalSuperformIds);
    }

    function test_superVault_rebalance_assetNotSupported() public {
        uint256[] memory finalSuperformIds = new uint256[](1);
        finalSuperformIds[0] = underlyingSuperformIds[0];

        address superPositions = getContract(SOURCE_CHAIN, "SuperPositions");
        (address superform,,) = finalSuperformIds[0].getSuperform();

        vm.mockCall(
            superform, abi.encodeWithSelector(IBaseForm.getVaultAsset.selector), abi.encode(address(0xDEADBEEF))
        );

        vm.expectRevert(ISuperVault.SUPERFORM_DOES_NOT_SUPPORT_ASSET.selector);
        superVaultHarness.updateSVData(superPositions, finalSuperformIds);
    }

    function test_superVault_rebalance_duplicateSuperformIdsRebalanceFrom() public {
        uint256[] memory superformIdsRebalanceFrom = new uint256[](2);
        superformIdsRebalanceFrom[0] = underlyingSuperformIds[0];
        superformIdsRebalanceFrom[1] = underlyingSuperformIds[0];

        uint256[] memory finalSuperformIds = new uint256[](1);
        finalSuperformIds[0] = underlyingSuperformIds[0];

        uint256[] memory amountsRebalanceFrom = new uint256[](2);
        amountsRebalanceFrom[0] = 1 ether;
        amountsRebalanceFrom[1] = 1 ether;

        uint256[] memory weightsOfRedistribution = new uint256[](1);
        weightsOfRedistribution[0] = 10_000;

        vm.startPrank(deployer);
        vm.expectRevert(ISuperVault.DUPLICATE_SUPERFORM_IDS_REBALANCE_FROM.selector);
        superVaultHarness.rebalance(
            ISuperVault.RebalanceArgs(
                superformIdsRebalanceFrom, amountsRebalanceFrom, finalSuperformIds, weightsOfRedistribution, 100
            )
        );
        vm.stopPrank();
    }

    function test_superVault_rebalance_duplicateFinalSuperformIds() public {
        uint256[] memory superformIdsRebalanceFrom = new uint256[](2);
        superformIdsRebalanceFrom[0] = underlyingSuperformIds[0];
        superformIdsRebalanceFrom[1] = underlyingSuperformIds[1];

        uint256[] memory finalSuperformIds = new uint256[](2);
        finalSuperformIds[0] = underlyingSuperformIds[0];
        finalSuperformIds[1] = underlyingSuperformIds[0];

        uint256[] memory amountsRebalanceFrom = new uint256[](2);
        amountsRebalanceFrom[0] = 1 ether;
        amountsRebalanceFrom[1] = 1 ether;

        uint256[] memory weightsOfRedistribution = new uint256[](2);
        weightsOfRedistribution[0] = 10_000;
        weightsOfRedistribution[1] = 20_000;

        vm.startPrank(deployer);
        vm.expectRevert(ISuperVault.DUPLICATE_FINAL_SUPERFORM_IDS.selector);
        superVaultHarness.rebalance(
            ISuperVault.RebalanceArgs(
                superformIdsRebalanceFrom, amountsRebalanceFrom, finalSuperformIds, weightsOfRedistribution, 100
            )
        );
        vm.stopPrank();
    }

    function test_superVault_rebalance_notWhitelisted() public {
        uint256[] memory superformIdsRebalanceFrom = new uint256[](2);
        superformIdsRebalanceFrom[0] = underlyingSuperformIds[0];
        superformIdsRebalanceFrom[1] = underlyingSuperformIds[1];

        uint256[] memory finalSuperformIds = new uint256[](2);
        finalSuperformIds[0] = underlyingSuperformIds[0];
        finalSuperformIds[1] = type(uint256).max;

        uint256[] memory amountsRebalanceFrom = new uint256[](2);
        amountsRebalanceFrom[0] = 1 ether;
        amountsRebalanceFrom[1] = 1 ether;

        uint256[] memory weightsOfRedistribution = new uint256[](2);
        weightsOfRedistribution[0] = 10_000;
        weightsOfRedistribution[1] = 20_000;

        vm.startPrank(deployer);
        vm.expectRevert(ISuperVault.SUPERFORM_NOT_WHITELISTED.selector);
        superVaultHarness.rebalance(
            ISuperVault.RebalanceArgs(
                superformIdsRebalanceFrom, amountsRebalanceFrom, finalSuperformIds, weightsOfRedistribution, 100
            )
        );
        vm.stopPrank();
    }

    function test_superVault_rebalance_fullyRebalancedSuperform() public {
        // First do a deposit to have some funds to rebalance
        vm.startPrank(deployer);
        uint256 depositAmount = 10_000e6; // 10,000 USDC
        deal(getContract(ETH, "USDC"), deployer, depositAmount);
        _directDeposit(deployer, SUPER_VAULT_ID1, depositAmount, "");

        uint256[] memory superformIdsRebalanceFrom = new uint256[](1);
        superformIdsRebalanceFrom[0] = underlyingSuperformIds[0];

        uint256[] memory finalSuperformIds = new uint256[](1);
        finalSuperformIds[0] = underlyingSuperformIds[1]; // expect a full rebalance

        // Get the full balance of the first superform to attempt full rebalance
        (address superFormSuperVault,,) = SUPER_VAULT_ID1.getSuperform();
        address superVaultAddress = IBaseForm(superFormSuperVault).getVaultAddress();
        uint256 fullBalance =
            SuperPositions(SUPER_POSITIONS_SOURCE).balanceOf(superVaultAddress, superformIdsRebalanceFrom[0]);

        uint256[] memory amountsRebalanceFrom = new uint256[](1);
        amountsRebalanceFrom[0] = fullBalance / 2; // Attempt to rebalance half position

        uint256[] memory weightsOfRedistribution = new uint256[](1);
        weightsOfRedistribution[0] = 10_000; // expect a full rebalance
        vm.expectRevert(
            abi.encodeWithSelector(ISuperVault.INVALID_SP_FULL_REBALANCE.selector, superformIdsRebalanceFrom[0])
        );
        // Perform the rebalance
        SuperVault(payable(superVaultAddress)).rebalance{ value: 4 ether }(
            ISuperVault.RebalanceArgs(
                superformIdsRebalanceFrom, amountsRebalanceFrom, finalSuperformIds, weightsOfRedistribution, 100
            )
        );

        vm.stopPrank();
    }

    function test_superVault_rebalance() public {
        vm.startPrank(deployer);
        SOURCE_CHAIN = ETH;

        uint256 amount = 10_000e6;
        // Perform a direct deposit to the SuperVault
        _directDeposit(deployer, SUPER_VAULT_ID1, amount, "");

        _assertSuperPositionsSplitAccordingToWeights(ETH);

        // Test case 1
        uint256[] memory finalIndexes = new uint256[](2);
        finalIndexes[0] = 1;
        finalIndexes[1] = 2;
        uint256[] memory finalWeightsTargets = new uint256[](2);
        finalWeightsTargets[0] = 4000;
        finalWeightsTargets[1] = 6000;
        uint256[] memory indexesRebalanceFrom = new uint256[](1);
        indexesRebalanceFrom[0] = 0;

        _performRebalance(SUPER_VAULT_ID1, finalIndexes, finalWeightsTargets, indexesRebalanceFrom, allSuperformIds, "");
        _assertWeightsWithinTolerance(finalIndexes, finalWeightsTargets);

        // Test case 2
        finalIndexes = new uint256[](2);
        finalIndexes[0] = 0;
        finalIndexes[1] = 2;
        finalWeightsTargets = new uint256[](2);
        finalWeightsTargets[0] = 5000;
        finalWeightsTargets[1] = 5000;
        indexesRebalanceFrom = new uint256[](2);
        indexesRebalanceFrom[0] = 1;
        indexesRebalanceFrom[1] = 2;

        _performRebalance(SUPER_VAULT_ID1, finalIndexes, finalWeightsTargets, indexesRebalanceFrom, allSuperformIds, "");
        _assertWeightsWithinTolerance(finalIndexes, finalWeightsTargets);
    }

    function test_superVault_rebalance_newVault() public {
        vm.startPrank(deployer);
        SOURCE_CHAIN = ETH;

        uint256[] memory superformIds = new uint256[](1);
        superformIds[0] = allSuperformIds[3];
        bool[] memory isWhitelisted = new bool[](1);
        isWhitelisted[0] = true;

        ISuperVault(superVault).setWhitelist(superformIds, isWhitelisted);

        uint256 amount = 10_000e6;
        // Perform a direct deposit to the SuperVault
        _directDeposit(deployer, SUPER_VAULT_ID1, amount, "");

        _assertSuperPositionsSplitAccordingToWeights(ETH);

        // This test will calculate an increase to index 0, put indexes 1 and 2 to 0% and add the rest to index 3
        uint256[] memory finalIndexes = new uint256[](2);
        finalIndexes[0] = 0;
        finalIndexes[1] = 3;
        uint256[] memory finalWeightsTargets = new uint256[](2);
        finalWeightsTargets[0] = 5000;
        finalWeightsTargets[1] = 5000;
        uint256[] memory indexesRebalanceFrom = new uint256[](2);
        indexesRebalanceFrom[0] = 1;
        indexesRebalanceFrom[1] = 2;

        _performRebalance(SUPER_VAULT_ID1, finalIndexes, finalWeightsTargets, indexesRebalanceFrom, allSuperformIds, "");
        _assertWeightsWithinTolerance(finalIndexes, finalWeightsTargets);

        finalIndexes = new uint256[](3);
        finalIndexes[0] = 0;
        finalIndexes[1] = 1;
        finalIndexes[2] = 2;

        finalWeightsTargets = new uint256[](3);
        finalWeightsTargets[0] = 2500;
        finalWeightsTargets[1] = 5000;
        finalWeightsTargets[2] = 2500;

        indexesRebalanceFrom = new uint256[](2);
        indexesRebalanceFrom[0] = 0;
        indexesRebalanceFrom[1] = 3;

        _performRebalance(SUPER_VAULT_ID1, finalIndexes, finalWeightsTargets, indexesRebalanceFrom, allSuperformIds, "");
        _assertWeightsWithinTolerance(finalIndexes, finalWeightsTargets);
    }

    function test_superVault_rebalance_5115() public {
        vm.startPrank(deployer);
        SOURCE_CHAIN = ETH;

        uint256 amount = 10_000e6;
        // Perform a direct deposit to the SuperVault
        _directDeposit(deployer, SUPER_VAULT_ID1, amount, "");

        _assertSuperPositionsSplitAccordingToWeights(ETH);

        // This test will calculate an increase to index 0, put indexes 1 and 2 to 0% and add the rest to index 3
        uint256[] memory finalIndexes = new uint256[](2);
        finalIndexes[0] = 0;
        finalIndexes[1] = 4;
        uint256[] memory finalWeightsTargets = new uint256[](2);
        finalWeightsTargets[0] = 3000;
        finalWeightsTargets[1] = 7000;
        uint256[] memory indexesRebalanceFrom = new uint256[](3);
        indexesRebalanceFrom[0] = 0;
        indexesRebalanceFrom[1] = 1;
        indexesRebalanceFrom[2] = 2;

        _performRebalance(SUPER_VAULT_ID1, finalIndexes, finalWeightsTargets, indexesRebalanceFrom, allSuperformIds, "");
        _assertWeightsWithinTolerance(finalIndexes, finalWeightsTargets);

        finalIndexes = new uint256[](2);
        finalIndexes[0] = 0;
        finalIndexes[1] = 4;
        finalWeightsTargets = new uint256[](2);
        finalWeightsTargets[0] = 5000;
        finalWeightsTargets[1] = 5000;
        indexesRebalanceFrom = new uint256[](1);
        indexesRebalanceFrom[0] = 4;

        _performRebalance(SUPER_VAULT_ID1, finalIndexes, finalWeightsTargets, indexesRebalanceFrom, allSuperformIds, "");
        _assertWeightsWithinTolerance(finalIndexes, finalWeightsTargets);

        console.log("----withdrawing full balance----");

        // Withdraw full balance
        _directWithdraw(deployer, SUPER_VAULT_ID1, false);

        _assertUnderlyingBalanceAfterFullWithdraw(ETH);
    }

    function test_superVault_rebalance_5115_stress() public {
        vm.startPrank(deployer);
        SOURCE_CHAIN = ETH;

        (address superFormSuperVault,,) = SUPER_VAULT_ID1.getSuperform();
        address superVaultAddress = IBaseForm(superFormSuperVault).getVaultAddress();

        // Initial deposit
        uint256 amount = 50_000e6; // Larger initial deposit
        _directDeposit(deployer, SUPER_VAULT_ID1, amount, "");
        _assertSuperPositionsSplitAccordingToWeights(ETH);

        for (uint256 i = 0; i < allSuperformIds.length; i++) {
            uint256 spBalanceInSuperVault =
                SuperPositions(SUPER_POSITIONS_SOURCE).balanceOf(superVaultAddress, allSuperformIds[i]);

            console.log("SuperPosition balance for underlying Superform", i, ":", spBalanceInSuperVault);
        }

        // First rebalance: Move everything to index 4 (5115)
        uint256[] memory finalIndexes = new uint256[](1);
        finalIndexes[0] = 4;
        uint256[] memory finalWeightsTargets = new uint256[](1);
        finalWeightsTargets[0] = 10_000; // 100%
        uint256[] memory indexesRebalanceFrom = new uint256[](3);
        indexesRebalanceFrom[0] = 0;
        indexesRebalanceFrom[1] = 1;
        indexesRebalanceFrom[2] = 2;
        console.log("----rebalancing to 100% in index 4----");

        _performRebalance(SUPER_VAULT_ID1, finalIndexes, finalWeightsTargets, indexesRebalanceFrom, allSuperformIds, "");
        _assertWeightsWithinTolerance(finalIndexes, finalWeightsTargets);

        for (uint256 i = 0; i < allSuperformIds.length; i++) {
            uint256 spBalanceInSuperVault =
                SuperPositions(SUPER_POSITIONS_SOURCE).balanceOf(superVaultAddress, allSuperformIds[i]);

            console.log("SuperPosition balance for underlying Superform", i, ":", spBalanceInSuperVault);
        }

        console.log("----additional deposit----");
        // Additional single deposit
        _directDeposit(deployer, SUPER_VAULT_ID1, amount, "");
        // Partial single withdraw
        _directWithdraw(deployer, SUPER_VAULT_ID1, true);

        // Second rebalance: Split between index 0 and 4
        finalIndexes = new uint256[](2);
        finalIndexes[0] = 0;
        finalIndexes[1] = 4;
        finalWeightsTargets = new uint256[](2);
        finalWeightsTargets[0] = 4000; // 40%
        finalWeightsTargets[1] = 6000; // 60%
        indexesRebalanceFrom = new uint256[](1);
        indexesRebalanceFrom[0] = 4;
        console.log("----rebalancing to 40% in index 0 and 60% in index 4----");

        _performRebalance(SUPER_VAULT_ID1, finalIndexes, finalWeightsTargets, indexesRebalanceFrom, allSuperformIds, "");
        _assertWeightsWithinTolerance(finalIndexes, finalWeightsTargets);

        for (uint256 i = 0; i < allSuperformIds.length; i++) {
            uint256 spBalanceInSuperVault =
                SuperPositions(SUPER_POSITIONS_SOURCE).balanceOf(superVaultAddress, allSuperformIds[i]);

            console.log("SuperPosition balance for underlying Superform", i, ":", spBalanceInSuperVault);
        }
        console.log("----partial withdraw----");
        // Partial withdraw
        _directWithdraw(deployer, SUPER_VAULT_ID1, true);

        // Third rebalance: Move everything back to index 4
        finalIndexes = new uint256[](1);
        finalIndexes[0] = 4;
        finalWeightsTargets = new uint256[](1);
        finalWeightsTargets[0] = 10_000; // 100%
        indexesRebalanceFrom = new uint256[](1);
        indexesRebalanceFrom[0] = 0;
        console.log("----rebalancing to 100% in index 4----");
        _performRebalance(SUPER_VAULT_ID1, finalIndexes, finalWeightsTargets, indexesRebalanceFrom, allSuperformIds, "");
        _assertWeightsWithinTolerance(finalIndexes, finalWeightsTargets);

        for (uint256 i = 0; i < allSuperformIds.length; i++) {
            uint256 spBalanceInSuperVault =
                SuperPositions(SUPER_POSITIONS_SOURCE).balanceOf(superVaultAddress, allSuperformIds[i]);

            console.log("SuperPosition balance for underlying Superform", i, ":", spBalanceInSuperVault);
        }
        // Final withdrawal
        console.log("----withdrawing remaining balance----");
        _directWithdraw(deployer, SUPER_VAULT_ID1, false);
        _assertUnderlyingBalanceAfterFullWithdraw(ETH);

        vm.stopPrank();
    }

    function test_superVault_multiUser_stress() public {
        vm.startPrank(deployer);
        SOURCE_CHAIN = ETH;

        (address superFormSuperVault,,) = SUPER_VAULT_ID1.getSuperform();
        address superVaultAddress = IBaseForm(superFormSuperVault).getVaultAddress();
        address usdcToken = getContract(ETH, "USDC");

        // Setup 5 users with different deposit amounts
        address[] memory users_ = new address[](5);
        uint256[] memory depositAmounts = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            users_[i] = address(uint160(0x1000 + i));
            depositAmounts[i] = (i + 1) * 10_000e6; // 10k, 20k, 30k, 40k, 50k USDC
            vm.deal(users_[i], 10 ether);
            deal(usdcToken, users_[i], depositAmounts[i]);
        }

        // First wave of deposits (users 0, 1, 2)
        for (uint256 i = 0; i < 3; i++) {
            vm.startPrank(users_[i]);
            _directDeposit(users_[i], SUPER_VAULT_ID1, depositAmounts[i], "");
            vm.stopPrank();
        }

        _assertSuperPositionsSplitAccordingToWeights(ETH);
        console.log("----Initial deposits completed----");
        _logSuperPositionBalances(superVaultAddress);

        // First rebalance: Move majority to indexes 0 and 1
        uint256[] memory finalIndexes = new uint256[](2);
        finalIndexes[0] = 0;
        finalIndexes[1] = 1;
        uint256[] memory finalWeightsTargets = new uint256[](2);
        finalWeightsTargets[0] = 6000; // 60%
        finalWeightsTargets[1] = 4000; // 40%
        uint256[] memory indexesRebalanceFrom = new uint256[](1);
        indexesRebalanceFrom[0] = 2;

        console.log("----First rebalance: 60% index 0, 40% index 1----");
        vm.startPrank(deployer);
        _performRebalance(SUPER_VAULT_ID1, finalIndexes, finalWeightsTargets, indexesRebalanceFrom, allSuperformIds, "");
        _assertWeightsWithinTolerance(finalIndexes, finalWeightsTargets);
        vm.stopPrank();
        _logSuperPositionBalances(superVaultAddress);

        console.log("----Second wave of deposits (users 3, 4) and first withdrawal (user 0)----");
        vm.startPrank(users_[0]);
        _directWithdraw(users_[0], SUPER_VAULT_ID1, true); // Partial withdrawal
        vm.stopPrank();

        for (uint256 i = 3; i < 5; i++) {
            vm.startPrank(users_[i]);
            _directDeposit(users_[i], SUPER_VAULT_ID1, depositAmounts[i], "");
            vm.stopPrank();
        }

        console.log("----After more deposits and first withdrawal----");
        _logSuperPositionBalances(superVaultAddress);

        // Second rebalance: Redistribute across all three indexes
        finalIndexes = new uint256[](3);
        finalIndexes[0] = 0;
        finalIndexes[1] = 1;
        finalIndexes[2] = 4;
        finalWeightsTargets = new uint256[](3);
        finalWeightsTargets[0] = 4000; // 40%
        finalWeightsTargets[1] = 3000; // 30%
        finalWeightsTargets[2] = 3000; // 30%
        indexesRebalanceFrom = new uint256[](2);
        indexesRebalanceFrom[0] = 0;
        indexesRebalanceFrom[1] = 1;

        console.log("----Second rebalance: 40/30/30 split----");
        vm.startPrank(deployer);
        _performRebalance(SUPER_VAULT_ID1, finalIndexes, finalWeightsTargets, indexesRebalanceFrom, allSuperformIds, "");
        _assertWeightsWithinTolerance(finalIndexes, finalWeightsTargets);
        vm.stopPrank();
        _logSuperPositionBalances(superVaultAddress);

        console.log("----Final wave of mixed actions----");
        vm.startPrank(users_[1]);
        _directWithdraw(users_[1], SUPER_VAULT_ID1, false); // Full withdrawal
        vm.stopPrank();

        vm.startPrank(users_[2]);
        _directWithdraw(users_[2], SUPER_VAULT_ID1, true); // Partial withdrawal
        vm.stopPrank();

        vm.startPrank(users_[3]);
        deal(usdcToken, users_[3], depositAmounts[3]); // Give more USDC
        _directDeposit(users_[3], SUPER_VAULT_ID1, depositAmounts[3], ""); // Additional deposit
        vm.stopPrank();

        console.log("----After final wave of actions----");
        _logSuperPositionBalances(superVaultAddress);

        // Final withdrawals
        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(users_[i]);
            uint256 spBalance = SuperPositions(SUPER_POSITIONS_SOURCE).balanceOf(users_[i], SUPER_VAULT_ID1);
            if (spBalance > 0) {
                _directWithdraw(users_[i], SUPER_VAULT_ID1, false);
            }
            vm.stopPrank();
        }

        console.log("----After all withdrawals----");
        _logSuperPositionBalances(superVaultAddress);
        _assertUnderlyingBalanceAfterFullWithdraw(ETH);

        vm.stopPrank();
    }

    function _logSuperPositionBalances(address superVaultAddress) internal view {
        for (uint256 i = 0; i < allSuperformIds.length; i++) {
            uint256 spBalanceInSuperVault =
                SuperPositions(SUPER_POSITIONS_SOURCE).balanceOf(superVaultAddress, allSuperformIds[i]);
            (address superform,,) = allSuperformIds[i].getSuperform();
            uint256 underlyingBalance = IBaseForm(superform).previewRedeemFrom(spBalanceInSuperVault);
            console.log(
                string.concat(
                    "SuperPosition ",
                    Strings.toString(i),
                    " balance: ",
                    Strings.toString(spBalanceInSuperVault),
                    " (",
                    Strings.toString(underlyingBalance),
                    " underlying)"
                )
            );
        }
    }

    function test_superVault_rebalance_emptyAmountsRebalanceFrom() public {
        uint256[] memory superformIdsRebalanceFrom = new uint256[](2);
        superformIdsRebalanceFrom[0] = underlyingSuperformIds[0];
        superformIdsRebalanceFrom[1] = underlyingSuperformIds[1];

        uint256[] memory superformIdsRebalanceTo = new uint256[](1);
        superformIdsRebalanceTo[0] = underlyingSuperformIds[2];

        uint256[] memory finalWeightsTargets = new uint256[](2);
        finalWeightsTargets[0] = 5000;
        finalWeightsTargets[1] = 5000;

        uint256[] memory amountsRebalanceFrom = new uint256[](0);
        vm.startPrank(deployer);
        vm.expectRevert(ISuperVault.EMPTY_AMOUNTS_REBALANCE_FROM.selector);

        superVault.rebalance(
            ISuperVault.RebalanceArgs(
                superformIdsRebalanceFrom, amountsRebalanceFrom, superformIdsRebalanceTo, finalWeightsTargets, 100
            )
        );
        vm.stopPrank();
    }

    function test_superVault_rebalance_invalidWeights() public {
        vm.startPrank(deployer);
        // Setup
        uint256[] memory superformIdsRebalanceFrom = new uint256[](1);
        superformIdsRebalanceFrom[0] = underlyingSuperformIds[0];

        uint256[] memory amountsRebalanceFrom = new uint256[](1);
        amountsRebalanceFrom[0] = 1e18;

        uint256[] memory superformIdsRebalanceTo = new uint256[](1);
        superformIdsRebalanceTo[0] = underlyingSuperformIds[2];

        uint256[] memory weightsOfRedistribution = new uint256[](1);
        weightsOfRedistribution[0] = 100_000; // > TOTAL_WEIGHT (10_000)

        // Get SuperVault address
        (address superFormSuperVault,,) = SUPER_VAULT_ID1.getSuperform();
        address superVaultAddress = IBaseForm(superFormSuperVault).getVaultAddress();

        // Expect revert with ARRAY_LENGTH_MISMATCH error
        vm.expectRevert(abi.encodeWithSignature("INVALID_WEIGHTS()"));

        // Call rebalance function
        SuperVault(payable(superVaultAddress)).rebalance(
            ISuperVault.RebalanceArgs(
                superformIdsRebalanceFrom, amountsRebalanceFrom, superformIdsRebalanceTo, weightsOfRedistribution, 100
            )
        );
        vm.stopPrank();
    }

    function test_rebalanceArrayLengthMismatch() public {
        vm.startPrank(deployer);
        // Setup
        uint256[] memory superformIdsRebalanceFrom = new uint256[](2);
        superformIdsRebalanceFrom[0] = underlyingSuperformIds[0];
        superformIdsRebalanceFrom[1] = underlyingSuperformIds[1];

        uint256[] memory amountsRebalanceFrom = new uint256[](3); // Mismatched length
        amountsRebalanceFrom[0] = 1e18;
        amountsRebalanceFrom[1] = 2e18;
        amountsRebalanceFrom[2] = 3e18;

        uint256[] memory superformIdsRebalanceTo = new uint256[](1);
        superformIdsRebalanceTo[0] = underlyingSuperformIds[2];

        uint256[] memory weightsOfRedistribution = new uint256[](1);
        weightsOfRedistribution[0] = 10_000;

        // Get SuperVault address
        (address superFormSuperVault,,) = SUPER_VAULT_ID1.getSuperform();
        address superVaultAddress = IBaseForm(superFormSuperVault).getVaultAddress();

        // Expect revert with ARRAY_LENGTH_MISMATCH error
        vm.expectRevert(abi.encodeWithSignature("ARRAY_LENGTH_MISMATCH()"));

        // Call rebalance function
        SuperVault(payable(superVaultAddress)).rebalance(
            ISuperVault.RebalanceArgs(
                superformIdsRebalanceFrom, amountsRebalanceFrom, superformIdsRebalanceTo, weightsOfRedistribution, 100
            )
        );
        vm.stopPrank();
    }

    function test_rebalance_onlyStrategist() public {
        // Setup rebalance parameters
        uint256[] memory superformIdsRebalanceFrom = new uint256[](1);
        superformIdsRebalanceFrom[0] = underlyingSuperformIds[0];

        uint256[] memory amountsRebalanceFrom = new uint256[](1);
        amountsRebalanceFrom[0] = 1 ether;

        uint256[] memory superformIdsRebalanceTo = new uint256[](1);
        superformIdsRebalanceTo[0] = underlyingSuperformIds[1];

        uint256[] memory weightsOfRedistribution = new uint256[](1);
        weightsOfRedistribution[0] = 10_000;

        // Get SuperVault address
        (address superFormSuperVault,,) = SUPER_VAULT_ID1.getSuperform();
        address superVaultAddress = IBaseForm(superFormSuperVault).getVaultAddress();

        // Try to call rebalance from a non-strategist address
        address nonStrategist = address(0xdead);
        vm.startPrank(nonStrategist);
        vm.expectRevert(ISuperVault.NOT_SUPER_VAULTS_STRATEGIST.selector);
        SuperVault(payable(superVaultAddress)).rebalance(
            ISuperVault.RebalanceArgs(
                superformIdsRebalanceFrom, amountsRebalanceFrom, superformIdsRebalanceTo, weightsOfRedistribution, 100
            )
        );
        vm.stopPrank();
    }

    function test_harvestAndReport() public {
        SOURCE_CHAIN = ETH;

        uint256 depositAmount = 10_000e6; // 10,000 USDC
        uint256 numUsers = 30;
        address[] memory depositUsers = new address[](numUsers);

        // Generate 30 user addresses
        for (uint256 i = 1; i < numUsers; i++) {
            depositUsers[i] = address(uint160(0x1000 + i));
        }

        // Get USDC token address
        address usdcToken = getContract(ETH, "USDC");

        for (uint256 i = 1; i < numUsers; i++) {
            vm.deal(depositUsers[i], 10 ether);
            // Deal USDC tokens to the current user
            deal(usdcToken, depositUsers[i], depositAmount);

            // Perform direct deposit for the current user
            vm.startPrank(depositUsers[i]);
            _directDeposit(depositUsers[i], SUPER_VAULT_ID1, depositAmount, "");
            vm.stopPrank();

            // Warp 1 day
            vm.warp(block.timestamp + 1 days);
        }

        vm.stopPrank();
        // Get SuperVault address
        (address superFormSuperVault,,) = SUPER_VAULT_ID1.getSuperform();
        address superVaultAddress = IBaseForm(superFormSuperVault).getVaultAddress();
        (bool success, bytes memory returnData) = superVaultAddress.call(abi.encodeWithSignature("totalAssets()"));
        require(success, "totalAssets() call failed");

        uint256 totalAssets = abi.decode(returnData, (uint256));
        console.log("Total Assets:", totalAssets);

        vm.warp(block.timestamp + 30 days);
        (success, returnData) = superVaultAddress.call(abi.encodeWithSignature("totalAssets()"));
        require(success, "totalAssets() call failed");
        uint256 totalAssetsAfter = abi.decode(returnData, (uint256));
        console.log("Total Assets after 30 days:", totalAssetsAfter);

        assertEq(totalAssetsAfter, totalAssets);

        uint256 balanceFeeRecipientBeforeReport = IERC4626(address(superVault)).balanceOf(PERFORMANCE_FEE_RECIPIENT);
        console.log("Balance of performance fee recipient before report:", balanceFeeRecipientBeforeReport);

        // Call report() function with a keeper
        vm.prank(KEEPER);
        (success,) = superVaultAddress.call(abi.encodeWithSignature("report()"));
        require(success, "report() call failed");

        (success, returnData) = superVaultAddress.call(abi.encodeWithSignature("totalAssets()"));
        require(success, "totalAssets() call failed");
        uint256 totalAssetsAfterReport = abi.decode(returnData, (uint256));

        console.log("Total Assets after report:", totalAssetsAfterReport);

        assertGt(totalAssetsAfterReport, totalAssetsAfter);

        uint256 balanceFeeRecipientAfterReport = IERC4626(address(superVault)).balanceOf(PERFORMANCE_FEE_RECIPIENT);
        console.log("Balance of performance fee recipient:", balanceFeeRecipientAfterReport);

        assertGt(balanceFeeRecipientAfterReport, balanceFeeRecipientBeforeReport);
    }

    function test_setDepositLimit() public {
        uint256 newDepositLimit = 2000 ether;
        (address superFormSuperVault,,) = SUPER_VAULT_ID1.getSuperform();
        address superVaultAddress = IBaseForm(superFormSuperVault).getVaultAddress();

        // Expect the DepositLimitSet event to be emitted
        vm.expectEmit(true, true, true, true);
        emit ISuperVault.DepositLimitSet(newDepositLimit);

        // Call setDepositLimit as the superVaultsStrategist
        vm.prank(deployer);
        SuperVault(payable(superVaultAddress)).setDepositLimit(newDepositLimit);

        // Verify the new deposit limit
        assertEq(SuperVault(payable(superVaultAddress)).availableDepositLimit(address(0)), newDepositLimit);
    }

    //////////////////////////////////////////////////////////////
    //                     FUZZ TESTS                           //
    //////////////////////////////////////////////////////////////

    function testFuzz_superVault_rebalance(uint256 finalWeightsOne, uint256 amount, uint256 finalIndex) public {
        vm.startPrank(deployer);
        SOURCE_CHAIN = ETH;

        vm.assume(amount > 0);
        finalIndex = bound(finalIndex, 1, 2);
        amount = bound(amount, 1000e6, 100_000e6);

        // Perform a direct deposit to the SuperVault
        (address superform,,) = SUPER_VAULT_ID1.getSuperform();
        deal(IBaseForm(superform).getVaultAsset(), deployer, amount);
        _directDeposit(deployer, SUPER_VAULT_ID1, amount, "");

        _assertSuperPositionsSplitAccordingToWeights(ETH);

        // determine fuzzed variables

        uint256[] memory underlyingIndexes = _calculateUnderlyingIndexes();

        address superVaultAddress = IBaseForm(superform).getVaultAddress();

        uint256[] memory calculatedWeights = _calculateRealWeights(superVaultAddress, underlyingIndexes);

        uint256[] memory finalIndexes = new uint256[](2);
        finalIndexes[0] = finalIndex;

        if (finalIndex == 1) {
            finalIndexes[1] = 2;
        } else if (finalIndex == 2) {
            finalIndexes[1] = 1;
        }
        // Sort finalIndexes
        if (finalIndexes[0] > finalIndexes[1]) {
            (finalIndexes[0], finalIndexes[1]) = (finalIndexes[1], finalIndexes[0]);
        }

        uint256[] memory indexesRebalanceFrom = new uint256[](1);
        indexesRebalanceFrom[0] = 0;

        finalWeightsOne = bound(finalWeightsOne, calculatedWeights[finalIndexes[0]], 6600);
        uint256 finalWeightsTwo = 10_000 - finalWeightsOne;

        console.log("finalWeightsOne", finalWeightsOne);
        console.log("finalWeightsTwo", finalWeightsTwo);

        uint256[] memory finalWeightsTargets = new uint256[](2);
        finalWeightsTargets[0] = finalWeightsOne;
        finalWeightsTargets[1] = finalWeightsTwo;

        // perform rebalance and assert
        _performRebalance(SUPER_VAULT_ID1, finalIndexes, finalWeightsTargets, indexesRebalanceFrom, allSuperformIds, "");
        _assertWeightsWithinTolerance(finalIndexes, finalWeightsTargets);
    }

    struct BatchTestVars {
        uint256[] oneFormGas;
        uint256[] twoFormGas;
        uint256[] threeFormGas;
        uint256 depositAmount;
        uint256 oneFormAvg;
        uint256 twoFormAvg;
        uint256 threeFormAvg;
        uint256 twoFormIndex;
        uint256[] oneSuperformIds;
        uint256[] oneWeights;
        uint256[] twoSuperformIds;
        uint256[] twoWeights;
        uint256[] threeSuperformIds;
        uint256[] threeWeights;
    }

    function test_gas_consumption_deposits() public {
        vm.startPrank(deployer);
        SOURCE_CHAIN = ETH;

        BatchTestVars memory vars = BatchTestVars({
            oneFormGas: new uint256[](3),
            twoFormGas: new uint256[](3),
            threeFormGas: new uint256[](1),
            depositAmount: 10_000e6,
            oneFormAvg: 0,
            twoFormAvg: 0,
            threeFormAvg: 0,
            twoFormIndex: 0,
            oneSuperformIds: new uint256[](1),
            oneWeights: new uint256[](1),
            twoSuperformIds: new uint256[](2),
            twoWeights: new uint256[](2),
            threeSuperformIds: new uint256[](3),
            threeWeights: new uint256[](3)
        });

        // Test single form combinations
        console.log("\n=== Testing Single Form Combinations ===");
        string memory snapshotName;
        for (uint256 i = 0; i < 3; i++) {
            vars.oneSuperformIds[0] = gasTestSuperformIds[i];
            vars.oneWeights[0] = 10_000;
            snapshotName = string.concat("Deposit with one underlying superform: ", gasTestSuperformNames[i]);
            console.log(snapshotName);

            SuperVault superVaultOne = new SuperVault(
                getContract(ETH, "SuperRegistry"),
                getContract(ETH, "USDC"),
                deployer,
                deployer,
                string.concat("USDCSuperVaultOne", Strings.toString(i)),
                type(uint256).max,
                vars.oneSuperformIds,
                vars.oneWeights
            );

            (uint256 superVaultIdOne,) = SuperformFactory(getContract(SOURCE_CHAIN, "SuperformFactory")).createSuperform(
                1, address(superVaultOne)
            );

            deal(getContract(ETH, "USDC"), deployer, vars.depositAmount);
            vars.oneFormGas[i] = _directDeposit(deployer, superVaultIdOne, vars.depositAmount, snapshotName);
        }

        // Test two form combinations
        console.log("\n=== Testing Two Form Combinations ===");
        for (uint256 i = 0; i < 2; i++) {
            for (uint256 j = i + 1; j < 3; j++) {
                snapshotName = string.concat(
                    "Deposit with two underlying superforms: ",
                    gasTestSuperformNames[i],
                    " + ",
                    gasTestSuperformNames[j]
                );
                console.log(snapshotName);

                vars.twoSuperformIds[0] = gasTestSuperformIds[i];
                vars.twoSuperformIds[1] = gasTestSuperformIds[j];
                vars.twoWeights[0] = 5000;
                vars.twoWeights[1] = 5000;

                SuperVault superVaultTwo = new SuperVault(
                    getContract(ETH, "SuperRegistry"),
                    getContract(ETH, "USDC"),
                    deployer,
                    deployer,
                    string.concat("USDCSuperVaultTwo", Strings.toString(vars.twoFormIndex)),
                    type(uint256).max,
                    vars.twoSuperformIds,
                    vars.twoWeights
                );

                (uint256 superVaultIdTwo,) = SuperformFactory(getContract(SOURCE_CHAIN, "SuperformFactory"))
                    .createSuperform(1, address(superVaultTwo));

                deal(getContract(ETH, "USDC"), deployer, vars.depositAmount);
                vars.twoFormGas[vars.twoFormIndex] =
                    _directDeposit(deployer, superVaultIdTwo, vars.depositAmount, snapshotName);
                vars.twoFormIndex++;
            }
        }

        // Test three form combination
        console.log("\n=== Testing Three Form Combination ===");
        snapshotName = string.concat(
            "Deposit with three underlying superforms: ",
            gasTestSuperformNames[0],
            " + ",
            gasTestSuperformNames[1],
            " + ",
            gasTestSuperformNames[2]
        );
        console.log(snapshotName);

        vars.threeSuperformIds[0] = gasTestSuperformIds[0];
        vars.threeSuperformIds[1] = gasTestSuperformIds[1];
        vars.threeSuperformIds[2] = gasTestSuperformIds[2];
        vars.threeWeights[0] = 3334;
        vars.threeWeights[1] = 3333;
        vars.threeWeights[2] = 3333;

        SuperVault superVaultThree = new SuperVault(
            getContract(ETH, "SuperRegistry"),
            getContract(ETH, "USDC"),
            deployer,
            deployer,
            "USDCSuperVaultThree",
            type(uint256).max,
            vars.threeSuperformIds,
            vars.threeWeights
        );

        (uint256 superVaultIdThree,) =
            SuperformFactory(getContract(SOURCE_CHAIN, "SuperformFactory")).createSuperform(1, address(superVaultThree));

        deal(getContract(ETH, "USDC"), deployer, vars.depositAmount);
        vars.threeFormGas[0] = _directDeposit(deployer, superVaultIdThree, vars.depositAmount, snapshotName);
        vars.threeFormAvg = vars.threeFormGas[0];

        // Calculate averages
        for (uint256 i = 0; i < vars.oneFormGas.length; i++) {
            vars.oneFormAvg += vars.oneFormGas[i];
        }
        vars.oneFormAvg = vars.oneFormAvg / vars.oneFormGas.length;

        for (uint256 i = 0; i < vars.twoFormGas.length; i++) {
            vars.twoFormAvg += vars.twoFormGas[i];
        }
        vars.twoFormAvg = vars.twoFormAvg / vars.twoFormGas.length;

        // Print gas consumption summary
        console.log("\n=== Gas Consumption Summary ===");
        for (uint256 i = 0; i < vars.oneFormGas.length; i++) {
            console.log(
                string.concat(
                    "Gas for single form (", gasTestSuperformNames[i], "): ", Strings.toString(vars.oneFormGas[i])
                )
            );
        }

        uint256 twoFormIndex2 = 0;
        for (uint256 i = 0; i < 2; i++) {
            for (uint256 j = i + 1; j < 3; j++) {
                console.log(
                    string.concat(
                        "Gas for two forms (",
                        gasTestSuperformNames[i],
                        " + ",
                        gasTestSuperformNames[j],
                        "): ",
                        Strings.toString(vars.twoFormGas[twoFormIndex2])
                    )
                );
                twoFormIndex2++;
            }
        }

        console.log(
            string.concat(
                "Gas for three forms (",
                gasTestSuperformNames[0],
                " + ",
                gasTestSuperformNames[1],
                " + ",
                gasTestSuperformNames[2],
                "): ",
                Strings.toString(vars.threeFormGas[0])
            )
        );

        console.log("\n=== Averages ===");
        console.log("Average gas for 1 underlying superform:", vars.oneFormAvg);
        console.log("Average gas for 2 underlying superforms:", vars.twoFormAvg);
        console.log("Average gas for 3 underlying superforms:", vars.threeFormAvg);

        vm.stopPrank();
    }

    struct BatchTestVarsRebalance {
        uint256[] twoFormGas;
        uint256[] threeFormGas;
        uint256 depositAmount;
        uint256 twoFormAvg;
        uint256 threeFormAvg;
        uint256 twoFormIndex;
        uint256[] twoSuperformIds;
        uint256[] twoWeights;
        uint256[] threeSuperformIds;
        uint256[] threeWeights;
    }

    function test_gas_consumption_rebalance() public {
        vm.startPrank(deployer);
        SOURCE_CHAIN = ETH;

        BatchTestVarsRebalance memory vars = BatchTestVarsRebalance({
            twoFormGas: new uint256[](3),
            threeFormGas: new uint256[](1),
            depositAmount: 10_000e6,
            twoFormAvg: 0,
            threeFormAvg: 0,
            twoFormIndex: 0,
            twoSuperformIds: new uint256[](2),
            twoWeights: new uint256[](2),
            threeSuperformIds: new uint256[](3),
            threeWeights: new uint256[](3)
        });
        uint256[] memory finalIndexes;
        uint256[] memory finalWeightsTargets;
        uint256[] memory indexesRebalanceFrom;
        // Test two form combinations
        console.log("\n=== Testing Two Form Rebalance Gas Consumption ===");
        string memory snapshotName;
        for (uint256 i = 0; i < 2; i++) {
            for (uint256 j = i + 1; j < 3; j++) {
                snapshotName = string.concat(
                    "Rebalance with two underlying superforms: ",
                    gasTestSuperformNames[i],
                    " + ",
                    gasTestSuperformNames[j]
                );
                console.log(snapshotName);

                vars.twoSuperformIds[0] = gasTestSuperformIds[i];
                vars.twoSuperformIds[1] = gasTestSuperformIds[j];
                vars.twoWeights[0] = 5000;
                vars.twoWeights[1] = 5000;

                SuperVault superVaultTwo = new SuperVault(
                    getContract(ETH, "SuperRegistry"),
                    getContract(ETH, "USDC"),
                    deployer,
                    deployer,
                    string.concat("USDCSuperVaultTwo", Strings.toString(vars.twoFormIndex)),
                    type(uint256).max,
                    vars.twoSuperformIds,
                    vars.twoWeights
                );

                (uint256 superVaultIdTwo,) = SuperformFactory(getContract(SOURCE_CHAIN, "SuperformFactory"))
                    .createSuperform(1, address(superVaultTwo));

                // Initial deposit
                deal(getContract(ETH, "USDC"), deployer, vars.depositAmount);
                _directDeposit(deployer, superVaultIdTwo, vars.depositAmount, "");

                // Perform rebalance
                finalIndexes = new uint256[](2);
                finalIndexes[0] = i;
                finalIndexes[1] = j;
                finalWeightsTargets = new uint256[](2);
                finalWeightsTargets[0] = 6000; // 60%
                finalWeightsTargets[1] = 4000; // 40%
                indexesRebalanceFrom = new uint256[](1);
                indexesRebalanceFrom[0] = j;

                vars.twoFormGas[vars.twoFormIndex] = _performRebalance(
                    superVaultIdTwo,
                    finalIndexes,
                    finalWeightsTargets,
                    indexesRebalanceFrom,
                    gasTestSuperformIds,
                    snapshotName
                );
                console.log(snapshotName, "Gas used:", vars.twoFormGas[vars.twoFormIndex]);
                vars.twoFormIndex++;
            }
        }

        // Test three form combination
        console.log("\n=== Testing Three Form Rebalance Gas Consumption ===");
        snapshotName = string.concat(
            "Rebalance with three underlying superforms: ",
            gasTestSuperformNames[0],
            " + ",
            gasTestSuperformNames[1],
            " + ",
            gasTestSuperformNames[2]
        );
        console.log(snapshotName);

        vars.threeSuperformIds[0] = gasTestSuperformIds[0];
        vars.threeSuperformIds[1] = gasTestSuperformIds[1];
        vars.threeSuperformIds[2] = gasTestSuperformIds[2];
        vars.threeWeights[0] = 3334;
        vars.threeWeights[1] = 3333;
        vars.threeWeights[2] = 3333;

        SuperVault superVaultThree = new SuperVault(
            getContract(ETH, "SuperRegistry"),
            getContract(ETH, "USDC"),
            deployer,
            deployer,
            "USDCSuperVaultThree",
            type(uint256).max,
            vars.threeSuperformIds,
            vars.threeWeights
        );

        (uint256 superVaultIdThree,) =
            SuperformFactory(getContract(SOURCE_CHAIN, "SuperformFactory")).createSuperform(1, address(superVaultThree));

        // Initial deposit
        deal(getContract(ETH, "USDC"), deployer, vars.depositAmount);
        _directDeposit(deployer, superVaultIdThree, vars.depositAmount, "");

        // Perform rebalance
        finalIndexes = new uint256[](3);
        finalIndexes[0] = 0;
        finalIndexes[1] = 1;
        finalIndexes[2] = 2;
        finalWeightsTargets = new uint256[](3);
        finalWeightsTargets[0] = 5000; // 50%
        finalWeightsTargets[1] = 3000; // 30%
        finalWeightsTargets[2] = 2000; // 20%
        indexesRebalanceFrom = new uint256[](2);
        indexesRebalanceFrom[0] = 1;
        indexesRebalanceFrom[1] = 2;

        vars.threeFormGas[0] = _performRebalance(
            superVaultIdThree,
            finalIndexes,
            finalWeightsTargets,
            indexesRebalanceFrom,
            gasTestSuperformIds,
            snapshotName
        );
        console.log(snapshotName, "Gas used:", vars.threeFormGas[0]);

        // Calculate averages
        for (uint256 i = 0; i < vars.twoFormGas.length; i++) {
            vars.twoFormAvg += vars.twoFormGas[i];
        }
        vars.twoFormAvg = vars.twoFormAvg / vars.twoFormGas.length;
        vars.threeFormAvg = vars.threeFormGas[0];

        // Print summary
        console.log("\n=== Gas Consumption Summary ===");
        uint256 twoFormIndex2 = 0;
        for (uint256 i = 0; i < 2; i++) {
            for (uint256 j = i + 1; j < 3; j++) {
                console.log(
                    string.concat(
                        "Gas for two forms rebalance (",
                        gasTestSuperformNames[i],
                        " + ",
                        gasTestSuperformNames[j],
                        "): ",
                        Strings.toString(vars.twoFormGas[twoFormIndex2])
                    )
                );
                twoFormIndex2++;
            }
        }

        console.log(
            string.concat(
                "Gas for three forms rebalance (",
                gasTestSuperformNames[0],
                " + ",
                gasTestSuperformNames[1],
                " + ",
                gasTestSuperformNames[2],
                "): ",
                Strings.toString(vars.threeFormGas[0])
            )
        );

        console.log("\n=== Averages ===");
        console.log("Average gas for 2 underlying superforms rebalance:", vars.twoFormAvg);
        console.log("Average gas for 3 underlying superforms rebalance:", vars.threeFormAvg);

        vm.stopPrank();
    }

    struct CompareEarningsVars {
        uint256 underlyingSfId;
        uint256[] superformIds;
        uint256[] weights;
        uint256 newSuperVaultId;
        uint256 depositAmount;
        address superVaultAddress;
        uint256 initialSuperVaultShares;
        uint256 initialDirectShares;
        uint256 yieldAmount;
        address underlyingSuperform;
        address underlyingVault;
        uint256 superPositonsAmountSuperVault;
        uint256 superPositonsAmountDirect;
        address superVaultSuperform;
        uint256 finalSuperVaultValue;
        uint256 finalDirectValue;
        uint256 superVaultEarnings;
        uint256 directEarnings;
    }

    function test_superVault_compare_earnings() public {
        vm.startPrank(deployer);
        SOURCE_CHAIN = ETH;
        vm.selectFork(FORKS[SOURCE_CHAIN]);

        // Test each gasTestSuperformId
        for (uint256 i = 0; i < gasTestSuperformIds.length; i++) {
            console.log("\n=== Testing Superform:", gasTestSuperformNames[i], "===");

            CompareEarningsVars memory vars;
            vars.underlyingSfId = gasTestSuperformIds[i];

            // Create a new SuperVault with a single underlying vault
            vars.superformIds = new uint256[](1);
            vars.superformIds[0] = vars.underlyingSfId;

            vars.weights = new uint256[](1);
            vars.weights[0] = 10_000; // 100% allocation to single vault

            string memory vaultName = string.concat("TestCompareEarningsVault_", gasTestSuperformNames[i]);

            SuperVault newSuperVault = new SuperVault(
                getContract(ETH, "SuperRegistry"),
                getContract(ETH, "USDC"),
                deployer,
                deployer,
                vaultName,
                type(uint256).max,
                vars.superformIds,
                vars.weights
            );

            vars.superVaultAddress = address(newSuperVault);

            /// @dev warning dont do the following in production under the risk of sandwiching
            (bool successInitials,) =
                vars.superVaultAddress.call(abi.encodeWithSignature("setProfitMaxUnlockTime(uint256)", 0));
            require(successInitials, "setProfitMaxUnlockTime(uint256) call failed");

            (successInitials,) = vars.superVaultAddress.call(abi.encodeWithSignature("setPerformanceFee(uint16)", 0));
            require(successInitials, "setPerformanceFee(uint16) call failed");

            // Create superform for the new vault
            (vars.newSuperVaultId,) = SuperformFactory(getContract(SOURCE_CHAIN, "SuperformFactory")).createSuperform(
                1, vars.superVaultAddress
            );

            // Initial setup
            vars.depositAmount = 10_000e6; // 10,000 USDC
            deal(getContract(ETH, "USDC"), deployer, vars.depositAmount * 2); // Double for both deposits

            console.log("---FIRST DEPOSIT THROUGH SUPER VAULT---");
            _directDeposit(deployer, vars.newSuperVaultId, vars.depositAmount, "");
            {
                (bool success, bytes memory returnData) =
                    vars.superVaultAddress.call(abi.encodeWithSignature("totalSupply()"));
                require(success, "totalSupply() call failed");
                console.log("TotalSupply After Deposit:", abi.decode(returnData, (uint256)));
            }

            console.log("---SECOND DEPOSIT THROUGH SUPERFORM---");
            _directDeposit(deployer, vars.underlyingSfId, vars.depositAmount, "");

            console.log("---SIMULATING YIELD---");

            // Simulate 1 day passing and vault earnings
            vm.warp(block.timestamp + 1 days);

            // Mock some yield for the underlying vault (e.g., 10% APY = ~0.026% daily)
            (vars.underlyingSuperform,,) = vars.underlyingSfId.getSuperform();
            vars.underlyingVault = IBaseForm(vars.underlyingSuperform).getVaultAddress();
            vars.yieldAmount = (vars.depositAmount * 26) / 100_000; // 0.026% of deposit
            deal(
                getContract(ETH, "USDC"),
                vars.underlyingVault,
                IERC20(getContract(ETH, "USDC")).balanceOf(vars.underlyingVault) + vars.yieldAmount
            );

            console.log("---CALLING REPORT---");

            {
                (bool success, bytes memory returnData) =
                    vars.superVaultAddress.call(abi.encodeWithSignature("totalAssets()"));
                require(success, "totalAssets() call failed");

                uint256 totalAssetsBefore = abi.decode(returnData, (uint256));
                console.log("Total Assets Before Report:", totalAssetsBefore);

                (success, returnData) = vars.superVaultAddress.call(abi.encodeWithSignature("totalSupply()"));
                require(success, "totalSupply() call failed");
                console.log("TotalSupply Before Report:", abi.decode(returnData, (uint256)));

                // call report on the SuperVault
                (success,) = vars.superVaultAddress.call(abi.encodeWithSignature("report()"));
                if (!success) {
                    revert("Report not successful");
                }

                (success, returnData) = vars.superVaultAddress.call(abi.encodeWithSignature("totalSupply()"));
                require(success, "totalSupply() call failed");
                console.log("TotalSupply After Report:", abi.decode(returnData, (uint256)));

                (success, returnData) = vars.superVaultAddress.call(abi.encodeWithSignature("totalAssets()"));
                require(success, "totalAssets() call failed");

                uint256 totalAssetsAfter = abi.decode(returnData, (uint256));
                console.log("Total Assets After Report:", totalAssetsAfter);
            }

            console.log("---LOGGING FINAL VALUES---");
            vars.superPositonsAmountSuperVault =
                SuperPositions(SUPER_POSITIONS_SOURCE).balanceOf(deployer, vars.newSuperVaultId);
            vars.superPositonsAmountDirect =
                SuperPositions(SUPER_POSITIONS_SOURCE).balanceOf(deployer, vars.underlyingSfId);

            console.log("SuperPositions Amount SuperVault:", vars.superPositonsAmountSuperVault);
            console.log("SuperPositions Amount Direct:", vars.superPositonsAmountDirect);

            (vars.superVaultSuperform,,) = vars.newSuperVaultId.getSuperform();
            // Calculate final values in USDC
            vars.finalSuperVaultValue =
                IBaseForm(vars.superVaultSuperform).previewRedeemFrom(vars.superPositonsAmountSuperVault);
            vars.finalDirectValue =
                IBaseForm(vars.underlyingSuperform).previewRedeemFrom(vars.superPositonsAmountDirect);

            console.log("Final SuperVault Value (USDC):", vars.finalSuperVaultValue);
            console.log("Final Direct Value (USDC):", vars.finalDirectValue);
            console.log("Initial Deposit Amount (USDC):", vars.depositAmount);

            // Calculate earnings
            vars.superVaultEarnings = vars.finalSuperVaultValue - vars.depositAmount;
            vars.directEarnings = vars.finalDirectValue - vars.depositAmount;

            console.log("SuperVault earnings (USDC):", vars.superVaultEarnings);
            console.log("Direct deposit earnings (USDC):", vars.directEarnings);

            assertEq(
                vars.superVaultEarnings,
                vars.directEarnings,
                string.concat("Earnings mismatch for ", gasTestSuperformNames[i])
            );

            // Reset state for next iteration
            vm.warp(block.timestamp - 1 days);
        }

        vm.stopPrank();
    }

    //////////////////////////////////////////////////////////////
    //               INTERNAL HELPERS                           //
    //////////////////////////////////////////////////////////////

    function _directDeposit(
        address user,
        uint256 superformId,
        uint256 amount,
        string memory snapshotName
    )
        internal
        returns (uint256 gasLastCall)
    {
        vm.selectFork(FORKS[SOURCE_CHAIN]);
        (address superform,,) = superformId.getSuperform();

        SingleVaultSFData memory data = SingleVaultSFData(
            superformId,
            amount,
            IBaseForm(superform).previewDepositTo(amount),
            100,
            LiqRequest("", IBaseForm(superform).getVaultAsset(), address(0), 1, SOURCE_CHAIN, 0),
            "",
            false,
            false,
            user,
            user,
            ""
        );

        SingleDirectSingleVaultStateReq memory req = SingleDirectSingleVaultStateReq(data);
        MockERC20(IBaseForm(superform).getVaultAsset()).approve(
            address(payable(getContract(SOURCE_CHAIN, "SuperformRouter"))), req.superformData.amount
        );

        /// @dev msg sender is wallet, tx origin is deployer
        address router = getContract(SOURCE_CHAIN, "SuperformRouter");
        SuperformRouter(payable(router)).singleDirectSingleVaultDeposit{ value: 2 ether }(req);
        if (bytes(snapshotName).length > 0) {
            gasLastCall = vm.snapshotGasLastCall("Deposit", snapshotName);
            console.log("---GAS USED IN DEPOSIT---", gasLastCall);
        }
    }

    function _directWithdraw(address user, uint256 superformId, bool partialWithdraw) internal {
        vm.selectFork(FORKS[SOURCE_CHAIN]);
        (address superform,,) = superformId.getSuperform();
        address superPositions = getContract(SOURCE_CHAIN, "SuperPositions");
        uint256 amountToWithdraw = SuperPositions(superPositions).balanceOf(user, superformId);

        if (partialWithdraw) {
            amountToWithdraw = amountToWithdraw / 2;
        }

        SingleVaultSFData memory data = SingleVaultSFData(
            superformId,
            amountToWithdraw,
            IBaseForm(superform).previewWithdrawFrom(amountToWithdraw),
            100,
            LiqRequest("", IBaseForm(superform).getVaultAsset(), address(0), 1, SOURCE_CHAIN, 0),
            "",
            false,
            false,
            user,
            user,
            ""
        );

        SingleDirectSingleVaultStateReq memory req = SingleDirectSingleVaultStateReq(data);
        address superformRouter = getContract(SOURCE_CHAIN, "SuperformRouter");
        SuperPositions(superPositions).setApprovalForOne(superformRouter, superformId, amountToWithdraw);

        /// @dev msg sender is wallet, tx origin is deployer
        SuperformRouter(payable(superformRouter)).singleDirectSingleVaultWithdraw{ value: 2 ether }(req);
    }

    function _xChainDeposit(
        uint256 superformId,
        uint256 amount,
        uint64 dstChainId,
        uint256 payloadIdToProcess
    )
        internal
    {
        (address superform,,) = superformId.getSuperform();

        vm.selectFork(FORKS[dstChainId]);

        address underlyingToken = IBaseForm(superform).getVaultAsset();

        uint256 totalAmountToDeposit =
            _convertDecimals(amount, getContract(SOURCE_CHAIN, "DAI"), underlyingToken, SOURCE_CHAIN, dstChainId);

        SingleVaultSFData memory data = SingleVaultSFData(
            superformId,
            totalAmountToDeposit,
            IBaseForm(superform).previewDepositTo(totalAmountToDeposit),
            100,
            LiqRequest(
                _buildLiqBridgeTxData(
                    LiqBridgeTxDataArgs(
                        1,
                        getContract(SOURCE_CHAIN, "DAI"),
                        getContract(SOURCE_CHAIN, ERC20(underlyingToken).symbol()),
                        underlyingToken,
                        getContract(SOURCE_CHAIN, "SuperformRouter"),
                        SOURCE_CHAIN,
                        dstChainId,
                        dstChainId,
                        false,
                        getContract(dstChainId, "CoreStateRegistry"),
                        uint256(dstChainId),
                        amount,
                        false,
                        /// @dev placeholder value, not used
                        0,
                        1,
                        1,
                        1,
                        address(0)
                    ),
                    false
                ),
                getContract(SOURCE_CHAIN, "DAI"),
                address(0),
                1,
                dstChainId,
                0
            ),
            "",
            false,
            false,
            deployer,
            deployer,
            ""
        );
        vm.selectFork(FORKS[SOURCE_CHAIN]);

        SingleXChainSingleVaultStateReq memory req = SingleXChainSingleVaultStateReq(AMBs, dstChainId, data);
        MockERC20(getContract(SOURCE_CHAIN, "DAI")).approve(
            address(payable(getContract(SOURCE_CHAIN, "SuperformRouter"))), amount
        );

        vm.recordLogs();
        /// @dev msg sender is wallet, tx origin is deployer
        SuperformRouter(payable(getContract(SOURCE_CHAIN, "SuperformRouter"))).singleXChainSingleVaultDeposit{
            value: 2 ether
        }(req);

        _processXChainDepositOneVault(
            SOURCE_CHAIN, dstChainId, vm.getRecordedLogs(), underlyingToken, totalAmountToDeposit, payloadIdToProcess
        );

        vm.selectFork(FORKS[SOURCE_CHAIN]);
    }

    function _xChainWithdraw(uint256 superformId, uint64 dstChainId, uint256 payloadIdToProcess) internal {
        vm.selectFork(FORKS[SOURCE_CHAIN]);
        (address superform,,) = superformId.getSuperform();
        address superPositions = getContract(SOURCE_CHAIN, "SuperPositions");
        uint256 amountToWithdraw = SuperPositions(superPositions).balanceOf(deployer, superformId);
        vm.selectFork(FORKS[dstChainId]);

        SingleVaultSFData memory data = SingleVaultSFData(
            superformId,
            amountToWithdraw,
            IBaseForm(superform).previewWithdrawFrom(amountToWithdraw),
            100,
            LiqRequest("", address(0), address(0), 1, dstChainId, 0),
            "",
            false,
            false,
            deployer,
            deployer,
            ""
        );

        vm.selectFork(FORKS[SOURCE_CHAIN]);

        SingleXChainSingleVaultStateReq memory req = SingleXChainSingleVaultStateReq(AMBs, dstChainId, data);
        address superformRouter = getContract(SOURCE_CHAIN, "SuperformRouter");
        SuperPositions(superPositions).setApprovalForOne(superformRouter, superformId, amountToWithdraw);

        vm.recordLogs();
        /// @dev msg sender is wallet, tx origin is deployer
        SuperformRouter(payable(superformRouter)).singleXChainSingleVaultWithdraw{ value: 2 ether }(req);

        _processXChainWithdrawOneVault(SOURCE_CHAIN, dstChainId, vm.getRecordedLogs(), payloadIdToProcess);

        vm.selectFork(FORKS[SOURCE_CHAIN]);
    }

    function _deliverAMBMessage(uint64 fromChain, uint64 toChain, Vm.Log[] memory logs) internal {
        for (uint256 i = 0; i < AMBs.length; i++) {
            if (AMBs[i] == 2) {
                // Hyperlane
                HyperlaneHelper(getContract(fromChain, "HyperlaneHelper")).help(
                    address(HYPERLANE_MAILBOXES[fromChain]), address(HYPERLANE_MAILBOXES[toChain]), FORKS[toChain], logs
                );
            } else if (AMBs[i] == 3) {
                WormholeHelper(getContract(fromChain, "WormholeHelper")).help(
                    WORMHOLE_CHAIN_IDS[fromChain], FORKS[toChain], wormholeRelayer, logs
                );
            }
            // Add other AMB helpers as needed
        }
    }

    function _convertDecimals(
        uint256 amount,
        address token1,
        address token2,
        uint64 chainId1,
        uint64 chainId2
    )
        internal
        returns (uint256 convertedAmount)
    {
        uint256 initialFork = vm.activeFork();
        vm.selectFork(FORKS[chainId1]);
        uint256 decimals1 = MockERC20(token1).decimals();
        vm.selectFork(FORKS[chainId2]);
        uint256 decimals2 = MockERC20(token2).decimals();

        if (decimals1 > decimals2) {
            convertedAmount = amount / (10 ** (decimals1 - decimals2));
        } else {
            convertedAmount = amount * 10 ** (decimals2 - decimals1);
        }
        vm.selectFork(initialFork);
    }

    function _processXChainDepositOneVault(
        uint64 fromChain,
        uint64 toChain,
        Vm.Log[] memory logs,
        address destinationToken,
        uint256 amountArrivedInDst,
        uint256 payloadIdToProcess
    )
        internal
    {
        vm.stopPrank();
        // Simulate AMB message delivery
        _deliverAMBMessage(fromChain, toChain, logs);

        vm.startPrank(deployer);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amountArrivedInDst;

        address[] memory bridgedTokens = new address[](1);
        bridgedTokens[0] = destinationToken;

        CoreStateRegistry coreStateRegistry = CoreStateRegistry(getContract(toChain, "CoreStateRegistry"));
        vm.selectFork(FORKS[toChain]);

        coreStateRegistry.updateDepositPayload(payloadIdToProcess, bridgedTokens, amounts);

        // Perform processPayload on CoreStateRegistry on destination chain
        uint256 nativeAmount = PaymentHelper(getContract(toChain, "PaymentHelper")).estimateAckCost(payloadIdToProcess);
        vm.recordLogs();

        coreStateRegistry.processPayload{ value: nativeAmount }(payloadIdToProcess);
        logs = vm.getRecordedLogs();

        vm.stopPrank();

        // Simulate AMB message delivery back to source chain
        _deliverAMBMessage(toChain, fromChain, logs);

        vm.startPrank(deployer);
        // Switch back to source chain fork
        vm.selectFork(FORKS[fromChain]);

        // Perform processPayload on source chain to mint SuperPositions
        coreStateRegistry = CoreStateRegistry(getContract(fromChain, "CoreStateRegistry"));

        coreStateRegistry.processPayload(coreStateRegistry.payloadsCount());

        vm.stopPrank();
    }

    function _processXChainWithdrawOneVault(
        uint64 fromChain,
        uint64 toChain,
        Vm.Log[] memory logs,
        uint256 payloadIdToProcess
    )
        internal
    {
        vm.stopPrank();

        // Simulate AMB message delivery
        _deliverAMBMessage(fromChain, toChain, logs);

        vm.startPrank(deployer);

        vm.selectFork(FORKS[toChain]);
        CoreStateRegistry coreStateRegistry = CoreStateRegistry(getContract(toChain, "CoreStateRegistry"));

        // Perform processPayload on CoreStateRegistry on destination chain
        uint256 nativeAmount = PaymentHelper(getContract(toChain, "PaymentHelper")).estimateAckCost(payloadIdToProcess);
        vm.recordLogs();

        coreStateRegistry.processPayload{ value: nativeAmount }(payloadIdToProcess);

        vm.stopPrank();
    }

    function _calculateUnderlyingIndexes() internal view returns (uint256[] memory underlyingIndexes) {
        underlyingIndexes = new uint256[](underlyingSuperformIds.length);
        for (uint256 i = 0; i < underlyingSuperformIds.length; i++) {
            for (uint256 j = 0; j < allSuperformIds.length; j++) {
                if (allSuperformIds[j] == underlyingSuperformIds[i]) {
                    underlyingIndexes[i] = j;
                    break;
                }
            }
        }
    }

    function _assertSuperPositionsSplitAccordingToWeights(uint64 dstChain) internal {
        vm.selectFork(FORKS[dstChain]);

        (address superFormSuperVault,,) = SUPER_VAULT_ID1.getSuperform();
        address superVaultAddress = IBaseForm(superFormSuperVault).getVaultAddress();
        uint256[] memory svDataWeights = new uint256[](underlyingSuperformIds.length);
        SuperVault vault = SuperVault(superVaultAddress);
        for (uint256 i; i < underlyingSuperformIds.length; i++) {
            svDataWeights[i] = vault.weights(i);
        }
        uint256[] memory underlyingIndexes = _calculateUnderlyingIndexes();
        uint256[] memory calculatedWeights = _calculateRealWeights(superVaultAddress, underlyingIndexes);

        for (uint256 i = 0; i < underlyingSuperformIds.length; i++) {
            console.log("Calculated weight", calculatedWeights[i], "Sv data weight", svDataWeights[i]);
            assertApproxEqRel(calculatedWeights[i], svDataWeights[i], 0.5e18);
        }
    }

    function _assertWeightsWithinTolerance(
        uint256[] memory finalIndexes,
        uint256[] memory finalWeightsTargets
    )
        internal
        view
    {
        (address superFormSuperVault,,) = SUPER_VAULT_ID1.getSuperform();
        address superVaultAddress = IBaseForm(superFormSuperVault).getVaultAddress();

        uint256[] memory realWeights = _calculateRealWeights(superVaultAddress, finalIndexes);

        for (uint256 i = 0; i < finalIndexes.length; i++) {
            uint256 index = finalIndexes[i];
            uint256 targetWeight = finalWeightsTargets[i];
            uint256 realWeight = realWeights[i];

            // Calculate the difference between target and real weight
            uint256 difference = targetWeight > realWeight ? targetWeight - realWeight : realWeight - targetWeight;
            console.log("Target Weight:", targetWeight, "Real Weight:", realWeight);

            // Assert that the difference is within 1% (100 basis points) of the target weight
            assertLe(
                difference,
                targetWeight / 100,
                string(abi.encodePacked("Weight for index ", Strings.toString(index), " is off by more than 1%"))
            );
        }
    }

    function _calculateRealWeights(
        address superVaultAddress,
        uint256[] memory indexes
    )
        internal
        view
        returns (uint256[] memory)
    {
        uint256 totalUnderlyingBalanceOfSuperVault;
        uint256[] memory underlyingBalanceOfSuperVault = new uint256[](indexes.length);

        for (uint256 i = 0; i < indexes.length; i++) {
            uint256 superformId = allSuperformIds[indexes[i]];
            uint256 spBalanceInSuperVault =
                SuperPositions(SUPER_POSITIONS_SOURCE).balanceOf(superVaultAddress, superformId);
            (address superform,,) = superformId.getSuperform();
            underlyingBalanceOfSuperVault[i] = IBaseForm(superform).previewRedeemFrom(spBalanceInSuperVault);
            console.log("Underlying balance of SuperVault", i, ":", underlyingBalanceOfSuperVault[i]);
            totalUnderlyingBalanceOfSuperVault += underlyingBalanceOfSuperVault[i];
        }
        console.log("Total underlying balance of SuperVault:", totalUnderlyingBalanceOfSuperVault);

        uint256[] memory calculatedWeights = new uint256[](indexes.length);
        for (uint256 i = 0; i < indexes.length; i++) {
            calculatedWeights[i] =
                underlyingBalanceOfSuperVault[i].mulDiv(10_000, totalUnderlyingBalanceOfSuperVault, Math.Rounding.Up);
            console.log("Calculated weight", indexes[i], ":", calculatedWeights[i]);
        }

        return calculatedWeights;
    }

    function _assertUnderlyingBalanceAfterFullWithdraw(uint64 dstChain) internal {
        vm.selectFork(FORKS[dstChain]);

        (address superFormSuperVault,,) = SUPER_VAULT_ID1.getSuperform();
        address superVaultAddress = IBaseForm(superFormSuperVault).getVaultAddress();

        // Assert that the SuperPositions are 0 after full withdrawal
        for (uint256 i = 0; i < underlyingSuperformIds.length; i++) {
            uint256 spBalanceInSuperVault =
                SuperPositions(SUPER_POSITIONS_SOURCE).balanceOf(superVaultAddress, underlyingSuperformIds[i]);

            (address underlyingSuperform,,) = underlyingSuperformIds[i].getSuperform();

            uint256 underlyingBalance = IBaseForm(underlyingSuperform).previewRedeemFrom(spBalanceInSuperVault);
            // Allow for 5 units of difference
            assertLe(underlyingBalance, 5, "Underlying balance should not exceed 5 units after full withdrawal");
        }
    }

    struct RebalanceLocalVars {
        uint256[] indexesToRebalanceTo;
        uint256[] finalWeightsTargets;
        uint256[] indexesRebalanceFrom;
        uint256 nIndexesToRebalanceTo;
        address superFormSuperVault;
        address superVaultAddress;
        uint256 totalUSDCValue;
        uint256[] targetUSDC;
        uint256[] currentUSDC;
        uint256[] currentShares;
        uint256[] additionalUSDC;
        uint256 totalAdditionalUSDC;
        uint256[] weightsOfRedistribution;
        uint256[] superformIdsRebalanceFrom;
        uint256[] amountsRebalanceFrom;
        uint256[] superformIdsRebalanceTo;
    }

    function _performRebalance(
        uint256 superVaultId_,
        uint256[] memory finalSuperformIndexes,
        uint256[] memory finalWeights,
        uint256[] memory indexesRebalanceFrom,
        uint256[] memory masterListSuperformIds,
        string memory snapshotName
    )
        internal
        returns (uint256 gasLastCall)
    {
        RebalanceLocalVars memory vars;

        (vars.superFormSuperVault,,) = superVaultId_.getSuperform();
        vars.superVaultAddress = IBaseForm(vars.superFormSuperVault).getVaultAddress();

        // Calculate current weights and total USDC value
        vars.totalUSDCValue = 0;
        uint256[] memory currentUSDC = new uint256[](masterListSuperformIds.length);
        uint256[] memory currentWeights = new uint256[](masterListSuperformIds.length);
        for (uint256 i = 0; i < masterListSuperformIds.length; i++) {
            (address superform,,) = masterListSuperformIds[i].getSuperform();
            uint256 superformShares =
                SuperPositions(SUPER_POSITIONS_SOURCE).balanceOf(vars.superVaultAddress, masterListSuperformIds[i]);
            currentUSDC[i] = IBaseForm(superform).previewRedeemFrom(superformShares);
            vars.totalUSDCValue += currentUSDC[i];
            console.log("Current USDC", i, ":", currentUSDC[i]);
        }
        console.log("Total USDC Value:", vars.totalUSDCValue);

        // Then, calculate current weights
        for (uint256 i = 0; i < masterListSuperformIds.length; i++) {
            currentWeights[i] = vars.totalUSDCValue > 0 ? currentUSDC[i] * 10_000 / vars.totalUSDCValue : 0;
            console.log("Current weight", i, ":", currentWeights[i]);
        }

        // Prepare arrays for rebalancing
        vars.superformIdsRebalanceFrom = new uint256[](indexesRebalanceFrom.length);
        vars.amountsRebalanceFrom = new uint256[](indexesRebalanceFrom.length);
        vars.superformIdsRebalanceTo = new uint256[](finalSuperformIndexes.length);
        vars.weightsOfRedistribution = new uint256[](finalSuperformIndexes.length);

        uint256 totalUSDCToRedistribute = 0;

        // Calculate amounts to rebalance from each source
        for (uint256 i = 0; i < indexesRebalanceFrom.length; i++) {
            uint256 index = indexesRebalanceFrom[i];
            vars.superformIdsRebalanceFrom[i] = masterListSuperformIds[index];
            uint256 finalWeight = 0;
            bool isInFinalIndexes = false;
            for (uint256 j = 0; j < finalSuperformIndexes.length; j++) {
                if (finalSuperformIndexes[j] == index) {
                    finalWeight = finalWeights[j];
                    isInFinalIndexes = true;
                    break;
                }
            }

            if (!isInFinalIndexes || finalWeight < currentWeights[index]) {
                uint256 usdcToRemove = isInFinalIndexes
                    ? currentUSDC[index] - (vars.totalUSDCValue * finalWeight / 10_000)
                    : currentUSDC[index];
                console.log("usdcToRemove", index, ":", usdcToRemove);
                totalUSDCToRedistribute += usdcToRemove;

                (address superform,,) = vars.superformIdsRebalanceFrom[i].getSuperform();

                /// for partial and full rebalances
                vars.amountsRebalanceFrom[i] = usdcToRemove != currentUSDC[index]
                    ? IBaseForm(superform).previewDepositTo(usdcToRemove)
                    : SuperPositions(SUPER_POSITIONS_SOURCE).balanceOf(
                        vars.superVaultAddress, vars.superformIdsRebalanceFrom[i]
                    );

                console.log("amountsRebalanceFrom", index, ":", vars.amountsRebalanceFrom[i]);
            } else {
                vars.amountsRebalanceFrom[i] = 0;
            }
        }

        console.log("totalUSDCToRedistribute", totalUSDCToRedistribute);

        // Calculate weights for redistribution
        uint256 totalRedistributionWeight = 0;
        for (uint256 i = 0; i < finalSuperformIndexes.length; i++) {
            uint256 index = finalSuperformIndexes[i];
            vars.superformIdsRebalanceTo[i] = masterListSuperformIds[index];
            uint256 currentWeight = currentWeights[index];
            if (finalWeights[i] > currentWeight) {
                vars.weightsOfRedistribution[i] = finalWeights[i] - currentWeight;
                totalRedistributionWeight += vars.weightsOfRedistribution[i];
                console.log("weightsOfRedistribution", i, ":", vars.weightsOfRedistribution[i]);
            }
        }

        console.log("totalRedistributionWeight", totalRedistributionWeight);

        // Normalize weights of redistribution
        uint256 totalAssignedWeight = 0;
        for (uint256 i = 0; i < vars.weightsOfRedistribution.length; i++) {
            if (totalRedistributionWeight > 0) {
                if (i == vars.weightsOfRedistribution.length - 1) {
                    // Assign remaining weight to the last index
                    vars.weightsOfRedistribution[i] = 10_000 - totalAssignedWeight;
                } else {
                    vars.weightsOfRedistribution[i] =
                        vars.weightsOfRedistribution[i] * 10_000 / totalRedistributionWeight;
                    totalAssignedWeight += vars.weightsOfRedistribution[i];
                }
            }
            console.log("Weight of redistribution", i, ":", vars.weightsOfRedistribution[i]);
        }
        address _superVault = IBaseForm(vars.superFormSuperVault).getVaultAddress();
        // Perform the rebalance
        SuperVault(payable(_superVault)).rebalance{ value: 4 ether }(
            ISuperVault.RebalanceArgs(
                vars.superformIdsRebalanceFrom,
                vars.amountsRebalanceFrom,
                vars.superformIdsRebalanceTo,
                vars.weightsOfRedistribution,
                100
            )
        );
        if (bytes(snapshotName).length > 0) {
            gasLastCall = vm.snapshotGasLastCall("Rebalance", snapshotName);
            console.log("---GAS USED IN DEPOSIT---", gasLastCall);
        }
    }
}
