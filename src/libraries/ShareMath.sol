// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

import {FullMath} from "v3-core-0.8/libraries/FullMath.sol";

library ShareMath {
    uint256 internal constant DECIMAL = 18;
    uint256 internal constant DECIMAL_OFFSET = 10 ** DECIMAL;
    uint256 internal constant PLACEHOLDER_UINT = 1;

    /**
     * @notice Converts an amount of tokens to shares.
     * @param assetAmount The amount of tokens to convert.
     * @param assetPerShare The price per share.
     * @return The equivalent amount of shares.
     *
     * Note: All rounding errors should be rounded down in the interest of the protocol's safety.
     * Token transfers, including deposit and withdraw operations, may require a rounding, leading to potential
     * transferring at most one GWEI less than expected aggregated over a long period of time.
     */
    function assetToShares(uint256 assetAmount, uint256 assetPerShare) internal pure returns (uint256) {
        require(assetPerShare > PLACEHOLDER_UINT, "ShareMath Lib: Invalid assetPerShare");
        return FullMath.mulDiv(assetAmount, DECIMAL_OFFSET, assetPerShare);
    }

    /**
     * @notice Converts an amount of shares to tokens.
     * @param shares The amount of shares to convert.
     * @param assetPerShare The price per share.
     * @return The equivalent amount of tokens.
     */
    function sharesToAsset(uint256 shares, uint256 assetPerShare) internal pure returns (uint256) {
        require(assetPerShare > PLACEHOLDER_UINT, "ShareMath Lib: Invalid assetPerShare");
        return FullMath.mulDiv(shares, assetPerShare, DECIMAL_OFFSET);
    }
}
