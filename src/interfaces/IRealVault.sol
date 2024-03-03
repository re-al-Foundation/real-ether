// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

/**
 * @title RealVault Interface
 * @dev Interface for a vault contract managing real ether.
 */
interface IRealVault {
    /**
     * @dev Deposits funds into the vault and mints corresponding shares.
     * @return mintAmount amount of shares minted.
     */
    function deposit() external payable returns (uint256 mintAmount);

    /**
     * @dev Deposits funds into the vault on behalf of a specified receiver and mints corresponding shares.
     * @param receiver The address to receive the minted shares.
     * @return mintAmount amount of shares minted.
     */
    function depositFor(address receiver) external payable returns (uint256 mintAmount);

    /**
     * @dev Requests withdrawal of a specified amount of shares.
     * @param shares The amount of shares to withdraw.
     */
    function requestWithdraw(uint256 shares) external;

    /**
     * @dev Cancels a withdrawal request for a specified amount of shares.
     * @param shares The amount of shares for which withdrawal is to be canceled.
     */
    function cancelWithdraw(uint256 shares) external;

    /**
     * @dev Executes an instant withdrawal of a specified amount of shares, converting them to funds.
     * @param _amount The amount of shares to withdraw.
     * @param _shares The number of shares to withdraw.
     * @return actualWithdrawn actual amount withdrawn.
     */
    function instantWithdraw(uint256 _amount, uint256 _shares) external returns (uint256 actualWithdrawn);

    /**
     * @dev Retrieves the current price per share.
     * @return price current price per share.
     */
    function currentSharePrice() external view returns (uint256 price);
}
