// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IStrategyManager} from "../interface/IStrategyManager.sol";

error Strategy__ZeroAddress();
error Strategy__NotManager();
error Strategy__NotGovernance();

abstract contract Strategy {
    address payable public immutable manager;

    address public governance;

    string public name;

    modifier onlyGovernance() {
        if (governance != msg.sender) revert Strategy__NotGovernance();
        _;
    }

    event TransferGovernance(address oldOwner, address newOwner);

    constructor(address payable _manager, string memory _name) {
        if (_manager == address(0)) revert Strategy__NotManager();

        governance = msg.sender;
        manager = _manager;
        name = _name;
    }

    modifier onlyManager() {
        if (manager != msg.sender) revert Strategy__NotManager();
        _;
    }

    function deposit() public payable virtual onlyManager {}

    function withdraw(uint256 _amount) public virtual onlyManager returns (uint256 actualAmount) {}

    function instantWithdraw(uint256 _amount) public virtual onlyManager returns (uint256 actualAmount) {}

    function clear() public virtual onlyManager returns (uint256 amount) {}

    function execPendingRequest(uint256 _amount) public virtual returns (uint256 amount) {}

    function getAllValue() public virtual returns (uint256 value) {}

    function getPendingValue() public virtual returns (uint256 value) {}

    function getInvestedValue() public virtual returns (uint256 value) {}

    function checkPendingStatus() public virtual returns (uint256 pending, uint256 executable) {}

    function setGovernance(address _governance) external onlyGovernance {
        emit TransferGovernance(governance, _governance);
        governance = _governance;
    }
}
