// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IStrategy {
    function clear() external;
    function deposit() external payable;
    function withdraw(uint256 withAmount) external;
    function instantWithdraw(uint256 withAmount) external returns (uint256 amount);

    function manager() external view returns (address manager);
    function getAllValue() external view returns (uint256 value);
    function getInvestedValue() external view returns (uint256 value);
    function getPendingValue() external view returns (uint256 value);
}
