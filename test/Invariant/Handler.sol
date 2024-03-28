// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import {Real} from "src/token/Real.sol";
import {RealVault} from "src/RealVault.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {console2 as console} from "forge-std/Test.sol";
import {ShareMath} from "src/libraries/ShareMath.sol";
import {AddressSet, LibAddressSet} from "./LibAddressSet.sol";

interface IERC20EXTT {
    function balanceOf(address from) external returns (uint256);
}

contract Handler is CommonBase, StdCheats, StdUtils {
    using LibAddressSet for AddressSet;

    Real public real;
    RealVault public realVault;
    AddressSet internal _actors;

    struct Cancel {
        bool canceled;
        uint256 round;
        uint256 upForCancelation;
        bool hasRequestedWithdrawal;
    }

    mapping(address => uint256) ids;
    mapping(bytes32 => uint256) public calls;
    mapping(address => Cancel) public cancel;

    address currentActor;

    uint256 public ghost_ethSum;
    uint256 public ghost_zeroMint;
    uint256 public ghost_shareSum;
    uint256 public ghost_actualMint;
    uint256 public ghost_zeroDeposits;
    uint256 public ghost_ethInVault;
    uint256 public ghost_amountInStrategy;
    uint256 public ghost_withdrawRequested;
    uint256 public ghost_TokenInRealVault;
    uint256 public ghost_zeroWithdrawRequested;
    uint256 public ghost_cancelWithdrawRequested;
    uint256 public ghost_withdrawingSharesInRound;
    uint256 public ghost_withdrawableAmountInPast;
    uint256 public ghost_zeroCancelWithdrawRequested;
    uint256 public ghost_withdrawingSharesInPast;
    uint256 public ghost_burnt;
    uint256 public ghost_updateWith;

    constructor(RealVault _realVault, Real _real) {
        real = _real;
        realVault = _realVault;
    }

    modifier createActor() {
        currentActor = msg.sender;
        _actors.add(currentActor);
        _;
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = _actors.rand(actorIndexSeed);
        _;
    }

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    function deposit(uint256 amount) public createActor countCall("deposit") {
        amount = bound(amount, 0, type(uint160).max);

        if (currentActor != address(realVault) || currentActor != makeAccount("deadShares").addr) {
            if (amount != 0) {
                deal(currentActor, amount);

                vm.startPrank(currentActor);
                uint256 shares = realVault.deposit{value: amount}();
                vm.stopPrank();

                ghost_ethSum += amount;
                ghost_shareSum += shares;
                ghost_ethInVault += amount;
            } else {
                ghost_zeroDeposits++;
            }
        }
    }

    function requestWithdraw(uint256 shares, uint256 actorSeed)
        public
        useActor(actorSeed)
        countCall("requestWithdraw")
    {
        shares = bound(shares, 0, real.balanceOf(currentActor));

        (uint256 withdrawRound, uint256 withdrawShares,) = realVault.userReceipts(currentActor);

        if (shares != 0) {
            ghost_withdrawRequested++;
            vm.startPrank(currentActor);

            real.approve(address(realVault), shares);
            realVault.requestWithdraw(shares);

            vm.stopPrank();
            if (withdrawRound != 0 && withdrawRound != currentRound) {
                ghost_updateWith++;

                ghost_withdrawingSharesInPast -= withdrawShares;
                cancel[currentActor].round = currentRound;

                ghost_burnt += withdrawShares;
            }
            ghost_TokenInRealVault += shares;
            ghost_withdrawingSharesInRound += shares;

            cancel[currentActor].round = currentRound;
            cancel[currentActor].upForCancelation = shares;
            cancel[currentActor].hasRequestedWithdrawal = true;
        } else {
            ghost_zeroWithdrawRequested++;
        }
    }

    function cancelWithdraw(uint256 shares, uint256 actorSeed) public useActor(actorSeed) countCall("cancelWithdraw") {
        if (cancel[currentActor].hasRequestedWithdrawal && cancel[currentActor].round == currentRound) {
            shares = bound(shares, 0, cancel[currentActor].upForCancelation);

            if (shares != 0) {
                ghost_cancelWithdrawRequested++;
                vm.startPrank(currentActor);
                realVault.cancelWithdraw(shares);

                vm.stopPrank();
                ghost_TokenInRealVault -= shares;
                ghost_withdrawingSharesInRound -= shares;
                cancel[currentActor].upForCancelation = cancel[currentActor].upForCancelation - shares;

                if (cancel[currentActor].upForCancelation == 0) {
                    cancel[currentActor].hasRequestedWithdrawal == false;
                    cancel[currentActor].round = 0;
                }
            }
        } else {
            ghost_zeroCancelWithdrawRequested++;
        }
    }

    uint256 public currentRound = 1;

    function rollToNextRound() public countCall("rollToNextRound") {
        if (realVault.rebaseTime() + realVault.rebaseTimeInterval() > block.timestamp) {
            vm.warp(realVault.rebaseTime() + realVault.rebaseTimeInterval());
        }

        uint256 amountToWithdraw =
            ShareMath.sharesToAsset(ghost_withdrawingSharesInRound, realVault.currentSharePrice());

        uint256 amountVaultNeed = ghost_withdrawableAmountInPast + amountToWithdraw;

        if (ghost_ethInVault > amountVaultNeed) {
            uint256 amount = ghost_ethInVault - amountVaultNeed;
            ghost_amountInStrategy += amount;
            ghost_ethInVault -= amount;
        } else if (ghost_ethInVault < amountVaultNeed) {
            uint256 amount = amountVaultNeed - ghost_ethInVault;
            ghost_amountInStrategy -= amount;
            ghost_ethInVault += amount;
        }

        realVault.rollToNextRound();

        ghost_withdrawableAmountInPast +=
            ShareMath.sharesToAsset(ghost_withdrawingSharesInRound, realVault.currentSharePrice());

        ghost_withdrawingSharesInPast += ghost_withdrawingSharesInRound;
        ghost_withdrawingSharesInRound = 0;

        currentRound++;
    }

    function instantWithdraw(uint256 actorSeed, uint256 amount)
        public
        useActor(actorSeed)
        countCall("instantWithdraw")
    {
        // amount = bound(amount, 0, real.balanceOf(currentActor));
        // uint256 currSharePrice = realVault.currentSharePrice();
        // uint256 latestSharePrice = realVault.roundPricePerShare(currentRound - 1);

        // uint256 sharePrice = latestSharePrice < currSharePrice ? latestSharePrice : currSharePrice;
        // uint256 amountToWithdraw = ShareMath.sharesToAsset(amount, sharePrice);

        // if (amount != 0 && amountToWithdraw <= ghost_ethInVault) {
        //     vm.startPrank(currentActor);
        //     uint256 actualWithdrawn = realVault.instantWithdraw(0, amount);
        //     ghost_ethInVault -= amountToWithdraw;
        //     vm.stopPrank();

        //     console.log(actualWithdrawn, amountToWithdraw, "amountToWithdraw");
        // }

        (uint256 withdrawRound, uint256 withdrawShares, uint256 withdrawableAmount) =
            realVault.userReceipts(currentActor);

        uint256 amountToWithdraw;

        if (withdrawRound != currentRound && withdrawRound != 0) {
            amountToWithdraw = ShareMath.sharesToAsset(withdrawShares, realVault.roundPricePerShare(withdrawRound));

            if (withdrawableAmount + amountToWithdraw <= ghost_ethInVault) {
                ghost_withdrawingSharesInPast -= withdrawShares;
                ghost_burnt += withdrawShares;
            }
        }

        uint256 withdrawAmount = withdrawableAmount + amountToWithdraw;

        if (withdrawAmount <= ghost_ethInVault && withdrawAmount != 0) {
            vm.startPrank(currentActor);
            realVault.instantWithdraw(withdrawAmount, 0);

            ghost_withdrawableAmountInPast -= withdrawAmount;
            ghost_ethInVault -= withdrawAmount;
            vm.stopPrank();
        }
    }

    function reduceActors(uint256 acc, function(uint256, address) external returns (uint256) func)
        public
        returns (uint256)
    {
        return _actors.reduce(acc, func);
    }

    function forEachActor(function(address) external func) public {
        return _actors.forEach(func);
    }

    function actors() external view returns (address[] memory) {
        return _actors.addrs;
    }

    function callSummary() external view {
        console.log("-------------------");
        console.log("  ");
        console.log("Call summary:");
        console.log("  ");
        console.log("-------------------");
        console.log("Deposit(s)", calls["deposit"]);
        console.log("Cancel Withdraw(s)", calls["cancelWithdraw"]);
        console.log("Request Withdraw(s)", calls["requestWithdraw"]);

        console.log("Mint(s):", ghost_zeroWithdrawRequested, ghost_withdrawRequested);
        console.log("ghost_updateWith(s):", ghost_updateWith);
        console.log("Cancel(s):", ghost_zeroCancelWithdrawRequested, ghost_cancelWithdrawRequested);
    }

    // function callSummary() external view {
    //     console.log("-------------------");
    //     console.log("  ");
    //     console.log("Call summary:");
    //     console.log("  ");
    //     console.log("-------------------");
    //     console.log("Call Count:");
    //     console.log("-------------------");
    //     console.log("Deposit(s)", calls["deposit"]);
    //     console.log("Claim(s)", calls["claim"]);
    //     console.log("Set Reward(s)", calls["set reward"]);
    //     console.log("-------------------");
    //     console.log("Zero Calls:");
    //     console.log("-------------------");
    //     console.log("Mint(s):", ghost_zeroMint);
    //     console.log("-------------------");
    //     console.log("-------------------");
    //     console.log("Actual Calls:");
    //     console.log("-------------------");
    //     console.log("Mint(s):", ghost_actualMint);
    // }

    function __mint(address addr, uint256 amount) internal {}
    receive() external payable {}
}
