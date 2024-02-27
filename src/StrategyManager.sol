// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {EnumerableSet} from "oz/utils/structs/EnumerableSet.sol";
import {TransferHelper} from "v3-periphery/libraries/TransferHelper.sol";

import {IStrategy} from "./interface/IStrategy.sol";
import {IAssetsVault} from "./interface/IAssetsVault.sol";

error StrategyManager__ZeroAddress();
error StrategyManager__InvalidLength();
error StrategyManager__InvalidRatio();
error StrategyManager__InvalidPercentage();
error StrategyManager__NotVault();
error StrategyManager__InvalidManager();
error StrategyManager__StillActive(address strategy);

contract StrategyManager {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct StrategySnapshot {
        address strategy;
        bool isDeposit;
        uint256 amount;
    }

    uint256 internal constant ONE_HUNDRED_PERCENT = 1000_000;

    address public realVault;
    address payable public immutable assetsVault;

    EnumerableSet.AddressSet private strategies;

    mapping(address => uint256) public ratios;

    constructor(address payable _assetsVault, address[] memory _strategies, uint256[] memory _ratios) {
        if (_assetsVault == address(0)) revert StrategyManager__ZeroAddress();

        uint256 length = _strategies.length;
        for (uint256 i; i < length;) {
            if (_strategies[i] == address(0)) revert StrategyManager__ZeroAddress();
            unchecked {
                i++;
            }
        }

        realVault = msg.sender;
        assetsVault = _assetsVault;

        _loadStrategies(_strategies, _ratios);
    }

    modifier onlyVault() {
        if (realVault != msg.sender) revert StrategyManager__NotVault();
        _;
    }

    // [SETTER Functions]

    function setNewVault(address _vault) external onlyVault {
        realVault = _vault;
    }

    function setStrategies(address[] memory _strategies, uint256[] memory _ratios) external onlyVault {
        _setStrategies(_strategies, _ratios);
    }

    function addStrategy(address _strategy) external onlyVault {
        require(!strategies.contains(_strategy), "already exist");
        strategies.add(_strategy);
    }

    function destroyStrategy(address _strategy) external onlyVault {
        _destoryStrategy(_strategy);
    }

    function clearStrategy(address _strategy) public onlyVault {
        _clearStrategy(_strategy, false);
    }

    function forceWithdraw(uint256 _amount) external onlyVault returns (uint256 actualAmount) {
        uint256 balanceBeforeRepay = address(this).balance;

        if (balanceBeforeRepay >= _amount) {
            _repayToVault();

            actualAmount = balanceBeforeRepay;
        } else {
            actualAmount = _forceWithdraw(_amount - balanceBeforeRepay) + balanceBeforeRepay;
        }
    }

    function onlyRebaseStrategies() external {
        _rebase(0, 0);
    }

    function rebaseStrategies(uint256 _in, uint256 _out) external payable onlyVault {
        _rebase(_in, _out);
    }

    // [Internal Functions]

    /// @dev update the invested value accross all strategies
    function _rebase(uint256 _in, uint256 _out) internal {
        require(_in == 0 || _out == 0, "only deposit or withdraw");

        if (_in != 0) {
            IAssetsVault(assetsVault).withdraw(address(this), _in);
        }
        uint256 total = getAllStrategyValidValue();
        if (total < _out) {
            total = 0;
        } else {
            total = total + _in - _out;
        }

        uint256 length = strategies.length();
        StrategySnapshot[] memory snapshots = new StrategySnapshot[](length);
        uint256 head;
        uint256 tail = length - 1;
        for (uint256 i; i < length; i++) {
            address strategy = strategies.at(i);
            if (ratios[strategy] == 0) {
                _clearStrategy(strategy, true);
                continue;
            }
            uint256 newPosition = (total * ratios[strategy]) / ONE_HUNDRED_PERCENT;
            uint256 position = getStrategyValidValue(strategy);

            if (newPosition < position) {
                snapshots[head] = StrategySnapshot(strategy, false, position - newPosition);
                head++;
            } else if (newPosition > position) {
                snapshots[tail] = StrategySnapshot(strategy, true, newPosition - position);
                if (tail != 0) {
                    tail--;
                }
            }
        }

        // update the strategy invested value based on latest position
        length = snapshots.length;
        for (uint256 i; i < length; i++) {
            StrategySnapshot memory snapshot = snapshots[i];

            if (snapshot.amount == 0) {
                continue;
            }

            if (snapshot.isDeposit) {
                if (address(this).balance < snapshot.amount) {
                    snapshot.amount = address(this).balance;
                }
                _depositToStrategy(snapshot.strategy, snapshot.amount);
            } else {
                _withdrawFromStrategy(snapshot.strategy, snapshot.amount);
            }
        }

        _repayToVault();
    }

    function _repayToVault() internal {
        if (address(this).balance != 0) {
            TransferHelper.safeTransferETH(assetsVault, address(this).balance);
        }
    }

    function _forceWithdraw(uint256 _amount) internal returns (uint256 actualAmount) {
        uint256 length = strategies.length();
        for (uint256 i; i < length;) {
            address strategy = strategies.at(i);

            uint256 withAmount = (_amount * ratios[strategy]) / ONE_HUNDRED_PERCENT;

            if (withAmount != 0) {
                actualAmount = IStrategy(strategy).instantWithdraw(withAmount) + actualAmount;
            }

            unchecked {
                i++;
            }
        }

        _repayToVault();
    }

    function _depositToStrategy(address _strategy, uint256 _amount) internal {
        IStrategy(_strategy).deposit{value: _amount}();
    }

    function _withdrawFromStrategy(address _strategy, uint256 _amount) internal {
        IStrategy(_strategy).withdraw(_amount);
    }

    function _loadStrategies(address[] memory _strategies, uint256[] memory _ratios) internal {
        if (_strategies.length != _ratios.length) revert StrategyManager__InvalidLength();

        uint256 totalRatio;
        uint256 length = _strategies.length;
        for (uint256 i; i < length;) {
            if (IStrategy(_strategies[i]).manager() != address(this)) revert StrategyManager__InvalidManager();

            strategies.add(_strategies[i]);
            ratios[_strategies[i]] = _ratios[i];
            totalRatio = totalRatio + _ratios[i];

            unchecked {
                i++;
            }
        }

        if (totalRatio > ONE_HUNDRED_PERCENT) revert StrategyManager__InvalidPercentage();
    }

    function _setStrategies(address[] memory _strategies, uint256[] memory _ratios) internal {
        // reset old strategies ratio
        uint256 oldLength = strategies.length();
        for (uint256 i; i < oldLength; i++) {
            ratios[strategies.at(i)] = 0;
        }

        // load new strategies
        _loadStrategies(_strategies, _ratios);
    }

    function _clearStrategy(address _strategy, bool _isRebase) internal {
        IStrategy(_strategy).clear();

        if (!_isRebase) {
            _repayToVault();
        }
    }

    function _destoryStrategy(address _strategy) internal {
        if (!_couldDestroyStrategy(_strategy)) revert StrategyManager__StillActive(_strategy);

        strategies.remove(_strategy);

        _repayToVault();
    }

    function _couldDestroyStrategy(address _strategy) internal view returns (bool status) {
        return ratios[_strategy] == 0 && IStrategy(_strategy).getAllValue() < 1e4;
    }

    // [View Functions]

    function getStrategyValue(address _strategy) public view returns (uint256 _value) {
        return IStrategy(_strategy).getAllValue();
    }

    function getStrategyValidValue(address _strategy) public view returns (uint256 _value) {
        return IStrategy(_strategy).getInvestedValue();
    }

    function getStrategyPendingValue(address _strategy) public view returns (uint256 _value) {
        return IStrategy(_strategy).getPendingValue();
    }

    function getAllStrategiesValue() public view returns (uint256 _value) {
        uint256 length = strategies.length();
        for (uint256 i; i < length;) {
            _value = _value + getStrategyValue(strategies.at(i));
            unchecked {
                i++;
            }
        }
    }

    function getAllStrategyValidValue() public view returns (uint256 _value) {
        uint256 length = strategies.length();
        for (uint256 i; i < length;) {
            _value = _value + getStrategyValidValue(strategies.at(i));
            unchecked {
                i++;
            }
        }
    }

    function getAllStrategyPendingValue() public view returns (uint256 _value) {
        uint256 length = strategies.length();
        for (uint256 i; i < length;) {
            _value = _value + getStrategyPendingValue(strategies.at(i));
            unchecked {
                i++;
            }
        }
    }

    function getStrategies() public view returns (address[] memory addrs, uint256[] memory portions) {
        uint256 length = strategies.length();

        addrs = new address[](length);
        portions = new uint256[](length);

        for (uint256 i; i < length;) {
            address addr = strategies.at(i);
            addrs[i] = addr;
            portions[i] = ratios[addr];

            unchecked {
                i++;
            }
        }
    }

    receive() external payable {}
}
