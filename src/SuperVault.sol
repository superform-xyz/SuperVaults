// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

contract SuperVault is BaseStrategy {
    /**
     * @dev Can deploy up to '_amount' of 'asset' in the yield source.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy can attempt
     * to deposit in the yield source.
     */
    function _deployFunds(uint256 _amount) internal override {
        /// take amount
        /// split according to asset percentages using swapper
        /// generate a same chain state request and call router on this chain (must import v1 functionality, making it incompatible with v2)
        /// it must not contain txData otherwise this invalidates 4626 standard
        /// confirm obtaining superPositions
    }
}
