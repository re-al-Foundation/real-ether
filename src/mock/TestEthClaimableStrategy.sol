// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

import {Strategy} from "../strategy/Strategy.sol";
import {TransferHelper} from "v3-periphery/libraries/TransferHelper.sol";
import {IStrategyManager} from "../interfaces/IStrategyManager.sol";

error TestEthClaimableStrategy__ZeroAmount();
error TestEthClaimableStrategy__InsufficientBalance();

contract TestEthClaimableStrategy is Strategy {
    address public swapManager;
    uint256 lockedReserve;
    uint256 pendingReserve;

    constructor(address payable _manager, string memory _name) Strategy(_manager, _name) {}

    function deposit() external payable override onlyManager {
        if (msg.value == 0) revert TestEthClaimableStrategy__ZeroAmount();
        lockedReserve += msg.value;
    }

    function withdraw(uint256 _ethAmount) external override onlyManager returns (uint256 actualAmount) {
        if (_ethAmount == 0) revert TestEthClaimableStrategy__ZeroAmount();
        if (_ethAmount > getTotalValue()) revert TestEthClaimableStrategy__InsufficientBalance();
        // Mock: On withdraw request will be raised to initiate withdraw from the strategy protocol
        // amount can be claimed after approval by the strategy protocol
        pendingReserve += _ethAmount;
        actualAmount = _ethAmount;
        TransferHelper.safeTransferETH(manager, address(this).balance);
    }

    function claimAllPendingAssets() external {
        uint256 _amount = pendingReserve;
        pendingReserve = 0;
        TransferHelper.safeTransferETH(IStrategyManager(manager).assetsVault(), _amount);
    }

    function clear() external override onlyManager returns (uint256 amount) {
        uint256 claimableAmount = getClaimableValue();
        amount = getBalance() + claimableAmount;
        if (amount > address(this).balance) revert TestEthClaimableStrategy__InsufficientBalance();
        if (claimableAmount > 0) pendingReserve -= claimableAmount;
        TransferHelper.safeTransferETH(manager, amount);
    }

    function getBalance() public view returns (uint256 amount) {
        //  Mock: Using pending balance to mimic the claimable action from the strategy protocol
        amount = address(this).balance - getPendingValue();
    }

    function getTotalValue() public view override returns (uint256 value) {
        value = getInvestedValue() + getClaimableAndPendingValue();
    }

    function getInvestedValue() public view override returns (uint256 value) {
        value = address(this).balance;
    }

    function getPendingValue() public view override returns (uint256 value) {
        value = pendingReserve;
    }

    function getClaimableValue() public view returns (uint256 value) {
        value = pendingReserve;
    }

    function getClaimableAndPendingValue() public pure returns (uint256 value) {
        value = 0;
    }
}
