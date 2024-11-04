// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Address } from "openzeppelin/contracts/utils/Address.sol";
import { Math } from "openzeppelin/contracts/utils/math/Math.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
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
import { ITokenizedStrategy } from "tokenized-strategy/interfaces/ITokenizedStrategy.sol";
import { ISuperVault, IERC1155Receiver } from "./ISuperVault.sol";

/// @title SuperVault
/// @notice A vault contract that manages multiple Superform positions
/// @dev Inherits from BaseStrategy and implements ISuperVault and IERC1155Receiver
/// @author Superform Labs
contract SuperVault is BaseStrategy, ISuperVault {
    using Math for uint256;
    using DataLib for uint256;
    using SafeERC20 for ERC20;
    using SafeERC20 for IERC20;

    //////////////////////////////////////////////////////////////
    //                     STATE VARIABLES                      //
    //////////////////////////////////////////////////////////////

    /// @notice The chain ID of the network this contract is deployed on
    uint64 public immutable CHAIN_ID;

    /// @notice The address of the SuperVault Strategist
    address public strategist;

    /// @notice The address of the SuperRegistry contract
    ISuperRegistry public immutable superRegistry;

    /// @notice The address of the SuperformFactory contract
    ISuperformFactory public immutable superformFactory;

    /// @notice The total weight used for calculating proportions (10000 = 100%)
    uint256 public constant TOTAL_WEIGHT = 10_000;

    /// @notice The maximum allowed slippage (1% = 100)
    uint256 public constant MAX_SLIPPAGE = 100;

    /// @notice The number of superforms in the vault
    uint256 numberOfSuperforms;

    /// @notice The deposit limit for the vault
    uint256 depositLimit;

    /// @notice Struct containing SuperVault strategy data
    SuperVaultStrategyData private SV;

    /// @notice Mapping to track whitelisted Superform IDs
    mapping(uint256 => bool) public whitelistedSuperformIds;

    /// @notice Array of whitelisted Superform IDs for easy access
    uint256[] public whitelistedSuperformIdArray;

    /// @notice Array of superform IDs in the vault
    uint256[] superformIds;

    /// @notice Array of weights for each superform in the vault
    uint256[] weights;

    //////////////////////////////////////////////////////////////
    //                       MODIFIERS                          //
    //////////////////////////////////////////////////////////////

    /// @notice Ensures that only the Super Vaults Strategist can call the function
    modifier onlySuperVaultsStrategist() {
        if (strategist != msg.sender) {
            revert NOT_SUPER_VAULTS_STRATEGIST();
        }
        _;
    }

    /// @notice Ensures that only the Vault Manager can call the function
    modifier onlyVaultManager() {
        if (SV.vaultManager != msg.sender) {
            revert NOT_VAULT_MANAGER();
        }
        _;
    }

    //////////////////////////////////////////////////////////////
    //                       CONSTRUCTOR                        //
    //////////////////////////////////////////////////////////////

    /// @param superRegistry_ Address of the SuperRegistry contract
    /// @param asset_ Address of the asset token
    /// @param name_ Name of the strategy
    /// @param depositLimit_ Maximum deposit limit
    /// @param superformIds_ Array of Superform IDs
    /// @param startingWeights_ Array of starting weights for each Superform
    constructor(
        address superRegistry_,
        address asset_,
        address strategist_,
        string memory name_,
        uint256 depositLimit_,
        uint256[] memory superformIds_,
        uint256[] memory startingWeights_
    )
        BaseStrategy(asset_, name_)
    {
        numberOfSuperforms = superformIds_.length;

        if (numberOfSuperforms == 0) {
            revert ZERO_SUPERFORMS();
        }

        if (numberOfSuperforms != startingWeights_.length) {
            revert ARRAY_LENGTH_MISMATCH();
        }

        if (superRegistry_ == address(0) || strategist_ == address(0) || vaultManager_ == address(0)) {
            revert ZERO_ADDRESS();
        }

        if (block.chainid > type(uint64).max) {
            revert BLOCK_CHAIN_ID_OUT_OF_BOUNDS();
        }

        CHAIN_ID = uint64(block.chainid);

        superRegistry = ISuperRegistry(superRegistry_);
        superformFactory = ISuperformFactory(superRegistry.getAddress(keccak256("SUPERFORM_FACTORY")));

        CHAIN_ID = uint64(block.chainid);

        if (CHAIN_ID > type(uint64).max) {
            revert BLOCK_CHAIN_ID_OUT_OF_BOUNDS();
        }

        uint256 totalWeight;
        address superform;

        for (uint256 i; i < numberOfSuperforms; ++i) {
            /// @dev this superVault only supports superforms that have the same asset as the vault
            (superform,,) = superformIds_[i].getSuperform();

            if (!superformFactory.isSuperform(superformIds_[i])) {
                revert SUPERFORM_DOES_NOT_EXIST(superformIds_[i]);
            }

            if (IBaseForm(superform).getVaultAsset() != asset_) {
                revert SUPERFORM_DOES_NOT_SUPPORT_ASSET();
            }

            /// @dev initial whitelist of superform IDs
            _addToWhitelist(superformIds_[i]);

            totalWeight += startingWeights_[i];
        }

        if (totalWeight != TOTAL_WEIGHT) revert INVALID_WEIGHTS();

        strategist = strategist_;
        for (uint256 i; i < numberOfSuperforms; ++i) {
            superformIds[i] = superformIds_[i];
            weights[i] = startingWeights_[i];
        }
        depositLimit = depositLimit_;
    }

    //////////////////////////////////////////////////////////////
    //                  EXTERNAL  FUNCTIONS                     //
    //////////////////////////////////////////////////////////////

    /// @inheritdoc ISuperVault
    function setDepositLimit(uint256 depositLimit_) external override onlyVaultManager {
        depositLimit = depositLimit_;

        emit DepositLimitSet(depositLimit_);
    }

    /// @notice Sets the strategist for the vault
    /// @param strategist_ The new strategist
    function setStrategist(address strategist_) external onlyManagement {
        strategist = strategist_;

        emit StrategistSet(strategist_);
    }

    /// @inheritdoc ISuperVault
    function rebalance(RebalanceArgs calldata rebalanceArgs) external payable override onlySuperVaultsStrategist {
        uint256 lenRebalanceFrom = rebalanceArgs.superformIdsRebalanceFrom.length;
        uint256 lenAmountsRebalanceFrom = rebalanceArgs.amountsRebalanceFrom.length;
        uint256 lenFinal = rebalanceArgs.finalSuperformIds.length;

        if (lenAmountsRebalanceFrom == 0) revert EMPTY_AMOUNTS_REBALANCE_FROM();
        if (lenFinal == 0) revert EMPTY_FINAL_SUPERFORM_IDS();

        /// @dev sanity check input arrays
        if (lenRebalanceFrom != lenAmountsRebalanceFrom || lenFinal != rebalanceArgs.weightsOfRedestribution.length) {
            revert ARRAY_LENGTH_MISMATCH();
        }

        {
            /// @dev caching to avoid multiple SLOADs
            uint256 foundCount;

            for (uint256 i; i < lenRebalanceFrom; ++i) {
                for (uint256 j; j < numberOfSuperforms; ++j) {
                    if (rebalanceArgs.superformIdsRebalanceFrom[i] == superformIds[j]) {
                        foundCount++;
                        break;
                    }
                }
            }

            if (foundCount != lenRebalanceFrom) {
                revert INVALID_SUPERFORM_ID_REBALANCE_FROM();
            }
        }
        for (uint256 i = 1; i < lenRebalanceFrom; ++i) {
            if (rebalanceArgs.superformIdsRebalanceFrom[i] <= rebalanceArgs.superformIdsRebalanceFrom[i - 1]) {
                revert DUPLICATE_SUPERFORM_IDS_REBALANCE_FROM();
            }
        }

        for (uint256 i; i < lenFinal; ++i) {
            if (i >= 1 && rebalanceArgs.finalSuperformIds[i] <= rebalanceArgs.finalSuperformIds[i - 1]) {
                revert DUPLICATE_FINAL_SUPERFORM_IDS();
            }
            if (!whitelistedSuperformIds[rebalanceArgs.finalSuperformIds[i]]) {
                revert SUPERFORM_NOT_WHITELISTED();
            }
        }

        /// @dev step 1: prepare rebalance arguments
        ISuperformRouterPlus.RebalanceMultiPositionsSyncArgs memory args = _prepareRebalanceArgs(
            rebalanceArgs.superformIdsRebalanceFrom,
            rebalanceArgs.amountsRebalanceFrom,
            rebalanceArgs.finalSuperformIds,
            rebalanceArgs.weightsOfRedestribution,
            rebalanceArgs.slippage
        );

        address routerPlus = _getAddress(keccak256("SUPERFORM_ROUTER_PLUS"));
        address superPositions = _getAddress(keccak256("SUPER_POSITIONS"));

        /// @dev step 2: execute rebalance
        ISuperPositions(superPositions).setApprovalForMany(routerPlus, args.ids, args.sharesToRedeem);

        ISuperformRouterPlus(routerPlus).rebalanceMultiPositions(args);

        /// @dev step 3: update data
        /// @notice no issue about reentrancy as the external contracts are trusted
        /// @notice updateSVData emits rebalance event
        _updateSVData(superPositions, rebalanceArgs.finalSuperformIds);
    }

    /// @inheritdoc ISuperVault
    function forwardDustToPaymaster() external override {
        address paymaster = superRegistry.getAddress(keccak256("PAYMASTER"));
        IERC20 token = IERC20(asset);

        uint256 dust = token.balanceOf(address(this));
        if (dust != 0) {
            token.safeTransfer(paymaster, dust);
            emit DustForwardedToPaymaster(dust);
        }
    }

    /// @inheritdoc ISuperVault
    function setWhitelist(
        uint256[] memory superformIds,
        bool[] memory isWhitelisted
    )
        external
        override
        onlyVaultManager
    {
        uint256 length = superformIds.length;
        if (length != isWhitelisted.length) revert ARRAY_LENGTH_MISMATCH();
        if (length == 0) revert ZERO_SUPERFORMS();
        for (uint256 i; i < length; ++i) {
            _changeSuperformWhitelist(superformIds[i], isWhitelisted[i]);
        }
    }

    /// @inheritdoc ISuperVault
    function setVaultManager(address vaultManager_) external override onlyManagement {
        if (vaultManager_ == address(0)) revert ZERO_ADDRESS();
        SV.vaultManager = vaultManager_;

        emit VaultManagerSet(vaultManager_);
    }

    //////////////////////////////////////////////////////////////
    //                 EXTERNAL VIEW/PURE FUNCTIONS             //
    //////////////////////////////////////////////////////////////

    /// @inheritdoc ISuperVault
    function getSuperVaultData()
        external
        view
        returns (uint256 numberOfSuperforms, uint256[] memory superformIds, uint256[] memory weights)
    {
        return (SV.numberOfSuperforms, SV.superformIds, SV.weights);
    }

    /// @inheritdoc ISuperVault
    function getIsWhitelisted(uint256[] memory superformIds) external view returns (bool[] memory isWhitelisted) {
        uint256 length = superformIds.length;
        isWhitelisted = new bool[](length);

        for (uint256 i; i < length; ++i) {
            isWhitelisted[i] = whitelistedSuperformIds[superformIds[i]];
        }

        return isWhitelisted;
    }

    /// @inheritdoc ISuperVault
    function getWhitelist() external view override returns (uint256[] memory) {
        return whitelistedSuperformIdArray;
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
    }

    /// @notice Reports the total assets of the vault
    /// @return totalAssets The total assets of the vault
    function _harvestAndReport() internal view override returns (uint256 totalAssets) {
        uint256 totalAssetsInVaults;
        uint256 numberOfSuperforms = SV.numberOfSuperforms;
        uint256[] memory superformIds = SV.superformIds;

        address superPositions = _getAddress(keccak256("SUPER_POSITIONS"));

        for (uint256 i; i < numberOfSuperforms; ++i) {
            (address superform,,) = superformIds[i].getSuperform();

            /// @dev This contract holds superPositions, not shares
            uint256 spBalance = ISuperPositions(superPositions).balanceOf(address(this), superformIds[i]);
            totalAssetsInVaults += IBaseForm(superform).previewRedeemFrom(spBalance);
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
        mvData.receiverAddress = address(this);
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
                /// @dev assets
                mvData.outputAmounts[i] = amount_.mulDiv(SV.weights[i], TOTAL_WEIGHT, Math.Rounding.Down);
                /// @dev shares - in 4626Form this uses convertToShares in 5115Form this uses previewDeposit
                mvData.amounts[i] = superformContract.previewDepositTo(mvData.outputAmounts[i]);
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
    /// @param slippage Maximum allowed slippage
    function _prepareRebalanceArgs(
        uint256[] calldata superformIdsRebalanceFrom,
        uint256[] calldata amountsRebalanceFrom,
        uint256[] calldata finalSuperformIds,
        uint256[] calldata weightsOfRedestribution,
        uint256 slippage
    )
        internal
        view
        returns (ISuperformRouterPlus.RebalanceMultiPositionsSyncArgs memory args)
    {
        args.ids = superformIdsRebalanceFrom;
        args.sharesToRedeem = amountsRebalanceFrom;
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
        for (uint256 i; i < weights.length; ++i) {
            amounts[i] = totalOutputAmount.mulDiv(weights[i], TOTAL_WEIGHT, Math.Rounding.Down);
        }
    }

    /// @notice Filters out zero weights and returns corresponding superform IDs and weights
    /// @param superformIds Array of Superform IDs
    /// @param weights Array of weights
    /// @return filteredIds Array of filtered Superform IDs
    /// @return filteredWeights Array of filtered weights
    function _filterNonZeroWeights(
        uint256[] calldata superformIds,
        uint256[] calldata weights
    )
        internal
        pure
        returns (uint256[] memory filteredIds, uint256[] memory filteredWeights)
    {
        uint256 count;
        uint256 length = weights.length;
        for (uint256 i; i < length; ++i) {
            if (weights[i] != 0) {
                count++;
            }
        }

        filteredIds = new uint256[](count);
        filteredWeights = new uint256[](count);

        uint256 j;
        uint256 totalWeight;
        for (uint256 i; i < length; ++i) {
            if (weights[i] != 0) {
                filteredIds[j] = superformIds[i];
                filteredWeights[j] = weights[i];
                totalWeight += weights[i];
                j++;
            }
        }
        if (totalWeight != TOTAL_WEIGHT) revert INVALID_WEIGHTS();
    }

    /// @notice Updates the SuperVault data after rebalancing
    /// @param superPositions Address of the SuperPositions contract
    /// @param finalSuperformIds Array of Superform IDs to rebalance to
    function _updatSVData(address superPositions, uint256[] memory finalSuperformIds) internal {
        uint256 totalWeight;

        uint256 length = finalSuperformIds.length;
        if (length == 0) revert ZERO_SUPERFORMS();

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
            value = IBaseForm(superform).previewRedeemFrom(balance);

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
        weights = newWeights;
        superformIds = finalSuperformIds;
        numberOfSuperforms = length;

        emit RebalanceComplete(finalSuperformIds, newWeights);
    }

    /// @notice Changes the whitelist for a Superform ID
    /// @param superformId The Superform ID to change
    /// @param isWhitelisted Whether to whitelist or blacklist
    function _changeSuperformWhitelist(uint256 superformId, bool isWhitelisted) internal {
        bool currentlyWhitelisted = whitelistedSuperformIds[superformId];

        // Only process if there's an actual change
        if (currentlyWhitelisted != isWhitelisted) {
            whitelistedSuperformIds[superformId] = isWhitelisted;

            if (isWhitelisted) {
                _addToWhitelist(superformId);
            } else {
                _removeFromWhitelist(superformId);
            }

            emit SuperformWhitelisted(superformId, isWhitelisted);
        }
    }

    /// @notice Adds a superform ID to the whitelist array
    /// @param superformId The Superform ID to add
    function _addToWhitelist(uint256 superformId) internal {
        whitelistedSuperformIds[superformId] = true;
        whitelistedSuperformIdArray.push(superformId);
    }

    /// @notice Removes a superform ID from the whitelist array
    /// @param superformId The Superform ID to remove
    function _removeFromWhitelist(uint256 superformId) internal {
        whitelistedSuperformIds[superformId] = false;

        uint256 length = whitelistedSuperformIdArray.length;
        // Find and remove the superformId from the array
        for (uint256 i; i < length; ++i) {
            if (whitelistedSuperformIdArray[i] == superformId) {
                // Move the last element to the position being deleted
                whitelistedSuperformIdArray[i] = whitelistedSuperformIdArray[length - 1];
                // Remove the last element
                whitelistedSuperformIdArray.pop();
                break;
            }
        }
    }
}
