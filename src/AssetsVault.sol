// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

import {TransferHelper} from "v3-periphery/libraries/TransferHelper.sol";

error AssetsVault__ZeroAddress();
error AssetsVault__NotPermit();
error AssetsVault__InvalidAmount();

/**
 * @title ReETH Assets Vault
 * @author Mavvverick
 * @notice The ReETH Assets Vault is a secure smart contract designed to hold ETH deposits
 * in exchange for issuing ReETH tokens for the re.al Chain network. Users can deposit ETH into the real Vault,
 * which securely stores it in this vault until they choose to redeem it for ReETH tokens.
 * These tokens represent a claim to the underlying ETH assets and yield held within the Vault.
 */
contract AssetsVault {
    address public realVault;
    address public immutable strategyManager;

    event VaultUpdated(address oldRealVault, address newRealVault);

    /**
     * @dev Modifier to restrict access to only permitted addresses.
     * Only the real vault and strategy manager are permitted to execute certain functions.
     */
    modifier onlyPermit() {
        if (realVault != msg.sender && strategyManager != msg.sender) revert AssetsVault__NotPermit();
        _;
    }

    /**
     * @param _realVault Address of the real vault contract.
     * @param _strategyManager Address of the strategy manager contract.
     */
    constructor(address _realVault, address _strategyManager) {
        if (_realVault == address(0) || _strategyManager == address(0)) revert AssetsVault__ZeroAddress();

        realVault = _realVault;
        strategyManager = _strategyManager;
    }

    /**
     * @dev Deposit function to accept incoming Ether.
     */
    function deposit() external payable {
        if (msg.value == 0) revert AssetsVault__InvalidAmount();
    }

    /**
     * @dev Withdraw function to transfer Ether to a specified address.
     * Only permitted addresses can execute this function.
     * @param _to Address to which Ether will be transferred.
     * @param _amount Amount of Ether to transfer.
     */
    function withdraw(address _to, uint256 _amount) external onlyPermit {
        TransferHelper.safeTransferETH(_to, _amount);
    }

    /**
     * @dev Function to set a new vault address.
     * Only permitted addresses can execute this function.
     * @param _vault Address of the new vault contract.
     */
    function setNewVault(address _vault) external onlyPermit {
        if (_vault == address(0)) revert AssetsVault__ZeroAddress();
        emit VaultUpdated(realVault, _vault);
        realVault = _vault;
    }

    /**
     * @dev Function to get the balance of Ether held by the contract.
     * @return amount The balance of Ether held by the contract.
     */
    function getBalance() external view returns (uint256 amount) {
        amount = address(this).balance;
    }

    /**
     * @dev Fallback function to receive Ether.
     */
    receive() external payable {}
}
