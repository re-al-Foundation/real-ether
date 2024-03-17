// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

import {IStrategyManager} from "../interfaces/IStrategyManager.sol";

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

    /**
     * @dev Throws if the caller is not the manager address.
     */
    modifier onlyManager() {
        if (manager != msg.sender) revert Strategy__NotManager();
        _;
    }

    /**
     * @dev Deposit function to deposit funds into the strategy.
     */
    function deposit() external payable virtual onlyManager {}

    /**
     * @dev Withdraw function to withdraw funds from the strategy.
     * @param _amount The amount of funds to withdraw.
     * @return actualAmount The actual amount withdrawn.
     */
    function withdraw(uint256 _amount) external virtual onlyManager returns (uint256 actualAmount) {}

    /**
     * @dev Instant withdraw function to immediately withdraw funds from the strategy.
     * @param _amount The amount of funds to withdraw.
     * @return actualAmount The actual amount withdrawn.
     */
    function instantWithdraw(uint256 _amount) external virtual onlyManager returns (uint256 actualAmount) {}

    /**
     * @dev Clear function to clear any allocated funds or assets in the strategy.
     * @return amount The amount of funds cleared.
     */
    function clear() external virtual onlyManager returns (uint256 amount) {}

    /**
     * @dev Execute pending request function to execute any pending transactions in the strategy.
     * @param _amount The amount of funds to execute pending requests.
     * @return amount The amount of funds executed.
     */
    function execPendingRequest(uint256 _amount) public virtual returns (uint256 amount) {}

    /**
     * @dev Get all value function to get the total value of assets held in the strategy.
     * @return value The total value of assets held in the strategy.
     */
    function getTotalValue() public virtual returns (uint256 value) {}

    /**
     * @dev Get pending value function to get the pending value of assets in the strategy.
     * @return value The pending value of assets in the strategy.
     */
    function getPendingValue() public virtual returns (uint256 value) {}

    /**
     * @dev Get invested value function to get the currently invested value of assets in the strategy.
     * @return value The currently invested value of assets in the strategy.
     */
    function getInvestedValue() public virtual returns (uint256 value) {}

    /**
     * @dev Check pending status function to check the status of pending transactions in the strategy.
     * @return pending The amount of pending transactions.
     * @return executable The claimable amount of transactions ready to be executed.
     */
    function checkPendingStatus() external virtual returns (uint256 pending, uint256 executable) {}

    /**
     * @dev Sets the governance address.
     * @param _governance The address to set as the new governance.
     */
    function setGovernance(address _governance) external onlyGovernance {
        if (_governance == address(0)) revert Strategy__ZeroAddress();
        emit TransferGovernance(governance, _governance);
        governance = _governance;
    }
}
