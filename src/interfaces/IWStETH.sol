// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

/**
 * @title Wrapped stETH Interface
 * @dev Interface for a contract representing wrapped staked Ether (wstETH).
 */
abstract contract IWStETH {
    /**
     * @dev Unwraps a specified amount of wstETH tokens into stETH tokens.
     * @param _wstETHAmount The amount of wstETH tokens to unwrap.
     * @return The amount of stETH tokens received.
     */
    function unwrap(uint256 _wstETHAmount) external virtual returns (uint256);

    /**
     * @notice Exchanges stETH to wstETH
     * @param _stETHAmount amount of stETH to wrap in exchange for wstETH
     * @dev Requirements:
     *  - `_stETHAmount` must be non-zero
     *  - msg.sender must approve at least `_stETHAmount` stETH to this
     *    contract.
     *  - msg.sender must have at least `_stETHAmount` of stETH.
     * User should first approve _stETHAmount to the WstETH contract
     * @return Amount of wstETH user receives after wrap
     */
    function wrap(uint256 _stETHAmount) external virtual returns (uint256);

    /**
     * @dev Converts a specified amount of stETH tokens into wstETH tokens.
     * @param _stETHAmount The amount of stETH tokens to convert.
     * @return The amount of wstETH tokens received.
     */
    function getWstETHByStETH(uint256 _stETHAmount) external view virtual returns (uint256);

    /**
     * @dev Converts a specified amount of wstETH tokens into stETH tokens.
     * @param _wstETHAmount The amount of wstETH tokens to convert.
     * @return The amount of stETH tokens received.
     */
    function getStETHByWstETH(uint256 _wstETHAmount) external view virtual returns (uint256);

    /**
     * @dev Retrieves the current exchange rate of stETH to wstETH.
     * @return The current exchange rate of stETH to wstETH.
     */
    function stEthPerToken() external view virtual returns (uint256);
}
