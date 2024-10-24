// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.23;

import "superform-core/test/utils/ProtocolActions.sol";
import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { Math } from "openzeppelin/contracts/utils/math/Math.sol";
import { ISuperVault } from "../src/ISuperVault.sol";
import { SuperVault } from "../src/SuperVault.sol";
import { ITokenizedStrategy } from "tokenized-strategy/interfaces/ITokenizedStrategy.sol";

contract SuperVaultHarness is SuperVault {
    constructor(
        address superRegistry_,
        address asset_,
        address strategist_,
        string memory name_,
        uint256 depositLimit_,
        uint256[] memory superformIds_,
        uint256[] memory startingWeights_
    )
        SuperVault(superRegistry_, asset_, strategist_, name_, depositLimit_, superformIds_, startingWeights_)
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

    uint256 SUPER_VAULT_ID1;

    uint256[] underlyingSuperformIds;
    uint256[] allSuperformIds;

    SuperVault superVault;
    SuperVaultHarness superVaultHarness;

    /// @dev yearn address factory on ETH
    address constant FACTORY = 0x444045c5C13C246e117eD36437303cac8E250aB0;

    function setUp() public override {
        chainIds = [ETH, ARBI];
        super.setUp();
        MULTI_TX_SLIPPAGE_SHARE = 0;
        AMBs = [2, 3];
        SOURCE_CHAIN = ETH;

        SUPER_POSITIONS_SOURCE = getContract(SOURCE_CHAIN, "SuperPositions");
        // 1 - USDC SuperVault: Morpho + Euler + Aave USDC (3 vaults total to start)) -> ETH
        //      Asset: USDC

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
            if (i < 3) {
                underlyingSuperformIds[i] = allSuperformIds[i];
            }
        }

        uint256[] memory weights = new uint256[](vaultAddresses.length - 1);
        for (uint256 i = 0; i < vaultAddresses.length - 1; i++) {
            weights[i] = uint256(10_000) / 3;
            if (i == 2) {
                weights[i] += 1;
            }
        }

        // Deploy SuperVault
        superVault = new SuperVault(
            getContract(SOURCE_CHAIN, "SuperRegistry"),
            getContract(ETH, "USDC"),
            deployer,
            "USDCSuperVaultMorphoEulerAave",
            type(uint256).max,
            underlyingSuperformIds,
            weights
        );
        superVaultHarness = new SuperVaultHarness(
            getContract(SOURCE_CHAIN, "SuperRegistry"),
            getContract(ETH, "USDC"),
            deployer,
            "USDCSuperVaultMorphoEulerAave",
            type(uint256).max,
            underlyingSuperformIds,
            weights
        );

        (bool success,) =
            address(superVault).call(abi.encodeWithSelector(ITokenizedStrategy.setPerformanceFee.selector, 0));
        require(success, "Failed to set performance fee to 0");

        (bool success2, bytes memory data) =
            address(superVault).call(abi.encodeWithSelector(ITokenizedStrategy.performanceFee.selector));
        require(success2, "Failed to get performance fee");
        uint256 performanceFee = abi.decode(data, (uint256));
        assertEq(performanceFee, 0, "Performance fee should be 0");
        address superVaultAddress = address(superVault);

        // Deploy Superform
        (SUPER_VAULT_ID1,) = superformFactory.createSuperform(1, superVaultAddress);

        assertTrue(superformFactory.isSuperform(SUPER_VAULT_ID1), "Superform should be registered");

        SuperRegistry(getContract(ETH, "SuperRegistry")).setAddress(keccak256("SUPER_VAULTS_STRATEGIST"), deployer, ETH);

        vm.stopPrank();
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
            "TestSuperVault",
            type(uint256).max,
            superformIds,
            weights
        );
    }

    function test_onlyVaultStrategistCanCall() public {
        vm.startPrank(address(0xdead));
        vm.expectRevert(ISuperVault.NOT_SUPER_VAULTS_STRATEGIST.selector);
        SuperVault(address(superVault)).setDepositLimit(type(uint256).max);
        vm.stopPrank();
    }

    function test_zeroAddressSetRefundsReceiver() public {
        vm.startPrank(deployer);
        vm.expectRevert(ISuperVault.ZERO_ADDRESS.selector);
        SuperVault(address(superVault)).setRefundsReceiver(address(0));
        vm.stopPrank();
    }

    function test_superVaultConstructorReverts() public {
        address superRegistry = getContract(ETH, "SuperRegistry");
        address asset = getContract(ETH, "USDC");
        string memory name = "TestSuperVault";
        uint256 depositLimit = type(uint256).max;
        uint256[] memory superformIds = underlyingSuperformIds;
        uint256[] memory startingWeights = new uint256[](3);

        // Setup valid parameters
        startingWeights[0] = 3334;
        startingWeights[1] = 3333;
        startingWeights[2] = 3333;

        // Test 1: ZERO_ADDRESS revert
        vm.expectRevert(abi.encodeWithSignature("ZERO_ADDRESS()"));
        new SuperVault(address(0), asset, deployer, name, depositLimit, superformIds, startingWeights);

        vm.expectRevert(abi.encodeWithSignature("ZERO_ADDRESS()"));
        new SuperVault(superRegistry, asset, address(0), name, depositLimit, superformIds, startingWeights);

        // Test 2: ARRAY_LENGTH_MISMATCH revert
        uint256[] memory mismatchedWeights = new uint256[](2);
        mismatchedWeights[0] = 5000;
        mismatchedWeights[1] = 5000;

        vm.expectRevert(abi.encodeWithSignature("ARRAY_LENGTH_MISMATCH()"));
        new SuperVault(superRegistry, asset, deployer, name, depositLimit, superformIds, mismatchedWeights);

        // Test 3: SUPERFORM_DOES_NOT_SUPPORT_ASSET revert

        vm.expectRevert(abi.encodeWithSignature("SUPERFORM_DOES_NOT_SUPPORT_ASSET()"));
        new SuperVault(
            superRegistry, getContract(ETH, "DAI"), deployer, name, depositLimit, superformIds, startingWeights
        );

        // Test 4: INVALID_WEIGHTS revert
        uint256[] memory invalidWeights = new uint256[](3);
        invalidWeights[0] = 3000;
        invalidWeights[1] = 3000;
        invalidWeights[2] = 3000;

        vm.expectRevert(abi.encodeWithSignature("INVALID_WEIGHTS()"));
        new SuperVault(superRegistry, asset, deployer, name, depositLimit, superformIds, invalidWeights);
    }

    function test_superVault_assertSuperPositions_splitAccordingToWeights() public {
        vm.startPrank(deployer);
        SOURCE_CHAIN = ETH;
        vm.selectFork(FORKS[SOURCE_CHAIN]);

        uint256 amount = 500e6;
        // Perform a direct deposit to the SuperVault
        _directDeposit(SUPER_VAULT_ID1, amount);

        _assertSuperPositionsSplitAccordingToWeights(ETH);

        _directWithdraw(SUPER_VAULT_ID1);

        _assertSuperPositionsAfterWithdraw(ETH);

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

    function test_superVault_xChainDeposit_assertSuperPositions_splitAccordingToWeights() public {
        vm.startPrank(deployer);
        SOURCE_CHAIN = ARBI;

        uint256 amount = 500e18;
        // Perform a xChain deposit to the SuperVault
        _xChainDeposit(SUPER_VAULT_ID1, amount, ETH, 1);

        _assertSuperPositionsSplitAccordingToWeights(ETH);

        vm.startPrank(deployer);

        _xChainWithdraw(SUPER_VAULT_ID1, ETH, 2);

        _assertSuperPositionsAfterWithdraw(ETH);

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

    function test_superVault_rebalance() public {
        vm.startPrank(deployer);
        SOURCE_CHAIN = ETH;

        uint256 amount = 10_000e6;
        // Perform a direct deposit to the SuperVault
        _directDeposit(SUPER_VAULT_ID1, amount);

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

        _performRebalance(finalIndexes, finalWeightsTargets, indexesRebalanceFrom);
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

        _performRebalance(finalIndexes, finalWeightsTargets, indexesRebalanceFrom);
        _assertWeightsWithinTolerance(finalIndexes, finalWeightsTargets);
    }

    function test_superVault_rebalance_newVault() public {
        vm.startPrank(deployer);
        SOURCE_CHAIN = ETH;

        uint256 amount = 10_000e6;
        // Perform a direct deposit to the SuperVault
        _directDeposit(SUPER_VAULT_ID1, amount);

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

        _performRebalance(finalIndexes, finalWeightsTargets, indexesRebalanceFrom);
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

        _performRebalance(finalIndexes, finalWeightsTargets, indexesRebalanceFrom);
        _assertWeightsWithinTolerance(finalIndexes, finalWeightsTargets);
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

    function test_harvestAndReport() public {
        vm.startPrank(deployer);
        SOURCE_CHAIN = ETH;

        uint256 depositAmount = 10_000e6; // 10,000 USDC
        // Perform a direct deposit to the SuperVault
        _directDeposit(SUPER_VAULT_ID1, depositAmount);

        // Get SuperVault address
        (address superFormSuperVault,,) = SUPER_VAULT_ID1.getSuperform();
        address superVaultAddress = IBaseForm(superFormSuperVault).getVaultAddress();

        // Call report() function
        (bool success,) = superVaultAddress.call(abi.encodeWithSignature("report()"));
        require(success, "report() call failed");

        vm.stopPrank();
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

    function test_setRefundsReceiver() public {
        (address superFormSuperVault,,) = SUPER_VAULT_ID1.getSuperform();
        address superVaultAddress = IBaseForm(superFormSuperVault).getVaultAddress();

        // Ensure the caller is not the strategist
        vm.prank(address(0xdead));
        vm.expectRevert(ISuperVault.NOT_SUPER_VAULTS_STRATEGIST.selector);
        SuperVault(payable(superVaultAddress)).setRefundsReceiver(deployer);

        // Set the new refunds receiver as the strategist
        vm.prank(deployer);
        vm.expectEmit(true, true, true, true);
        emit ISuperVault.RefundsReceiverSet(deployer);
        SuperVault(payable(superVaultAddress)).setRefundsReceiver(deployer);

        // Assert
        assertEq(SuperVault(payable(superVaultAddress)).refundReceiver(), deployer);
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
        _directDeposit(SUPER_VAULT_ID1, amount);

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
        } else if (finalIndex == 3) {
            finalIndexes[1] = 1;
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
        _performRebalance(finalIndexes, finalWeightsTargets, indexesRebalanceFrom);
        _assertWeightsWithinTolerance(finalIndexes, finalWeightsTargets);
    }

    //////////////////////////////////////////////////////////////
    //               INTERNAL HELPERS                           //
    //////////////////////////////////////////////////////////////

    function _directDeposit(uint256 superformId, uint256 amount) internal {
        vm.selectFork(FORKS[SOURCE_CHAIN]);
        (address superform,,) = superformId.getSuperform();

        SingleVaultSFData memory data = SingleVaultSFData(
            superformId,
            amount,
            amount,
            100,
            LiqRequest("", IBaseForm(superform).getVaultAsset(), address(0), 1, SOURCE_CHAIN, 0),
            "",
            false,
            false,
            deployer,
            deployer,
            ""
        );

        SingleDirectSingleVaultStateReq memory req = SingleDirectSingleVaultStateReq(data);
        MockERC20(IBaseForm(superform).getVaultAsset()).approve(
            address(payable(getContract(SOURCE_CHAIN, "SuperformRouter"))), req.superformData.amount
        );

        /// @dev msg sender is wallet, tx origin is deployer
        SuperformRouter(payable(getContract(SOURCE_CHAIN, "SuperformRouter"))).singleDirectSingleVaultDeposit{
            value: 2 ether
        }(req);
    }

    function _directWithdraw(uint256 superformId) internal {
        vm.selectFork(FORKS[SOURCE_CHAIN]);
        (address superform,,) = superformId.getSuperform();
        address superPositions = getContract(SOURCE_CHAIN, "SuperPositions");
        uint256 amountToWithdraw = SuperPositions(superPositions).balanceOf(deployer, superformId);

        SingleVaultSFData memory data = SingleVaultSFData(
            superformId,
            amountToWithdraw,
            IBaseForm(superform).previewWithdrawFrom(amountToWithdraw),
            100,
            LiqRequest("", IBaseForm(superform).getVaultAsset(), address(0), 1, SOURCE_CHAIN, 0),
            "",
            false,
            false,
            deployer,
            deployer,
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
        (,, svDataWeights) = SuperVault(superVaultAddress).getSuperVaultData();
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
            underlyingBalanceOfSuperVault[i] =
                IERC4626(IBaseForm(superform).getVaultAddress()).convertToAssets(spBalanceInSuperVault);
            totalUnderlyingBalanceOfSuperVault += underlyingBalanceOfSuperVault[i];
        }

        uint256[] memory calculatedWeights = new uint256[](indexes.length);
        for (uint256 i = 0; i < indexes.length; i++) {
            calculatedWeights[i] =
                underlyingBalanceOfSuperVault[i].mulDiv(10_000, totalUnderlyingBalanceOfSuperVault, Math.Rounding.Up);
            console.log("Calculated weight", indexes[i], ":", calculatedWeights[i]);
        }

        return calculatedWeights;
    }

    function _assertSuperPositionsAfterWithdraw(uint64 dstChain) internal {
        vm.selectFork(FORKS[dstChain]);

        (address superFormSuperVault,,) = SUPER_VAULT_ID1.getSuperform();
        address superVaultAddress = IBaseForm(superFormSuperVault).getVaultAddress();

        // Assert that the SuperPositions are 0 after full withdrawal
        for (uint256 i = 0; i < underlyingSuperformIds.length; i++) {
            uint256 spBalanceInSuperVault =
                SuperPositions(SUPER_POSITIONS_SOURCE).balanceOf(superVaultAddress, underlyingSuperformIds[i]);

            console.log("SuperPosition balance for underlying Superform", i, ":", spBalanceInSuperVault);

            assertEq(spBalanceInSuperVault, 0, "SuperPosition balance should be 0 after full withdrawal");
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
        uint256[] memory finalSuperformIndexes,
        uint256[] memory finalWeights,
        uint256[] memory indexesRebalanceFrom
    )
        internal
    {
        RebalanceLocalVars memory vars;

        (vars.superFormSuperVault,,) = SUPER_VAULT_ID1.getSuperform();
        vars.superVaultAddress = IBaseForm(vars.superFormSuperVault).getVaultAddress();

        // Calculate current weights and total USDC value
        vars.totalUSDCValue = 0;
        uint256[] memory currentUSDC = new uint256[](allSuperformIds.length);
        uint256[] memory currentWeights = new uint256[](allSuperformIds.length);
        for (uint256 i = 0; i < allSuperformIds.length; i++) {
            (address superform,,) = allSuperformIds[i].getSuperform();
            uint256 superformShares =
                SuperPositions(SUPER_POSITIONS_SOURCE).balanceOf(vars.superVaultAddress, allSuperformIds[i]);
            currentUSDC[i] = IBaseForm(superform).previewRedeemFrom(superformShares);
            vars.totalUSDCValue += currentUSDC[i];
            console.log("Current USDC", i, ":", currentUSDC[i]);
        }
        console.log("Total USDC Value:", vars.totalUSDCValue);

        // Then, calculate current weights
        for (uint256 i = 0; i < allSuperformIds.length; i++) {
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
            vars.superformIdsRebalanceFrom[i] = allSuperformIds[index];
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

                vars.amountsRebalanceFrom[i] = IBaseForm(superform).previewDepositTo(usdcToRemove);

                console.log("amountsRebalanceFrom", index, ":", vars.amountsRebalanceFrom[i]);
            } else {
                vars.amountsRebalanceFrom[i] = 0;
            }
        }

        console.log("totalUSDCToRedistribute", totalUSDCToRedistribute);

        // Calculate weights for redistribution
        uint256 totalRedistributionWeight = 0;
        // 1,2
        for (uint256 i = 0; i < finalSuperformIndexes.length; i++) {
            uint256 index = finalSuperformIndexes[i];
            vars.superformIdsRebalanceTo[i] = allSuperformIds[index];
            uint256 currentWeight = currentWeights[index];
            // index1 current weight = 33%
            // final weight = 70%
            // 36%
            // index current weight == 33%
            // final weight = 30% -> Not covered
            if (finalWeights[i] > currentWeight) {
                vars.weightsOfRedistribution[i] = finalWeights[i] - currentWeight;
                totalRedistributionWeight += vars.weightsOfRedistribution[i];
                console.log("weightsOfRedistribution", i, ":", vars.weightsOfRedistribution[i]);
            }
        }

        console.log("totalRedistributionWeight", totalRedistributionWeight);

        // Normalize weights of redistribution
        for (uint256 i = 0; i < vars.weightsOfRedistribution.length; i++) {
            if (totalRedistributionWeight > 0) {
                vars.weightsOfRedistribution[i] = vars.weightsOfRedistribution[i] * 10_000 / totalRedistributionWeight;
            } else {
                vars.weightsOfRedistribution[i] = 0;
            }
            console.log("Weight of redistribution", i, ":", vars.weightsOfRedistribution[i]);
        }

        // Perform the rebalance
        SuperVault(payable(IBaseForm(vars.superFormSuperVault).getVaultAddress())).rebalance{ value: 4 ether }(
            ISuperVault.RebalanceArgs(
                vars.superformIdsRebalanceFrom,
                vars.amountsRebalanceFrom,
                vars.superformIdsRebalanceTo,
                vars.weightsOfRedistribution,
                100
            )
        );
    }
}
