// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

/**
 * @title Strategy Interface
 * @dev Interface for a strategy contract managing eth investment strategies.
 */
interface IStrategy {
    /**
     * @dev Clears the strategy, potentially withdrawing all funds and resetting parameters.
     */
    function clear() external;

    /**
     * @dev Deposits funds into the strategy.
     */
    function deposit() external payable;

    /**
     * @dev Withdraws a specified amount of funds from the strategy.
     * @param withAmount The amount of funds to withdraw.
     */
    function withdraw(uint256 withAmount) external;

    /**
     * @dev Executes an instant withdrawal of a specified amount of funds from the strategy.
     * @param withAmount The amount of funds to withdraw.
     * @return amount The actual amount withdrawn.
     */
    function instantWithdraw(uint256 withAmount) external returns (uint256 amount);

    /**
     * @dev Retrieves the address of the strategy manager.
     * @return manager The address of the strategy manager.
     */
    function manager() external view returns (address manager);

    /**
     * @dev Retrieves the total value managed by the strategy.
     * @return value The total value managed by the strategy.
     */
    function getAllValue() external view returns (uint256 value);

    /**
     * @dev Retrieves the amount of funds currently invested in the strategy.
     * @return value The amount of funds currently invested in the strategy.
     */
    function getInvestedValue() external view returns (uint256 value);

    /**
     * @dev Retrieves the amount of funds pending investment in the strategy.
     * @return value The amount of funds pending investment in the strategy.
     */
    function getPendingValue() external view returns (uint256 value);
}
