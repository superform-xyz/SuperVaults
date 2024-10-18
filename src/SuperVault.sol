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
import { BaseStrategy } from "tokenized-strategy/BaseStrategy.sol";
import { ISuperVault, IERC1155Receiver } from "./ISuperVault.sol";

/// @title SuperVault
/// @notice A vault contract that manages multiple Superform positions
/// @dev Inherits from BaseStrategy and implements ISuperVault and IERC1155Receiver
/// @author Superform Labs
contract SuperVault is BaseStrategy, ISuperVault {
    using Math for uint256;
    using DataLib for uint256;
    using SafeERC20 for ERC20;

    //////////////////////////////////////////////////////////////
    //                     STATE VARIABLES                      //
    //////////////////////////////////////////////////////////////

    /// @notice The chain ID of the network this contract is deployed on
    uint64 public immutable CHAIN_ID;

    /// @notice The address of the SuperRegistry contract
    ISuperRegistry public immutable superRegistry;

    /// @notice The total weight used for calculating proportions (10000 = 100%)
    uint256 public constant TOTAL_WEIGHT = 10_000;

    /// @notice The maximum allowed slippage (1% = 100)
    uint256 public constant MAX_SLIPPAGE = 100;

    /// @notice The address that receives refunds
    address public refundReceiver;

    /// @notice Struct containing SuperVault strategy data
    SuperVaultStrategyData private SV;

    //////////////////////////////////////////////////////////////
    //                       MODIFIERS                          //
    //////////////////////////////////////////////////////////////

    /// @notice Ensures that only the Super Vaults Strategist can call the function
    modifier onlySuperVaultsStrategist() {
        if (_getAddress(keccak256("SUPER_VAULTS_STRATEGIST")) != msg.sender) {
            revert NOT_SUPER_VAULTS_STRATEGIST();
        }
        _;
    }

    //////////////////////////////////////////////////////////////
    //                       CONSTRUCTOR                        //
    //////////////////////////////////////////////////////////////

    /// @param superRegistry_ Address of the SuperRegistry contract
    /// @param asset_ Address of the asset token
    /// @param refundsReceiver_ Address to receive refunds
    /// @param name_ Name of the strategy
    /// @param depositLimit_ Maximum deposit limit
    /// @param superformIds_ Array of Superform IDs
    /// @param startingWeights_ Array of starting weights for each Superform
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
        refundReceiver = refundsReceiver_;

        uint256 numberOfSuperforms = superformIds_.length;
        if (numberOfSuperforms != startingWeights_.length) {
            revert ARRAY_LENGTH_MISMATCH();
        }

        ISuperformFactory factory = ISuperformFactory(_getAddress(keccak256("SUPERFORM_FACTORY")));

        uint256 totalWeight;
        address superform;

        for (uint256 i; i < numberOfSuperforms; ++i) {
            /// @dev this superVault only supports superforms that have the same asset as the vault
            (superform,,) = superformIds_[i].getSuperform();

            if (!factory.isSuperform(superformIds_[i])) {
                revert SUPERFORM_DOES_NOT_EXIST(superformIds_[i]);
            }

            if (IBaseForm(superform).getVaultAsset() != asset_) {
                revert SUPERFORM_DOES_NOT_SUPPORT_ASSET();
            }

            totalWeight += startingWeights_[i];
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

    /// @notice Sets the deposit limit for the vault
    /// @param depositLimit_ The new deposit limi
    function setDepositLimit(uint256 depositLimit_) external onlySuperVaultsStrategist {
        SV.depositLimit = depositLimit_;

        emit DepositLimitSet(depositLimit_);
    }

    /// @notice Sets the refunds receiver address
    /// @param refundReceiver_ The new refunds receiver address
    function setRefundsReceiver(address refundReceiver_) external onlySuperVaultsStrategist {
        if (refundReceiver_ == address(0)) revert ZERO_ADDRESS();
        refundReceiver = refundReceiver_;

        emit RefundsReceiverSet(refundReceiver_);
    }

    /// @inheritdoc ISuperVault
    function rebalance(RebalanceArgs calldata rebalanceArgs) external payable override onlySuperVaultsStrategist {
        uint256 lenRebalanceFrom = rebalanceArgs.superformIdsRebalanceFrom.length;
        uint256 lenFinal = rebalanceArgs.finalSuperformIds.length;

        /// @dev sanity check input arrays
        if (
            lenRebalanceFrom != rebalanceArgs.amountsRebalanceFrom.length
                || lenFinal != rebalanceArgs.weightsOfRedestribution.length
        ) {
            revert ARRAY_LENGTH_MISMATCH();
        }

        {
            /// @dev caching to avoid multiple SLOADs
            uint256 numberOfSuperforms = SV.numberOfSuperforms;
            uint256 foundCount;

            for (uint256 i; i < lenRebalanceFrom; ++i) {
                for (uint256 j; j < numberOfSuperforms; ++j) {
                    if (rebalanceArgs.superformIdsRebalanceFrom[i] == SV.superformIds[j]) {
                        foundCount++;
                        break;
                    }
                }
            }

            if (foundCount != lenRebalanceFrom) {
                revert INVALID_SUPERFORM_ID_REBALANCE_FROM();
            }
        }

        /// @dev step 1: prepare rebalance arguments
        ISuperformRouterPlus.RebalanceMultiPositionsSyncArgs memory args = _prepareRebalanceArgs(
            rebalanceArgs.superformIdsRebalanceFrom,
            rebalanceArgs.amountsRebalanceFrom,
            rebalanceArgs.finalSuperformIds,
            rebalanceArgs.weightsOfRedestribution,
            rebalanceArgs.rebalanceFromMsgValue,
            rebalanceArgs.rebalanceToMsgValue,
            rebalanceArgs.slippage
        );

        address routerPlus = _getAddress(keccak256("SUPERFORM_ROUTER_PLUS"));
        address superPositions = _getAddress(keccak256("SUPER_POSITIONS"));

        /// @dev step 2: execute rebalance
        ISuperPositions(superPositions).setApprovalForMany(routerPlus, args.ids, args.sharesToRedeem);

        ISuperformRouterPlus(routerPlus).rebalanceMultiPositions{
            value: args.rebalanceFromMsgValue + args.rebalanceToMsgValue
        }(args);

        ISuperPositions(superPositions).setApprovalForMany(routerPlus, args.ids, new uint256[](args.ids.length));

        /// @dev step 3: update SV data
        /// @notice no issue about reentrancy as the external contracts are trusted
        /// @notice updateSV emits rebalance event
        _updateSVData(superPositions, rebalanceArgs.finalSuperformIds);
    }

    //////////////////////////////////////////////////////////////
    //                 EXTERNAL VIEW/PURE FUNCTIONS             //
    //////////////////////////////////////////////////////////////

    /// @notice Returns the SuperVault data
    /// @return numberOfSuperforms The number of Superforms
    /// @return superformIds Array of Superform IDs
    /// @return weights Array of weights for each Superform
    function getSuperVaultData()
        external
        view
        returns (uint256 numberOfSuperforms, uint256[] memory superformIds, uint256[] memory weights)
    {
        return (SV.numberOfSuperforms, SV.superformIds, SV.weights);
    }

    /// @inheritdoc IERC1155Receiver
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

    /// @inheritdoc IERC1155Receiver
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

    /// @notice Checks if the contract supports a given interface
    /// @param interfaceId The interface identifier
    /// @return bool True if the contract supports the interface
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId;
    }

    /// @inheritdoc BaseStrategy
    function availableDepositLimit(address /*_owner*/ ) public view override returns (uint256) {
        uint256 totalAssets = TokenizedStrategy.totalAssets();
        uint256 depositLimit = SV.depositLimit;
        return totalAssets >= depositLimit ? 0 : depositLimit - totalAssets;
    }

    //////////////////////////////////////////////////////////////
    //                     BASESTRATEGY OVERRIDES               //
    //////////////////////////////////////////////////////////////

    /// @notice Deploys funds to the underlying Superforms
    /// @param amount_ The amount of funds to deploy
    function _deployFunds(uint256 amount_) internal override {
        MultiVaultSFData memory mvData = _prepareMultiVaultData(amount_, true);
        address router = _getAddress(keccak256("SUPERFORM_ROUTER"));

        bytes memory callData = abi.encodeWithSelector(
            IBaseRouter.singleDirectMultiVaultDeposit.selector, SingleDirectMultiVaultStateReq(mvData)
        );

        asset.safeIncreaseAllowance(router, amount_);

        /// @dev this call has to be enforced with 0 msg.value not to break the 4626 standard
        (bool success, bytes memory returndata) = router.call(callData);

        Address.verifyCallResult(success, returndata, "CallRevertWithNoReturnData");

        if (asset.allowance(address(this), router) > 0) asset.forceApprove(router, 0);
    }

    /// @notice Frees funds from the underlying Superforms
    /// @param amount_ The amount of funds to free
    function _freeFunds(uint256 amount_) internal override {
        (MultiVaultSFData memory mvData) = _prepareMultiVaultData(amount_, false);
        address router = _getAddress(keccak256("SUPERFORM_ROUTER"));
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

    /// @notice Reports the total assets of the vault
    /// @return totalAssets The total assets of the vault
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
    //                     INTERNAL FUNCTIONS                   //
    //////////////////////////////////////////////////////////////

    /// @notice Prepares multi-vault data for deposit or withdrawal
    /// @param amount_ The amount to deposit or withdraw
    /// @param isDeposit True if depositing, false if withdrawing
    /// @return mvData The prepared multi-vault data
    function _prepareMultiVaultData(
        uint256 amount_,
        bool isDeposit
    )
        internal
        view
        returns (MultiVaultSFData memory mvData)
    {
        uint256 numberOfSuperforms = SV.numberOfSuperforms;

        mvData.superformIds = SV.superformIds;
        mvData.amounts = new uint256[](numberOfSuperforms);
        mvData.maxSlippages = new uint256[](numberOfSuperforms);
        mvData.liqRequests = new LiqRequest[](numberOfSuperforms);
        mvData.hasDstSwaps = new bool[](numberOfSuperforms);
        mvData.retain4626s = mvData.hasDstSwaps;
        mvData.receiverAddress = isDeposit ? refundReceiver : address(this);
        mvData.receiverAddressSP = address(this);
        mvData.outputAmounts = new uint256[](numberOfSuperforms);

        /// @dev caching to avoid multiple MLOADs
        address superform;
        IBaseForm superformContract;

        for (uint256 i; i < numberOfSuperforms; ++i) {
            mvData.liqRequests[i].token = address(asset);

            (superform,,) = mvData.superformIds[i].getSuperform();
            superformContract = IBaseForm(superform);

            if (isDeposit) {
                /// @notice rounding down to avoid one-off issue
                mvData.amounts[i] = amount_.mulDiv(SV.weights[i], TOTAL_WEIGHT, Math.Rounding.Down);
                mvData.outputAmounts[i] = superformContract.previewDepositTo(mvData.amounts[i]);
            } else {
                mvData.outputAmounts[i] = amount_.mulDiv(SV.weights[i], TOTAL_WEIGHT, Math.Rounding.Down);
                /// @notice convertToShares here helps avoid round up issue
                mvData.amounts[i] =
                    IERC4626(superformContract.getVaultAddress()).convertToShares(mvData.outputAmounts[i]);
            }

            mvData.maxSlippages[i] = MAX_SLIPPAGE;
        }
    }

    /// @dev returns the address for id_ from super registry
    function _getAddress(bytes32 id_) internal view returns (address) {
        return superRegistry.getAddress(id_);
    }

    /// @notice Prepares rebalance arguments for Superform Router Plus
    /// @param superformIdsRebalanceFrom Array of Superform IDs to rebalance from
    /// @param amountsRebalanceFrom Array of amounts to rebalance from
    /// @param finalSuperformIds Array of Superform IDs to rebalance to
    /// @param weightsOfRedestribution Array of weights for redestribution
    /// @param rebalanceFromMsgValue Value to send with rebalanceFrom call
    /// @param rebalanceToMsgValue Value to send with rebalanceTo call
    /// @param slippage Maximum allowed slippage
    function _prepareRebalanceArgs(
        uint256[] calldata superformIdsRebalanceFrom,
        uint256[] calldata amountsRebalanceFrom,
        uint256[] calldata finalSuperformIds,
        uint256[] calldata weightsOfRedestribution,
        uint256 rebalanceFromMsgValue,
        uint256 rebalanceToMsgValue,
        uint256 slippage
    )
        internal
        view
        returns (ISuperformRouterPlus.RebalanceMultiPositionsSyncArgs memory args)
    {
        args.ids = superformIdsRebalanceFrom;
        args.sharesToRedeem = amountsRebalanceFrom;
        args.rebalanceFromMsgValue = rebalanceFromMsgValue;
        args.rebalanceToMsgValue = rebalanceToMsgValue;
        args.interimAsset = address(asset); // Assuming 'asset' is the interim token
        args.slippage = slippage; // 1% slippage, adjust as needed
        args.receiverAddressSP = address(this);

        (SingleDirectMultiVaultStateReq memory req, uint256 totalOutputAmount) =
            _prepareSingleDirectMultiVaultStateReq(superformIdsRebalanceFrom, amountsRebalanceFrom, slippage, true);

        /// @dev prepare callData for rebalance from
        args.callData = abi.encodeWithSelector(IBaseRouter.singleDirectMultiVaultWithdraw.selector, req);

        /// @dev create a filtered version of superformIdsRebalanceTo
        (uint256[] memory filteredSuperformIds, uint256[] memory filteredWeights) =
            _filterNonZeroWeights(finalSuperformIds, weightsOfRedestribution);

        (req,) = _prepareSingleDirectMultiVaultStateReq(
            filteredSuperformIds, _calculateAmounts(totalOutputAmount, filteredWeights), slippage, false
        );

        /// @dev prepare rebalanceToCallData
        args.rebalanceToCallData = abi.encodeWithSelector(IBaseRouter.singleDirectMultiVaultDeposit.selector, req);
        args.expectedAmountToReceivePostRebalanceFrom = totalOutputAmount;
    }

    /// @notice Prepares single direct multi-vault state request
    /// @param superformIds Array of Superform IDs
    /// @param amounts Array of amounts
    /// @param slippage Maximum allowed slippage
    /// @param isWithdraw True if withdrawing, false if depositing
    /// @return req The prepared single direct multi-vault state request
    /// @return totalOutputAmount The total output amount
    function _prepareSingleDirectMultiVaultStateReq(
        uint256[] memory superformIds,
        uint256[] memory amounts,
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

        address routerPlus = _getAddress(keccak256("SUPERFORM_ROUTER_PLUS"));

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

    /// @notice Calculates amounts based on total output amount and weights
    /// @param totalOutputAmount The total output amount
    /// @param weights Array of weights
    /// @return amounts Array of calculated amounts
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

    /// @notice Filters out zero weights and returns corresponding superform IDs and weights
    /// @param superformIds Array of Superform IDs
    /// @param weights Array of weights
    /// @return filteredIds Array of filtered Superform IDs
    /// @return filteredWeights Array of filtered weights
    function _filterNonZeroWeights(
        uint256[] memory superformIds,
        uint256[] memory weights
    )
        internal
        pure
        returns (uint256[] memory filteredIds, uint256[] memory filteredWeights)
    {
        uint256 count;
        for (uint256 i; i < weights.length; ++i) {
            if (weights[i] != 0) {
                count++;
            }
        }

        filteredIds = new uint256[](count);
        filteredWeights = new uint256[](count);

        uint256 j;
        for (uint256 i; i < weights.length; ++i) {
            if (weights[i] != 0) {
                filteredIds[j] = superformIds[i];
                filteredWeights[j] = weights[i];
                j++;
            }
        }
    }

    /// @notice Updates the SuperVault data after rebalancing
    /// @param superPositions Address of the SuperPositions contract
    /// @param finalSuperformIds Array of Superform IDs to rebalance to
    function _updateSVData(address superPositions, uint256[] memory finalSuperformIds) internal {
        uint256 totalWeight;

        uint256 length = finalSuperformIds.length;
        uint256[] memory newWeights = new uint256[](length);

        /// @dev check if finalSuperformIds are present in superform factory and support the asset
        ISuperformFactory factory = ISuperformFactory(_getAddress(keccak256("SUPERFORM_FACTORY")));
        address superform;
        uint256 value;
        address assetCache = address(asset);

        /// @dev calculate total value and individual values
        for (uint256 i; i < length; ++i) {
            if (!factory.isSuperform(finalSuperformIds[i])) {
                revert SUPERFORM_DOES_NOT_EXIST(finalSuperformIds[i]);
            }

            (superform,,) = finalSuperformIds[i].getSuperform();

            if (IBaseForm(superform).getVaultAsset() != assetCache) {
                revert SUPERFORM_DOES_NOT_SUPPORT_ASSET();
            }

            uint256 balance = ISuperPositions(superPositions).balanceOf(address(this), finalSuperformIds[i]);
            value = IERC4626(IBaseForm(superform).getVaultAddress()).convertToAssets(balance);

            newWeights[i] = value;
            totalWeight += value;
        }

        /// @dev calculate new weights as percentages
        uint256 totalAssignedWeight;
        for (uint256 i; i < length - 1; ++i) {
            newWeights[i] = newWeights[i].mulDiv(TOTAL_WEIGHT, totalWeight, Math.Rounding.Down);
            totalAssignedWeight += newWeights[i];
        }

        /// @notice assign remaining weight to the last index
        newWeights[length - 1] = TOTAL_WEIGHT - totalAssignedWeight;

        /// @dev update SV weights
        SV.weights = newWeights;
        SV.superformIds = finalSuperformIds;
        SV.numberOfSuperforms = length;

        emit RebalanceComplete(finalSuperformIds, newWeights);
    }
}
