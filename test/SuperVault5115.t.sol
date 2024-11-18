// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "superform-core/test/utils/ProtocolActions.sol";
import { VaultMock } from "superform-core/test/mocks/VaultMock.sol";

import { console2 } from "forge-std/console2.sol";
import { Math } from "openzeppelin/contracts/utils/math/Math.sol";

import { SuperVault } from "../src/SuperVault.sol";
import { ISuperVault } from "../src/interfaces/ISuperVault.sol";
import { IStandardizedYield } from "../test/pendle/IStandardizedYield.sol";
import { ITokenizedStrategy } from "tokenized-strategy/interfaces/ITokenizedStrategy.sol";

contract Mock5115VaultWithRewards is Test {
    address public constant asset = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

    address constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    function deposit(uint256 amount) external {
        deal(USDC, msg.sender, amount);
    }

    function previewDeposit(uint256 amount) external view returns (uint256) {
        return amount;
    }

    function withdraw(uint256 amount) external {
        deal(USDT, msg.sender, amount);
    }

    function previewWithdraw(uint256 amount) external view returns (uint256) {
        return amount;
    }

    function getRewardTokens() external pure returns (address[] memory) {
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = USDT;
        rewardTokens[1] = USDC;

        return rewardTokens;
    }

    function claimRewards(address user) external returns (uint256[] memory rewardAmounts) {
        deal(USDT, user, 1e6);
        deal(USDC, user, 2e6);

        rewardAmounts = new uint256[](2);
        rewardAmounts[0] = 1e6;
        rewardAmounts[1] = 2e6;
    }

    function accruedRewards(address) external pure returns (uint256[] memory rewardAmounts) {
        rewardAmounts = new uint256[](2);
        rewardAmounts[0] = 1e6;
        rewardAmounts[1] = 2e6;
    }

    function rewardIndexesStored() external pure returns (uint256[] memory indices) {
        indices = new uint256[](2);
        indices[0] = 1;
        indices[1] = 2;
    }

    function isValidTokenIn(address) external pure returns (bool isValid) {
        isValid = true;
    }

    function isValidTokenOut(address) external pure returns (bool isValid) {
        isValid = true;
    }
}

contract SuperVault5115Test is ProtocolActions {
    using Math for uint256;

    uint32 FORM_ID = 3;
    uint256 SUPER_VAULT_ID;

    uint256[] superform5115Ids;

    ERC5115Form targetSuperform;
    ERC5115Form rewardsSuperform;

    SuperVault superVaultWith5115;

    IStandardizedYield targetVault;

    ISuperformFactory superformFactory;

    ERC5115To4626Wrapper targetWrapper;
    ERC5115To4626Wrapper rewardsWrapper;

    Mock5115VaultWithRewards rewardsVault;

    address SUPER_POSITIONS_SOURCE;

    address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

    address constant KEEPER = address(uint160(uint256(keccak256("KEEPER"))));
    address constant PERFORMANCE_FEE_RECIPIENT = address(uint160(uint256(keccak256("PERFORMANCE_FEE_RECIPIENT"))));

    function setUp() public override {
        super.setUp();

        SUPER_POSITIONS_SOURCE = getContract(ARBI, "SuperPositions");

        // Setup ARBI 5115 SuperVault
        vm.selectFork(FORKS[ARBI]);   
        vm.startPrank(deployer);

        rewardsVault = new Mock5115VaultWithRewards();
        
        rewardsWrapper = new ERC5115To4626Wrapper(
            address(rewardsVault),
            getContract(ARBI, "wstETH"),
            USDC
        );

        targetSuperform = ERC5115Form(getContract(ARBI, "wstETHERC5115Superform3"));

        targetWrapper = ERC5115To4626Wrapper(targetSuperform.vault());

        targetVault = IStandardizedYield(targetSuperform.vault());

      //   (uint256[] memory idsByVault, ) = superformFactory.getAllSuperformsFromVault(address(targetVault));
      //  uint256 targetSuperformId = idsByVault[0];

        superformFactory = ISuperformFactory(getContract(ARBI, "SuperformFactory"));

        (uint256 rewardsSuperformId, address rewardsSuperformCreated) =
            superformFactory.createSuperform(FORM_ID, address(rewardsVault));
        rewardsSuperform = ERC5115Form(rewardsSuperformCreated);
        // rewardsWrapper = new ERC5115To4626Wrapper(
        //     address(rewardsVault), 
        //     getContract(ARBI, "wstETH"), 
        //     USDC
        // );
        rewardsWrapper = new ERC5115To4626Wrapper(
            address(rewardsVault), 
            USDT, 
            USDC
        );

        superform5115Ids = new uint256[](1);
        superform5115Ids[0] = rewardsSuperformId;
        //superform5115Ids[0] = targetSuperformId;

        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        // Deploy 5115 SuperVault
        superVaultWith5115 = new SuperVault(
            getContract(ARBI, "SuperRegistry"),
            USDT,
            deployer,
            deployer,
            "USDT5115SuperVault",
            type(uint256).max,
            superform5115Ids,
            weights
        );

        bool[] memory isWhitelisted5115 = new bool[](1);
        isWhitelisted5115[0] = true;

        ISuperVault(address(superVaultWith5115)).setWhitelist(superform5115Ids, isWhitelisted5115);

        deal(USDT, deployer, 1e18);

        /// @dev after deploying superVault, deployer (a FB role) needs to accept management
        /// @dev also needs to be set as keeper (a new FB role)
        /// @dev also we need to have a performance fee recipient (a new FB role)
        (bool setKeeperSuccess,) = address(superVaultWith5115).call(abi.encodeWithSignature("setKeeper(address)", KEEPER));
        require(setKeeperSuccess, "Failed to set keeper");

        (bool setPerformanceFeeRecipientSuccess,) = address(superVaultWith5115).call(
            abi.encodeWithSignature("setPerformanceFeeRecipient(address)", PERFORMANCE_FEE_RECIPIENT)
        );
        require(setPerformanceFeeRecipientSuccess, "Failed to set performance fee recipient");

        (bool getPerformanceFeeSuccess,) = address(superVaultWith5115).call(abi.encodeWithSelector(ITokenizedStrategy.performanceFee.selector));
        require(getPerformanceFeeSuccess, "Failed to get performance fee");

        // Deploy Superform
        (SUPER_VAULT_ID,) = superformFactory.createSuperform(1, address(superVaultWith5115));

        SuperRegistry(getContract(ARBI, "SuperRegistry")).setAddress(
            keccak256("SUPER_VAULTS_STRATEGIST"), deployer, ARBI
        );

        SuperRegistry(getContract(ARBI, "SuperRegistry")).setAddress(keccak256("VAULT_MANAGER"), deployer, ARBI);

        vm.stopPrank();
    }

    function test_setUp() public {
        assertTrue(superformFactory.isSuperform(SUPER_VAULT_ID), "Superform should be registered");

        assertTrue(superVaultWith5115.getIsWhitelisted(superform5115Ids)[0], "Superform should be whitelisted");

        assertEq(superVaultWith5115.availableDepositLimit(deployer), type(uint256).max, "Deposit limit should be max");

        assertEq(superVaultWith5115.vaultManager(), deployer, "Vault manager should be deployer");

        assertEq(superVaultWith5115.strategist(), deployer, "Strategist should be deployer");
    }

    function test_setVaultManager() public {
        address newVaultManager = address(0xDEAD);
        // Test successful vault manager update
        vm.prank(deployer);
        superVaultWith5115.setVaultManager(newVaultManager);
    }

    function test_superVault5115_depositAndWithdraw() public {
        vm.startPrank(deployer);
        vm.selectFork(FORKS[ARBI]);

        uint256 amount = 500e6;

        // Perform a direct deposit to the SuperVault
        _directDeposit(SUPER_VAULT_ID, amount);

        //_assertSuperPositionsSplitAccordingToWeights(ETH);

        _directWithdraw(SUPER_VAULT_ID);

        //_assertSuperPositionsAfterWithdraw(ETH);

        vm.stopPrank();
    }

    // function test_onERC1155Received() public view {
    //     // Arrange
    //     address operator = address(0x1);
    //     address from = address(0x2);
    //     uint256 id = 1;
    //     uint256 value = 100;
    //     bytes memory data = "";
    //     (address superFormSuperVault5115,,) = SUPER_VAULT_ID.getSuperform();
    //     address superVault5115Address = IBaseForm(superFormSuperVault5115).getVaultAddress();

    //     // Act
    //     bytes4 result = SuperVault(superVault5115Address).onERC1155Received(operator, from, id, value, data);

    //     // Assert
    //     bytes4 expectedSelector = SuperVault.onERC1155Received.selector;
    //     assertEq(result, expectedSelector, "onERC1155Received should return the correct selector");
    // }

    //////////////////////////////////////////////////////////////
    //               INTERNAL HELPERS                           //
    //////////////////////////////////////////////////////////////

    function _directDeposit(uint256 superformId, uint256 amount) internal {
        vm.selectFork(FORKS[ARBI]);
        address superform = address(superVaultWith5115);

        SingleVaultSFData memory data = SingleVaultSFData(
            superformId,
            amount,
            amount,
            100,
            LiqRequest("", 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9, address(0), 1, ARBI, 0),
            "",
            false,
            false,
            deployer,
            deployer,
            ""
        );

        SingleDirectSingleVaultStateReq memory req = SingleDirectSingleVaultStateReq(data);
        MockERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9).approve(
            address(payable(getContract(ARBI, "SuperformRouter"))), req.superformData.amount
        );

        /// @dev msg sender is wallet, tx origin is deployer
        SuperformRouter(payable(getContract(ARBI, "SuperformRouter"))).singleDirectSingleVaultDeposit{
            value: 2 ether
        }(req);
    }

    function _directWithdraw(uint256 superformId) internal {
        vm.selectFork(FORKS[ARBI]);
        address superform = address(superVaultWith5115);
        address superPositions = getContract(ARBI, "SuperPositions");
        uint256 amountToWithdraw = SuperPositions(superPositions).balanceOf(deployer, superformId);

        SingleVaultSFData memory data = SingleVaultSFData(
            superformId,
            amountToWithdraw,
            IBaseForm(superform).previewWithdrawFrom(amountToWithdraw),
            100,
            LiqRequest("", 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9, address(0), 1, ARBI, 0),
            "",
            false,
            false,
            deployer,
            deployer,
            ""
        );

        SingleDirectSingleVaultStateReq memory req = SingleDirectSingleVaultStateReq(data);
        address superformRouter = getContract(ARBI, "SuperformRouter");
        SuperPositions(superPositions).setApprovalForOne(superformRouter, superformId, amountToWithdraw);

        /// @dev msg sender is wallet, tx origin is deployer
        SuperformRouter(payable(superformRouter)).singleDirectSingleVaultWithdraw{ value: 2 ether }(req);
    }

    // function _assertSuperPositionsSplitAccordingToWeights(uint64 dstChain) internal {
    //     vm.selectFork(FORKS[dstChain]);

    //     (address superFormSuperVault,,) = SUPER_VAULT_ID.getSuperform();
    //     address superVaultAddress = IBaseForm(superFormSuperVault).getVaultAddress();
    //     uint256[] memory svDataWeights = new uint256[](underlyingSuperformIds.length);
    //     SuperVault vault = SuperVault(superVaultAddress);
    //     for (uint256 i; i < underlyingSuperformIds.length; i++) {
    //         svDataWeights[i] = vault.weights(i);
    //     }
    //     uint256[] memory underlyingIndexes = _calculateUnderlyingIndexes();
    //     uint256[] memory calculatedWeights = _calculateRealWeights(superVaultAddress, underlyingIndexes);

    //     for (uint256 i = 0; i < underlyingSuperformIds.length; i++) {
    //         console.log("Calculated weight", calculatedWeights[i], "Sv data weight", svDataWeights[i]);
    //         assertApproxEqRel(calculatedWeights[i], svDataWeights[i], 0.5e18);
    //     }
    // }

    // function _assertSuperPositionsAfterWithdraw(uint64 dstChain) internal {
    //     vm.selectFork(FORKS[dstChain]);

    //     (address superFormSuperVault,,) = SUPER_VAULT_ID.getSuperform();
    //     address superVaultAddress = IBaseForm(superFormSuperVault).getVaultAddress();

    //     // Assert that the SuperPositions are 0 after full withdrawal
    //     for (uint256 i = 0; i < superform5115Ids.length; i++) {
    //         uint256 spBalanceInSuperVault =
    //             SuperPositions(SUPER_POSITIONS_SOURCE).balanceOf(superVaultAddress, superform5115Ids[i]);

    //         console.log("SuperPosition balance for underlying Superform", i, ":", spBalanceInSuperVault);

    //         assertEq(spBalanceInSuperVault, 0, "SuperPosition balance should be 0 after full withdrawal");
    //     }
    // }

    // function _calculateUnderlyingIndexes() internal view returns (uint256[] memory underlyingIndexes) {
    //     underlyingIndexes = new uint256[](superform5115Ids.length);
    //     for (uint256 i = 0; i < underlyingSuperformIds.length; i++) {
    //         for (uint256 j = 0; j < allSuperformIds.length; j++) {
    //             if (allSuperformIds[j] == underlyingSuperformIds[i]) {
    //                 underlyingIndexes[i] = j;
    //                 break;
    //             }
    //         }
    //     }
    // }

    // function _calculateRealWeights(
    //     address superVaultAddress,
    //     uint256[] memory indexes
    // )
    //     internal
    //     view
    //     returns (uint256[] memory)
    // {
    //     uint256 totalUnderlyingBalanceOfSuperVault;
    //     uint256[] memory underlyingBalanceOfSuperVault = new uint256[](indexes.length);

    //     for (uint256 i = 0; i < indexes.length; i++) {
    //         uint256 superformId = superform5115Ids[indexes[i]];
    //         uint256 spBalanceInSuperVault =
    //             SuperPositions(SUPER_POSITIONS_SOURCE).balanceOf(superVaultAddress, superformId);
    //         (address superform,,) = superformId.getSuperform();
    //         underlyingBalanceOfSuperVault[i] =
    //             IERC4626(IBaseForm(superform).getVaultAddress()).convertToAssets(spBalanceInSuperVault);
    //         totalUnderlyingBalanceOfSuperVault += underlyingBalanceOfSuperVault[i];
    //     }

    //     uint256[] memory calculatedWeights = new uint256[](indexes.length);
    //     for (uint256 i = 0; i < indexes.length; i++) {
    //         calculatedWeights[i] =
    //             underlyingBalanceOfSuperVault[i].mulDiv(10_000, totalUnderlyingBalanceOfSuperVault, Math.Rounding.Up);
    //         console.log("Calculated weight", indexes[i], ":", calculatedWeights[i]);
    //     }

    //     return calculatedWeights;
    // }

    // function _xChainDeposit(
    //     uint256 superformId,
    //     uint256 amount,
    //     uint64 dstChainId,
    //     uint256 payloadIdToProcess
    // )
    //     internal
    // {
    //     (address superform,,) = superformId.getSuperform();

    //     vm.selectFork(FORKS[dstChainId]);

    //     address underlyingToken = IBaseForm(superform).getVaultAsset();

    //     uint256 totalAmountToDeposit =
    //         _convertDecimals(amount, getContract(ARBI, "DAI"), underlyingToken, ARBI, dstChainId);

    //     SingleVaultSFData memory data = SingleVaultSFData(
    //         superformId,
    //         totalAmountToDeposit,
    //         IBaseForm(superform).previewDepositTo(totalAmountToDeposit),
    //         100,
    //         LiqRequest(
    //             _buildLiqBridgeTxData(
    //                 LiqBridgeTxDataArgs(
    //                     1,
    //                     getContract(ARBI, "DAI"),
    //                     getContract(ARBI, ERC20(underlyingToken).symbol()),
    //                     underlyingToken,
    //                     getContract(ARBI, "SuperformRouter"),
    //                     ARBI,
    //                     dstChainId,
    //                     dstChainId,
    //                     false,
    //                     getContract(dstChainId, "CoreStateRegistry"),
    //                     uint256(dstChainId),
    //                     amount,
    //                     false,
    //                     /// @dev placeholder value, not used
    //                     0,
    //                     1,
    //                     1,
    //                     1,
    //                     address(0)
    //                 ),
    //                 false
    //             ),
    //             getContract(ARBI, "DAI"),
    //             address(0),
    //             1,
    //             dstChainId,
    //             0
    //         ),
    //         "",
    //         false,
    //         false,
    //         deployer,
    //         deployer,
    //         ""
    //     );
    //     vm.selectFork(FORKS[ARBI]);

    //     SingleXChainSingleVaultStateReq memory req = SingleXChainSingleVaultStateReq(AMBs, dstChainId, data);
    //     MockERC20(getContract(ARBI, "DAI")).approve(
    //         address(payable(getContract(ARBI, "SuperformRouter"))), amount
    //     );

    //     vm.recordLogs();
    //     /// @dev msg sender is wallet, tx origin is deployer
    //     SuperformRouter(payable(getContract(ARBI, "SuperformRouter"))).singleXChainSingleVaultDeposit{
    //         value: 2 ether
    //     }(req);

    //     _processXChainDepositOneVault(
    //         ARBI, dstChainId, vm.getRecordedLogs(), underlyingToken, totalAmountToDeposit, payloadIdToProcess
    //     );

    //     vm.selectFork(FORKS[ARBI]);
    // }

    // function _xChainWithdraw(uint256 superformId, uint64 dstChainId, uint256 payloadIdToProcess) internal {
    //     vm.selectFork(FORKS[ARBI]);
    //     (address superform,,) = superformId.getSuperform();
    //     address superPositions = getContract(ARBI, "SuperPositions");
    //     uint256 amountToWithdraw = SuperPositions(superPositions).balanceOf(deployer, superformId);
    //     vm.selectFork(FORKS[dstChainId]);

    //     SingleVaultSFData memory data = SingleVaultSFData(
    //         superformId,
    //         amountToWithdraw,
    //         IBaseForm(superform).previewWithdrawFrom(amountToWithdraw),
    //         100,
    //         LiqRequest("", address(0), address(0), 1, dstChainId, 0),
    //         "",
    //         false,
    //         false,
    //         deployer,
    //         deployer,
    //         ""
    //     );

    //     vm.selectFork(FORKS[ARBI]);

    //     SingleXChainSingleVaultStateReq memory req = SingleXChainSingleVaultStateReq(AMBs, dstChainId, data);
    //     address superformRouter = getContract(ARBI, "SuperformRouter");
    //     SuperPositions(superPositions).setApprovalForOne(superformRouter, superformId, amountToWithdraw);

    //     vm.recordLogs();
    //     /// @dev msg sender is wallet, tx origin is deployer
    //     SuperformRouter(payable(superformRouter)).singleXChainSingleVaultWithdraw{ value: 2 ether }(req);

    //     _processXChainWithdrawOneVault(ARBI, dstChainId, vm.getRecordedLogs(), payloadIdToProcess);

    //     vm.selectFork(FORKS[ARBI]);
    // }

    // function _deliverAMBMessage(uint64 fromChain, uint64 toChain, Vm.Log[] memory logs) internal {
    //     for (uint256 i = 0; i < AMBs.length; i++) {
    //         if (AMBs[i] == 2) {
    //             // Hyperlane
    //             HyperlaneHelper(getContract(fromChain, "HyperlaneHelper")).help(
    //                 address(HYPERLANE_MAILBOXES[fromChain]), address(HYPERLANE_MAILBOXES[toChain]), FORKS[toChain], logs
    //             );
    //         } else if (AMBs[i] == 3) {
    //             WormholeHelper(getContract(fromChain, "WormholeHelper")).help(
    //                 WORMHOLE_CHAIN_IDS[fromChain], FORKS[toChain], wormholeRelayer, logs
    //             );
    //         }
    //     }
    // }

    // function _convertDecimals(
    //     uint256 amount,
    //     address token1,
    //     address token2,
    //     uint64 chainId1,
    //     uint64 chainId2
    // )
    //     internal
    //     returns (uint256 convertedAmount)
    // {
    //     uint256 initialFork = vm.activeFork();
    //     vm.selectFork(FORKS[chainId1]);
    //     uint256 decimals1 = MockERC20(token1).decimals();
    //     vm.selectFork(FORKS[chainId2]);
    //     uint256 decimals2 = MockERC20(token2).decimals();

    //     if (decimals1 > decimals2) {
    //         convertedAmount = amount / (10 ** (decimals1 - decimals2));
    //     } else {
    //         convertedAmount = amount * 10 ** (decimals2 - decimals1);
    //     }
    //     vm.selectFork(initialFork);
    // }

    // function _processXChainDepositOneVault(
    //     uint64 fromChain,
    //     uint64 toChain,
    //     Vm.Log[] memory logs,
    //     address destinationToken,
    //     uint256 amountArrivedInDst,
    //     uint256 payloadIdToProcess
    // )
    //     internal
    // {
    //     vm.stopPrank();
    //     // Simulate AMB message delivery
    //     _deliverAMBMessage(fromChain, toChain, logs);

    //     vm.startPrank(deployer);

    //     uint256[] memory amounts = new uint256[](1);
    //     amounts[0] = amountArrivedInDst;

    //     address[] memory bridgedTokens = new address[](1);
    //     bridgedTokens[0] = destinationToken;

    //     CoreStateRegistry coreStateRegistry = CoreStateRegistry(getContract(toChain, "CoreStateRegistry"));
    //     vm.selectFork(FORKS[toChain]);

    //     coreStateRegistry.updateDepositPayload(payloadIdToProcess, bridgedTokens, amounts);

    //     // Perform processPayload on CoreStateRegistry on destination chain
    //     uint256 nativeAmount = PaymentHelper(getContract(toChain, "PaymentHelper")).estimateAckCost(payloadIdToProcess);
    //     vm.recordLogs();

    //     coreStateRegistry.processPayload{ value: nativeAmount }(payloadIdToProcess);
    //     logs = vm.getRecordedLogs();

    //     vm.stopPrank();

    //     // Simulate AMB message delivery back to source chain
    //     _deliverAMBMessage(toChain, fromChain, logs);

    //     vm.startPrank(deployer);
    //     // Switch back to source chain fork
    //     vm.selectFork(FORKS[fromChain]);

    //     // Perform processPayload on source chain to mint SuperPositions
    //     coreStateRegistry = CoreStateRegistry(getContract(fromChain, "CoreStateRegistry"));

    //     coreStateRegistry.processPayload(coreStateRegistry.payloadsCount());

    //     vm.stopPrank();
    // }

    // function _processXChainWithdrawOneVault(
    //     uint64 fromChain,
    //     uint64 toChain,
    //     Vm.Log[] memory logs,
    //     uint256 payloadIdToProcess
    // )
    //     internal
    // {
    //     vm.stopPrank();

    //     // Simulate AMB message delivery
    //     _deliverAMBMessage(fromChain, toChain, logs);

    //     vm.startPrank(deployer);

    //     vm.selectFork(FORKS[toChain]);
    //     CoreStateRegistry coreStateRegistry = CoreStateRegistry(getContract(toChain, "CoreStateRegistry"));

    //     // Perform processPayload on CoreStateRegistry on destination chain
    //     uint256 nativeAmount = PaymentHelper(getContract(toChain, "PaymentHelper")).estimateAckCost(payloadIdToProcess);
    //     vm.recordLogs();

    //     coreStateRegistry.processPayload{ value: nativeAmount }(payloadIdToProcess);

    //     vm.stopPrank();
    // }

    // function _assertWeightsWithinTolerance(
    //     uint256[] memory finalIndexes,
    //     uint256[] memory finalWeightsTargets
    // )
    //     internal
    //     view
    // {
    //     (address superFormSuperVault,,) = SUPER_VAULT_ID1.getSuperform();
    //     address superVaultAddress = IBaseForm(superFormSuperVault).getVaultAddress();

    //     uint256[] memory realWeights = _calculateRealWeights(superVaultAddress, finalIndexes);

    //     for (uint256 i = 0; i < finalIndexes.length; i++) {
    //         uint256 index = finalIndexes[i];
    //         uint256 targetWeight = finalWeightsTargets[i];
    //         uint256 realWeight = realWeights[i];

    //         // Calculate the difference between target and real weight
    //         uint256 difference = targetWeight > realWeight ? targetWeight - realWeight : realWeight - targetWeight;
    //         console.log("Target Weight:", targetWeight, "Real Weight:", realWeight);

    //         // Assert that the difference is within 1% (100 basis points) of the target weight
    //         assertLe(
    //             difference,
    //             targetWeight / 100,
    //             string(abi.encodePacked("Weight for index ", Strings.toString(index), " is off by more than 1%"))
    //         );
    //     }
    // }
}
