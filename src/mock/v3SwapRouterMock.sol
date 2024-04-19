// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";

contract v3SwapRouterMock {
    uint256 amountOut;

    function setAmountOut(uint256 _amount) external returns (uint256) {
        amountOut = _amount;
    }

    function exactInputSingle(ISwapRouter.ExactInputSingleParams calldata) external view returns (uint256) {
        return amountOut;
    }

    function test() public {}
}
