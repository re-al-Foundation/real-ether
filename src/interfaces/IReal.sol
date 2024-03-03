// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

import {IERC20} from "oz/token/ERC20/IERC20.sol";

/**
 * @title Real Interface
 * @dev Interface for a token contract representing real-world assets.
 */
interface IReal is IERC20 {
    /**
     * @dev Mints tokens and assigns them to the specified address.
     * @param _to The address to which the minted tokens will be assigned.
     * @param _amount The amount of tokens to mint.
     */
    function mint(address _to, uint256 _amount) external;

    /**
     * @dev Burns tokens from the specified address.
     * @param _from The address from which tokens will be burned.
     * @param _amount The amount of tokens to burn.
     */
    function burn(address _from, uint256 _amount) external;
}
