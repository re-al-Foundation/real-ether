// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface ISwapManager {
    function swap(address tokenIn, uint256 amountIn) external returns (uint256 amountOut);
}
