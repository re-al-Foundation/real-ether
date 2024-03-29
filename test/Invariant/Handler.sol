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
    uint256 public currentRound = 1;

    uint256 public ghost_ethInVault;
    uint256 public ghost_nonZeroDeposits;
    uint256 public ghost_TokenInRealVault;
    uint256 public ghost_amountInStrategy;
    uint256 public ghost_withdrawRequested;
    uint256 public ghost_updatePastRequest;
    uint256 public ghost_tokenBurntInRealVault;
    uint256 public ghost_zeroWithdrawRequested;
    uint256 public ghost_cancelWithdrawRequested;
    uint256 public ghost_withdrawingSharesInPast;
    uint256 public ghost_instantWithdrawRequested;
    uint256 public ghost_withdrawingSharesInRound;
    uint256 public ghost_withdrawableAmountInPast;
    uint256 public ghost_zeroCancelWithdrawRequested;
    uint256 public ghost_zeroInstantWithdrawRequested;
    uint256 public ghost_zeroDepositsOrContractAddress;

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
        bool isContract = currentActor.code.length > 0;
        amount = bound(amount, 0, type(uint160).max);

        if (!isContract && amount != 0) {
            ghost_nonZeroDeposits++;
            deal(currentActor, amount);

            vm.startPrank(currentActor);
            realVault.deposit{value: amount}();

            vm.stopPrank();
            ghost_ethInVault += amount;
        } else {
            ghost_zeroDepositsOrContractAddress++;
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
                ghost_updatePastRequest++;
                ghost_withdrawingSharesInPast -= withdrawShares;

                cancel[currentActor].round = currentRound;
                ghost_tokenBurntInRealVault += withdrawShares;
            }

            ghost_TokenInRealVault += shares;
            ghost_withdrawingSharesInRound += shares;

            cancel[currentActor].upForCancelation = shares;

            cancel[currentActor].round = currentRound;
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
                cancel[currentActor].upForCancelation -= shares;

                if (cancel[currentActor].upForCancelation == 0) {
                    cancel[currentActor].hasRequestedWithdrawal == false;
                    cancel[currentActor].round = 0;
                }
            }
        } else {
            ghost_zeroCancelWithdrawRequested++;
        }
    }

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
        currentRound++;

        ghost_withdrawableAmountInPast +=
            ShareMath.sharesToAsset(ghost_withdrawingSharesInRound, realVault.currentSharePrice());

        ghost_withdrawingSharesInPast += ghost_withdrawingSharesInRound;
        ghost_withdrawingSharesInRound = 0;
    }

    function instantWithdraw(uint256 actorSeed, uint256 amount, bool shares)
        public
        useActor(actorSeed)
        countCall("instantWithdraw")
    {
        if (shares) {
            amount = bound(amount, 0, real.balanceOf(currentActor));
            uint256 currSharePrice = realVault.currentSharePrice();
            uint256 latestSharePrice = realVault.roundPricePerShare(currentRound - 1);

            uint256 sharePrice = latestSharePrice < currSharePrice ? latestSharePrice : currSharePrice;
            uint256 amountToWithdraw = ShareMath.sharesToAsset(amount, sharePrice);

            if (amount != 0 && amountToWithdraw <= ghost_ethInVault) {
                ghost_instantWithdrawRequested++;
                vm.startPrank(currentActor);
                uint256 actualWithdrawn = realVault.instantWithdraw(0, amount);

                vm.stopPrank();
                uint256 idelAmount;

                if (ghost_ethInVault > ghost_withdrawableAmountInPast) {
                    idelAmount = ghost_ethInVault - ghost_withdrawableAmountInPast;
                }

                if (actualWithdrawn <= idelAmount) {
                    ghost_ethInVault -= actualWithdrawn;
                } else {
                    uint256 am = actualWithdrawn - idelAmount;
                    ghost_ethInVault -= idelAmount;
                    ghost_amountInStrategy -= am;
                }
            } else {
                ghost_zeroInstantWithdrawRequested++;
            }
        } else {
            (uint256 withdrawRound, uint256 withdrawShares, uint256 withdrawableAmount) =
                realVault.userReceipts(currentActor);

            uint256 withdrawAmount;
            uint256 amountToWithdraw;

            if (withdrawRound != currentRound && withdrawRound != 0) {
                amountToWithdraw = ShareMath.sharesToAsset(withdrawShares, realVault.roundPricePerShare(withdrawRound));
                withdrawAmount = withdrawableAmount + amountToWithdraw;

                if (withdrawAmount <= ghost_ethInVault) {
                    ghost_withdrawingSharesInPast -= withdrawShares;
                    ghost_tokenBurntInRealVault += withdrawShares;
                }
            }

            if (withdrawAmount <= ghost_ethInVault && withdrawAmount != 0) {
                ghost_instantWithdrawRequested++;
                vm.startPrank(currentActor);
                realVault.instantWithdraw(withdrawAmount, 0);
                vm.stopPrank();

                ghost_withdrawableAmountInPast -= withdrawAmount;
                ghost_ethInVault -= withdrawAmount;
            } else {
                ghost_zeroInstantWithdrawRequested++;
            }
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
        console.log("Roll To Next Round", calls["rollToNextRound"]);
        console.log("Request Withdraw(s)", calls["requestWithdraw"]);
        console.log("Instant Withdraw(s)", calls["instantWithdraw"]);
        console.log("-------------------");
        console.log("Zero Calls:");
        console.log("-------------------");
        console.log("Zero Deposits / Is ContractAddress(s):", ghost_zeroDepositsOrContractAddress);
        console.log("Zero Cancel(s):", ghost_zeroCancelWithdrawRequested);
        console.log("Zero Request((s):", ghost_zeroWithdrawRequested);
        console.log("Zero Instant((s):", ghost_zeroInstantWithdrawRequested);
        console.log("-------------------");
        console.log("Actual Calls:");
        console.log("-------------------");
        console.log("Deposit(s):", ghost_nonZeroDeposits);
        console.log("Cancel Withdraw((s):", ghost_cancelWithdrawRequested);
        console.log("Request Withdraw((s):", ghost_withdrawRequested);
        console.log("Instant Withdraw(s):", ghost_instantWithdrawRequested);
        console.log("ghost_updatePastRequest(s):", ghost_updatePastRequest);
    }

    receive() external payable {}
}
