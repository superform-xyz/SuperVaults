// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.23;

import "superform-core/test/utils/ProtocolActions.sol";
import { ISuperformRouterPlus } from "superform-core/src/interfaces/ISuperformRouterPlus.sol";
import { ISuperformRouterPlusAsync } from "superform-core/src/interfaces/ISuperformRouterPlusAsync.sol";
import { IBaseRouter } from "superform-core/src/interfaces/IBaseRouter.sol";
import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { Math } from "openzeppelin/contracts/utils/math/Math.sol";
import { SuperVault } from "../src/SuperVault.sol";

contract SuperVaultTest is ProtocolActions {
    using Math for uint256;

    using DataLib for uint256;

    address SUPER_POSITIONS_SOURCE;

    uint64 SOURCE_CHAIN;

    uint256 SUPER_VAULT_ID1;
    uint256[] underlyingSuperformIds;

    function setUp() public override {
        chainIds = [ETH];
        super.setUp();

        SOURCE_CHAIN = ETH;

        SUPER_POSITIONS_SOURCE = getContract(SOURCE_CHAIN, "SuperPositions");

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
        for (uint256 i = 0; i < vaultAddresses.length; i++) {
            (underlyingSuperformIds[i],) = superformFactory.createSuperform(1, vaultAddresses[i]);
        }

        uint256[] memory weights = new uint256[](vaultAddresses.length);
        for (uint256 i = 0; i < vaultAddresses.length; i++) {
            weights[i] = uint256(10_000) / 3;
            if (i == 2) {
                weights[i] += 1;
            }
        }

        // Deploy SuperVault
        SuperVault superVault = new SuperVault(
            getContract(SOURCE_CHAIN, "SuperRegistry"),
            getContract(ETH, "USDC"),
            deployer,
            "USDCSuperVaultMorphoEulerAave",
            underlyingSuperformIds,
            weights
        );
        address superVaultAddress = address(superVault);

        // Deploy Superform
        (SUPER_VAULT_ID1,) = superformFactory.createSuperform(1, superVaultAddress);

        assertTrue(superformFactory.isSuperform(SUPER_VAULT_ID1), "Superform should be registered");

        vm.stopPrank();
    }

    function test_superVault_assertSuperPositions_splitAccordingToWeights() public {
        vm.startPrank(deployer);

        // Perform a direct deposit to the SuperVault
        _directDeposit(SUPER_VAULT_ID1);
        (address superVault,,) = SUPER_VAULT_ID1.getSuperform();
        // Assert that the SuperPositions minted are split evenly according to the weights
        for (uint256 i = 0; i < underlyingSuperformIds.length; i++) {
            uint256 balance = SuperPositions(SUPER_POSITIONS_SOURCE).balanceOf(superVault, underlyingSuperformIds[i]);
            assertEq(
                balance,
                1e18 / underlyingSuperformIds.length,
                "SuperPositions should be split evenly according to the weights"
            );
        }

        vm.stopPrank();
    }
    //////////////////////////////////////////////////////////////
    //               INTERNAL HELPERS                           //
    //////////////////////////////////////////////////////////////

    function _directDeposit(uint256 superformId) internal {
        vm.selectFork(FORKS[SOURCE_CHAIN]);
        (address superform,,) = superformId.getSuperform();

        SingleVaultSFData memory data = SingleVaultSFData(
            superformId,
            1e18,
            1e18,
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

        assertGt(SuperPositions(SUPER_POSITIONS_SOURCE).balanceOf(deployer, superformId), 0);
    }

    function _xChainDeposit(uint256 superformId, uint64 dstChainId, uint256 payloadIdToProcess) internal {
        (address superform,,) = superformId.getSuperform();

        vm.selectFork(FORKS[dstChainId]);

        address underlyingToken = IBaseForm(superform).getVaultAsset();

        SingleVaultSFData memory data = SingleVaultSFData(
            superformId,
            1e18,
            1e18,
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
                        1e18,
                        //1e18,
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
            address(payable(getContract(SOURCE_CHAIN, "SuperformRouter"))), req.superformData.amount
        );

        vm.recordLogs();
        /// @dev msg sender is wallet, tx origin is deployer
        SuperformRouter(payable(getContract(SOURCE_CHAIN, "SuperformRouter"))).singleXChainSingleVaultDeposit{
            value: 2 ether
        }(req);

        uint256 totalAmountToDeposit =
            _convertDecimals(data.amount, getContract(SOURCE_CHAIN, "DAI"), underlyingToken, SOURCE_CHAIN, dstChainId);

        _processXChainDepositOneVault(
            SOURCE_CHAIN, dstChainId, vm.getRecordedLogs(), underlyingToken, totalAmountToDeposit, payloadIdToProcess
        );

        vm.selectFork(FORKS[SOURCE_CHAIN]);

        assertGt(SuperPositions(getContract(SOURCE_CHAIN, "SuperPositions")).balanceOf(deployer, superformId), 0);
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
}
