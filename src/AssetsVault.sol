// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {TransferHelper} from "v3-periphery/libraries/TransferHelper.sol";

error AssetsVault__ZeroAddress();
error AssetsVault__NotPermit();
error AssetsVault__InvalidAmount();

contract AssetsVault {
    address public realvault;
    address public strategyManager;

    modifier onlyPermit() {
        if (realvault != msg.sender && strategyManager != msg.sender) revert AssetsVault__NotPermit();
        _;
    }

    constructor(address _realvault, address _strategyManager) {
        if (_realvault == address(0) || _strategyManager == address(0)) revert AssetsVault__ZeroAddress();

        realvault = _realvault;
        strategyManager = _strategyManager;
    }

    function deposit() external payable {
        if (msg.value == 0) revert AssetsVault__InvalidAmount();
    }

    function withdraw(address _to, uint256 _amount) external onlyPermit {
        TransferHelper.safeTransferETH(_to, _amount);
    }

    function setNewVault(address _vault) external onlyPermit {
        realvault = _vault;
    }

    function getBalance() external view returns (uint256 amount) {
        amount = address(this).balance;
    }

    receive() external payable {}
}
