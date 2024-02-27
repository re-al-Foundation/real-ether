// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IMinter {
    function setNewVault(address _vault) external;
    function mint(address _to, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external;

    function real() external view returns (address);
    function getTokenPrice() external view returns (uint256 price);
}
