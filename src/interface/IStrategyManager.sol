// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IStrategyManager {
    function setNewVault(address _vault) external;
    function addStrategy(address _strategy) external;
    function destroyStrategy(address _strategy) external;
    function clearStrategy(address _strategy) external;
    function rebaseStrategies(uint256 amountIn, uint256 amountOut) external;
    function forceWithdraw(uint256 ethAmount) external returns (uint256 actualAmount);
    function setStrategies(address[] memory _strategies, uint256[] memory _ratios) external;

    function getAllStrategiesValue() external view returns (uint256 amount);
    function getAllStrategyValidValue() external view returns (uint256 amount);
    function getAllStrategyPendingValue() external view returns (uint256 amount);
}
