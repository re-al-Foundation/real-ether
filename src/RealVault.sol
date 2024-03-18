// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC4626.sol

import {ReentrancyGuard} from "oz/utils/ReentrancyGuard.sol";
import {Ownable} from "oz/access/Ownable.sol";
import {TransferHelper} from "v3-periphery/libraries/TransferHelper.sol";
import {IReal} from "./interfaces/IReal.sol";
import {IMinter} from "./interfaces/IMinter.sol";
import {IAssetsVault} from "./interfaces/IAssetsVault.sol";
import {IStrategyManager} from "./interfaces/IStrategyManager.sol";
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

/**
 * @title Real Ether Vault (reETH)
 * @author Mavvverick
 * @notice The Real Vault (reETH) is responsible for managing deposit, withdrawal, and settlement processes
 * using ERC4626 standard. Users can deposit ETH into the Vault, where it is held securely until settlement,
 * thereby participating in the yield generation process and receiving rewards as reETH token holders.
 * Upon settlement, funds are deployed to the underlying strategy pool for yield generation.The Vault ensures
 * the security of deposited assets and facilitates seamless interactions within the Real Network ecosystem.
 * Users can interact with the Vault to deposit, withdraw, and settle RealETH tokens, contributing to the
 * stability and growth of the platform. Additionally, the Vault's architecture provides flexibility for
 * future yield staking /re-staking strategy and optimizations, ensuring its continued effectiveness in
 * managing assets and supporting the Real Network infrastructure.
 */
contract RealVault is ReentrancyGuard, Ownable {
    uint256 internal constant ONE = 1;
    uint256 internal constant MULTIPLIER = 10 ** 18;
    uint256 internal constant ONE_HUNDRED_PERCENT = 1_000_000;
    uint256 internal constant MAXMIUM_FEE_RATE = ONE_HUNDRED_PERCENT / 100; // 1%
    uint256 internal constant MINIMUM_REBASE_INTERVAL = 60 * 60; // 1hour
    uint256 internal constant NUMBER_OF_DEAD_SHARES = 10 ** 15;

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
    event RollToNextRound(uint256 indexed round, uint256 vaultIn, uint256 vaultOut, uint256 sharePrice);
    event VaultMigrated(address indexed oldVault, address newVault);
    event StragetyAdded(address indexed strategy);
    event StragetyDestroyed(address indexed strategy);
    event StragetyCleared(address indexed strategy);
    event InvestmentPortfolioUpdated(address[] indexed strategies, uint256[] indexed ratios);
    event FeeCharged(address indexed account, uint256 amount);
    event SetWithdrawFeeRate(uint256 indexed oldRate, uint256 newRate);
    event SetFeeRecipient(address indexed oldAddr, address newAddr);
    event SetRebaseInterval(uint256 indexed interval);

    /**
     * @param _intialOwner Address of the initial owner of the contract.
     * @param _minter Address of the minter contract.
     * @param _assetsVault Address of the assets vault contract.
     * @param _strategyManager Address of the strategy manager contract.
     * @param _proposal Address of the proposal contract.
     */
    constructor(
        address _intialOwner,
        address _minter,
        address payable _assetsVault,
        address payable _strategyManager,
        address _proposal
    ) Ownable(_intialOwner) {
        if (_proposal == address(0) || _assetsVault == address(0) || _strategyManager == address(0)) {
            revert RealVault__ZeroAddress();
        }

        minter = _minter;
        proposal = _proposal;
        assetsVault = _assetsVault;
        strategyManager = _strategyManager;

        real = IMinter(_minter).real();
        rebaseTime = block.timestamp;

        // mint dead
        // TransferHelper.safeTransferETH(assetsVault, NUMBER_OF_DEAD_SHARES);
        // IMinter(minter).mint(address(0xdead), NUMBER_OF_DEAD_SHARES);
    }

    /**
     * @dev Modifier to restrict access to only the proposal contract.
     */
    modifier onlyProposal() {
        if (proposal != msg.sender) revert RealVault__NotProposal();
        _;
    }

    /**
     * @dev Deposit assets into the RealVault.
     * @return mintAmount The amount of shares minted.
     */
    function deposit() external payable nonReentrant returns (uint256 mintAmount) {
        mintAmount = _depositFor(msg.sender, msg.sender, msg.value);
    }

    /**
     * @dev Deposit assets into the RealVault on behalf of another address.
     * @param receiver Address to receive the minted shares.
     * @return mintAmount The amount of shares minted.
     */
    function depositFor(address receiver) external payable nonReentrant returns (uint256 mintAmount) {
        mintAmount = _depositFor(msg.sender, receiver, msg.value);
    }

    /**
     * @dev Initiate a withdrawal request for a specified number of shares.
     * @param _shares Number of shares to withdraw.
     */
    function requestWithdraw(uint256 _shares) external nonReentrant {
        if (_shares == 0) revert RealVault__InvalidAmount();

        uint256 _latestRoundID = latestRoundID;

        if (_latestRoundID == 0) revert RealVault__WithdrawInstantly();

        IReal realToken = IReal(real);
        IMinter realEthMinter = IMinter(minter);

        if (realToken.balanceOf(msg.sender) < _shares) revert RealVault__ExceedBalance();
        TransferHelper.safeTransferFrom(real, msg.sender, address(this), _shares);

        withdrawingSharesInRound = withdrawingSharesInRound + _shares;
        WithdrawReceipt memory mReceipt = userReceipts[msg.sender];

        if (mReceipt.withdrawRound == _latestRoundID) {
            mReceipt.withdrawShares = mReceipt.withdrawShares + _shares;
        } else if (mReceipt.withdrawRound == 0) {
            mReceipt.withdrawShares = _shares;
            mReceipt.withdrawRound = _latestRoundID;
        } else {
            // Withdraw previous round share first
            mReceipt = _updateUserReceipt(mReceipt, realEthMinter, _shares, _latestRoundID);
        }

        userReceipts[msg.sender] = mReceipt;
        emit InitiateWithdraw(msg.sender, _shares, _latestRoundID);
    }

    /**
     * @dev Cancel a pending withdrawal request.
     * @param _shares Number of shares to cancel the withdrawal for.
     */
    function cancelWithdraw(uint256 _shares) external nonReentrant {
        if (_shares == 0) revert RealVault__InvalidAmount();

        WithdrawReceipt memory mReceipt = userReceipts[msg.sender];
        uint256 _latestRoundID = latestRoundID;

        if (mReceipt.withdrawRound != _latestRoundID) revert RealVault__NoRequestFound();
        if (_shares > mReceipt.withdrawShares) {
            revert RealVault__ExceedRequestedAmount(_shares, mReceipt.withdrawShares);
        }

        unchecked {
            mReceipt.withdrawShares -= _shares;
        }

        TransferHelper.safeTransfer(real, msg.sender, _shares);

        if (mReceipt.withdrawShares == 0) {
            mReceipt.withdrawRound = 0;
        }

        userReceipts[msg.sender] = mReceipt;
        withdrawingSharesInRound = withdrawingSharesInRound - _shares;

        emit CancelWithdraw(msg.sender, _shares, _latestRoundID);
    }

    /**
     * @dev Withdraw assets instantly or after a delay, depending on availability.
     * @param _amount Amount of assets to withdraw.
     * @param _shares Number of shares to withdraw.
     * @return actualWithdrawn The actual amount of assets withdrawn.
     */
    function instantWithdraw(uint256 _amount, uint256 _shares)
        external
        nonReentrant
        returns (uint256 actualWithdrawn)
    {
        if (_amount == 0 && _shares == 0) revert RealVault__InvalidAmount();

        IAssetsVault aVault = IAssetsVault(assetsVault);
        IMinter realEthMinter = IMinter(minter);

        uint256 _latestRoundID = latestRoundID;
        (uint256 idleAmount,) = getVaultAvailableAmount();

        if (_amount != 0) {
            WithdrawReceipt memory mReceipt = userReceipts[msg.sender];

            if (mReceipt.withdrawRound != _latestRoundID && mReceipt.withdrawRound != 0) {
                // Withdraw previous round share first
                mReceipt = _updateUserReceipt(mReceipt, realEthMinter, 0, 0);
            }

            if (mReceipt.withdrawableAmount < _amount) revert RealVault__ExceedWithdrawAmount();

            unchecked {
                mReceipt.withdrawableAmount -= _amount;
            }

            userReceipts[msg.sender] = mReceipt;

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
                uint256 latestSharePrice;

                unchecked {
                    latestSharePrice = roundPricePerShare[_latestRoundID - ONE];
                }
                sharePrice = latestSharePrice < currSharePrice ? latestSharePrice : currSharePrice;
            }

            uint256 ethAmount = ShareMath.sharesToAsset(_shares, sharePrice);

            realEthMinter.burn(msg.sender, _shares);

            if (ethAmount <= idleAmount) {
                actualWithdrawn = actualWithdrawn + ethAmount;

                emit Withdrawn(msg.sender, ethAmount, _latestRoundID);
            } else {
                actualWithdrawn = actualWithdrawn + idleAmount;

                unchecked {
                    ethAmount = ethAmount - idleAmount;
                }

                IStrategyManager manager = IStrategyManager(strategyManager);
                // if strategy sells the LSD token on the decentralized exchange (DEX),
                // deducting swap fees from the requested amount.
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
        unchecked {
            aVault.withdraw(msg.sender, actualWithdrawn - withFee);
        }
    }

    /**
     * @dev Transition to the next round, managing vault balances and share prices.
     */
    function rollToNextRound() external nonReentrant {
        if (block.timestamp < rebaseTime + rebaseTimeInterval) revert RealVault__NotReady();
        rebaseTime = block.timestamp;

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
            unchecked {
                vaultIn = vaultBalance - amountVaultNeed;
            }
        } else if (vaultBalance + allPendingValue < amountVaultNeed) {
            unchecked {
                vaultOut = amountVaultNeed - vaultBalance - allPendingValue;
            }
        }

        manager.rebaseStrategies(vaultIn, vaultOut);

        uint256 _latestRoundID = latestRoundID;
        uint256 newSharePrice = currentSharePrice();
        roundPricePerShare[_latestRoundID] = previewSharePrice < newSharePrice ? previewSharePrice : newSharePrice;

        settlementTime[_latestRoundID] = block.timestamp;
        unchecked {
            latestRoundID = _latestRoundID + ONE;
        }

        withdrawingSharesInPast = withdrawingSharesInPast + withdrawingSharesInRound;
        withdrawableAmountInPast =
            withdrawableAmountInPast + ShareMath.sharesToAsset(withdrawingSharesInRound, newSharePrice);
        withdrawingSharesInRound = 0;
        emit RollToNextRound(latestRoundID, vaultIn, vaultOut, newSharePrice);
    }

    /**
     * @dev Migrate the vault to a new contract.
     * @param _vault Address of the new vault.
     */
    function migrateVault(address _vault) external onlyProposal {
        IMinter(minter).setNewVault(_vault);
        IAssetsVault(assetsVault).setNewVault(_vault);
        IStrategyManager(strategyManager).setNewVault(_vault);

        // migrate pending withdrawals by transferring any real token balance held by the contract
        // to the new implementation which should manually migrate userReceipts entries.
        IReal realToken = IReal(real);
        uint256 balance = realToken.balanceOf(address(this));
        if (balance > 0) TransferHelper.safeTransfer(real, _vault, balance);

        emit VaultMigrated(address(this), _vault);
    }

    /**
     * @dev Add a new strategy to the strategy manager.
     * @param _strategy Address of the new strategy.
     */
    function addStrategy(address _strategy) external onlyProposal {
        IStrategyManager manager = IStrategyManager(strategyManager);

        manager.addStrategy(_strategy);
        emit StragetyAdded(_strategy);
    }

    /**
     * @dev Destroy a strategy from the strategy manager.
     * Funds must be returned to the asset valut from the strategy before destroyin the strategy.
     * @param _strategy Address of the strategy to destroy.
     */
    function destroyStrategy(address _strategy) external onlyOwner {
        IStrategyManager manager = IStrategyManager(strategyManager);

        manager.destroyStrategy(_strategy);
        emit StragetyDestroyed(_strategy);
    }

    /**
     * @dev Clear a strategy from the vault.
     * Funds will be returned to the asset valut from the strategy
     * @param _strategy Address of the strategy to clear.
     */
    function clearStrategy(address _strategy) external onlyOwner {
        IStrategyManager manager = IStrategyManager(strategyManager);

        manager.clearStrategy(_strategy);
        emit StragetyCleared(_strategy);
    }

    /**
     * @dev Update the investment portfolio of the vault.
     * Set the strategy and potfolio allocation ratio in the manager.
     * Previous strategy ratios will set to zero before applying the new allocation ratio.
     * @param _strategies Array of addresses representing the new strategies.
     * @param _ratios Array of ratios corresponding to the strategies.
     */
    function updateInvestmentPortfolio(address[] memory _strategies, uint256[] memory _ratios) external onlyProposal {
        IStrategyManager manager = IStrategyManager(strategyManager);

        manager.setStrategies(_strategies, _ratios);

        emit InvestmentPortfolioUpdated(_strategies, _ratios);
    }

    /**
     * @dev Update the address of the proposal contract or multisig.
     * @param _proposal Address of the new proposal contract or multisig.
     */
    function updateProposal(address _proposal) external onlyProposal {
        if (_proposal == address(0)) revert RealVault__ZeroAddress();
        proposal = _proposal;
    }

    // [INTERNAL FUNCTIONS]
    function _depositFor(address caller, address receiver, uint256 assets) internal returns (uint256 mintAmount) {
        if (assets == 0) revert RealVault__InvalidAmount();

        mintAmount = previewDeposit(address(this).balance); // shares amount to be minted
        IAssetsVault(assetsVault).deposit{value: address(this).balance}();
        IMinter(minter).mint(receiver, mintAmount);
        emit Deposit(caller, receiver, assets, mintAmount);
    }

    // [SETTER FUNCTIONS]

    /**
     * @dev Sets the withdrawal fee rate.
     * @param _withdrawFeeRate The new withdrawal fee rate.
     * Requirements:
     * - The new fee rate must not exceed the maximum fee rate.
     */
    function setWithdrawFeeRate(uint256 _withdrawFeeRate) external onlyOwner {
        if (_withdrawFeeRate > MAXMIUM_FEE_RATE) revert RealVault__ExceedMaxFeeRate(_withdrawFeeRate);

        emit SetWithdrawFeeRate(withdrawFeeRate, _withdrawFeeRate);

        withdrawFeeRate = _withdrawFeeRate;
    }

    /**
     * @dev Sets the fee recipient address.
     * @param _feeRecipient The new fee recipient address.
     * Requirements:
     * - The new fee recipient address must not be the zero address.
     */
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient == address(0)) revert RealVault__ZeroAddress();

        emit SetFeeRecipient(feeRecipient, _feeRecipient);

        feeRecipient = _feeRecipient;
    }

    /**
     * @dev Sets the rebase interval.
     * @param _interval The new rebase interval.
     * Requirements:
     * - The new interval must not be less than the minimum rebase interval.
     */
    function setRebaseInterval(uint256 _interval) external onlyOwner {
        if (_interval > MINIMUM_REBASE_INTERVAL) revert RealVault__MinimumRebaseInterval(MINIMUM_REBASE_INTERVAL);
        rebaseTimeInterval = _interval;
        emit SetRebaseInterval(rebaseTimeInterval);
    }

    // [VIEW FUNCTIONS]

    /**
     * @dev Calculates the number of shares corresponding to a given asset amount.
     * @param assets The amount of assets to calculate shares for.
     * @return The number of shares.
     */
    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        uint256 sharePrice;
        if (latestRoundID == 0) {
            sharePrice = MULTIPLIER;
        } else {
            uint256 currSharePrice = currentSharePrice();
            uint256 latestSharePrice;
            unchecked {
                latestSharePrice = roundPricePerShare[latestRoundID - ONE];
            }
            sharePrice = latestSharePrice > currSharePrice ? latestSharePrice : currSharePrice;
        }

        return (assets * MULTIPLIER) / sharePrice;
    }

    /**
     * @dev Retrieves the current share price.
     * Send a certain amount of shares to the blackhole address when the protocol accepts
     * deposits for the first time. https://github.com/OpenZeppelin/openzeppelin-contracts/issues/3706
     * @return price current share price.
     */
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

    /**
     * @dev Retrieves the available amount in the vault.
     * @return idleAmount idle amount amount in the vault.
     * @return investedAmount invested amount in the vault.
     */
    function getVaultAvailableAmount() public view returns (uint256 idleAmount, uint256 investedAmount) {
        IAssetsVault vault = IAssetsVault(assetsVault);

        if (vault.getBalance() > withdrawableAmountInPast) {
            unchecked {
                idleAmount = vault.getBalance() - withdrawableAmountInPast;
            }
        }

        investedAmount = IStrategyManager(strategyManager).getAllStrategyInvestedValue();
    }

    function _updateUserReceipt(
        WithdrawReceipt memory mReceipt,
        IMinter realEthMinter,
        uint256 _shares,
        uint256 _latestRoundID
    ) private returns (WithdrawReceipt memory) {
        uint256 withdrawAmount =
            ShareMath.sharesToAsset(mReceipt.withdrawShares, roundPricePerShare[mReceipt.withdrawRound]);
        console2.log(withdrawAmount);

        realEthMinter.burn(address(this), mReceipt.withdrawShares);
        withdrawingSharesInPast = withdrawingSharesInPast - mReceipt.withdrawShares;

        mReceipt.withdrawShares = _shares;
        mReceipt.withdrawableAmount = mReceipt.withdrawableAmount + withdrawAmount;

        mReceipt.withdrawRound = _latestRoundID;
        return mReceipt;
    }

    receive() external payable {}
}
