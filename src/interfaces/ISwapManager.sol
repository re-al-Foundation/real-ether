// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

/**
 * @title SwapManager Interface
 * @dev Interface for a contract managing token swaps.
 */
interface ISwapManager {
    /**
     * @dev Swaps a specified amount of input tokens for output tokens.
     * @param tokenIn The address of the input token.
     * @param amountIn The amount of input tokens to swap.
     * @return amountOut  The amount of output tokens received.
     */
    function swap(address tokenIn, uint256 amountIn) external returns (uint256 amountOut);

    /**
     * @dev Sets a Uniswap V3 pool address on the whitelist for a specific token.
     * @param token The address of the token.
     * @param pool The address of the V3 pool.
     */
    function setWhitelistV3Pool(address token, address pool) external;

    /**
     * @dev Sets a Curve pool address on the whitelist for a specific token.
     * @param token The address of the token.
     * @param pool The address of the Curve pool.
     */
    function setWhitelistCurvePool(address token, address pool) external;

    /**
     * @dev Sets the fee for a specific pool.
     * @param token The address of the token.
     * @param fees The fee to be set.
     */
    function setPoolFee(address token, uint24 fees) external;
    function transferETH() external;

    /**
     * @dev Estimates the output amount of a token swap using the fair quote method.
     * @param tokenIn The address of the input token.
     * @param amountIn The amount of input tokens.
     * @return amountOut The estimated amount of output tokens.
     */
    function getFairQuote(address tokenIn, uint256 amountIn) external returns (uint256 amountOut);

    function swapUinv3(address tokenIn, uint256 amountIn) external returns (uint256 amountOut);

    function swapCurve(address tokenIn, uint256 amountIn) external returns (uint256 amountOut);

    function getMinimumAmount(address token, uint256 amount) external view returns (uint256);

    /**
     * @dev Estimates the output amount of a token swap in a Curve pool.
     * @param amountIn The amount of input tokens.
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @return amountOut The estimated amount of output tokens.
     */
    function estimateCurveAmountOut(uint256 amountIn, address tokenIn, address tokenOut)
        external
        view
        returns (uint256 amountOut);

    /**
     * @dev Estimates the output amount of a token swap in a V3 pool.
     * @param amountIn The amount of input tokens.
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @return amountOut The estimated amount of output tokens.
     */
    function estimateV3AmountOut(uint128 amountIn, address tokenIn, address tokenOut)
        external
        view
        returns (uint256 amountOut);
}
