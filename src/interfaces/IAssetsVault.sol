// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

/**
 * @title AssetsVault Interface
 * @dev Interface for managing assets within a vault contract.
 */
interface IAssetsVault {
    /**
     * @dev Deposits funds into the vault.
     */
    function deposit() external payable;

    /**
     * @dev Withdraws funds from the vault.
     * @param to The address to which the withdrawn funds will be transferred.
     * @param amount The amount of funds to withdraw.
     */
    function withdraw(address to, uint256 amount) external;

    /**
     * @dev Sets a new vault address.
     * @param _vault The address of the new vault.
     */
    function setNewVault(address _vault) external;

    /**
     * @dev Gets the balance of the vault.
     * @return balanceAmount The balance of the vault.
     */
    function getBalance() external view returns (uint256 balanceAmount);
}
