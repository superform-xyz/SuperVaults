// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Math } from "openzeppelin/contracts/utils/math/Math.sol";
import { Address } from "openzeppelin/contracts/utils/Address.sol";
import { EnumerableSet } from "openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IERC165 } from "openzeppelin/contracts/utils/introspection/IERC165.sol";
import {
    SingleDirectSingleVaultStateReq,
    SingleDirectMultiVaultStateReq,
    MultiVaultSFData,
    SingleVaultSFData,
    LiqRequest
} from "superform-core/src/types/DataTypes.sol";
import { ISuperPositions } from "superform-core/src/interfaces/ISuperPositions.sol";
import { DataLib } from "superform-core/src/libraries/DataLib.sol";
import { IBaseForm } from "superform-core/src/interfaces/IBaseForm.sol";
import { IBaseRouter } from "superform-core/src/interfaces/IBaseRouter.sol";
import { ISuperformRouterPlus } from "superform-core/src/interfaces/ISuperformRouterPlus.sol";
import { ISuperRegistry } from "superform-core/src/interfaces/ISuperRegistry.sol";
import { ISuperVault, IERC1155Receiver } from "./interfaces/ISuperVault.sol";
import { ISuperformFactory } from "superform-core/src/interfaces/ISuperformFactory.sol";
import { TransientContext } from "transience/TransientContext.sol";
import { BaseStrategy } from "tokenized-strategy/BaseStrategy.sol";
import { ISuperformFactoryMinimal } from "./interfaces/ISuperformFactoryMinimal.sol";

/// @title SuperVault
/// @notice A vault contract that manages multiple Superform positions
/// @dev Inherits from BaseStrategy and implements ISuperVault and IERC1155Receiver
/// @author Superform Labs
contract SuperVault is BaseStrategy, ISuperVault {
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;
    using SafeERC20 for ERC20;
    using DataLib for uint256;
    using Math for uint256;

    //////////////////////////////////////////////////////////////
    //                     STATE VARIABLES                      //
    //////////////////////////////////////////////////////////////

    /// @notice The chain ID of the network this contract is deployed on
    uint64 public immutable CHAIN_ID;

    /// @notice The address of the SuperVault Strategist
    address public strategist;

    /// @notice The address of the SuperVault Vault Manager
    address public vaultManager;

    /// @notice The address of the SuperRegistry contract
    ISuperRegistry public immutable superRegistry;

    /// @notice The address of the SuperformFactory contract
    ISuperformFactory public immutable superformFactory;

    /// @notice The ID of the ERC5115 form implementation
    uint32 public ERC5115FormImplementationId;

    /// @notice The total weight used for calculating proportions (10000 = 100%)
    uint256 private constant TOTAL_WEIGHT = 10_000;

    /// @notice The maximum allowed slippage (1% = 100)
    uint256 private constant MAX_SLIPPAGE = 100;

    /// @dev Tolerance constant to account for minAmountOut check in 5115
    uint256 private constant TOLERANCE_CONSTANT = 10 wei;

    /// @notice The number of Superforms in the vault
    uint256 public numberOfSuperforms;

    /// @notice The deposit limit for the vault
    uint256 public depositLimit;

    /// @notice Set of whitelisted Superform IDs for easy access
    EnumerableSet.UintSet whitelistedSuperformIdsSet;

    /// @notice Array of Superform IDs in the vault
    uint256[] public superformIds;

    /// @notice Array of weights for each Superform in the vault
    uint256[] public weights;

    address private immutable _SUPER_POSITIONS;
    address private immutable _SUPERFORM_ROUTER;
    address private immutable _SUPERFORM_FACTORY;

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
        if (vaultManager != msg.sender) {
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
        address vaultManager_,
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

        superRegistry = ISuperRegistry(superRegistry_);
        superformFactory = ISuperformFactory(superRegistry.getAddress(keccak256("SUPERFORM_FACTORY")));

        if (CHAIN_ID > type(uint64).max) {
            revert BLOCK_CHAIN_ID_OUT_OF_BOUNDS();
        }

        CHAIN_ID = uint64(block.chainid);

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
        vaultManager = vaultManager_;
        superformIds = superformIds_;
        weights = startingWeights_;
        depositLimit = depositLimit_;

        {
            _SUPER_POSITIONS = _getAddress(keccak256("SUPER_POSITIONS"));
            _SUPERFORM_ROUTER = _getAddress(keccak256("SUPERFORM_ROUTER"));
            _SUPERFORM_FACTORY = _getAddress(keccak256("SUPERFORM_FACTORY"));
        }
    }

    //////////////////////////////////////////////////////////////
    //                  EXTERNAL  FUNCTIONS                     //
    //////////////////////////////////////////////////////////////

    /// @inheritdoc ISuperVault
    function setDepositLimit(uint256 depositLimit_) external override onlyVaultManager {
        depositLimit = depositLimit_;

        emit DepositLimitSet(depositLimit_);
    }

    /// @inheritdoc ISuperVault
    function setStrategist(address strategist_) external override onlyManagement {
        strategist = strategist_;

        emit StrategistSet(strategist_);
    }

    /// @inheritdoc ISuperVault
    function setValid5115FormImplementationId(uint32 formImplementationId_) external override onlyManagement {
        if (formImplementationId_ == 0) revert ZERO_ID();

        ERC5115FormImplementationId = formImplementationId_;
    }

    /// @inheritdoc ISuperVault
    function rebalance(RebalanceArgs calldata rebalanceArgs_) external payable override onlySuperVaultsStrategist {
        TransientContext.set(bytes32(0), rebalanceArgs_.superformIdsRebalanceFrom.length); // lenRebalanceFrom
        TransientContext.set("0x1", rebalanceArgs_.amountsRebalanceFrom.length); // lenAmountsRebalanceFrom
        TransientContext.set("0x2", rebalanceArgs_.finalSuperformIds.length); // lenFinal

        if (TransientContext.get("0x1") == 0) revert EMPTY_AMOUNTS_REBALANCE_FROM();

        if (TransientContext.get("0x2") == 0) revert EMPTY_FINAL_SUPERFORM_IDS();

        /// @dev sanity check input arrays
        if (TransientContext.get(bytes32(uint256(0))) != TransientContext.get("0x1") || TransientContext.get("0x2") != rebalanceArgs_.weightsOfRedestribution.length) {
            revert ARRAY_LENGTH_MISMATCH();
        }

        {
            /// @dev caching to avoid multiple loads
            TransientContext.set("0x3", 0); //foundCount

            for (uint256 i; i < TransientContext.get(bytes32(0)); ++i) {
                for (uint256 j; j < numberOfSuperforms; ++j) {
                    if (rebalanceArgs_.superformIdsRebalanceFrom[i] == superformIds[j]) {
                        TransientContext.set("0x3", TransientContext.get("0x3") + 1); // increment foundCount
                        break;
                    }
                }
            }

            if (TransientContext.get("0x3") != TransientContext.get(bytes32(0))) {
                revert INVALID_SUPERFORM_ID_REBALANCE_FROM();
            }
        }
        for (uint256 i = 1; i < TransientContext.get(bytes32(0)); ++i) {
            if (rebalanceArgs_.superformIdsRebalanceFrom[i] <= rebalanceArgs_.superformIdsRebalanceFrom[i - 1]) {
                revert DUPLICATE_SUPERFORM_IDS_REBALANCE_FROM();
            }
        }

        for (uint256 i; i < TransientContext.get("0x2"); ++i) {
            if (i >= 1 && rebalanceArgs_.finalSuperformIds[i] <= rebalanceArgs_.finalSuperformIds[i - 1]) {
                revert DUPLICATE_FINAL_SUPERFORM_IDS();
            }
            if (!whitelistedSuperformIdsSet.contains(rebalanceArgs_.finalSuperformIds[i])) {
                revert SUPERFORM_NOT_WHITELISTED();
            }
        }

        /// @dev step 1: prepare rebalance arguments
        ISuperformRouterPlus.RebalanceMultiPositionsSyncArgs memory args = _prepareRebalanceArgs(
            rebalanceArgs_.superformIdsRebalanceFrom,
            rebalanceArgs_.amountsRebalanceFrom,
            rebalanceArgs_.finalSuperformIds,
            rebalanceArgs_.weightsOfRedestribution,
            rebalanceArgs_.slippage
        );

        address routerPlus = _getAddress(keccak256("SUPERFORM_ROUTER_PLUS"));

        /// @dev step 2: execute rebalance
        _setSuperPositionsApproval(routerPlus, args.ids, args.sharesToRedeem);

        ISuperformRouterPlus(routerPlus).rebalanceMultiPositions(args);

        /// @dev step 3: update SV data
        /// @notice no issue about reentrancy as the external contracts are trusted
        /// @notice updateSV emits rebalance event
        _updateSVData(_SUPER_POSITIONS, rebalanceArgs_.finalSuperformIds);
    }

    /// @inheritdoc ISuperVault
    function forwardDustToPaymaster() external override {
        address paymaster = superRegistry.getAddress(keccak256("PAYMASTER"));
        IERC20 token = IERC20(asset);

        uint256 dust = _getAssetBalance(token);

        if (dust != 0) {
            token.safeTransfer(paymaster, dust);
            emit DustForwardedToPaymaster(dust);
        }
    }

    /// @inheritdoc ISuperVault
    function setWhitelist(
        uint256[] memory superformIds_,
        bool[] memory isWhitelisted_
    )
        external
        override
        onlyVaultManager
    {
        uint256 length = superformIds_.length;
        if (length != isWhitelisted_.length) revert ARRAY_LENGTH_MISMATCH();
        if (length == 0) revert ZERO_SUPERFORMS();
        for (uint256 i; i < length; ++i) {
            _changeSuperformWhitelist(superformIds_[i], isWhitelisted_[i]);
        }
    }

    /// @inheritdoc ISuperVault
    function setVaultManager(address vaultManager_) external override onlyManagement {
        if (vaultManager_ == address(0)) revert ZERO_ADDRESS();
        vaultManager = vaultManager_;

        emit VaultManagerSet(vaultManager_);
    }

    //////////////////////////////////////////////////////////////
    //                 EXTERNAL VIEW/PURE FUNCTIONS             //
    //////////////////////////////////////////////////////////////

    /// @inheritdoc ISuperVault
    function getIsWhitelisted(uint256[] memory superformIds_) external view returns (bool[] memory isWhitelisted) {
        uint256 length = superformIds_.length;
        isWhitelisted = new bool[](length);

        for (uint256 i; i < length; ++i) {
            isWhitelisted[i] = whitelistedSuperformIdsSet.contains(superformIds_[i]);
        }

        return isWhitelisted;
    }

    /// @inheritdoc ISuperVault
    function getWhitelist() external view override returns (uint256[] memory) {
        return whitelistedSuperformIdsSet.values();
    }

    /// @inheritdoc ISuperVault
    function getSuperVaultData() external view returns (uint256[] memory superformIds_, uint256[] memory weights_) {
        return (superformIds, weights);
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
        uint256 _depositLimit_ = depositLimit;
        return totalAssets >= _depositLimit_ ? 0 : _depositLimit_ - totalAssets;
    }

    //////////////////////////////////////////////////////////////
    //            BASESTRATEGY INTERNAL OVERRIDES               //
    //////////////////////////////////////////////////////////////

    /// @notice Deploys funds to the underlying Superforms
    /// @param amount_ The amount of funds to deploy
    function _deployFunds(uint256 amount_) internal override {
        TransientContext.set("0x0", amount_);

        bytes memory callData = numberOfSuperforms == 1
            ? abi.encodeWithSelector(
                IBaseRouter.singleDirectSingleVaultDeposit.selector,
                SingleDirectSingleVaultStateReq(_prepareSingleVaultDepositData(TransientContext.get("0x0")))
            )
            : abi.encodeWithSelector(
                IBaseRouter.singleDirectMultiVaultDeposit.selector,
                SingleDirectMultiVaultStateReq(_prepareMultiVaultDepositData(TransientContext.get("0x0")))
            );

        //address router = _SUPERFORM_ROUTER;
        TransientContext.set("0x1", uint256(uint160(_SUPERFORM_ROUTER)))); // router address
        
        asset.safeIncreaseAllowance(address(uint160(TransientContext.get("0x1"))), TransientContext.get("0x0"));

        /// @dev this call has to be enforced with 0 msg.value not to break the 4626 standard
        (bool success, bytes memory returndata) = address(uint160(TransientContext.get("0x1"))).call(callData);

        Address.verifyCallResult(success, returndata, "CallRevertWithNoReturnData");

        if (asset.allowance(address(this), address(uint160(TransientContext.get("0x1")))) > 0) asset.forceApprove(address(uint160(TransientContext.get("0x1"))), 0);
    }

    /// @notice Frees funds from the underlying Superforms
    /// @param amount_ The amount of funds to free
    function _freeFunds(uint256 amount_) internal override {
        TransientContext.set("0x0", amount_);
        bytes memory callData;
        TransientContext.set("0x1", uint256(uint160(_SUPERFORM_ROUTER))));

        if (numberOfSuperforms == 1) {
            SingleVaultSFData memory svData = _prepareSingleVaultWithdrawData(TransientContext.get("0x0"));
            callData = abi.encodeWithSelector(
                IBaseRouter.singleDirectSingleVaultWithdraw.selector, SingleDirectSingleVaultStateReq(svData)
            );
            _setSuperPositionApproval(address(uint160(TransientContext.get("0x1"))), svData.superformId, svData.amount);
        } else {
            MultiVaultSFData memory mvData = _prepareMultiVaultWithdrawData(TransientContext.get("0x0"));
            callData = abi.encodeWithSelector(
                IBaseRouter.singleDirectMultiVaultWithdraw.selector, SingleDirectMultiVaultStateReq(mvData)
            );
            _setSuperPositionsApproval(address(uint160(TransientContext.get("0x1"))), mvData.superformIds, mvData.amounts);
        }

        /// @dev this call has to be enforced with 0 msg.value not to break the 4626 standard
        (bool success, bytes memory returndata) = address(uint160(TransientContext.get("0x1"))).call(callData);

        Address.verifyCallResult(success, returndata, "CallRevertWithNoReturnData");
    }

    /// @notice Reports the total assets of the vault
    /// @return totalAssets The total assets of the vault
    function _harvestAndReport() internal view override returns (uint256 totalAssets) {
        uint256 totalAssetsInVaults;
        uint256 _numberOfSuperforms_ = numberOfSuperforms;
        uint256[] memory _superformIds_ = superformIds;
        address superPositions = _SUPER_POSITIONS;

        for (uint256 i; i < _numberOfSuperforms_;) {
            (address superform,,) = _superformIds_[i].getSuperform();

            /// @dev This contract holds superPositions, not shares
            uint256 spBalance = ISuperPositions(superPositions).balanceOf(address(this), _superformIds_[i]);
            totalAssetsInVaults += IBaseForm(superform).previewRedeemFrom(spBalance);

            unchecked {
                ++i;
            }
        }

        totalAssets = totalAssetsInVaults + _getAssetBalance(asset);
    }

    //////////////////////////////////////////////////////////////
    //                     INTERNAL FUNCTIONS                   //
    //////////////////////////////////////////////////////////////

    function _prepareMultiVaultDepositData(uint256 amount_) internal view returns (MultiVaultSFData memory mvData) {
        uint256 _numberOfSuperforms_ = numberOfSuperforms;

        mvData.superformIds = superformIds;
        mvData.amounts = new uint256[](_numberOfSuperforms_);
        mvData.maxSlippages = new uint256[](_numberOfSuperforms_);
        mvData.liqRequests = new LiqRequest[](_numberOfSuperforms_);
        mvData.hasDstSwaps = new bool[](_numberOfSuperforms_);
        mvData.retain4626s = mvData.hasDstSwaps;
        mvData.receiverAddress = address(this);
        mvData.receiverAddressSP = address(this);
        mvData.outputAmounts = new uint256[](_numberOfSuperforms_);

        bytes[] memory dataToEncode = new bytes[](_numberOfSuperforms_);

        uint256[] memory _weights_ = weights;
        for (uint256 i; i < _numberOfSuperforms_;) {
            mvData.liqRequests[i].token = address(asset);

            (address superform,,) = mvData.superformIds[i].getSuperform();

            dataToEncode[i] = _prepareDepositExtraFormDataForSuperform(mvData.superformIds[i]);

            /// @notice rounding down to avoid one-off issue
            mvData.amounts[i] = amount_.mulDiv(_weights_[i], TOTAL_WEIGHT, Math.Rounding.Down);
            mvData.outputAmounts[i] = IBaseForm(superform).previewDepositTo(mvData.amounts[i]);
            mvData.maxSlippages[i] = MAX_SLIPPAGE;

            unchecked {
                ++i;
            }
        }

        mvData.extraFormData = abi.encode(_numberOfSuperforms_, dataToEncode);
        return mvData;
    }

    function _prepareSingleVaultDepositData(uint256 amount_) internal view returns (SingleVaultSFData memory svData) {
        svData.superformId = superformIds[0];
        svData.amount = amount_;
        svData.maxSlippage = MAX_SLIPPAGE;
        svData.liqRequest.token = address(asset);
        svData.hasDstSwap = false;
        svData.retain4626 = false;
        svData.receiverAddress = address(this);
        svData.receiverAddressSP = address(this);

        (address superform,,) = svData.superformId.getSuperform();
        svData.outputAmount = IBaseForm(superform).previewDepositTo(amount_);
        bytes memory dataToEncode = _prepareDepositExtraFormDataForSuperform(svData.superformId);
        bytes[] memory finalDataToEncode = new bytes[](1);
        finalDataToEncode[0] = dataToEncode;
        svData.extraFormData = abi.encode(1, finalDataToEncode);

        return svData;
    }

    function _prepareMultiVaultWithdrawData(uint256 amount_) internal view returns (MultiVaultSFData memory mvData) {
        uint256 _numberOfSuperforms_ = numberOfSuperforms;

        mvData.superformIds = superformIds;
        mvData.amounts = new uint256[](_numberOfSuperforms_);
        mvData.maxSlippages = new uint256[](_numberOfSuperforms_);
        mvData.liqRequests = new LiqRequest[](_numberOfSuperforms_);
        mvData.hasDstSwaps = new bool[](_numberOfSuperforms_);
        mvData.retain4626s = mvData.hasDstSwaps;
        mvData.receiverAddress = address(this);
        mvData.receiverAddressSP = address(this);
        mvData.outputAmounts = new uint256[](_numberOfSuperforms_);

        address superPositions = _SUPER_POSITIONS;
        uint256 totalAssetsInVaults;
        uint256[] memory spBalances = new uint256[](_numberOfSuperforms_);
        uint256[] memory assetBalances = new uint256[](_numberOfSuperforms_);

        // Snapshot assets and SP balances
        for (uint256 i; i < _numberOfSuperforms_;) {
            (address superform,,) = mvData.superformIds[i].getSuperform();

            spBalances[i] = _getSuperPositionBalance(superPositions, mvData.superformIds[i]);
            assetBalances[i] = IBaseForm(superform).previewRedeemFrom(spBalances[i]);
            totalAssetsInVaults += assetBalances[i];

            unchecked {
                ++i;
            }
        }

        // Calculate withdrawal amounts
        for (uint256 i; i < _numberOfSuperforms_;) {
            mvData.liqRequests[i].token = address(asset);

            (address superform,,) = mvData.superformIds[i].getSuperform();

            bool isERC5115 = _isERC5115Vault(mvData.superformIds[i]);

            if (isERC5115) {
                mvData.liqRequests[i].interimToken = address(asset);
            }

            if (amount_ >= totalAssetsInVaults) {
                mvData.amounts[i] = spBalances[i];
                mvData.outputAmounts[i] = _tolerance(isERC5115, assetBalances[i]);
            } else {
                uint256 amountOut = amount_.mulDiv(weights[i], TOTAL_WEIGHT, Math.Rounding.Down);
                mvData.outputAmounts[i] = _tolerance(isERC5115, amountOut);
                mvData.amounts[i] = IBaseForm(superform).previewDepositTo(amountOut);

                if (mvData.amounts[i] > spBalances[i]) {
                    mvData.amounts[i] = spBalances[i];
                }
            }

            mvData.maxSlippages[i] = MAX_SLIPPAGE;

            unchecked {
                ++i;
            }
        }

        return mvData;
    }

    function _prepareSingleVaultWithdrawData(uint256 amount_) internal view returns (SingleVaultSFData memory svData) {
        svData.superformId = superformIds[0];
        (address superform,,) = svData.superformId.getSuperform();

        // Get current balances
        uint256 spBalance = _getSuperPositionBalance(_SUPER_POSITIONS, svData.superformId);
        uint256 assetBalance = IBaseForm(superform).previewRedeemFrom(spBalance);

        // Set up basic data
        svData.liqRequest.token = address(asset);
        bool isERC5115 = _isERC5115Vault(svData.superformId);

        if (isERC5115) {
            svData.liqRequest.interimToken = address(asset);
        }

        // Calculate withdrawal amounts
        if (amount_ >= assetBalance) {
            svData.amount = spBalance;
            svData.outputAmount = _tolerance(isERC5115, assetBalance);
        } else {
            svData.outputAmount = _tolerance(isERC5115, amount_);
            svData.amount = IBaseForm(superform).previewDepositTo(amount_);

            if (svData.amount > spBalance) {
                svData.amount = spBalance;
            }
        }

        svData.maxSlippage = MAX_SLIPPAGE;
        svData.hasDstSwap = false;
        svData.retain4626 = false;
        svData.receiverAddress = address(this);
        svData.receiverAddressSP = address(this);

        return svData;
    }

    /// @notice Checks if a vault is ERC5115 and validates form implementation IDs
    /// @param superformId_ The superform ID to check
    /// @return isERC5115 True if the vault is ERC5115
    function _isERC5115Vault(uint256 superformId_) internal view returns (bool isERC5115) {
        ISuperformFactoryMinimal factory = ISuperformFactoryMinimal(_SUPERFORM_FACTORY);

        address erc5115Implementation = factory.getFormImplementation(ERC5115FormImplementationId);

        (address superform,,) = superformId_.getSuperform();

        uint256 superFormId = factory.vaultFormImplCombinationToSuperforms(
            keccak256(abi.encode(erc5115Implementation, IBaseForm(superform).getVaultAddress()))
        );

        if (superFormId == superformId_) {
            isERC5115 = true;
        }
    }

    /// @dev returns the address for id_ from super registry
    function _getAddress(bytes32 id_) internal view returns (address) {
        return superRegistry.getAddress(id_);
    }

    /// @notice Sets approval for multiple SuperPositions
    /// @param router_ The router address to approve
    /// @param superformIds_ The superform IDs to approve
    /// @param amounts_ The amounts to approve
    function _setSuperPositionsApproval(
        address router_,
        uint256[] memory superformIds_,
        uint256[] memory amounts_
    )
        internal
    {
        ISuperPositions(_SUPER_POSITIONS).setApprovalForMany(router_, superformIds_, amounts_);
    }

    /// @notice Sets approval for a single SuperPosition
    /// @param router_ The router address to approve
    /// @param superformId_ The superform ID to approve
    /// @param amount_ The amount to approve
    function _setSuperPositionApproval(address router_, uint256 superformId_, uint256 amount_) internal {
        ISuperPositions(_SUPER_POSITIONS).setApprovalForOne(router_, superformId_, amount_);
    }

    /// @notice Gets the current balance of the asset token held by this contract
    /// @return balance The current balance of the asset token
    function _getAssetBalance(IERC20 token_) internal view returns (uint256) {
        return token_.balanceOf(address(this));
    }

    function _getSuperPositionBalance(address superPositions, uint256 superformId) internal view returns (uint256) {
        return ISuperPositions(superPositions).balanceOf(address(this), superformId);
    }

    /// @notice Prepares rebalance arguments for Superform Router Plus
    /// @param superformIdsRebalanceFrom_ Array of Superform IDs to rebalance from
    /// @param amountsRebalanceFrom_ Array of amounts to rebalance from
    /// @param finalSuperformIds_ Array of Superform IDs to rebalance to
    /// @param weightsOfRedestribution_ Array of weights for redestribution
    /// @param slippage_ Maximum allowed slippage
    function _prepareRebalanceArgs(
        uint256[] calldata superformIdsRebalanceFrom_,
        uint256[] calldata amountsRebalanceFrom_,
        uint256[] calldata finalSuperformIds_,
        uint256[] calldata weightsOfRedestribution_,
        uint256 slippage_
    )
        internal
        view
        returns (ISuperformRouterPlus.RebalanceMultiPositionsSyncArgs memory args)
    {
        args.ids = superformIdsRebalanceFrom_;
        args.sharesToRedeem = amountsRebalanceFrom_;
        args.interimAsset = address(asset); // Assuming 'asset' is the interim token
        args.slippage = slippage_; // 1% slippage, adjust as needed
        args.receiverAddressSP = address(this);

        (SingleDirectMultiVaultStateReq memory req, uint256 totalOutputAmount) =
            _prepareSingleDirectMultiVaultStateReq(superformIdsRebalanceFrom_, amountsRebalanceFrom_, slippage_, true);

        /// @dev prepare callData for rebalance from
        args.callData = abi.encodeWithSelector(IBaseRouter.singleDirectMultiVaultWithdraw.selector, req);

        /// @dev create a filtered version of superformIdsRebalanceTo
        (uint256[] memory filteredSuperformIds, uint256[] memory filteredWeights) =
            _filterNonZeroWeights(finalSuperformIds_, weightsOfRedestribution_);

        (req,) = _prepareSingleDirectMultiVaultStateReq(
            filteredSuperformIds, _calculateAmounts(totalOutputAmount, filteredWeights), slippage_, false
        );

        /// @dev prepare rebalanceToCallData
        args.rebalanceToCallData = abi.encodeWithSelector(IBaseRouter.singleDirectMultiVaultDeposit.selector, req);
        args.expectedAmountToReceivePostRebalanceFrom = totalOutputAmount;
    }

    /// @notice Prepares single direct multi-vault state request
    /// @param superformIds_ Array of Superform IDs
    /// @param amounts_ Array of amounts
    /// @param slippage_ Maximum allowed slippage
    /// @param isWithdraw_ True if withdrawing, false if depositing
    /// @return req The prepared single direct multi-vault state request
    /// @return totalOutputAmount The total output amount
    function _prepareSingleDirectMultiVaultStateReq(
        uint256[] memory superformIds_,
        uint256[] memory amounts_,
        uint256 slippage_,
        bool isWithdraw_
    )
        internal
        view
        returns (SingleDirectMultiVaultStateReq memory req, uint256 totalOutputAmount)
    {
        MultiVaultSFData memory data;
        data.superformIds = superformIds_;
        data.amounts = amounts_;

        address routerPlus = _getAddress(keccak256("SUPERFORM_ROUTER_PLUS"));

        uint256 _numberOfSuperforms_ = superformIds_.length;
        data.outputAmounts = new uint256[](_numberOfSuperforms_);
        data.maxSlippages = new uint256[](_numberOfSuperforms_);
        data.liqRequests = new LiqRequest[](_numberOfSuperforms_);
        bytes[] memory dataToEncode = new bytes[](_numberOfSuperforms_);

        for (uint256 i; i < _numberOfSuperforms_;) {
            (address superform,,) = superformIds_[i].getSuperform();

            if (isWithdraw_) {
                // Check if vault is ERC5115
                bool isERC5115 = _isERC5115Vault(superformIds_[i]);

                if (isERC5115) {
                    data.liqRequests[i].interimToken = address(asset);
                }

                uint256 amountOut = IBaseForm(superform).previewRedeemFrom(amounts_[i]);
                data.outputAmounts[i] = _tolerance(isERC5115, amountOut);
            } else {
                dataToEncode[i] = _prepareDepositExtraFormDataForSuperform(superformIds_[i]);

                data.outputAmounts[i] = IBaseForm(superform).previewDepositTo(amounts_[i]);
            }

            totalOutputAmount += data.outputAmounts[i];

            data.maxSlippages[i] = slippage_;
            data.liqRequests[i].token = address(asset);
            data.liqRequests[i].liqDstChainId = CHAIN_ID;

            unchecked {
                ++i;
            }
        }

        data.hasDstSwaps = new bool[](_numberOfSuperforms_);
        data.retain4626s = data.hasDstSwaps;
        /// @dev routerPlus receives assets to continue the rebalance
        data.receiverAddress = routerPlus;
        /// @dev in case of withdraw failure, this vault receives the superPositions back
        data.receiverAddressSP = address(this);

        if (!isWithdraw_) {
            data.extraFormData = abi.encode(_numberOfSuperforms_, dataToEncode);
        }
        req.superformData = data;
    }

    /// @notice Prepares deposit extra form data for a single superform
    /// @param superformId_ The superform ID
    /// @return bytes Encoded data for the superform
    function _prepareDepositExtraFormDataForSuperform(uint256 superformId_) internal view returns (bytes memory) {
        // For ERC4626 vaults, no extra data needed
        // For ERC5115 vaults, include asset address
        bytes memory extraData = _isERC5115Vault(superformId_) ? abi.encode(address(asset)) : bytes("");

        return abi.encode(superformId_, extraData);
    }

    /// @notice Calculates amounts based on total output amount and weights
    /// @param totalOutputAmount_ The total output amount
    /// @param weights_ Array of weights
    /// @return amounts Array of calculated amounts
    function _calculateAmounts(
        uint256 totalOutputAmount_,
        uint256[] memory weights_
    )
        internal
        pure
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](weights_.length);
        for (uint256 i; i < weights_.length; ++i) {
            amounts[i] = totalOutputAmount_.mulDiv(weights_[i], TOTAL_WEIGHT, Math.Rounding.Down);
        }
    }

    /// @notice Filters out zero weights and returns corresponding superform IDs and weights
    /// @param superformIds_ Array of Superform IDs
    /// @param weights_ Array of weights
    /// @return filteredIds Array of filtered Superform IDs
    /// @return filteredWeights Array of filtered weights
    function _filterNonZeroWeights(
        uint256[] calldata superformIds_,
        uint256[] calldata weights_
    )
        internal
        pure
        returns (uint256[] memory filteredIds, uint256[] memory filteredWeights)
    {
        uint256 count;
        uint256 length = weights_.length;
        for (uint256 i; i < length; ++i) {
            if (weights_[i] != 0) {
                count++;
            }
        }

        filteredIds = new uint256[](count);
        filteredWeights = new uint256[](count);

        uint256 j;
        uint256 totalWeight;
        for (uint256 i; i < length; ++i) {
            if (weights_[i] != 0) {
                filteredIds[j] = superformIds_[i];
                filteredWeights[j] = weights_[i];
                totalWeight += weights_[i];
                j++;
            }
        }
        if (totalWeight != TOTAL_WEIGHT) revert INVALID_WEIGHTS();
    }

    /// @notice Updates the SuperVault data after rebalancing
    /// @param superPositions_ Address of the SuperPositions contract
    /// @param finalSuperformIds_ Array of Superform IDs to rebalance to
    function _updateSVData(address superPositions_, uint256[] memory finalSuperformIds_) internal {
        // Cache current superform IDs
        uint256[] memory currentSuperformIds = superformIds;

        // For each current superform ID
        uint256 numSuperforms = currentSuperformIds.length;
        for (uint256 i; i < numSuperforms;) {
            bool found;
            // Check if it exists in finalSuperformIds_
            for (uint256 j; j < finalSuperformIds_.length; ++j) {
                if (currentSuperformIds[i] == finalSuperformIds_[j]) {
                    found = true;
                    break;
                }
            }
            // If not found in final IDs, it should be fully rebalanced
            if (!found) {
                if (_getSuperPositionBalance(superPositions_, currentSuperformIds[i]) != 0) {
                    revert INVALID_SP_FULL_REBALANCE(currentSuperformIds[i]);
                }
            }

            unchecked {
                ++i;
            }
        }

        uint256 totalWeight;
        uint256 length = finalSuperformIds_.length;
        if (length == 0) revert ZERO_SUPERFORMS();

        uint256[] memory newWeights = new uint256[](length);

        /// @dev check if finalSuperformIds are present in superform factory and support the asset
        ISuperformFactory factory = ISuperformFactory(_SUPERFORM_FACTORY);
        address superform;
        uint256 value;
        address assetCache = address(asset);

        /// @dev calculate total value and individual values
        for (uint256 i; i < length;) {
            if (!factory.isSuperform(finalSuperformIds_[i])) {
                revert SUPERFORM_DOES_NOT_EXIST(finalSuperformIds_[i]);
            }

            (superform,,) = finalSuperformIds_[i].getSuperform();

            if (IBaseForm(superform).getVaultAsset() != assetCache) {
                revert SUPERFORM_DOES_NOT_SUPPORT_ASSET();
            }

            uint256 balance = _getSuperPositionBalance(superPositions_, finalSuperformIds_[i]);
            value = IBaseForm(superform).previewRedeemFrom(balance);

            newWeights[i] = value;
            totalWeight += value;

            unchecked {
                ++i;
            }
        }

        /// @dev calculate new weights as percentages
        uint256 totalAssignedWeight;
        for (uint256 i; i < length - 1;) {
            newWeights[i] = newWeights[i].mulDiv(TOTAL_WEIGHT, totalWeight, Math.Rounding.Down);
            totalAssignedWeight += newWeights[i];

            unchecked {
                ++i;
            }
        }

        /// @notice assign remaining weight to the last index
        newWeights[length - 1] = TOTAL_WEIGHT - totalAssignedWeight;

        /// @dev update SV data
        weights = newWeights;
        superformIds = finalSuperformIds_;
        numberOfSuperforms = length;

        emit RebalanceComplete(finalSuperformIds_, newWeights);
    }

    /// @notice Changes the whitelist for a Superform ID
    /// @param superformId_ The Superform ID to change
    /// @param isWhitelisted_ Whether to whitelist or blacklist
    function _changeSuperformWhitelist(uint256 superformId_, bool isWhitelisted_) internal {
        bool currentlyWhitelisted = whitelistedSuperformIdsSet.contains(superformId_);

        // Only process if there's an actual change
        if (currentlyWhitelisted != isWhitelisted_) {
            if (isWhitelisted_) {
                _addToWhitelist(superformId_);
            } else {
                _removeFromWhitelist(superformId_);
            }

            emit SuperformWhitelisted(superformId_, isWhitelisted_);
        }
    }

    /// @notice Adds a superform ID to the whitelist array
    /// @param superformId The Superform ID to add
    function _addToWhitelist(uint256 superformId) internal {
        whitelistedSuperformIdsSet.add(superformId);
    }

    /// @notice Removes a superform ID from the whitelist array
    /// @param superformId The Superform ID to remove
    function _removeFromWhitelist(uint256 superformId) internal {
        whitelistedSuperformIdsSet.remove(superformId);
    }

    /// @notice Calculates the tolerance for ERC5115 vaults
    /// @param isERC5115 Whether the vault is ERC5115
    /// @param amount The amount to calculate tolerance for
    /// @return The calculated tolerance
    function _tolerance(bool isERC5115, uint256 amount) internal pure returns (uint256) {
        return isERC5115 ? amount - TOLERANCE_CONSTANT : amount;
    }
}
