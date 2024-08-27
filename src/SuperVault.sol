// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {BaseStrategy} from "./vendor/BaseStrategy.sol";

contract SuperVault is BaseStrategy {
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
