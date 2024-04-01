// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

import {EnumerableSet} from "oz/utils/structs/EnumerableSet.sol";
import {TransferHelper} from "v3-periphery/libraries/TransferHelper.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";
import {IAssetsVault} from "./interfaces/IAssetsVault.sol";

error StrategyManager__ZeroAddress();
error StrategyManager__ZeroStrategy();
error StrategyManager__InvalidLength();
error StrategyManager__InvalidRatio();
error StrategyManager__InvalidPercentage();
error StrategyManager__NotVault();
error StrategyManager__InvalidManager();
error StrategyManager__MinAllocation(uint256 minAllocation);
error StrategyManager__StillActive(address strategy);
error StrategyManager__AlreadyExist(address strategy);

/**
 * @title Strategy Manager
 * @author Mavvverick
 * @notice The Vault Strategy Manager is a critical component of the RealETH ecosystem,
 * responsible for managing asset yield routes and strategies within the Vault. It facilitates
 * efficient allocation of assets to various yield-generating opportunities while mitigating risks.
 * Through a whitelist mechanism, the Strategy Manager enables the selection and configuration of diverse yield strategies,
 * including staking pools, restaking protocols, and more. Each strategy route within the manager is isolated to prevent
 * cross-contamination and safeguard the security of RealETH assets. Users can interact with the Strategy Manager
 * to select and activate specific strategies, optimizing yield generation for their deposited assets.
 * Additionally, the Strategy Manager enhances the flexibility and adaptability of the RealETH ecosystem,
 * allowing for seamless integration of new yield opportunities and improvements over time.
 */
contract StrategyManager {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct StrategySnapshot {
        address strategy;
        bool isDeposit;
        uint256 amount;
    }

    uint256 internal cumulativeRatio;
    uint256 internal constant ONE = 1;
    uint256 internal constant DUST = 10_000;
    uint256 internal constant MINIMUM_ALLOCATION = 1_0000; // 1%
    uint256 internal constant ONE_HUNDRED_PERCENT = 100_0000; // 100%

    address public realVault;
    address payable public immutable assetsVault;

    EnumerableSet.AddressSet private strategies;

    mapping(address => uint256) public ratios;

    event VaultUpdated(address indexed oldRealVault, address newRealVault);

    /**
     * @param _realVault Address of the RealVault contract.
     * @param _assetsVault Address of the assets vault.
     * @param _strategies Array of strategy addresses.
     * @param _ratios Array of allocation ratios corresponding to each strategy.
     * Requirements:
     * - The assets vault address must not be the zero address.
     * - At least one strategy must be provided.
     * - Each strategy address must not be the zero address.
     */
    constructor(
        address _realVault,
        address payable _assetsVault,
        address[] memory _strategies,
        uint256[] memory _ratios
    ) {
        if (_assetsVault == address(0) || _realVault == address(0)) revert StrategyManager__ZeroAddress();

        uint256 length = _strategies.length;
        if (length == 0) revert StrategyManager__ZeroStrategy();

        for (uint256 i; i < length;) {
            if (_strategies[i] == address(0)) revert StrategyManager__ZeroAddress();
            unchecked {
                i++;
            }
        }

        realVault = _realVault;
        assetsVault = _assetsVault;

        _loadStrategies(_strategies, _ratios);
    }

    /**
     * @dev Modifier to restrict access to only the RealVault contract.
     * Requirements:
     * - The caller must be the RealVault contract.
     */
    modifier onlyVault() {
        _checkVault();
        _;
    }

    // [SETTER Functions]

    /**
     * @dev Sets a new RealVault contract address.
     * @param _vault The address of the new RealVault contract.
     * Requirements:
     * - The caller must be the current RealVault contract.
     */
    function setNewVault(address _vault) external onlyVault {
        if (_vault == address(0)) revert StrategyManager__ZeroAddress();
        emit VaultUpdated(realVault, _vault);
        realVault = _vault;
    }

    /**
     * @dev Sets new strategies and their allocation ratios.
     * @param _strategies Array of new strategy addresses.
     * @param _ratios Array of new allocation ratios corresponding to each strategy.
     * Requirements:
     * - The caller must be the current RealVault contract.
     */
    function setStrategies(address[] memory _strategies, uint256[] memory _ratios) external onlyVault {
        _setStrategies(_strategies, _ratios);
    }

    /**
     * @dev Adds a new strategy.
     * @param _strategy Address of the new strategy.
     * Requirements:
     * - The caller must be the current RealVault contract.
     * - The strategy must not already exist.
     */
    function addStrategy(address _strategy) external onlyVault {
        if (strategies.contains(_strategy)) revert StrategyManager__AlreadyExist(_strategy);
        strategies.add(_strategy);
    }

    /**
     * @dev Destroys a strategy.
     * @param _strategy Address of the strategy to destroy.
     * Requirements:
     * - The caller must be the current RealVault contract.
     * - The strategy must be inactive and eligible for destruction.
     */
    function destroyStrategy(address _strategy) external onlyVault {
        _destoryStrategy(_strategy);
    }

    /**
     * @notice Clears the total value from the given strategy.
     * @param _strategy The address of the strategy to clear.
     */
    function clearStrategy(address _strategy) external onlyVault {
        _clearStrategy(_strategy, false);
    }

    /**
     * @notice Force withdraws the specified amount from strategies.
     * @param _amount The amount to withdraw.
     * @return actualAmount The actual amount withdrawn.
     */
    function forceWithdraw(uint256 _amount) external onlyVault returns (uint256 actualAmount) {
        uint256 balanceBeforeRepay = address(this).balance;

        if (balanceBeforeRepay >= _amount) {
            _repayToVault();

            actualAmount = balanceBeforeRepay;
        } else {
            uint256 amount_;
            unchecked {
                amount_ = _amount - balanceBeforeRepay;
            }
            actualAmount = _forceWithdraw(amount_) + balanceBeforeRepay;
        }
    }

    /**
     * @notice Executes rebase for strategies.
     * update the existing balance in the strategies
     */
    function onlyRebaseStrategies() external {
        _rebase(0, 0);
    }

    /**
     * @notice Rebases strategies.
     * @param _in The amount to deposit.
     * @param _out The amount to withdraw.
     */
    function rebaseStrategies(uint256 _in, uint256 _out) external payable onlyVault {
        _rebase(_in, _out);
    }

    // [Internal Functions]

    /**
     * @dev Checks whether the caller is the real vault.
     */
    function _checkVault() internal view {
        if (realVault != msg.sender) revert StrategyManager__NotVault();
    }

    /**
     * @dev Rebalances strategies based on the given input and output amounts.
     * update the invested balances accross all strategies
     * @param _in The amount to deposit.
     * @param _out The amount to withdraw.
     */
    function _rebase(uint256 _in, uint256 _out) internal {
        require(_in == 0 || _out == 0, "only deposit or withdraw");

        if (_in != 0) {
            IAssetsVault(assetsVault).withdraw(address(this), _in);
        }

        (uint256 total, uint256[] memory strategiesValue) = getTotalInvestedValue();
        if (total < _out) {
            total = 0;
        } else {
            total = total + _in - _out;
        }

        uint256 length = strategies.length();
        StrategySnapshot[] memory snapshots = new StrategySnapshot[](length);
        uint256 head;
        uint256 tail = length;

        for (uint256 i; i < length;) {
            address strategy = strategies.at(i);
            uint256 ratio = ratios[strategy];
            if (ratio == 0) {
                _clearStrategy(strategy, true);

                unchecked {
                    i++;
                }

                continue;
            }
            uint256 newPosition = (total * ratio) / ONE_HUNDRED_PERCENT;
            uint256 position = strategiesValue[i];

            if (newPosition < position) {
                unchecked {
                    snapshots[head] =
                        StrategySnapshot({strategy: strategy, isDeposit: false, amount: position - newPosition});
                    head++;
                }
            } else if (newPosition > position) {
                unchecked {
                    tail--;
                    snapshots[tail] =
                        StrategySnapshot({strategy: strategy, isDeposit: true, amount: newPosition - position});
                }
            }

            unchecked {
                i++;
            }
        }

        // update the strategy invested value based on latest position
        for (uint256 i; i < length;) {
            StrategySnapshot memory snapshot = snapshots[i];

            if (snapshot.amount == 0) {
                unchecked {
                    i++;
                }

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

            unchecked {
                i++;
            }
        }

        _repayToVault();
    }

    function _repayToVault() internal {
        if (address(this).balance != 0) {
            TransferHelper.safeTransferETH(assetsVault, address(this).balance);
        }
    }

    /**
     * @dev Force withdraws the specified amount from strategies.
     * withdrawn amount will be returned to the assets vault.
     * @param _amount The amount to withdraw.
     * @return actualAmount The actual amount withdrawn.
     */
    function _forceWithdraw(uint256 _amount) internal returns (uint256 actualAmount) {
        uint256 length = strategies.length();
        for (uint256 i; i < length;) {
            address strategy = strategies.at(i);

            uint256 withAmount = (_amount * ratios[strategy]) / cumulativeRatio;

            if (withAmount != 0) {
                actualAmount = IStrategy(strategy).instantWithdraw(withAmount) + actualAmount;
            }

            unchecked {
                i++;
            }
        }

        _repayToVault();
    }

    /**
     * @dev Deposits the specified amount to the strategy.
     * @param _strategy The address of the strategy.
     * @param _amount The amount to deposit.
     */
    function _depositToStrategy(address _strategy, uint256 _amount) internal {
        IStrategy(_strategy).deposit{value: _amount}();
    }

    /**
     * @dev Withdraws the specified amount from the strategy.
     * @param _strategy The address of the strategy.
     * @param _amount The amount to withdraw.
     */
    function _withdrawFromStrategy(address _strategy, uint256 _amount) internal {
        IStrategy(_strategy).withdraw(_amount);
    }

    /**
     * @dev Loads the strategies with the provided addresses and funds allocation ratios.
     * @param _strategies The array of strategy addresses.
     * @param _ratios The array of allocation ratios.
     */
    function _loadStrategies(address[] memory _strategies, uint256[] memory _ratios) internal {
        if (_strategies.length != _ratios.length) revert StrategyManager__InvalidLength();

        uint256 totalRatio;
        uint256 length = _strategies.length;
        for (uint256 i; i < length;) {
            if (IStrategy(_strategies[i]).manager() != address(this)) revert StrategyManager__InvalidManager();
            // if (_ratios[i] < MINIMUM_ALLOCATION) revert StrategyManager__MinAllocation(MINIMUM_ALLOCATION);

            strategies.add(_strategies[i]);

            if (ratios[_strategies[i]] == 0) {
                ratios[_strategies[i]] = _ratios[i];
                totalRatio = totalRatio + _ratios[i];
            }

            unchecked {
                i++;
            }
        }

        cumulativeRatio = totalRatio;
        if (totalRatio > ONE_HUNDRED_PERCENT) revert StrategyManager__InvalidPercentage();
    }

    /**
     * @dev Sets the strategies with the provided addresses and allocation ratios.
     * @param _strategies The array of strategy addresses.
     * @param _ratios The array of allocation ratios.
     */
    function _setStrategies(address[] memory _strategies, uint256[] memory _ratios) internal {
        // reset old strategies ratio
        uint256 oldLength = strategies.length();
        for (uint256 i; i < oldLength;) {
            ratios[strategies.at(i)] = 0;

            unchecked {
                i++;
            }
        }

        // load new strategies
        _loadStrategies(_strategies, _ratios);
    }

    /**
     * @dev Clears the specified strategy.
     * @param _strategy The address of the strategy to clear.
     * @param _isRebase A boolean indicating whether it's a rebase operation.
     */
    function _clearStrategy(address _strategy, bool _isRebase) internal {
        IStrategy(_strategy).clear();

        if (!_isRebase) {
            _repayToVault();
        }
    }

    /**
     * @dev Destroys the specified strategy if it meets certain conditions.
     * @param _strategy The address of the strategy to destroy.
     */
    function _destoryStrategy(address _strategy) internal {
        if (!_couldDestroyStrategy(_strategy)) revert StrategyManager__StillActive(_strategy);

        strategies.remove(_strategy);

        _repayToVault();
    }

    /**
     * @dev Checks whether the specified strategy can be destroyed.
     * @param _strategy The address of the strategy to check.
     * @return status A boolean indicating whether the strategy can be destroyed.
     */
    function _couldDestroyStrategy(address _strategy) internal view returns (bool status) {
        return ratios[_strategy] == 0 && IStrategy(_strategy).getTotalValue() < DUST;
    }

    // [View Functions]

    /**
     * @notice Gets the total value of asset in a strategy.
     * @param _strategy The address of the strategy.
     * @return _value The total value of the strategy.
     */
    function getStrategyValue(address _strategy) public view returns (uint256 _value) {
        return IStrategy(_strategy).getTotalValue();
    }

    /**
     * @notice Gets the invested value of a strategy.
     * @param _strategy The address of the strategy.
     * @return _value The valid value of the strategy.
     */
    function getStrategyInvestedValue(address _strategy) public view returns (uint256 _value) {
        return IStrategy(_strategy).getInvestedValue();
    }

    /**
     * @notice Gets the pending asset value of a strategy.
     * @param _strategy The address of the strategy.
     * @return _value The pending value of the strategy.
     */
    function getStrategyPendingValue(address _strategy) public view returns (uint256 _value) {
        return IStrategy(_strategy).getPendingValue();
    }

    /**
     * @notice Gets the total asset value of all strategies.
     * @return _value The total value of all strategies.
     */
    function getAllStrategiesValue() external view returns (uint256 _value) {
        uint256 length = strategies.length();
        for (uint256 i; i < length;) {
            _value = _value + getStrategyValue(strategies.at(i));
            unchecked {
                i++;
            }
        }
    }

    /**
     * @notice Gets the total invested asset value of all strategies.
     * @return _value The total valid value of all strategies.
     */
    function getTotalInvestedValue() public view returns (uint256 _value, uint256[] memory strategiesValue) {
        uint256 length = strategies.length();
        strategiesValue = new uint256[](length);

        for (uint256 i; i < length;) {
            uint256 value_ = getStrategyInvestedValue(strategies.at(i));
            strategiesValue[i] = value_;
            _value = _value + value_;
            unchecked {
                i++;
            }
        }
    }

    /**
     * @notice Gets the total pending asset value of all strategies.
     * @return _value The total pending value of all strategies.
     */
    function getAllStrategyPendingValue() external view returns (uint256 _value) {
        uint256 length = strategies.length();
        for (uint256 i; i < length;) {
            _value = _value + getStrategyPendingValue(strategies.at(i));
            unchecked {
                i++;
            }
        }
    }

    /**
     * @notice Gets all strategies and their allocation ratios.
     * @return addrs The array of strategy addresses.
     * @return allocations The array of allocation ratios.
     */
    function getStrategies() external view returns (address[] memory addrs, uint256[] memory allocations) {
        uint256 length = strategies.length();

        addrs = new address[](length);
        allocations = new uint256[](length);

        for (uint256 i; i < length;) {
            address addr = strategies.at(i);
            addrs[i] = addr;
            allocations[i] = ratios[addr];

            unchecked {
                i++;
            }
        }
    }

    receive() external payable {}
}
