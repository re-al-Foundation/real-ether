// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

import {Real} from "src/token/Real.sol";
import {Minter} from "src/token/Minter.sol";
import {RealVault} from "src/RealVault.sol";
import {Test, console2} from "forge-std/Test.sol";
import {ShareMath} from "src/libraries/ShareMath.sol";
import {StrategyManager} from "src/StrategyManager.sol";
import {AssetsVault} from "src/AssetsVault.sol";
import {TestEthStrategy} from "src/mock/TestEthStrategy.sol";
import {TestEthStrategy2} from "src/mock/TestEthStrategy2.sol";
import {TestEthClaimableStrategy} from "src/mock/TestEthClaimableStrategy.sol";

contract VaultTest is Test {
    error OwnableUnauthorizedAccount(address);

    uint256 PRECISION = 10 ** 18;
    uint256 MIN_SHARES = 1_00;

    Real public real;
    Minter public minter;
    RealVault public realVault;
    StrategyManager public strategyManager;
    AssetsVault public assetsVault;
    TestEthStrategy public s1;
    TestEthStrategy2 public s;

    address minterAddress;
    address realVaultAddress;
    address strategyManagerAddress;
    address assetVaultAddress;

    Account public user;
    Account public user2;
    Account public deployer;
    Account public owner;
    Account public proposal;

    uint256 epoch0;
    mapping(uint256 => uint256) public bal;

    function setUp() public {
        user = makeAccount("user");
        user = makeAccount("user");
        user2 = makeAccount("user2");
        deployer = makeAccount("deployer");
        owner = makeAccount("owner");
        proposal = makeAccount("proposal");

        minterAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        realVaultAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 2);
        assetVaultAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 3);
        strategyManagerAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 5);

        deal(realVaultAddress, 0.001 ether);
        real = new Real(minterAddress);
        minter = new Minter(address(real), payable(realVaultAddress));
        realVault = new RealVault(
            address(owner.addr),
            minterAddress,
            payable(assetVaultAddress),
            payable(strategyManagerAddress),
            address(proposal.addr)
        );
        assetsVault = new AssetsVault(realVaultAddress, strategyManagerAddress);
        address[] memory strategies = new address[](1);
        uint256[] memory ratios = new uint256[](1);

        s1 = new TestEthStrategy(payable(strategyManagerAddress), "Mock Eth Investment");
        strategies[0] = address(s1);
        ratios[0] = 1000_000; // 1e6
        strategyManager = new StrategyManager(address(realVault), payable(assetVaultAddress), strategies, ratios);

        vm.startPrank(address(0xdead));
        realVault.instantWithdraw(0, 0.001 ether);
        vm.stopPrank();

        epoch0 = block.timestamp;
    }

    function test_assetVaultdeposit() public {
        deal(address(realVault), 1 ether);
        vm.startPrank(address(realVault));
        assetsVault.deposit{value: 1 ether}();
        vm.stopPrank();
        assertEq(address(assetsVault).balance, 1 ether);
    }

    function test_deposit() public {
        deal(user.addr, 10 ether);
        vm.startPrank(user.addr);
        realVault.deposit{value: 1 ether}();
        vm.stopPrank();

        assertEq(address(realVault).balance, 0 ether);
        assertEq(address(assetsVault).balance, 1 ether);
        assertEq(real.balanceOf(user.addr), 1 ether);
    }

    function test_depositTo0xdead() public {
        deal(user.addr, 10 ether);
        vm.startPrank(user.addr);
        realVault.depositFor{value: 1 ether}(address(0xdead));
        vm.stopPrank();

        assertEq(address(realVault).balance, 0 ether);
        assertEq(address(assetsVault).balance, 1 ether);
        assertEq(real.balanceOf(user.addr), 0 ether);
    }

    function test_requestWithdrawFail() public {
        deal(user.addr, 10 ether);
        vm.startPrank(user.addr);

        // Deposit in Round#0
        realVault.deposit{value: 1 ether}();

        // Request Withraw in Round#0
        uint256 bal = real.balanceOf(user.addr);
        vm.expectRevert(abi.encodeWithSelector(RealVault.RealVault__WithdrawInstantly.selector));

        realVault.requestWithdraw(bal);
        vm.stopPrank();
    }

    function test_dust() public {
        uint256 amount = 1 ether;
        deal(address(s1), 0.1 ether);
        deal(address(7), amount);

        vm.startPrank(address(7));
        uint256 shares = realVault.deposit{value: amount}();

        bal[0] = shares;
        vm.stopPrank();

        vm.warp(epoch0 + realVault.rebaseTimeInterval());
        realVault.rollToNextRound();
        deal(address(2), 20 ether);

        for (uint256 i = 1; i < 20; i++) {
            vm.startPrank(address(2));
            shares = realVault.deposit{value: amount}();

            bal[i] = shares;
            vm.stopPrank();
        }

        vm.warp(block.timestamp + realVault.rebaseTimeInterval());
        realVault.rollToNextRound();

        for (uint256 i = 1; i < 20; i++) {
            vm.startPrank(address(2));
            amount = bal[i];

            real.approve(address(realVault), amount);
            realVault.requestWithdraw(amount);

            vm.warp(block.timestamp + realVault.rebaseTimeInterval());
            realVault.rollToNextRound();

            realVault.instantWithdraw(amount, 0);
            vm.stopPrank();
        }

        assertGt(realVault.withdrawAmountDust(), 0);
    }

    function test_fuzzRequestWithdraw(address userAddress, uint256 amount) public {
        amount = bound(amount, MIN_SHARES, type(uint160).max);
        if (amount != 0 && userAddress != address(0)) {
            deal(userAddress, amount);
            vm.startPrank(userAddress);

            // Deposit in Round#0
            realVault.deposit{value: amount}();
            vm.warp(epoch0 + realVault.rebaseTimeInterval());

            // roll epoch to next round
            realVault.rollToNextRound();

            // Request Withraw in Round#0
            uint256 bal = real.balanceOf(userAddress);
            uint256 contractBal = real.balanceOf(address(realVault));

            uint256 withdrawingSharesInRound = realVault.withdrawingSharesInRound();
            real.approve(address(realVault), bal);

            assertEq(bal, amount);
            (uint256 withdrawRound, uint256 withdrawShares,) = realVault.userReceipts(userAddress);

            assertEq(withdrawRound, 0);
            assertEq(withdrawShares, 0);

            realVault.requestWithdraw(bal);
            (withdrawRound, withdrawShares,) = realVault.userReceipts(userAddress);

            assertEq(withdrawingSharesInRound + bal, realVault.withdrawingSharesInRound());
            assertEq(withdrawRound, 1);

            assertEq(withdrawShares, bal);
            assertEq(real.balanceOf(userAddress), 0);

            assertEq(real.balanceOf(address(realVault)), contractBal + bal);
            vm.stopPrank();
        }
    }

    function test_fuzzRequesMultiplytWithdrawsInSameRound(address userAddress, uint256 amount) public {
        amount = bound(amount, MIN_SHARES, type(uint160).max);

        if (amount != 0 && userAddress != address(0)) {
            deal(userAddress, amount * 2);
            vm.startPrank(userAddress);

            // Deposit in Round#0
            realVault.deposit{value: amount * 2}();
            vm.warp(epoch0 + realVault.rebaseTimeInterval());

            // roll epoch to next round
            realVault.rollToNextRound();
            uint256 bal = real.balanceOf(userAddress);

            uint256 contractBal = real.balanceOf(address(realVault));
            uint256 withdrawingSharesInRound = realVault.withdrawingSharesInRound();

            real.approve(address(realVault), bal);
            realVault.requestWithdraw(amount);

            (uint256 withdrawRound, uint256 withdrawShares,) = realVault.userReceipts(userAddress);
            assertEq(withdrawRound, 1);

            assertEq(withdrawShares, amount);
            assertEq(real.balanceOf(userAddress), amount);

            assertEq(real.balanceOf(address(realVault)), contractBal + amount);
            realVault.requestWithdraw(amount);

            (withdrawRound, withdrawShares,) = realVault.userReceipts(userAddress);
            assertEq(withdrawRound, 1);

            assertEq(withdrawShares, bal);
            assertEq(withdrawingSharesInRound + bal, realVault.withdrawingSharesInRound());

            assertEq(real.balanceOf(userAddress), 0);
            vm.stopPrank();
        }
    }

    function test_fuzzRequesMultiplytWithdrawsInDifferentRounds(address userAddress, uint256 amount) public {
        amount = bound(amount, MIN_SHARES, type(uint160).max);

        if (amount != 0 && userAddress != address(0)) {
            deal(userAddress, amount * 2);
            vm.startPrank(userAddress);

            // Deposit in Round#0
            realVault.deposit{value: amount * 2}();
            vm.warp(epoch0 + realVault.rebaseTimeInterval());

            // roll epoch to next round
            realVault.rollToNextRound();
            uint256 bal = real.balanceOf(userAddress);

            uint256 contractBal = real.balanceOf(address(realVault));
            uint256 withdrawingSharesInRound = realVault.withdrawingSharesInRound();

            real.approve(address(realVault), bal);
            realVault.requestWithdraw(amount);

            (uint256 withdrawRound, uint256 withdrawShares, uint256 withdrawableAmount) =
                realVault.userReceipts(userAddress);
            assertEq(withdrawingSharesInRound + amount, realVault.withdrawingSharesInRound());

            vm.warp(block.timestamp + realVault.rebaseTimeInterval());
            realVault.rollToNextRound();

            assertEq(0, realVault.withdrawingSharesInRound());

            realVault.requestWithdraw(amount);
            uint256 withdrawAmount =
                ShareMath.sharesToAsset(withdrawShares, realVault.roundPricePerShare(withdrawRound));

            (withdrawRound, withdrawShares, withdrawableAmount) = realVault.userReceipts(userAddress);
            assertEq(withdrawRound, 2);

            assertEq(withdrawShares, amount);
            assertEq(withdrawableAmount, withdrawAmount);

            assertEq(real.balanceOf(userAddress), 0);
            assertEq(amount, realVault.withdrawingSharesInRound());

            assertEq(real.balanceOf(address(realVault)), contractBal + amount);
            vm.stopPrank();
        }
    }

    function test_fuzzCancelWithdraw(address userAddress, uint256 amount) public {
        amount = bound(amount, MIN_SHARES, type(uint160).max);

        if (amount != 0 && userAddress != address(0)) {
            deal(userAddress, amount);
            vm.startPrank(userAddress);

            // Deposit in Round#0
            realVault.deposit{value: amount}();
            vm.warp(epoch0 + realVault.rebaseTimeInterval());

            realVault.rollToNextRound();
            uint256 bal = real.balanceOf(userAddress);

            uint256 contractBal = real.balanceOf(address(realVault));
            real.approve(address(realVault), bal);

            realVault.requestWithdraw(bal);
            (uint256 withdrawRound, uint256 withdrawShares,) = realVault.userReceipts(userAddress);

            assertEq(withdrawRound, 1);
            assertEq(withdrawShares, bal);

            assertEq(contractBal + bal, real.balanceOf(address(realVault)));
            assertEq(0, real.balanceOf(userAddress));

            assertEq(bal, realVault.withdrawingSharesInRound());
            realVault.cancelWithdraw(bal);

            assertEq(0, realVault.withdrawingSharesInRound());
            (withdrawRound, withdrawShares,) = realVault.userReceipts(userAddress);

            assertEq(withdrawRound, 0);
            assertEq(withdrawShares, 0);

            assertEq(contractBal, real.balanceOf(address(realVault)));
            assertEq(bal, real.balanceOf(userAddress));

            vm.stopPrank();
        }
    }

    function test_fuzzCancelPartOfRequestedWithdraw(address userAddress, uint256 amount) public {
        amount = bound(amount, MIN_SHARES, type(uint160).max);

        if (amount != 0 && userAddress != address(0)) {
            deal(userAddress, amount * 2);
            vm.startPrank(userAddress);

            // Deposit in Round#0
            realVault.deposit{value: amount * 2}();
            vm.warp(epoch0 + realVault.rebaseTimeInterval());

            realVault.rollToNextRound();
            uint256 bal = real.balanceOf(userAddress);

            uint256 contractBal = real.balanceOf(address(realVault));
            real.approve(address(realVault), bal);

            realVault.requestWithdraw(bal);
            (uint256 withdrawRound, uint256 withdrawShares,) = realVault.userReceipts(userAddress);

            realVault.cancelWithdraw(amount);
            assertEq(amount, realVault.withdrawingSharesInRound());

            (withdrawRound, withdrawShares,) = realVault.userReceipts(userAddress);
            assertEq(withdrawRound, 1);

            assertEq(withdrawShares, amount);
            assertEq(contractBal + amount, real.balanceOf(address(realVault)));

            assertEq(amount, real.balanceOf(userAddress));
            vm.stopPrank();
        }
    }

    function test_fuzzInstantWithdrawEthInPastRound(address userAddress, uint256 amount) public {
        amount = bound(amount, MIN_SHARES, type(uint160).max);

        if (amount != 0 && userAddress != address(0)) {
            deal(userAddress, amount);
            vm.startPrank(userAddress);

            // Deposit in Round#0
            realVault.deposit{value: amount}();

            vm.warp(epoch0 + realVault.rebaseTimeInterval());
            realVault.rollToNextRound();

            real.approve(address(realVault), amount);
            realVault.requestWithdraw(amount);

            (uint256 withdrawRound, uint256 withdrawShares, uint256 withdrawableAmount) =
                realVault.userReceipts(userAddress);
            assertEq(withdrawRound, 1);

            assertEq(withdrawShares, amount);
            vm.warp(block.timestamp + realVault.rebaseTimeInterval());

            realVault.rollToNextRound();
            (withdrawRound, withdrawShares,) = realVault.userReceipts(userAddress);

            uint256 withdrawAmount =
                ShareMath.sharesToAsset(withdrawShares, realVault.roundPricePerShare(withdrawRound));
            assertEq(realVault.withdrawableAmountInPast(), withdrawAmount);

            realVault.instantWithdraw(amount, 0);
            vm.stopPrank();

            (withdrawRound, withdrawShares, withdrawableAmount) = realVault.userReceipts(userAddress);
            assertEq(withdrawRound, 0);

            assertEq(withdrawShares, 0);
            assertEq(withdrawableAmount, 0);

            assertEq(real.balanceOf(userAddress), 0 ether);
            assertEq(address(assetsVault).balance, 0 ether);
            assertEq(userAddress.balance, amount);
        }
    }

    function test_round0InstantWithdraw() public {
        deal(user.addr, 2 ether);
        vm.startPrank(user.addr);

        // Deposit in Round#0
        realVault.deposit{value: 1 ether}();

        assertEq(address(assetsVault).balance, 1 ether);
        assertEq(user.addr.balance, 1 ether);

        // Instant withdraw in Round#0
        realVault.instantWithdraw(0, real.balanceOf(user.addr));
        vm.stopPrank();

        assertEq(real.balanceOf(user.addr), 0 ether);
        assertEq(address(assetsVault).balance, 0 ether);
        assertEq(user.addr.balance, 2 ether);
    }

    function test_rollToNextRound() public {
        deal(user.addr, 2 ether);
        vm.startPrank(user.addr);

        // Deposit in Round#0
        realVault.deposit{value: 1 ether}();

        // increment the time to the next round
        vm.warp(epoch0 + realVault.rebaseTimeInterval());

        // roll epoch to next round
        realVault.rollToNextRound();
        vm.stopPrank();

        assertEq(address(assetsVault).balance, 0 ether);
        assertEq(strategyManager.getAllStrategiesValue(), 1 ether);
    }

    function test_SharePriceIncrement() public {
        deal(user.addr, 2 ether);
        deal(user2.addr, 2 ether);

        vm.startPrank(user.addr);
        // deposit in Round#0 by user1 at 1 pps
        realVault.deposit{value: 1 ether}();

        // increment the time to the next round
        vm.warp(epoch0 + realVault.rebaseTimeInterval());

        // roll epoch to next round
        realVault.rollToNextRound();

        // increase the balance to update the vault pps 909090909090909090
        deal(address(s1), 1.1 ether);
        vm.stopPrank();

        // deposit in Round#1 by user2 at 909090909090909090 pps
        vm.startPrank(user2.addr);
        realVault.deposit{value: 1 ether}();
        vm.stopPrank();

        assertEq(address(assetsVault).balance, 1 ether);
        assertEq(strategyManager.getAllStrategiesValue(), 1.1 ether);

        assertEq(real.balanceOf(user.addr), 1 ether);
        assertEq(real.balanceOf(user2.addr), 909090909090909090);
    }

    function test_syncBalanceAfterMultipleRounds() public {
        deal(user.addr, 2 ether);
        deal(user2.addr, 2 ether);

        vm.startPrank(user.addr);
        // deposit in Round#0 by user1 at 1 pps
        realVault.deposit{value: 1 ether}();

        // increment the time to the next round
        vm.warp(epoch0 + realVault.rebaseTimeInterval());

        // roll epoch to next round
        realVault.rollToNextRound();

        uint256 price = real.tokenPrice();
        assertEq(real.tokenPrice(), 1 ether);

        // increase the balance to update the vault pps 909090909090909090
        deal(address(s1), 1.1 ether);
        vm.stopPrank();

        // deposit in Round#1 by user2 at 909090909090909090 pps
        vm.startPrank(user2.addr);
        realVault.deposit{value: 1 ether}();
        vm.stopPrank();

        price = real.tokenPrice();
        uint256 user1RealTokenValue = (real.balanceOf(user.addr) * price) / PRECISION;
        uint256 user2RealTokenValue = (real.balanceOf(user2.addr) * price) / PRECISION;

        assertEq(real.tokenPrice(), 1100000000000000000);
        assertApproxEqAbs(user1RealTokenValue + user2RealTokenValue, 2.1 ether, 1);
    }

    function test_addStrategy() public {
        TestEthClaimableStrategy s2 =
            new TestEthClaimableStrategy(payable(strategyManagerAddress), "Mock Eth Investment 2");
        vm.startPrank(proposal.addr);
        realVault.addStrategy(address(s2));
        vm.stopPrank();
        (address[] memory addrs,) = strategyManager.getStrategies();
        assertEq(addrs.length, 2);
    }

    function test_destroyStrategy() public {
        TestEthClaimableStrategy s2 =
            new TestEthClaimableStrategy(payable(strategyManagerAddress), "Mock Eth Investment 2");
        vm.startPrank(owner.addr);

        realVault.destroyStrategy(address(s2));
        vm.stopPrank();

        (address[] memory addrs,) = strategyManager.getStrategies();
        assertEq(addrs.length, 1);
    }

    function test_updatePortfolio() public {
        TestEthClaimableStrategy s2 =
            new TestEthClaimableStrategy(payable(strategyManagerAddress), "Mock Eth Investment 2");
        vm.startPrank(proposal.addr);

        address[] memory strategies = new address[](1);
        uint256[] memory ratios = new uint256[](1);

        strategies[0] = address(s2);
        ratios[0] = 40_00_00; //40%

        realVault.updateInvestmentPortfolio(strategies, ratios);
        vm.stopPrank();

        (address[] memory addrs, uint256[] memory allocations) = strategyManager.getStrategies();
        assertEq(addrs.length, 2);
        assertEq(allocations[1], 40_00_00);
        // must set the s1 allocation to Zero
        assertEq(allocations[0], 0);
    }

    function test_updateMultiplePortfolio() public {
        TestEthClaimableStrategy s2 =
            new TestEthClaimableStrategy(payable(strategyManagerAddress), "Mock Eth Investment 2");
        vm.startPrank(proposal.addr);

        address[] memory strategies = new address[](2);
        uint256[] memory ratios = new uint256[](2);

        strategies[0] = address(s2);
        ratios[0] = 40_00_00; //40%

        strategies[1] = address(s1);
        ratios[1] = 45_00_00; //45%

        realVault.updateInvestmentPortfolio(strategies, ratios);
        vm.stopPrank();

        (address[] memory addrs, uint256[] memory allocations) = strategyManager.getStrategies();
        assertEq(addrs.length, 2);
        assertEq(allocations[0], 45_00_00);
    }

    function test_clearInvestedStrategy() public {
        deal(user.addr, 2 ether);
        deal(user2.addr, 2 ether);

        vm.startPrank(user.addr);
        // deposit in Round#0 by user1 at 1 pps
        realVault.deposit{value: 1 ether}();
        // increment the time to the next round
        vm.warp(epoch0 + realVault.rebaseTimeInterval());
        // roll epoch to Round#2
        realVault.rollToNextRound();
        vm.stopPrank();

        TestEthClaimableStrategy s2 =
            new TestEthClaimableStrategy(payable(strategyManagerAddress), "Mock Eth Investment 2");
        vm.startPrank(proposal.addr);
        // add new strategy s2 to the vault
        address[] memory strategies = new address[](1);
        uint256[] memory ratios = new uint256[](1);
        strategies[0] = address(s2);
        ratios[0] = 40_00_00; //40%
        realVault.updateInvestmentPortfolio(strategies, ratios);
        vm.stopPrank();

        assertEq(strategyManager.getAllStrategiesValue(), 1 ether);

        vm.startPrank(owner.addr);
        // clear the s1 strategy; asset will be returned to the assetVault
        realVault.clearStrategy(address(s1));
        vm.stopPrank();

        assertEq(address(assetsVault).balance, 1 ether);
    }

    function test_clearInvestedStrategyAndRollOver() public {
        deal(user.addr, 2 ether);
        deal(user2.addr, 2 ether);

        vm.startPrank(user.addr);
        // deposit in Round#0 by user1 at 1 pps
        realVault.deposit{value: 1 ether}();
        // increment the time to the next round
        vm.warp(epoch0 + realVault.rebaseTimeInterval());
        // roll epoch to Round#2
        realVault.rollToNextRound();
        vm.stopPrank();

        TestEthClaimableStrategy s2 =
            new TestEthClaimableStrategy(payable(strategyManagerAddress), "Mock Eth Investment 2");

        vm.startPrank(proposal.addr);
        // add new strategy to the vault
        address[] memory strategies = new address[](1);
        uint256[] memory ratios = new uint256[](1);
        strategies[0] = address(s2);
        ratios[0] = 40_00_00; //40%
        realVault.updateInvestmentPortfolio(strategies, ratios);
        vm.stopPrank();

        vm.startPrank(owner.addr);
        // clear the s1 strategy; asset will be returned to the assetVault
        realVault.clearStrategy(address(s1));
        vm.stopPrank();

        // increment the time to the next round
        vm.warp(block.timestamp + realVault.rebaseTimeInterval());
        // roll epoch to Round#2
        realVault.rollToNextRound();
        assertEq(strategyManager.getAllStrategiesValue(), 0.4 ether);
    }

    function test_RollOverAndClearStrategy() public {
        deal(user.addr, 2 ether);
        deal(user2.addr, 2 ether);

        vm.startPrank(user.addr);
        // deposit in Round#0 by user1 at 1 pps
        realVault.deposit{value: 1 ether}();
        // increment the time to the next round
        vm.warp(epoch0 + realVault.rebaseTimeInterval());
        // roll epoch to Round#2
        realVault.rollToNextRound();
        vm.stopPrank();

        TestEthClaimableStrategy s2 =
            new TestEthClaimableStrategy(payable(strategyManagerAddress), "Mock Eth Investment 2");

        vm.startPrank(proposal.addr);
        // add new strategy to the vault
        address[] memory strategies = new address[](2);
        uint256[] memory ratios = new uint256[](2);
        strategies[0] = address(s2);
        ratios[0] = 40_00_00; //40%
        strategies[1] = address(s1);
        ratios[1] = 45_00_00; //45%
        realVault.updateInvestmentPortfolio(strategies, ratios);
        vm.stopPrank();

        // increment the time to the next round
        vm.warp(block.timestamp + realVault.rebaseTimeInterval());
        // roll epoch to Round#2
        realVault.rollToNextRound();
        vm.stopPrank();

        assertEq(strategyManager.getAllStrategiesValue(), 0.85 ether);

        vm.startPrank(owner.addr);
        // clear the s1 strategy; asset will be returned to the assetVault
        realVault.clearStrategy(address(s1));
        vm.stopPrank();

        assertEq(address(assetsVault).balance, 0.6 ether);
    }

    function test_CancelWithdrawMinShares() public {
        deal(user.addr, 2 ether);
        vm.startPrank(user.addr);
        // deposit in Round#0 by user1 at 1 pps
        realVault.deposit{value: 1 ether}();

        // min shares 100 wei
        vm.expectRevert(abi.encodeWithSelector(RealVault.RealVault__MininmumWithdraw.selector));
        realVault.requestWithdraw(10);
        vm.stopPrank();

        // increment the time to the next round
        vm.warp(epoch0 + realVault.rebaseTimeInterval());
        // roll epoch to Round#2
        realVault.rollToNextRound();

        vm.startPrank(user.addr);
        real.approve(address(realVault), 10_000);
        realVault.requestWithdraw(10_000);

        // reETH balance in the realvault should be 10_000 wei after withdraw request
        assertEq(real.balanceOf(address(realVault)), 10_000);

        // A minimum of 100 wei shares must remain after a withdrawal.
        vm.expectRevert(abi.encodeWithSelector(RealVault.RealVault__MininmumWithdraw.selector));
        realVault.cancelWithdraw(99_50);

        // reETH balance in the realvault should be 1_00 wei after canceling the 99_00 wei
        realVault.cancelWithdraw(99_00);
        assertEq(real.balanceOf(address(realVault)), 100);

        realVault.cancelWithdraw(1_00);
        assertEq(real.balanceOf(address(realVault)), 0);
        vm.stopPrank();
    }

    function test_ShareMathAssets() public {
        vm.expectRevert("ShareMath Lib: Invalid assetPerShare");
        ShareMath.sharesToAsset(1 ether, 0);

        uint256 assets = ShareMath.sharesToAsset(1 ether, 1 ether);
        assertEq(assets, 1 ether);
    }

    function testShouldFailIfCalledByNonOwner() external {
        vm.startPrank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(1)));
        realVault.setRebaseInterval(3_600);

        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(1)));
        realVault.setWithdrawFeeRate(3_600);

        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(1)));
        realVault.setMinWithdrawableShares(99);

        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(1)));
        realVault.setFeeRecipient(address(0));
        vm.stopPrank();
    }

    function testShouldPassWhenCalledByOwner() external {
        vm.startPrank(owner.addr);
        assertEq(realVault.rebaseTimeInterval(), 86_400);

        realVault.setRebaseInterval(3_600);
        assertEq(realVault.rebaseTimeInterval(), 3_600);

        assertEq(realVault.minWithdrawableShares(), 1_00);
        realVault.setMinWithdrawableShares(2_00);

        assertEq(realVault.minWithdrawableShares(), 2_00);
        assertEq(realVault.withdrawFeeRate(), 0);

        realVault.setWithdrawFeeRate(100);
        assertEq(realVault.withdrawFeeRate(), 100);

        assertEq(realVault.feeRecipient(), address(0));
        realVault.setFeeRecipient(address(1));
        assertEq(realVault.feeRecipient(), address(1));
        vm.stopPrank();
    }

    function testShouldFailIfCalledByNonProposalAddress() external {
        vm.expectRevert(abi.encodeWithSelector(RealVault.RealVault__NotProposal.selector));
        realVault.updateProposal(address(0));
    }

    function testShouldFailIfRollToNextRoundIsNotDue() external {
        vm.expectRevert(abi.encodeWithSelector(RealVault.RealVault__NotReady.selector));
        realVault.rollToNextRound();
    }

    function testShouldPassIfCalledByProposalAddress() external {
        vm.startPrank(proposal.addr);
        assertEq(realVault.proposal(), proposal.addr);

        realVault.updateProposal(address(1));

        assertEq(realVault.proposal(), address(1));
        vm.stopPrank();
    }

    function testShouldFailToSetRebaseInterval() external {
        vm.startPrank(owner.addr);
        vm.expectRevert(abi.encodeWithSelector(RealVault.RealVault__MinimumRebaseInterval.selector, 3600));
        realVault.setRebaseInterval(2_000);
        vm.stopPrank();
    }

    function testShouldFailToSetMinWithdrawableShares() external {
        vm.startPrank(owner.addr);
        vm.expectRevert(abi.encodeWithSelector(RealVault.RealVault__MinimumWithdrawableShares.selector));
        realVault.setMinWithdrawableShares(99);
        vm.stopPrank();
    }

    function testShouldFailToSetWithdrawFeeRateIfFeeAboveMaxFee() external {
        vm.startPrank(owner.addr);
        vm.expectRevert(abi.encodeWithSelector(RealVault.RealVault__ExceedMaxFeeRate.selector, 10_001));
        realVault.setWithdrawFeeRate(10_001);
        vm.stopPrank();
    }

    function testShouldFailIfAddressIsZero() external {
        vm.startPrank(owner.addr);
        vm.expectRevert(abi.encodeWithSelector(RealVault.RealVault__ZeroAddress.selector));
        realVault.setFeeRecipient(address(0));
        vm.stopPrank();

        vm.startPrank(proposal.addr);
        vm.expectRevert(abi.encodeWithSelector(RealVault.RealVault__ZeroAddress.selector));
        realVault.updateProposal(address(0));
        vm.stopPrank();
    }

    function testShouldFailIfValueIsZero() external {
        vm.expectRevert(abi.encodeWithSelector(RealVault.RealVault__InvalidAmount.selector));
        realVault.requestWithdraw(0);

        vm.expectRevert(abi.encodeWithSelector(RealVault.RealVault__InvalidAmount.selector));
        realVault.settleWithdrawDust(0);

        vm.expectRevert(abi.encodeWithSelector(RealVault.RealVault__InvalidAmount.selector));
        realVault.deposit{value: 0}();

        vm.expectRevert(abi.encodeWithSelector(RealVault.RealVault__InvalidAmount.selector));
        realVault.cancelWithdraw(0);

        vm.expectRevert(abi.encodeWithSelector(RealVault.RealVault__InvalidAmount.selector));
        realVault.instantWithdraw(0, 0);
    }

    function testShouldFailIfAmountIsAboveUserWithdrawableAmount() external {
        vm.expectRevert(abi.encodeWithSelector(RealVault.RealVault__ExceedWithdrawAmount.selector));
        realVault.instantWithdraw(1, 0);
    }

    function testShouldFailIfAmountisAboveDust() external {
        bytes32 withdrawAmountDustSlot = bytes32(uint256(13));
        bytes32 withdrawAmountDustValue = bytes32(uint256(1 ether));

        vm.store(address(realVault), withdrawAmountDustSlot, withdrawAmountDustValue);
        vm.expectRevert(abi.encodeWithSelector(RealVault.RealVault__ExceedBalance.selector));
        realVault.settleWithdrawDust(2 ether);
    }

    function testShouldReducePastWithdrawableAmountWithDust() external {
        bytes32 withdrawAmountDustSlot = bytes32(uint256(13));
        bytes32 withdrawableAmountInPastSlot = bytes32(uint256(10));

        bytes32 withdrawAmountDustValue = bytes32(uint256(2 ether));
        bytes32 withdrawableAmountInPastValue = bytes32(uint256(5 ether));

        vm.store(address(realVault), withdrawAmountDustSlot, withdrawAmountDustValue);
        vm.store(address(realVault), withdrawableAmountInPastSlot, withdrawableAmountInPastValue);

        assertEq(realVault.withdrawAmountDust(), 2 ether);
        assertEq(realVault.withdrawableAmountInPast(), 5 ether);

        realVault.settleWithdrawDust(1 ether);

        assertEq(realVault.withdrawAmountDust(), 1 ether);
        assertEq(realVault.withdrawableAmountInPast(), 4 ether);
    }

    function testShouldMigrateVault() external {
        vm.startPrank(address(minter));
        real.mint(address(realVault), 1 ether); // mint real token to increase totalSupply from  zero
        vm.stopPrank();

        RealVault newVault = new RealVault(
            address(owner.addr),
            minterAddress,
            payable(assetVaultAddress),
            payable(strategyManagerAddress),
            address(proposal.addr)
        );

        assertEq(minter.vault(), address(realVault));
        assertEq(assetsVault.realVault(), address(realVault));

        assertEq(strategyManager.realVault(), address(realVault));
        assertEq(real.balanceOf(address(realVault)), 1 ether);

        vm.startPrank(proposal.addr);
        realVault.migrateVault(address(newVault));
        vm.stopPrank();

        assertEq(minter.vault(), address(newVault));
        assertEq(assetsVault.realVault(), address(newVault));

        assertEq(strategyManager.realVault(), address(newVault));
        assertEq(real.balanceOf(address(realVault)), 0);
        assertEq(real.balanceOf(address(newVault)), 1 ether);
    }

    function testCancelWithdrawShouldFailIfAmountExceedUserShares() public {
        vm.expectRevert(abi.encodeWithSelector(RealVault.RealVault__ExceedRequestedAmount.selector, 1, 0));
        realVault.cancelWithdraw(1);
    }

    function testCancelWithdrawShouldFailIfRequestIsNotFound() public {
        deal(user.addr, 2 ether);
        vm.startPrank(user.addr);

        realVault.deposit{value: 1 ether}();
        vm.stopPrank();

        vm.warp(epoch0 + realVault.rebaseTimeInterval());
        realVault.rollToNextRound();

        vm.startPrank(user.addr);
        real.approve(address(realVault), 10_000);
        realVault.requestWithdraw(10_000);

        vm.warp(block.timestamp + realVault.rebaseTimeInterval());
        realVault.rollToNextRound();

        vm.expectRevert(abi.encodeWithSelector(RealVault.RealVault__NoRequestFound.selector));
        realVault.cancelWithdraw(10_000);
        vm.stopPrank();
    }

    function testShouldFailIfVaultDoesNotHaveEnoughEther() public {
        address[] memory strategies = new address[](1);
        uint256[] memory ratios = new uint256[](1);

        s = new TestEthStrategy2(payable(strategyManagerAddress), "Mock Eth Investment");
        strategies[0] = address(s);
        ratios[0] = 1000_000; // 1e6

        vm.startPrank(proposal.addr);
        realVault.updateInvestmentPortfolio(strategies, ratios);
        vm.stopPrank();

        vm.startPrank(owner.addr);
        realVault.destroyStrategy(address(s1));
        vm.stopPrank();

        deal(user.addr, 2 ether);
        vm.startPrank(user.addr);
        realVault.deposit{value: 1 ether}();
        vm.stopPrank();

        vm.warp(epoch0 + realVault.rebaseTimeInterval());
        realVault.rollToNextRound();

        vm.startPrank(user.addr);
        real.approve(address(realVault), 10_000);

        vm.expectRevert(abi.encodeWithSelector(RealVault.RealVault__WaitInQueue.selector));
        realVault.instantWithdraw(0, 10_000);
        vm.stopPrank();
    }

    function testRequestWithdrawShouldFailIfShareIsAboveUserBalance() public {
        deal(user.addr, 1 ether);
        vm.startPrank(user.addr);

        realVault.deposit{value: 1 ether}();
        vm.warp(block.timestamp + realVault.rebaseTimeInterval());

        realVault.rollToNextRound();
        uint256 balance = real.balanceOf(user.addr);

        vm.expectRevert(abi.encodeWithSelector(RealVault.RealVault__ExceedBalance.selector));
        realVault.requestWithdraw(balance + 1);
        vm.stopPrank();
    }

    function test_round0InstantWithdrawWithFee() public {
        vm.startPrank(owner.addr);
        realVault.setWithdrawFeeRate(100);

        realVault.setFeeRecipient(address(1));
        vm.stopPrank();

        deal(user.addr, 2 ether);
        vm.startPrank(user.addr);

        // Deposit in Round#0
        realVault.deposit{value: 1 ether}();

        assertEq(address(assetsVault).balance, 1 ether);
        assertEq(user.addr.balance, 1 ether);

        // Instant withdraw in Round#0
        realVault.instantWithdraw(0, real.balanceOf(user.addr));
        vm.stopPrank();

        uint256 feeAmount = (1 ether * 100) / 100_0000;
        assertEq(real.balanceOf(user.addr), 0 ether);

        assertEq(address(assetsVault).balance, 0 ether);
        assertEq(user.addr.balance, 2 ether - feeAmount);
        assertEq(address(1).balance, feeAmount);
    }
}
