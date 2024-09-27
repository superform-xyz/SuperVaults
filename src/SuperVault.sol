// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import { Address } from "openzeppelin/contracts/utils/Address.sol";
import { Math } from "openzeppelin/contracts/utils/math/Math.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { IERC165 } from "openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IERC4626 } from "openzeppelin/contracts/interfaces/IERC4626.sol";
import { SingleDirectMultiVaultStateReq, MultiVaultSFData, LiqRequest } from "superform-core/src/types/DataTypes.sol";
import { ISuperPositions } from "superform-core/src/interfaces/ISuperPositions.sol";
import { DataLib } from "superform-core/src/libraries/DataLib.sol";
import { IBaseForm } from "superform-core/src/interfaces/IBaseForm.sol";
import { IBaseRouter } from "superform-core/src/interfaces/IBaseRouter.sol";
import { ISuperformRouterPlus } from "superform-core/src/interfaces/ISuperformRouterPlus.sol";
import { ISuperRegistry } from "superform-core/src/interfaces/ISuperRegistry.sol";
import { ISuperformFactory } from "superform-core/src/interfaces/ISuperformFactory.sol";
import { BaseStrategy } from "tokenized-strategy/BaseStrategy.sol";
import { ISuperVault, IERC1155Receiver } from "./ISuperVault.sol";

import "forge-std/console.sol";

contract SuperVault is BaseStrategy, ISuperVault {
    using Math for uint256;
    using DataLib for uint256;
    using SafeERC20 for ERC20;

    //////////////////////////////////////////////////////////////
    //                     STATE VARIABLES                      //
    //////////////////////////////////////////////////////////////

    SuperVaultStrategyData private SV;

    uint64 public immutable CHAIN_ID;

    uint256 public constant TOTAL_WEIGHT = 10_000;
    uint256 public constant MAX_SLIPPAGE = 100; // 1%

    /// TODO who will be the refunds receiver? A superform controlled address
    address public REFUNDS_RECEIVER;

    ISuperRegistry public immutable superRegistry;

    //////////////////////////////////////////////////////////////
    //                       MODIFIERS                          //
    //////////////////////////////////////////////////////////////

    modifier onlySuperVaultsStrategist() {
        if (_getAddress(keccak256("SUPER_VAULTS_STRATEGIST")) != msg.sender) {
            revert NOT_SUPER_VAULTS_STRATEGIST();
        }
        _;
    }

    //////////////////////////////////////////////////////////////
    //                       CONSTRUCTOR                        //
    //////////////////////////////////////////////////////////////
    constructor(
        address superRegistry_,
        address asset_,
        address refundsReceiver_,
        string memory name_,
        uint256 depositLimit_,
        uint256[] memory superformIds_,
        uint256[] memory startingWeights_
    )
        BaseStrategy(asset_, name_)
    {
        if (superRegistry_ == address(0) || refundsReceiver_ == address(0)) {
            revert ZERO_ADDRESS();
        }

        if (block.chainid > type(uint64).max) {
            revert BLOCK_CHAIN_ID_OUT_OF_BOUNDS();
        }

        CHAIN_ID = uint64(block.chainid);

        superRegistry = ISuperRegistry(superRegistry_);
        REFUNDS_RECEIVER = refundsReceiver_;

        uint256 numberOfSuperforms = superformIds_.length;
        if (numberOfSuperforms != startingWeights_.length) {
            revert ARRAY_LENGTH_MISMATCH();
        }

        ISuperformFactory factory = ISuperformFactory(_getAddress(keccak256("SUPERFORM_FACTORY")));

        uint256 totalWeight;

        for (uint256 i; i < numberOfSuperforms; ++i) {
            totalWeight += startingWeights_[i];
            /// @dev this superVault only supports superforms that have the same asset as the vault
            (address superform,,) = superformIds_[i].getSuperform();
            if (!factory.isSuperform(superformIds_[i])) {
                revert SUPERFORM_DOES_NOT_EXIST(superformIds_[i]);
            }
            if (IBaseForm(superform).getVaultAsset() != asset_) {
                revert SUPERFORM_DOES_NOT_SUPPORT_ASSET();
            }
        }
        if (totalWeight != TOTAL_WEIGHT) revert INVALID_WEIGHTS();

        SV.numberOfSuperforms = numberOfSuperforms;
        SV.superformIds = superformIds_;
        SV.weights = startingWeights_;
        SV.depositLimit = depositLimit_;
    }

    //////////////////////////////////////////////////////////////
    //                  EXTERNAL  FUNCTIONS                     //
    //////////////////////////////////////////////////////////////

    function setDepositLimit(uint256 depositLimit_) external onlySuperVaultsStrategist {
        SV.depositLimit = depositLimit_;

        emit DepositLimitSet(depositLimit_);
    }

    function setRefundsReceiver(address refundReceiver_) external onlySuperVaultsStrategist {
        REFUNDS_RECEIVER = refundReceiver_;

        emit RefundsReceiverSet(refundReceiver_);
    }

    // @inheritdoc ISuperVault
    function rebalance(RebalanceArgs memory a) external payable override onlySuperVaultsStrategist {
        uint256 lenRebalanceFrom = a.superformIdsRebalanceFrom.length;
        uint256 lenFinal = a.finalSuperformIds.length;
        // Validate input arrays
        if (lenRebalanceFrom != a.amountsRebalanceFrom.length || lenFinal != a.weightsOfRedestribution.length) {
            revert ARRAY_LENGTH_MISMATCH();
        }
        uint256 numberOfSuperforms = SV.numberOfSuperforms;
        // Check if superformIdsRebalanceFrom is contained within SV Data and save the indexes of the found ids
        uint256 foundCount = 0;
        bool[] memory foundInSV = new bool[](lenRebalanceFrom);
        for (uint256 i; i < lenRebalanceFrom; ++i) {
            for (uint256 j; j < numberOfSuperforms; ++j) {
                if (a.superformIdsRebalanceFrom[i] == SV.superformIds[j]) {
                    foundCount++;
                    foundInSV[i] = true;
                    break;
                }
            }
        }
        if (foundCount != lenRebalanceFrom) {
            revert INVALID_SUPERFORM_ID_REBALANCE_FROM();
        }
        // Check if not found superformIdsRebalanceFrom are in finalSuperformIds
        for (uint256 i; i < lenRebalanceFrom; ++i) {
            if (!foundInSV[i]) {
                bool foundInRebalanceTo = false;
                for (uint256 j; j < lenFinal; ++j) {
                    if (a.superformIdsRebalanceFrom[i] == a.finalSuperformIds[j]) {
                        foundInRebalanceTo = true;
                        break;
                    }
                }
                if (!foundInRebalanceTo) {
                    revert REBALANCE_FROM_ID_NOT_FOUND_IN_FINAL_IDS();
                }
            }
        }

        // Check if finalSuperformIds are present in superform factory and support the asset
        ISuperformFactory factory = ISuperformFactory(_getAddress(keccak256("SUPERFORM_FACTORY")));
        for (uint256 i; i < lenFinal; ++i) {
            if (!factory.isSuperform(a.finalSuperformIds[i])) {
                revert SUPERFORM_DOES_NOT_EXIST(a.finalSuperformIds[i]);
            }
            (address superform,,) = a.finalSuperformIds[i].getSuperform();
            if (IBaseForm(superform).getVaultAsset() != address(asset)) {
                revert SUPERFORM_DOES_NOT_SUPPORT_ASSET();
            }
        }

        // Step 1: Prepare rebalance arguments
        (ISuperformRouterPlus.RebalanceMultiPositionsSyncArgs memory args, address routerPlus) = _prepareRebalanceArgs(
            a.superformIdsRebalanceFrom,
            a.amountsRebalanceFrom,
            a.finalSuperformIds,
            a.weightsOfRedestribution,
            a.rebalanceFromMsgValue,
            a.rebalanceToMsgValue,
            a.slippage
        );

        address superPositions = _getAddress(keccak256("SUPER_POSITIONS"));

        // Step 2: Execute rebalance
        ISuperPositions(superPositions).setApprovalForMany(routerPlus, args.ids, args.sharesToRedeem);

        ISuperformRouterPlus(routerPlus).rebalanceMultiPositions{
            value: args.rebalanceFromMsgValue + args.rebalanceToMsgValue
        }(args);

        ISuperPositions(superPositions).setApprovalForMany(routerPlus, args.ids, new uint256[](args.ids.length));

        // Step 3: Update SV data
        uint256[] memory newWeights = _updateSVData(superPositions, a.finalSuperformIds);

        emit RebalanceComplete(a.finalSuperformIds, newWeights);
    }

    function getSuperVaultData()
        external
        view
        returns (uint256 numberOfSuperforms, uint256[] memory superformIds, uint256[] memory weights)
    {
        return (SV.numberOfSuperforms, SV.superformIds, SV.weights);
    }

    //////////////////////////////////////////////////////////////
    //                  EXTERNAL PURE FUNCTIONS                //
    //////////////////////////////////////////////////////////////

    /// @dev overrides receive functions
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    )
        external
        pure
        override
        returns (bytes4)
    {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    )
        external
        pure
        override
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId;
    }

    function availableDepositLimit(address /*_owner*/ ) public view override returns (uint256) {
        uint256 totalAssets = TokenizedStrategy.totalAssets();
        uint256 depositLimit = SV.depositLimit;
        return totalAssets >= depositLimit ? 0 : depositLimit - totalAssets;
    }

    //////////////////////////////////////////////////////////////
    //                     BASESTRATEGY OVERRIDES               //
    //////////////////////////////////////////////////////////////

    function _deployFunds(uint256 amount_) internal override {
        (MultiVaultSFData memory mvData, address router) = _prepareMultiVaultData(amount_, true);

        bytes memory callData = abi.encodeWithSelector(
            IBaseRouter.singleDirectMultiVaultDeposit.selector, SingleDirectMultiVaultStateReq(mvData)
        );

        asset.safeIncreaseAllowance(router, amount_);

        /// @dev this call has to be enforced with 0 msg.value not to break the 4626 standard
        (bool success, bytes memory returndata) = router.call(callData);

        Address.verifyCallResult(success, returndata, "CallRevertWithNoReturnData");

        if (asset.allowance(address(this), router) > 0) asset.forceApprove(router, 0);
    }

    function _freeFunds(uint256 amount_) internal override {
        (MultiVaultSFData memory mvData, address router) = _prepareMultiVaultData(amount_, false);

        bytes memory callData = abi.encodeWithSelector(
            IBaseRouter.singleDirectMultiVaultWithdraw.selector, SingleDirectMultiVaultStateReq(mvData)
        );

        ISuperPositions(_getAddress(keccak256("SUPER_POSITIONS"))).setApprovalForMany(
            router, mvData.superformIds, mvData.amounts
        );

        /// @dev this call has to be enforced with 0 msg.value not to break the 4626 standard
        (bool success, bytes memory returndata) = router.call(callData);

        Address.verifyCallResult(success, returndata, "CallRevertWithNoReturnData");

        /// @dev reset approvals
        ISuperPositions(_getAddress(keccak256("SUPER_POSITIONS"))).setApprovalForMany(
            router, mvData.superformIds, new uint256[](mvData.superformIds.length)
        );
    }

    function _harvestAndReport() internal view override returns (uint256 totalAssets) {
        /// @dev we will be using reward distributor and transfer rewards to users directly
        /// @dev thus this function we will be unused (we just report full assets)
        uint256 totalAssetsInVaults;
        uint256 numberOfSuperforms = SV.numberOfSuperforms;
        uint256[] memory superformIds = SV.superformIds;
        for (uint256 i; i < numberOfSuperforms; ++i) {
            (address superform,,) = superformIds[i].getSuperform();
            address vault = IBaseForm(superform).getVaultAddress();
            totalAssetsInVaults += IERC4626(vault).balanceOf(address(this));
        }

        totalAssets = totalAssetsInVaults + asset.balanceOf(address(this));
    }

    //////////////////////////////////////////////////////////////
    //                     INTERNAL FUNCTIONS                     //
    //////////////////////////////////////////////////////////////

    function _prepareMultiVaultData(
        uint256 amount_,
        bool isDeposit
    )
        internal
        view
        returns (MultiVaultSFData memory mvData, address router)
    {
        uint256 numberOfSuperforms = SV.numberOfSuperforms;

        mvData.superformIds = SV.superformIds;
        mvData.amounts = new uint256[](numberOfSuperforms);
        mvData.maxSlippages = new uint256[](numberOfSuperforms);
        mvData.liqRequests = new LiqRequest[](numberOfSuperforms);
        mvData.hasDstSwaps = new bool[](numberOfSuperforms);
        mvData.retain4626s = mvData.hasDstSwaps;
        mvData.receiverAddress = isDeposit ? REFUNDS_RECEIVER : address(this);
        mvData.receiverAddressSP = address(this);
        mvData.outputAmounts = new uint256[](numberOfSuperforms);

        for (uint256 i; i < numberOfSuperforms; ++i) {
            mvData.liqRequests[i].token = address(asset);

            (address superform,,) = mvData.superformIds[i].getSuperform();
            IBaseForm superformContract = IBaseForm(superform);
            if (isDeposit) {
                mvData.amounts[i] = amount_.mulDiv(SV.weights[i], TOTAL_WEIGHT, Math.Rounding.Down);
                mvData.outputAmounts[i] = superformContract.previewDepositTo(mvData.amounts[i]);
            } else {
                mvData.outputAmounts[i] = amount_.mulDiv(SV.weights[i], TOTAL_WEIGHT, Math.Rounding.Down);
                /// @dev using convertToShares here to avoid round up issues
                mvData.amounts[i] =
                    IERC4626(superformContract.getVaultAddress()).convertToShares(mvData.outputAmounts[i]);
            }
            mvData.maxSlippages[i] = MAX_SLIPPAGE;
        }

        router = _getAddress(keccak256("SUPERFORM_ROUTER"));
    }

    /// @dev returns the address from super registry
    function _getAddress(bytes32 id_) internal view returns (address) {
        return superRegistry.getAddress(id_);
    }

    function _prepareRebalanceArgs(
        uint256[] memory superformIdsRebalanceFrom,
        uint256[] memory amountsRebalanceFrom,
        uint256[] memory superformIdsRebalanceTo,
        uint256[] memory weightsOfRedestribution,
        uint256 rebalanceFromMsgValue,
        uint256 rebalanceToMsgValue,
        uint256 slippage
    )
        internal
        view
        returns (ISuperformRouterPlus.RebalanceMultiPositionsSyncArgs memory args, address routerPlus)
    {
        args.ids = superformIdsRebalanceFrom;
        args.sharesToRedeem = amountsRebalanceFrom;
        args.rebalanceFromMsgValue = rebalanceFromMsgValue;
        args.rebalanceToMsgValue = rebalanceToMsgValue;
        args.interimAsset = address(asset); // Assuming 'asset' is the interim token
        args.slippage = slippage; // 1% slippage, adjust as needed
        args.receiverAddressSP = address(this);

        routerPlus = _getAddress(keccak256("SUPERFORM_ROUTER_PLUS"));

        (SingleDirectMultiVaultStateReq memory req, uint256 totalOutputAmount) = _prepareSingleDirectMultiVaultStateReq(
            superformIdsRebalanceFrom, amountsRebalanceFrom, routerPlus, slippage, true
        );
        // Prepare callData for rebalance from
        args.callData = abi.encodeWithSelector(IBaseRouter.singleDirectMultiVaultWithdraw.selector, req);

        (req,) = _prepareSingleDirectMultiVaultStateReq(
            superformIdsRebalanceTo,
            _calculateAmounts(totalOutputAmount, weightsOfRedestribution),
            routerPlus,
            slippage,
            false
        );

        // Prepare rebalanceToCallData
        args.rebalanceToCallData = abi.encodeWithSelector(IBaseRouter.singleDirectMultiVaultDeposit.selector, req);

        args.expectedAmountToReceivePostRebalanceFrom = totalOutputAmount;
    }

    function _prepareSingleDirectMultiVaultStateReq(
        uint256[] memory superformIds,
        uint256[] memory amounts,
        address routerPlus,
        uint256 slippage,
        bool isWithdraw
    )
        internal
        view
        returns (SingleDirectMultiVaultStateReq memory req, uint256 totalOutputAmount)
    {
        MultiVaultSFData memory data;
        data.superformIds = superformIds;
        data.amounts = amounts;
        uint256 length = superformIds.length;
        data.outputAmounts = new uint256[](length);
        data.maxSlippages = new uint256[](length);
        data.liqRequests = new LiqRequest[](length);

        for (uint256 i; i < length; ++i) {
            (address superform,,) = superformIds[i].getSuperform();

            if (isWithdraw) {
                data.outputAmounts[i] = IBaseForm(superform).previewRedeemFrom(amounts[i]);
            } else {
                data.outputAmounts[i] = IBaseForm(superform).previewDepositTo(amounts[i]);
            }

            totalOutputAmount += data.outputAmounts[i];

            /// TODO: decide on slippage if per vault or global
            data.maxSlippages[i] = slippage;
            data.liqRequests[i].token = address(asset);
            data.liqRequests[i].liqDstChainId = CHAIN_ID;
        }
        data.hasDstSwaps = new bool[](length);
        data.retain4626s = data.hasDstSwaps;
        /// @dev routerPlus receives assets to continue the rebalance
        data.receiverAddress = routerPlus;
        /// @dev in case of withdraw failure, this vault receives the superPositions back
        data.receiverAddressSP = address(this);

        req.superformData = data;
    }

    function _calculateAmounts(
        uint256 totalOutputAmount,
        uint256[] memory weights
    )
        internal
        pure
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](weights.length);
        for (uint256 i = 0; i < weights.length; i++) {
            amounts[i] = totalOutputAmount.mulDiv(weights[i], TOTAL_WEIGHT, Math.Rounding.Down);
        }
    }

    function _updateSVData(
        address superPositions,
        uint256[] memory finalSuperformIds
    )
        internal
        returns (uint256[] memory newWeights)
    {
        uint256 totalWeight = 0;
        uint256 length = finalSuperformIds.length;
        newWeights = new uint256[](length);

        // Calculate total value and individual values
        for (uint256 i; i < length; ++i) {
            uint256 balance = ISuperPositions(superPositions).balanceOf(address(this), finalSuperformIds[i]);
            (address superform,,) = finalSuperformIds[i].getSuperform();
            uint256 value = IERC4626(IBaseForm(superform).getVaultAddress()).convertToAssets(balance);
            totalWeight += value;
            newWeights[i] = value;
        }

        // Calculate new weights as percentages
        uint256 totalAssignedWeight = 0;
        for (uint256 i; i < length - 1; ++i) {
            newWeights[i] = newWeights[i].mulDiv(TOTAL_WEIGHT, totalWeight, Math.Rounding.Down);
            totalAssignedWeight += newWeights[i];
            console.log("newWeights", i, ":", newWeights[i]);
        }
        // Assign remaining weight to the last index
        newWeights[length - 1] = TOTAL_WEIGHT - totalAssignedWeight;
        console.log("newWeights", length - 1, ":", newWeights[length - 1]);
        // Update SV weights
        SV.weights = newWeights;
        SV.superformIds = finalSuperformIds;
        SV.numberOfSuperforms = length;
    }
}
