// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {TransferHelper} from "v3-periphery/libraries/TransferHelper.sol";

contract AssetsVault {
    address public realvault;
    address public strategyManager;

    modifier onlyPermit() {
        require(realvault == msg.sender || strategyManager == msg.sender, "not permit");
        _;
    }

    constructor(address _realvault, address _strategyManager) {
        require(_realvault != address(0) && _strategyManager != address(0), "ZERO ADDRESS");
        realvault = _realvault;
        strategyManager = _strategyManager;
    }

    function deposit() external payable {
        require(msg.value != 0, "too small");
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
