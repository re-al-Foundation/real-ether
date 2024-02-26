// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IMinter {
    function setNewVault(address _vault) external;
    function realETH() external view returns (address);
}
