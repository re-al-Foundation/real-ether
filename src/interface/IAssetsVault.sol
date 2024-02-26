// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IAssetsVault {
    function deposit() external payable;
    function withdraw(address to, uint256 amount) external;
    function setNewVault(address _vault) external;
    function getBalance() external view returns (uint256 balanceAmount);
}
