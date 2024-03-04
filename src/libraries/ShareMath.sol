// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

library ShareMath {
    uint256 internal constant decimals = 18;
    uint256 internal constant PLACEHOLDER_UINT = 1;

    function assetToShares(uint256 assetAmount, uint256 assetPerShare) internal pure returns (uint256) {
        // If this throws, it means that vault's roundPricePerShare[currentRound] has not been set yet
        // which should never happen.
        // Has to be larger than 1 because `1` is used in `initRoundPricePerShares` to prevent cold writes.
        require(assetPerShare > PLACEHOLDER_UINT, "ShareMath Lib: Invalid assetPerShare");
        return (assetAmount * 10 ** decimals) / assetPerShare;
    }

    function sharesToAsset(uint256 shares, uint256 assetPerShare) internal pure returns (uint256) {
        // If this throws, it means that vault's roundPricePerShare[currentRound] has not been set yet
        // which should never happen.
        // Has to be larger than 1 because `1` is used in `initRoundPricePerShares` to prevent cold writes.
        require(assetPerShare > PLACEHOLDER_UINT, "ShareMath Lib: Invalid assetPerShare");
        return (shares * assetPerShare) / 10 ** decimals;
    }
}
