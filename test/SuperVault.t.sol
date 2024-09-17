// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.23;

import "superform-core/test/utils/ProtocolActions.sol";
import { ISuperformRouterPlus } from "superform-core/src/interfaces/ISuperformRouterPlus.sol";
import { ISuperformRouterPlusAsync } from "superform-core/src/interfaces/ISuperformRouterPlusAsync.sol";
import { IBaseRouter } from "superform-core/src/interfaces/IBaseRouter.sol";
import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { Math } from "openzeppelin/contracts/utils/math/Math.sol";
import { ISuperVault } from "../src/ISuperVault.sol";

import { SuperVault } from "../src/SuperVault.sol";
import { TokenizedStrategy } from "../src/vendor/TokenizedStrategy.sol";

contract SuperVaultTest is ProtocolActions {
    using Math for uint256;

    using DataLib for uint256;

    address SUPER_POSITIONS_SOURCE;

    uint64 SOURCE_CHAIN;

    uint256 SUPER_VAULT_ID1;

    uint256[] underlyingSuperformIds;

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

        address[] memory vaultAddresses = new address[](3);
        vaultAddresses[0] = morphoVault;
        vaultAddresses[1] = aaveUsdcVault;
        vaultAddresses[2] = eulerUsdcVault;
        // Get the SuperformFactory
        SuperformFactory superformFactory = SuperformFactory(getContract(SOURCE_CHAIN, "SuperformFactory"));
        underlyingSuperformIds = new uint256[](vaultAddresses.length);
        address superformAddress;
        for (uint256 i = 0; i < vaultAddresses.length; i++) {
            (underlyingSuperformIds[i], superformAddress) = superformFactory.createSuperform(1, vaultAddresses[i]);
            console.log("Superform", i, "created at", superformAddress);
        }

        uint256[] memory weights = new uint256[](vaultAddresses.length);
        for (uint256 i = 0; i < vaultAddresses.length; i++) {
            weights[i] = uint256(10_000) / 3;
            if (i == 2) {
                weights[i] += 1;
            }
        }

        address tokenizedStrategyAddress = address(new TokenizedStrategy(FACTORY));

        console.log("TokenizedStrategy", tokenizedStrategyAddress);
        // Deploy SuperVault
        SuperVault superVault = new SuperVault(
            getContract(SOURCE_CHAIN, "SuperRegistry"),
            getContract(ETH, "USDC"),
            deployer,
            "USDCSuperVaultMorphoEulerAave",
            type(uint256).max,
            underlyingSuperformIds,
            weights
        );
        address superVaultAddress = address(superVault);

        // Deploy Superform
        (SUPER_VAULT_ID1,) = superformFactory.createSuperform(1, superVaultAddress);

        assertTrue(superformFactory.isSuperform(SUPER_VAULT_ID1), "Superform should be registered");

        SuperRegistry(getContract(ETH, "SuperRegistry")).setAddress(keccak256("SUPER_VAULTS_STRATEGIST"), deployer, ETH);

        vm.stopPrank();
    }

    function testSuperVaultConstructorReverts() public {
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

        uint256 amount = 500e6;
        // Perform a direct deposit to the SuperVault
        _directDeposit(SUPER_VAULT_ID1, amount);

        _assertSuperPositionsSplitAccordingToWeights(ETH);

        _directWithdraw(SUPER_VAULT_ID1);

        _assertSuperPositionsAfterWithdraw(ETH);

        vm.stopPrank();
    }

    function testOnERC1155Received() public {
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

    function test_superVault_rebalance() public {
        vm.startPrank(deployer);
        SOURCE_CHAIN = ETH;

        uint256 amount = 10_000e6;
        // Perform a direct deposit to the SuperVault
        _directDeposit(SUPER_VAULT_ID1, amount);

        _assertSuperPositionsSplitAccordingToWeights(ETH);

        // Test case 1
        uint256[] memory indexesToRebalanceTo = new uint256[](2);
        indexesToRebalanceTo[0] = 1;
        indexesToRebalanceTo[1] = 2;
        uint256[] memory finalWeightsTargets = new uint256[](2);
        finalWeightsTargets[0] = 4000;
        finalWeightsTargets[1] = 3500;
        uint256[] memory indexesRebalanceFrom = new uint256[](1);
        indexesRebalanceFrom[0] = 0;

        _performRebalance(indexesToRebalanceTo, finalWeightsTargets, indexesRebalanceFrom);

        // Test case 2
        indexesToRebalanceTo = new uint256[](2);
        indexesToRebalanceTo[0] = 0;
        indexesToRebalanceTo[1] = 2;
        finalWeightsTargets = new uint256[](2);
        finalWeightsTargets[0] = 5000;
        finalWeightsTargets[1] = 3600;
        indexesRebalanceFrom = new uint256[](1);
        indexesRebalanceFrom[0] = 1;

        _performRebalance(indexesToRebalanceTo, finalWeightsTargets, indexesRebalanceFrom);
    }

    function testRebalanceArrayLengthMismatch() public {
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
            superformIdsRebalanceFrom,
            amountsRebalanceFrom,
            superformIdsRebalanceTo,
            weightsOfRedistribution,
            1 ether,
            1 ether,
            100
        );
        vm.stopPrank();
    }

    function testRebalanceDuplicateSuperformId() public {
        vm.startPrank(deployer);
        // Setup
        uint256[] memory superformIdsRebalanceFrom = new uint256[](2);
        superformIdsRebalanceFrom[0] = underlyingSuperformIds[0];
        superformIdsRebalanceFrom[1] = underlyingSuperformIds[1];

        uint256[] memory amountsRebalanceFrom = new uint256[](2);
        amountsRebalanceFrom[0] = 1e18;
        amountsRebalanceFrom[1] = 2e18;

        uint256[] memory superformIdsRebalanceTo = new uint256[](2);
        superformIdsRebalanceTo[0] = underlyingSuperformIds[2];
        superformIdsRebalanceTo[1] = underlyingSuperformIds[0]; // Duplicate ID

        uint256[] memory weightsOfRedistribution = new uint256[](2);
        weightsOfRedistribution[0] = 5000;
        weightsOfRedistribution[1] = 5000;

        // Get SuperVault address
        (address superFormSuperVault,,) = SUPER_VAULT_ID1.getSuperform();
        address superVaultAddress = IBaseForm(superFormSuperVault).getVaultAddress();

        // Expect revert with DUPLICATE_SUPERFORM_ID error
        vm.expectRevert(abi.encodeWithSignature("DUPLICATE_SUPERFORM_ID()"));

        // Call rebalance function
        SuperVault(payable(superVaultAddress)).rebalance(
            superformIdsRebalanceFrom,
            amountsRebalanceFrom,
            superformIdsRebalanceTo,
            weightsOfRedistribution,
            1 ether,
            1 ether,
            100
        );
        vm.stopPrank();
    }

    function testHarvestAndReport() public {
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

    function testSetDepositLimit() public {
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

    function testSetRefundsReceiver() public {
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
        assertEq(SuperVault(payable(superVaultAddress)).REFUNDS_RECEIVER(), deployer);
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

    function _assertSuperPositionsSplitAccordingToWeights(uint64 dstChain) internal {
        vm.selectFork(FORKS[dstChain]);

        (address superFormSuperVault,,) = SUPER_VAULT_ID1.getSuperform();
        address superVaultAddress = IBaseForm(superFormSuperVault).getVaultAddress();
        uint256[] memory svDataWeights = new uint256[](underlyingSuperformIds.length);
        (,, svDataWeights) = SuperVault(superVaultAddress).getSuperVaultData();

        uint256[] memory calculatedWeights = _calculateRealWeights(superVaultAddress);

        for (uint256 i = 0; i < underlyingSuperformIds.length; i++) {
            console.log("Calculated weight", calculatedWeights[i], "Sv data weight", svDataWeights[i]);
            assertApproxEqRel(calculatedWeights[i], svDataWeights[i], 0.5e18);
        }
    }

    function _calculateRealWeights(address superVaultAddress) internal view returns (uint256[] memory) {
        uint256 totalUnderlyingBalanceOfSuperVault;
        uint256[] memory underlyingBalanceOfSuperVault = new uint256[](underlyingSuperformIds.length);

        for (uint256 i = 0; i < underlyingSuperformIds.length; i++) {
            uint256 spBalanceInSuperVault =
                SuperPositions(SUPER_POSITIONS_SOURCE).balanceOf(superVaultAddress, underlyingSuperformIds[i]);
            (address superform,,) = underlyingSuperformIds[i].getSuperform();
            underlyingBalanceOfSuperVault[i] =
                IERC4626(IBaseForm(superform).getVaultAddress()).convertToAssets(spBalanceInSuperVault);
            totalUnderlyingBalanceOfSuperVault += underlyingBalanceOfSuperVault[i];
        }

        uint256[] memory calculatedWeights = new uint256[](underlyingSuperformIds.length);
        for (uint256 i = 0; i < underlyingSuperformIds.length; i++) {
            calculatedWeights[i] =
                underlyingBalanceOfSuperVault[i].mulDiv(10_000, totalUnderlyingBalanceOfSuperVault, Math.Rounding.Up);
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
        uint256[] memory indexesToRebalanceTo,
        uint256[] memory finalWeightsTargets,
        uint256[] memory indexesRebalanceFrom
    )
        internal
    {
        RebalanceLocalVars memory vars;

        (vars.superFormSuperVault,,) = SUPER_VAULT_ID1.getSuperform();
        vars.superVaultAddress = IBaseForm(vars.superFormSuperVault).getVaultAddress();

        // Calculate current weights
        uint256[] memory currentWeights = _calculateRealWeights(vars.superVaultAddress);

        // Check that final weights targets are not lower than current weights
        for (uint256 i = 0; i < indexesToRebalanceTo.length; i++) {
            uint256 index = indexesToRebalanceTo[i];
            require(
                finalWeightsTargets[i] >= currentWeights[index],
                "Final weight target must be greater than or equal to current weight"
            );
        }

        vars.nIndexesToRebalanceTo = indexesToRebalanceTo.length;
        vars.indexesToRebalanceTo = indexesToRebalanceTo;
        vars.finalWeightsTargets = finalWeightsTargets;
        vars.indexesRebalanceFrom = indexesRebalanceFrom;

        vars.superformIdsRebalanceFrom = new uint256[](indexesRebalanceFrom.length);
        for (uint256 i = 0; i < indexesRebalanceFrom.length; i++) {
            vars.superformIdsRebalanceFrom[i] = underlyingSuperformIds[indexesRebalanceFrom[i]];
        }
        vars.amountsRebalanceFrom = new uint256[](indexesRebalanceFrom.length);
        vars.superformIdsRebalanceTo = new uint256[](vars.nIndexesToRebalanceTo);

        // Calculate total USDC value of all positions
        vars.totalUSDCValue = 0;
        uint256[] memory currentUSDC = new uint256[](underlyingSuperformIds.length);
        for (uint256 i = 0; i < underlyingSuperformIds.length; i++) {
            (address superform,,) = underlyingSuperformIds[i].getSuperform();
            uint256 superformShares =
                SuperPositions(SUPER_POSITIONS_SOURCE).balanceOf(vars.superVaultAddress, underlyingSuperformIds[i]);
            currentUSDC[i] = IBaseForm(superform).previewRedeemFrom(superformShares);
            vars.totalUSDCValue += currentUSDC[i];
            console.log("currentUSDC", i, ":", currentUSDC[i]);
        }

        console.log("totalUSDCValue", vars.totalUSDCValue);

        // Calculate target USDC amounts for positions to rebalance to
        vars.targetUSDC = new uint256[](vars.nIndexesToRebalanceTo);
        vars.currentUSDC = new uint256[](vars.nIndexesToRebalanceTo);
        vars.currentShares = new uint256[](vars.nIndexesToRebalanceTo);
        vars.additionalUSDC = new uint256[](vars.nIndexesToRebalanceTo);
        vars.totalAdditionalUSDC = 0;

        for (uint256 i = 0; i < vars.nIndexesToRebalanceTo; i++) {
            uint256 index = vars.indexesToRebalanceTo[i];

            vars.superformIdsRebalanceTo[i] = underlyingSuperformIds[index];

            vars.targetUSDC[i] = vars.totalUSDCValue * vars.finalWeightsTargets[i] / 10_000;
            (address superform,,) = vars.superformIdsRebalanceTo[i].getSuperform();
            vars.currentShares[i] = SuperPositions(SUPER_POSITIONS_SOURCE).balanceOf(
                vars.superVaultAddress, vars.superformIdsRebalanceTo[i]
            );
            vars.currentUSDC[i] = IBaseForm(superform).previewRedeemFrom(vars.currentShares[i]);
            vars.additionalUSDC[i] =
                vars.targetUSDC[i] > vars.currentUSDC[i] ? vars.targetUSDC[i] - vars.currentUSDC[i] : 0;
            console.log("additionalUSDC", i, ":", vars.additionalUSDC[i]);
            vars.totalAdditionalUSDC += vars.additionalUSDC[i];
        }

        // Calculate amounts to rebalance from each source
        uint256 totalCurrentUSDCFromSources = 0;
        for (uint256 i = 0; i < vars.indexesRebalanceFrom.length; i++) {
            uint256 index = vars.indexesRebalanceFrom[i];
            totalCurrentUSDCFromSources += currentUSDC[index];
        }

        for (uint256 i = 0; i < vars.indexesRebalanceFrom.length; i++) {
            uint256 index = vars.indexesRebalanceFrom[i];
            (address superform,,) = vars.superformIdsRebalanceFrom[i].getSuperform();
            uint256 amountUSDCToRebalance = vars.totalAdditionalUSDC * currentUSDC[index] / totalCurrentUSDCFromSources;
            vars.amountsRebalanceFrom[i] = IBaseForm(superform).previewDepositTo(amountUSDCToRebalance);
            console.log("amountsRebalanceFrom", i, ":", vars.amountsRebalanceFrom[i]);
        }

        // Calculate weights for redistribution
        console.log("Weights of redistribution:");
        vars.weightsOfRedistribution = new uint256[](vars.nIndexesToRebalanceTo);
        uint256 totalWeights = 0;
        for (uint256 i = 0; i < vars.nIndexesToRebalanceTo; i++) {
            if (i != vars.nIndexesToRebalanceTo - 1) {
                vars.weightsOfRedistribution[i] = vars.totalAdditionalUSDC > 0
                    ? vars.additionalUSDC[i].mulDiv(10_000, vars.totalAdditionalUSDC, Math.Rounding.Down)
                    : 0;
                totalWeights += vars.weightsOfRedistribution[i];
            } else {
                vars.weightsOfRedistribution[i] = 10_000 - totalWeights;
            }
            console.log(vars.weightsOfRedistribution[i]);
        }

        SuperVault(payable(IBaseForm(vars.superFormSuperVault).getVaultAddress())).rebalance{ value: 4 ether }(
            vars.superformIdsRebalanceFrom,
            vars.amountsRebalanceFrom,
            vars.superformIdsRebalanceTo,
            vars.weightsOfRedistribution,
            2 ether,
            2 ether,
            100
        );
    }
}
