// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC4626.sol

import {ReentrancyGuard} from "oz/utils/ReentrancyGuard.sol";
import {Ownable} from "oz/access/Ownable.sol";
import {TransferHelper} from "v3-periphery/libraries/TransferHelper.sol";
import {IReal} from "./interface/IReal.sol";
import {IMinter} from "./interface/IMinter.sol";
import {IAssetsVault} from "./interface/IAssetsVault.sol";
import {IStrategyManager} from "./interface/IStrategyManager.sol";
import {ShareMath} from "./libraries/ShareMath.sol";

error RealVault__NotReady();
error RealVault__InvalidAmount();
error RealVault__ZeroAddress();
error RealVault__WithdrawInstantly();
error RealVault__NoRequestFound();
error RealVault__NotProposal();
error RealVault__ExceedBalance();
error RealVault__WaitInQueue();
error RealVault__ExceedRequestedAmount(uint256 requestedAmount, uint256 actualAmount);
error RealVault__ExceedWithdrawAmount();
error RealVault__ExceedMaxFeeRate(uint256 _feeRate);
error RealVault__MinimumRebaseInterval(uint256 minInterval);

contract RealVault is ReentrancyGuard, Ownable {
    uint256 internal constant MULTIPLIER = 10 ** 18;
    uint256 internal constant ONE_HUNDRED_PERCENT = 1000_000;
    uint256 internal constant MAXMIUM_FEE_RATE = ONE_HUNDRED_PERCENT / 20; // 5%
    uint256 internal constant MINIMUM_REBASE_INTERVAL = 60 * 60; // 1hour

    uint256 public rebaseTimeInterval = 24 * 60 * 60; // 1 day
    uint256 public rebaseTime;

    address public immutable minter;
    address public immutable real;
    address payable public immutable assetsVault;
    address payable public immutable strategyManager;

    address public proposal;
    address public feeRecipient;

    uint256 public latestRoundID;
    uint256 public withdrawFeeRate;

    uint256 public withdrawableAmountInPast;
    uint256 public withdrawingSharesInPast;
    uint256 public withdrawingSharesInRound;

    /// @notice On every round's close, the pricePerShare value of an real token is stored
    /// This is used to determine the number of shares to be returned
    /// to a user at the time of minting
    mapping(uint256 => uint256) public roundPricePerShare;
    mapping(uint256 => uint256) public settlementTime;
    mapping(address => WithdrawReceipt) public userReceipts;

    struct WithdrawReceipt {
        uint256 withdrawRound;
        uint256 withdrawShares;
        uint256 withdrawableAmount;
    }

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event InitiateWithdraw(address indexed account, uint256 shares, uint256 round);
    event CancelWithdraw(address indexed account, uint256 amount, uint256 round);
    event Withdrawn(address indexed account, uint256 amount, uint256 round);
    event WithdrawnFromStrategy(address indexed account, uint256 amount, uint256 actualAmount, uint256 round);
    event RollToNextRound(uint256 round, uint256 vaultIn, uint256 vaultOut, uint256 sharePrice);
    event StragetyAdded(address strategy);
    event StragetyDestroyed(address strategy);
    event StragetyCleared(address strategy);
    event PortfolioConfigUpdated(address[] strategies, uint256[] ratios);
    event FeeCharged(address indexed account, uint256 amount);
    event SetWithdrawFeeRate(uint256 oldRate, uint256 newRate);
    event SetFeeRecipient(address oldAddr, address newAddr);
    event SetRebaseInterval(uint256 interval);

    constructor(
        address _intialOwner,
        address _minter,
        address payable _assetsVault,
        address payable _strategyManager,
        address _proposal
    ) Ownable(_intialOwner) {
        if (
            _minter == address(0) || _proposal == address(0) || _assetsVault == address(0)
                || _strategyManager == address(0)
        ) revert RealVault__ZeroAddress();

        minter = _minter;
        proposal = _proposal;
        assetsVault = _assetsVault;
        strategyManager = _strategyManager;

        real = IMinter(_minter).real();

        withdrawFeeRate = 0;
    }

    modifier onlyProposal() {
        if (proposal != msg.sender) revert RealVault__NotProposal();
        _;
    }

    function deposit() external payable nonReentrant returns (uint256 mintAmount) {
        mintAmount = _depositFor(msg.sender, msg.sender, msg.value);
    }

    function depositFor(address receiver) external payable nonReentrant returns (uint256 mintAmount) {
        mintAmount = _depositFor(msg.sender, receiver, msg.value);
    }

    function requestWithdraw(uint256 _shares) external nonReentrant {
        if (_shares == 0) revert RealVault__InvalidAmount();

        uint256 _latestRoundID = latestRoundID;

        if (_latestRoundID == 0) revert RealVault__WithdrawInstantly();

        IReal realToken = IReal(real);
        IMinter realEthMinter = IMinter(minter);

        if (realToken.balanceOf(msg.sender) < _shares) revert RealVault__ExceedBalance();

        TransferHelper.safeTransferFrom(real, msg.sender, address(this), _shares);

        withdrawingSharesInRound = withdrawingSharesInRound + _shares;

        WithdrawReceipt storage receipt = userReceipts[msg.sender];

        if (receipt.withdrawRound == _latestRoundID) {
            receipt.withdrawShares = receipt.withdrawShares + _shares;
        } else if (receipt.withdrawRound == 0) {
            receipt.withdrawShares = _shares;
            receipt.withdrawRound = _latestRoundID;
        } else {
            // Withdraw previous round share first
            uint256 withdrawAmount =
                ShareMath.sharesToAsset(receipt.withdrawShares, roundPricePerShare[receipt.withdrawRound]);

            realEthMinter.burn(address(this), receipt.withdrawShares);
            withdrawingSharesInPast = withdrawingSharesInPast - receipt.withdrawShares;

            receipt.withdrawShares = _shares;
            receipt.withdrawableAmount = receipt.withdrawableAmount + withdrawAmount;
            receipt.withdrawRound = _latestRoundID;
        }

        emit InitiateWithdraw(msg.sender, _shares, _latestRoundID);
    }

    function cancelWithdraw(uint256 _shares) external nonReentrant {
        if (_shares == 0) revert RealVault__InvalidAmount();

        WithdrawReceipt storage receipt = userReceipts[msg.sender];

        uint256 _latestRoundID = latestRoundID;

        if (receipt.withdrawRound != _latestRoundID) revert RealVault__NoRequestFound();
        if (_shares > receipt.withdrawShares) revert RealVault__ExceedRequestedAmount(_shares, receipt.withdrawShares);

        receipt.withdrawShares = receipt.withdrawShares - _shares;

        TransferHelper.safeTransfer(real, msg.sender, _shares);

        if (receipt.withdrawShares == 0) {
            receipt.withdrawRound = 0;
        }

        withdrawingSharesInRound = withdrawingSharesInRound - _shares;

        emit CancelWithdraw(msg.sender, _shares, _latestRoundID);
    }

    function instantWithdraw(uint256 _amount, uint256 _shares)
        external
        payable
        nonReentrant
        returns (uint256 actualWithdrawn)
    {
        if (_amount == 0 && _shares == 0) revert RealVault__InvalidAmount();

        IAssetsVault aVault = IAssetsVault(assetsVault);
        IMinter realEthMinter = IMinter(minter);

        uint256 _latestRoundID = latestRoundID;
        (uint256 idleAmount,) = getVaultAvailableAmount();

        if (_amount != 0) {
            WithdrawReceipt storage receipt = userReceipts[msg.sender];

            if (receipt.withdrawRound != _latestRoundID && receipt.withdrawRound != 0) {
                // Withdraw previous round share first
                uint256 withdrawAmount =
                    ShareMath.sharesToAsset(receipt.withdrawShares, roundPricePerShare[receipt.withdrawRound]);

                realEthMinter.burn(address(this), receipt.withdrawShares);

                withdrawingSharesInPast = withdrawingSharesInPast - receipt.withdrawShares;
                receipt.withdrawShares = 0;
                receipt.withdrawableAmount = receipt.withdrawableAmount + withdrawAmount;
                receipt.withdrawRound = 0;
            }

            if (receipt.withdrawableAmount < _amount) revert RealVault__ExceedWithdrawAmount();

            receipt.withdrawableAmount = receipt.withdrawableAmount - _amount;
            withdrawableAmountInPast = withdrawableAmountInPast - _amount;
            actualWithdrawn = _amount;

            emit Withdrawn(msg.sender, _amount, _latestRoundID);
        }

        if (_shares != 0) {
            uint256 sharePrice;

            if (_latestRoundID == 0) {
                sharePrice = MULTIPLIER;
            } else {
                uint256 currSharePrice = currentSharePrice();
                uint256 latestSharePrice = roundPricePerShare[_latestRoundID - 1];

                sharePrice = latestSharePrice < currSharePrice ? latestSharePrice : currSharePrice;
            }

            uint256 ethAmount = ShareMath.sharesToAsset(_shares, sharePrice);

            realEthMinter.burn(msg.sender, _shares);

            if (ethAmount <= idleAmount) {
                actualWithdrawn = actualWithdrawn + ethAmount;

                emit Withdrawn(msg.sender, ethAmount, _latestRoundID);
            } else {
                actualWithdrawn = actualWithdrawn + idleAmount;
                ethAmount = ethAmount - idleAmount;

                IStrategyManager manager = IStrategyManager(strategyManager);
                uint256 actualAmount = manager.forceWithdraw(ethAmount);

                actualWithdrawn = actualWithdrawn + actualAmount;

                emit WithdrawnFromStrategy(msg.sender, ethAmount, actualAmount, _latestRoundID);
            }
        }

        if (aVault.getBalance() < actualWithdrawn) revert RealVault__WaitInQueue();

        uint256 withFee;
        if (withdrawFeeRate != 0) {
            withFee = (actualWithdrawn * withdrawFeeRate) / ONE_HUNDRED_PERCENT;
            aVault.withdraw(feeRecipient, withFee);

            emit FeeCharged(msg.sender, withFee);
        }
        aVault.withdraw(msg.sender, actualWithdrawn - withFee);
    }

    function rollToNextRound() external {
        if (block.timestamp < rebaseTime + rebaseTimeInterval) revert RealVault__NotReady();

        IStrategyManager manager = IStrategyManager(strategyManager);
        IAssetsVault aVault = IAssetsVault(assetsVault);
        uint256 previewSharePrice = currentSharePrice();

        uint256 vaultBalance = aVault.getBalance();
        uint256 amountToWithdraw = ShareMath.sharesToAsset(withdrawingSharesInRound, previewSharePrice);
        uint256 amountVaultNeed = withdrawableAmountInPast + amountToWithdraw;
        uint256 allPendingValue = manager.getAllStrategyPendingValue();

        uint256 vaultIn;
        uint256 vaultOut;

        if (vaultBalance > amountVaultNeed) {
            vaultIn = vaultBalance - amountVaultNeed;
        } else if (vaultBalance + allPendingValue < amountVaultNeed) {
            vaultOut = amountVaultNeed - vaultBalance - allPendingValue;
        }

        manager.rebaseStrategies(vaultIn, vaultOut);

        uint256 _latestRoundID = latestRoundID;
        uint256 newSharePrice = currentSharePrice();
        roundPricePerShare[_latestRoundID] = previewSharePrice < newSharePrice ? previewSharePrice : newSharePrice;

        settlementTime[_latestRoundID] = block.timestamp;
        latestRoundID = _latestRoundID + 1;

        withdrawingSharesInPast = withdrawingSharesInPast + withdrawingSharesInRound;
        withdrawableAmountInPast =
            withdrawableAmountInPast + ShareMath.sharesToAsset(withdrawingSharesInRound, newSharePrice);
        withdrawingSharesInRound = 0;
        rebaseTime = block.timestamp;

        emit RollToNextRound(latestRoundID, vaultIn, vaultOut, newSharePrice);
    }

    function migrateVault(address _vault) external onlyProposal {
        IMinter(minter).setNewVault(_vault);
        IAssetsVault(assetsVault).setNewVault(_vault);
        IStrategyManager(strategyManager).setNewVault(_vault);
    }

    function addStrategy(address _strategy) external onlyProposal {
        IStrategyManager manager = IStrategyManager(strategyManager);

        manager.addStrategy(_strategy);
        emit StragetyAdded(_strategy);
    }

    function destroyStrategy(address _strategy) external onlyOwner {
        IStrategyManager manager = IStrategyManager(strategyManager);

        manager.destroyStrategy(_strategy);
        emit StragetyDestroyed(_strategy);
    }

    function clearStrategy(address _strategy) external onlyOwner {
        IStrategyManager manager = IStrategyManager(strategyManager);

        manager.clearStrategy(_strategy);
        emit StragetyCleared(_strategy);
    }

    function updatePortfolioConfig(address[] memory _strategies, uint256[] memory _ratios) external onlyProposal {
        IStrategyManager manager = IStrategyManager(strategyManager);

        manager.setStrategies(_strategies, _ratios);

        emit PortfolioConfigUpdated(_strategies, _ratios);
    }

    function updateProposal(address _proposal) external onlyProposal {
        if (_proposal == address(0)) revert RealVault__ZeroAddress();
        proposal = _proposal;
    }

    // [INTERNAL FUNCTIONS]

    function _depositFor(address caller, address receiver, uint256 assets) internal returns (uint256 mintAmount) {
        if (assets == 0) revert RealVault__InvalidAmount();

        mintAmount = previewDeposit(assets); // shares amount to be minted

        IAssetsVault(assetsVault).deposit{value: address(this).balance}();
        IMinter(minter).mint(receiver, mintAmount);

        emit Deposit(caller, receiver, assets, mintAmount);
    }

    // [SETTER FUNCTIONS]

    function setWithdrawFeeRate(uint256 _withdrawFeeRate) external onlyOwner {
        if (_withdrawFeeRate > MAXMIUM_FEE_RATE) revert RealVault__ExceedMaxFeeRate(_withdrawFeeRate);

        emit SetWithdrawFeeRate(withdrawFeeRate, _withdrawFeeRate);

        withdrawFeeRate = _withdrawFeeRate;
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient == address(0)) revert RealVault__ZeroAddress();

        emit SetFeeRecipient(feeRecipient, _feeRecipient);

        feeRecipient = _feeRecipient;
    }

    function setRebaseInterval(uint256 _interval) external onlyOwner {
        if (_interval > MINIMUM_REBASE_INTERVAL) revert RealVault__MinimumRebaseInterval(MINIMUM_REBASE_INTERVAL);
        rebaseTimeInterval = _interval;
        emit SetRebaseInterval(rebaseTimeInterval);
    }

    // [VIEW FUNCTIONS]

    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        uint256 sharePrice;
        uint256 currSharePrice = currentSharePrice();
        if (latestRoundID == 0) {
            sharePrice = MULTIPLIER;
        } else {
            uint256 latestSharePrice = roundPricePerShare[latestRoundID - 1];
            sharePrice = latestSharePrice > currSharePrice ? latestSharePrice : currSharePrice;
        }

        return (assets * MULTIPLIER) / sharePrice;
    }

    /// @dev send a certain amount of shares to the blackhole address when the protocol accepts
    /// deposits for the first time. https://github.com/OpenZeppelin/openzeppelin-contracts/issues/3706
    function currentSharePrice() public view returns (uint256 price) {
        IReal realToken = IReal(real);
        uint256 totalReal = realToken.totalSupply();
        if (latestRoundID == 0 || totalReal == 0 || totalReal == withdrawingSharesInPast) {
            return MULTIPLIER;
        }

        uint256 etherAmount = IAssetsVault(assetsVault).getBalance()
            + IStrategyManager(strategyManager).getAllStrategiesValue() - withdrawableAmountInPast;
        uint256 activeShare = totalReal - withdrawingSharesInPast;
        return (etherAmount * MULTIPLIER) / activeShare;
    }

    function getVaultAvailableAmount() public view returns (uint256 idleAmount, uint256 investedAmount) {
        IAssetsVault vault = IAssetsVault(assetsVault);

        if (vault.getBalance() > withdrawableAmountInPast) {
            idleAmount = vault.getBalance() - withdrawableAmountInPast;
        }

        investedAmount = IStrategyManager(strategyManager).getAllStrategyValidValue();
    }

    receive() external payable {}
}
