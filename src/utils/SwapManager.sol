// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

contract SwapManager {
    constructor() {}

    function getQuote(address tokenIn, uint256 amountIn) public view virtual returns (uint256 amountOut) {}
    function swap(address tokenIn, uint256 amountIn) external virtual returns (uint256 amountOut) {}
}
