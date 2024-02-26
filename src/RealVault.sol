// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC4626.sol

import {ReentrancyGuard} from "oz/utils/ReentrancyGuard.sol";
import {Ownable} from "oz/access/Ownable.sol";

import "./utils/Error.sol";

import {RealETH} from "./token/RealETH.sol";
import {Minter} from "./token/Minter.sol";
import {IAssetsVault} from "./interface/IAssetsVault.sol";
import {IStrategyManager} from "./interface/IStrategyManager.sol";

error InvestmentManager__InvalidParam(uint256 percentage);

contract RealVault is ReentrancyGuard, Ownable {
    uint256 internal constant MULTIPLIER = 10 ** 18;
    uint256 internal constant ONE_HUNDRED_PERCENT = 1000_000;

    address public immutable minter;
    address public immutable realETH;
    address payable public immutable assetsVault;
    address payable public immutable strategyManager;

    address public proposal;

    uint256 public latestRoundID;

    uint256 public withdrawableAmountInPast;
    uint256 public withdrawingSharesInPast;
    uint256 public withdrawingSharesInRound;

    /// @notice On every round's close, the pricePerShare value of an realETH token is stored
    /// This is used to determine the number of shares to be returned
    /// to a user at the time of minting
    mapping(uint256 => uint256) public roundPricePerShare;
    mapping(address => WithdrawReceipt) public userReceipts;

    struct WithdrawReceipt {
        uint256 withdrawRound;
        uint256 withdrawShares;
        uint256 withdrawableAmount;
    }

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    constructor(address _intialOwner, address _minter, address payable _assetsVault, address _proposal)
        Ownable(_intialOwner)
    {
        require(_minter != address(0) && _proposal != address(0) && _assetsVault != address(0), "ZERO ADDRESS");

        minter = _minter;
        proposal = _proposal;
        assetsVault = _assetsVault;

        realETH = Minter(_minter).realETH();
    }

    modifier onlyProposal() {
        require(proposal == msg.sender, "not proposal");
        _;
    }

    function deposit() external payable nonReentrant returns (uint256 mintAmount) {
        mintAmount = _depositFor(msg.sender, msg.sender, msg.value);
    }

    function depositFor(address receiver) external payable nonReentrant returns (uint256 mintAmount) {
        mintAmount = _depositFor(msg.sender, receiver, msg.value);
    }

    function requestWithdraw() external payable nonReentrant returns (uint256 amount) {}

    function redeem() external payable nonReentrant returns (uint256 amount) {}

    function rollToNextRound() external {}

    function migrateVault(address _vault) external onlyProposal {
        Minter(minter).setNewVault(_vault);
        IAssetsVault(assetsVault).setNewVault(_vault);
        IStrategyManager(strategyManager).setNewVault(_vault);
    }

    // [INTERNAL FUNCTIONS]
    function _depositFor(address caller, address receiver, uint256 assets) internal returns (uint256 mintAmount) {
        if (assets == 0) revert RealETH__InvalidAmount();

        mintAmount = previewDeposit(assets); // shares amount to be minted
        IAssetsVault(assetsVault).deposit{value: address(this).balance}();
        Minter(minter).mint(receiver, mintAmount);

        emit Deposit(caller, receiver, assets, mintAmount);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal {}

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

    function currentSharePrice() public view returns (uint256 price) {
        RealETH realETHToken = RealETH(realETH);
        uint256 totalRealETH = realETHToken.totalSupply();
        if (latestRoundID == 0 || totalRealETH == 0 || totalRealETH == withdrawingSharesInPast) {
            return MULTIPLIER;
        }

        uint256 etherAmount = IAssetsVault(assetsVault).getBalance()
            + IStrategyManager(strategyManager).getAllStrategiesValue() - withdrawableAmountInPast;
        uint256 activeShare = totalRealETH - withdrawingSharesInPast;
        return (etherAmount * MULTIPLIER) / activeShare;
    }

    receive() external payable {}
}
