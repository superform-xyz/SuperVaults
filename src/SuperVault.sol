// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IERC1155 } from "@openzeppelin/contracts/interfaces/IERC1155.sol";
import { IERC1155Receiver } from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import { BaseStrategy } from "./vendor/BaseStrategy.sol";
import { SingleDirectMultiVaultStateReq, MultiVaultSFData, LiqRequest } from "superform-core/types/DataTypes.sol";
import { DataLib } from "superform-core/libraries/DataLib.sol";
import { IBaseForm } from "superform-core/interfaces/IBaseForm.sol";
import { IBaseRouter } from "superform-core/interfaces/IBaseRouter.sol";
import { ISuperRegistry } from "superform-core/interfaces/ISuperRegistry.sol";

contract SuperVault is BaseStrategy, IERC1155Receiver {
    using Math for uint256;
    using DataLib for uint256;
    using SafeERC20 for ERC20;

    error ARRAY_LENGTH_MISMATCH();

    error INVALID_WEIGHTS();

    error NOT_SUPER_VAULTS_STRATEGIST();

    error ZERO_ADDRESS();

    error INVALID_SUPER_POSITIONS_OUTPUT();
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
    uint256 public constant SP_SLIPPAGE = 200; // 2%

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

    // This function is permissionless, so swaps or LP movements can be sandwiched or manipulated.
    function _deployFunds(uint256 amount_) internal override {
        MultiVaultSFData memory mvData;

        mvData.superformIds = SV.superformIds;
        mvData.amounts = new uint256[](SV.numberOfSuperforms);
        mvData.maxSlippages = new uint256[](SV.numberOfSuperforms);
        mvData.liqRequests = new LiqRequest[](SV.numberOfSuperforms);
        mvData.hasDstSwaps = new bool[](SV.numberOfSuperforms);
        mvData.retain4626s = mvData.hasDstSwaps;
        mvData.receiverAddress = REFUNDS_RECEIVER;
        mvData.receiverAddressSP = address(this);

        address[] memory thisAddress = new address[](SV.numberOfSuperforms);
        for (uint256 i; i < SV.numberOfSuperforms; ++i) {
            mvData.amounts[i] = amount_.mulDiv(SV.weights[i], TOTAL_WEIGHT, Math.Rounding.Down);
            (address superform,,) = mvData.superformIds[i].getSuperform();
            mvData.outputAmounts[i] = IBaseForm(superform).previewDepositTo(mvData.amounts[i]);
            mvData.maxSlippages[i] = MAX_SLIPPAGE;
            mvData.liqRequests[i] = LiqRequest("", address(asset), address(0), 0, 0, 0);
            thisAddress[i] = address(this);
        }

        bytes memory callData = abi.encodeWithSelector(
            IBaseRouter.singleDirectMultiVaultDeposit.selector, SingleDirectMultiVaultStateReq(mvData)
        );
        address router = _getAddress(keccak256("SUPERFORM_ROUTER"));
        address superPositions = _getAddress(keccak256("SUPER_POSITIONS"));
        asset.approve(router, amount_);

        uint256[] memory spBalanceBefore = IERC1155(superPositions).balanceOfBatch(thisAddress, mvData.superformIds);
        /// @dev this call has to be enforced with 0 msg.value not to break the 4626 standard
        (bool success, bytes memory returndata) = router.call(callData);

        Address.verifyCallResult(success, returndata, "CallRevertWithNoReturnData");

        if (asset.allowance(address(this), router) > 0) asset.forceApprove(router, 0);

        uint256[] memory spBalanceAfter = IERC1155(superPositions).balanceOfBatch(thisAddress, mvData.superformIds);

        for (uint256 i; i < SV.numberOfSuperforms; ++i) {
            if (spBalanceAfter[i] - spBalanceBefore[i] != mvData.outputAmounts[i]) {
                revert INVALID_SUPER_POSITIONS_OUTPUT();
            }
        }
    }

    function _freeFunds(uint256 amount_) internal override { }

    function _harvestAndReport() internal override returns (uint256 totalAssets) {
        /// call harvest on all superPositions
        /// call report on all superPositions
    }

    /// @dev returns the address from super registry
    function _getAddress(bytes32 id_) internal view returns (address) {
        return superRegistry.getAddress(id_);
    }
}
