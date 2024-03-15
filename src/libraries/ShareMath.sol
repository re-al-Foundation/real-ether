// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

library ShareMath {
    uint256 internal constant decimals = 18;
    uint256 internal constant PLACEHOLDER_UINT = 1;

    function assetToShares(uint256 assetAmount, uint256 assetPerShare) internal pure returns (uint256) {
        require(assetPerShare > PLACEHOLDER_UINT, "ShareMath Lib: Invalid assetPerShare");
        return (assetAmount * 10 ** decimals) / assetPerShare;
    }

    function sharesToAsset(uint256 shares, uint256 assetPerShare) internal pure returns (uint256) {
        require(assetPerShare > PLACEHOLDER_UINT, "ShareMath Lib: Invalid assetPerShare");
        return (shares * assetPerShare) / 10 ** decimals;
    }
}
