// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IStrategyManager {
    function setNewVault(address _vault) external;
    function getAllStrategiesValue() external view returns (uint256 amount);
}
