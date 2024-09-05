// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ISuperPositions } from "superform-core/interfaces/ISuperPositions.sol";
import { IERC1155Receiver } from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import { BaseStrategy } from "./vendor/BaseStrategy.sol";
import { SingleDirectMultiVaultStateReq, MultiVaultSFData, LiqRequest } from "superform-core/types/DataTypes.sol";
import { DataLib } from "superform-core/libraries/DataLib.sol";
import { IBaseForm } from "superform-core/interfaces/IBaseForm.sol";
import { IBaseRouter } from "superform-core/interfaces/IBaseRouter.sol";
import { ISuperformRouterPlus } from "superform-core/interfaces/ISuperformRouterPlus.sol";
import { ISuperRegistry } from "superform-core/interfaces/ISuperRegistry.sol";

contract SuperVault is BaseStrategy, IERC1155Receiver {
    using Math for uint256;
    using DataLib for uint256;
    using SafeERC20 for ERC20;

    error ARRAY_LENGTH_MISMATCH();

    error INVALID_WEIGHTS();

    error NOT_SUPER_VAULTS_STRATEGIST();

    error ZERO_ADDRESS();

    //
    // Examples:
    // 1 - USDC SuperVault: Morpho + Euler + Aave USDC (3 vaults total to start)) -> ETH
    //      Asset: USDC
    // 2 - Stablecoins SuperVault: Morpho + Euler + Aave (USDC, DAI, USDT (9 vaults total)) -> ETH
    //
    // Requirements:
    // 1 - Management can set %s for each Superform (done also at launch)
    // 2 - Factory: input superform ids + weights and deploy - anyone can create a super vault
    // 3 - Auto-Rebalancing: who will be rebalancing? A fireblocks keeper
    // 4 - There is an algorithm to tell the weights for the keeper to rebalance (TBD, function will allow any weights
    // to be set)

    //////////////////////////////////////////////////////////////
    //                     STATE VARIABLES                      //
    //////////////////////////////////////////////////////////////

    struct SuperVaultStrategyData {
        uint256 numberOfSuperforms;
        uint256[] superformIds;
        uint256[] weights;
    }

    SuperVaultStrategyData private SV;

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
        string memory name_,
        uint256[] memory superformIds_,
        uint256[] memory startingWeights_
    )
        BaseStrategy(asset_, name_)
    {
        if (superRegistry_ == address(0)) {
            revert ZERO_ADDRESS();
        }

        superRegistry = ISuperRegistry(superRegistry_);

        uint256 numberOfSuperforms = superformIds_.length;
        if (numberOfSuperforms != startingWeights_.length) {
            revert ARRAY_LENGTH_MISMATCH();
        }

        uint256 totalWeight;

        for (uint256 i; i < numberOfSuperforms; ++i) {
            totalWeight += startingWeights_[i];
        }
        if (totalWeight != TOTAL_WEIGHT) revert INVALID_WEIGHTS();

        SV.numberOfSuperforms = numberOfSuperforms;
        SV.superformIds = superformIds_;
        SV.weights = startingWeights_;
    }

    //////////////////////////////////////////////////////////////
    //                  EXTERNAL  FUNCTIONS                     //
    //////////////////////////////////////////////////////////////

    function rebalance(
        uint256[] memory superformIdsRebalanceFrom,
        uint256[] memory amountsRebalanceFrom,
        uint256[] memory superformIdsRebalanceTo,
        uint256[] memory weightsOfRedestribution,
        uint256 rebalanceFromMsgValue,
        uint256 rebalanceToMsgValue,
        uint256 slippage
    )
        external
        onlySuperVaultsStrategist
    {
        // Validate input arrays
        if (
            superformIdsRebalanceFrom.length != amountsRebalanceFrom.length
                || superformIdsRebalanceTo.length != weightsOfRedestribution.length
        ) {
            revert ARRAY_LENGTH_MISMATCH();
        }

        // Step 1: Prepare rebalance arguments
        (ISuperformRouterPlus.RebalanceMultiPositionsSyncArgs memory args, address routerPlus) = _prepareRebalanceArgs(
            superformIdsRebalanceFrom,
            amountsRebalanceFrom,
            superformIdsRebalanceTo,
            weightsOfRedestribution,
            rebalanceFromMsgValue,
            rebalanceToMsgValue,
            slippage
        );

        address superPositions = _getAddress(keccak256("SUPER_POSITIONS"));

        // Step 2: Execute rebalance
        ISuperPositions(superPositions).setApprovalForMany(routerPlus, args.ids, args.sharesToRedeem);

        ISuperformRouterPlus(routerPlus).rebalanceMultiPositions{
            value: args.rebalanceFromMsgValue + args.rebalanceToMsgValue
        }(args);

        ISuperPositions(superPositions).setApprovalForMany(routerPlus, args.ids, new uint256[](args.ids.length));

        // Step 3: Update SV data
        _updateSVData(superPositions);
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
        return interfaceId == type(IERC165).interfaceId;
    }
    //////////////////////////////////////////////////////////////
    //                     BASESTRATEGY OVERRIDES               //
    //////////////////////////////////////////////////////////////

    function _deployFunds(uint256 amount_) internal override {
        (MultiVaultSFData memory mvData, address router) = _prepareMultiVaultData(amount_, true);

        bytes memory callData = abi.encodeWithSelector(
            IBaseRouter.singleDirectMultiVaultDeposit.selector, SingleDirectMultiVaultStateReq(mvData)
        );

        asset.safeApprove(router, amount_);

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

    function _harvestAndReport() internal override returns (uint256 totalAssets) {
        /// call harvest on all superPositions
        /// call report on all superPositions
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
        mvData.receiverAddress = REFUNDS_RECEIVER;
        mvData.receiverAddressSP = address(this);
        mvData.outputAmounts = new uint256[](numberOfSuperforms);

        for (uint256 i; i < numberOfSuperforms; ++i) {
            (address superform,,) = mvData.superformIds[i].getSuperform();
            if (isDeposit) {
                mvData.amounts[i] = amount_.mulDiv(SV.weights[i], TOTAL_WEIGHT, Math.Rounding.Down);
                mvData.outputAmounts[i] = IBaseForm(superform).previewDepositTo(mvData.amounts[i]);
            } else {
                mvData.outputAmounts[i] = amount_.mulDiv(SV.weights[i], TOTAL_WEIGHT, Math.Rounding.Down);
                mvData.amounts[i] = IBaseForm(superform).previewWithdrawFrom(mvData.outputAmounts[i]);
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
        for (uint256 i = 0; i < superformIds.length; i++) {
            (address superform,,) = superformIds[i].getSuperform();

            if (isWithdraw) {
                data.outputAmounts[i] = IBaseForm(superform).previewRedeemFrom(amounts[i]);
            } else {
                data.outputAmounts[i] = IBaseForm(superform).previewDepositTo(amounts[i]);
            }

            totalOutputAmount += data.outputAmounts[i];

            /// TODO: decide on slippage if per vault or global
            data.maxSlippages[i] = slippage;
        }
        data.retain4626s = new bool[](superformIds.length);
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

    function _updateSVData(address superPositions) internal {
        uint256 totalValue = 0;
        uint256 length = SV.numberOfSuperforms;
        uint256[] memory newWeights = new uint256[](length);
        uint256[] memory superformIds = SV.superformIds;

        // Calculate total value and individual values
        for (uint256 i = 0; i < length; i++) {
            uint256 balance = ISuperPositions(superPositions).balanceOf(address(this), superformIds[i]);
            (address superform,,) = superformIds[i].getSuperform();
            uint256 value = IERC4626(IBaseForm(superform).getVaultAddress()).convertToAssets(balance);
            totalValue += value;
            newWeights[i] = value;
        }

        // Calculate new weights as percentages
        for (uint256 i = 0; i < length; i++) {
            newWeights[i] = newWeights[i].mulDiv(TOTAL_WEIGHT, totalValue, Math.Rounding.Down);
        }

        // Update SV weights
        SV.weights = newWeights;
    }
}
