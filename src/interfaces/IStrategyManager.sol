// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

/**
 * @title StrategyManager Interface
 * @dev Interface for a contract managing multiple eth investment strategies.
 */
interface IStrategyManager {
    /**
     * @dev Sets a new vault address.
     * @param _vault The address of the new vault.
     */
    function setNewVault(address _vault) external;

    /**
     * @dev Adds a new strategy to be managed.
     * @param _strategy The address of the strategy to add.
     */
    function addStrategy(address _strategy) external;

    /**
     * @dev Destroys a strategy, removing it from management.
     * @param _strategy The address of the strategy to destroy.
     */
    function destroyStrategy(address _strategy) external;

    /**
     * @dev Clears a strategy, potentially withdrawing its funds and resetting parameters.
     * @param _strategy The address of the strategy to clear.
     */
    function clearStrategy(address _strategy) external;

    /**
     * @dev Rebalances the strategies based on incoming and outgoing amounts.
     * @param amountIn The amount of funds to be rebalanced into the strategies.
     * @param amountOut The amount of funds to be rebalanced out of the strategies.
     */
    function rebaseStrategies(uint256 amountIn, uint256 amountOut) external;

    /**
     * @dev Forces a withdrawal of a specified amount of ETH from the strategies.
     * @param ethAmount The amount of ETH to withdraw.
     * @return actualAmount The actual amount of ETH withdrawn.
     */
    function forceWithdraw(uint256 ethAmount) external returns (uint256 actualAmount);

    /**
     * @dev Sets the strategies and their corresponding ratios.
     * @param _strategies The addresses of the strategies to set.
     * @param _ratios The corresponding ratios for each strategy.
     */
    function setStrategies(address[] memory _strategies, uint256[] memory _ratios) external;

    /**
     * @dev Retrieves the address of the assets vault managed by the strategy manager.
     * @return vault The address of the assets vault.
     */
    function assetsVault() external view returns (address vault);

    /**
     * @dev Retrieves the total value managed by all strategies.
     * @return amount The total value managed by all strategies.
     */
    function getAllStrategiesValue() external view returns (uint256 amount);

    /**
     * @dev Retrieves the total valid value managed by all strategies.
     * @return amount The total valid value managed by all strategies.
     */
    function getAllStrategyValidValue() external view returns (uint256 amount);

    /**
     * @dev Retrieves the total pending value managed by all strategies.
     * @return amount The total pending value managed by all strategies.
     */
    function getAllStrategyPendingValue() external view returns (uint256 amount);
}
