// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

import {Strategy} from "../strategy/Strategy.sol";
import {TransferHelper} from "v3-periphery/libraries/TransferHelper.sol";
import {IStrategyManager} from "../interfaces/IStrategyManager.sol";

error Strategy__ZeroAmount();
error Strategy__InsufficientBalance();

contract TestEthStrategy is Strategy {
    address public swapManager;
    uint256 pendingReserve;

    constructor(address payable _manager, string memory _name) Strategy(_manager, _name) {}

    function deposit() external payable override onlyManager {
        if (msg.value == 0) revert Strategy__ZeroAmount();
    }

    function withdraw(uint256 _ethAmount) external override onlyManager returns (uint256 actualAmount) {
        if (_ethAmount == 0) revert Strategy__ZeroAmount();
        if (_ethAmount > getTotalValue()) revert Strategy__InsufficientBalance();
        actualAmount = _ethAmount;
        TransferHelper.safeTransferETH(manager, _ethAmount);
    }

    function clear() external override onlyManager returns (uint256 amount) {
        amount = getTotalValue();
        TransferHelper.safeTransferETH(manager, amount);
    }

    function getBalance() public view returns (uint256 amount) {
        amount = address(this).balance;
    }

    function getTotalValue() public view override returns (uint256 value) {
        value = getInvestedValue() + getClaimableAndPendingValue();
    }

    function getInvestedValue() public view override returns (uint256 value) {
        value = address(this).balance;
    }

    function getPendingValue() public pure override returns (uint256 value) {
        value = 0;
    }

    function getClaimableValue() public pure returns (uint256 value) {
        value = 0;
    }

    function getClaimableAndPendingValue() public pure returns (uint256 value) {
        value = 0;
    }

    receive() external payable {}
}
