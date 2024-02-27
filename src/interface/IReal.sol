// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IERC20} from "oz/token/ERC20/IERC20.sol";

interface IReal is IERC20 {
    function mint(address _to, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external;
}
