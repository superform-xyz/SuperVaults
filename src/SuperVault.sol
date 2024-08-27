// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {BaseStrategy} from "./vendor/BaseStrategy.sol";

contract SuperVault is BaseStrategy {
    //
    // Examples:
    // 1 - USDC SuperVault: Morpho + Euler + Aave USDC (3 vaults total to start)) -> ETH
    // 2 - Stablecoins SuperVault: Morpho + Euler + Aave (USDC, DAI, USDT (9 vaults total)) -> ETH
    //
    // Requirements:
    // 1 - Management can set %s for each vault (done also at launch)
    // 2 - Factory: input superform ids + weights and deploy - anyone can create a super vault
    // 3 - Auto-Rebalancing: who will be rebalancing? A fireblocks keeper
    // 4 - There is an algorithm to tell the weights for the keeper to rebalance (TBD, function will allow any weights to be set)

    constructor(address _asset, string memory _name) BaseStrategy(_asset, _name) {}
    function _deployFunds(uint256 _amount) internal override {
        /// take amount
        /// split according to asset percentages using swapper
        /// generate a same chain state request and call router on this chain (must import v1 functionality, making it incompatible with v2)
        /// it must not contain txData otherwise this invalidates 4626 standard
        /// confirm obtaining superPositions
    }

    function _freeFunds(uint256 _amount) internal override {}

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        /// call harvest on all superPositions
        /// call report on all superPositions
    }
}
