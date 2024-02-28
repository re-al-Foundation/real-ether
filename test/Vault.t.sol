// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Test, console2} from "forge-std/Test.sol";

import {Real} from "src/token/Real.sol";
import {Minter} from "src/token/Minter.sol";
import {RealVault} from "src/RealVault.sol";
import {StrategyManager} from "src/StrategyManager.sol";
import {AssetsVault} from "src/AssetsVault.sol";
import {MockStrategy} from "src/mock/MockStrategy.sol";

contract VaultTest is Test {
    uint256 PRECISION = 10 ** 18;

    Real public real;
    Minter public minter;
    RealVault public realVault;
    StrategyManager public strategyManager;
    AssetsVault public assetsVault;
    MockStrategy public s1;

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

    function setUp() public {
        user = makeAccount("user");
        user2 = makeAccount("user2");
        deployer = makeAccount("deployer");
        owner = makeAccount("owner");
        proposal = makeAccount("proposal");

        minterAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        realVaultAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 2);
        assetVaultAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 3);
        strategyManagerAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 5);

        real = new Real(minterAddress);
        minter = new Minter(address(real), payable(realVaultAddress));
        realVault = new RealVault(
            address(owner.addr),
            minterAddress,
            payable(assetVaultAddress),
            payable(strategyManagerAddress),
            address(proposal.addr)
        );
        assetsVault = new AssetsVault(address(realVault), strategyManagerAddress);

        address[] memory strategies = new address[](1);
        uint256[] memory ratios = new uint256[](1);

        s1 = new MockStrategy(payable(strategyManagerAddress), "Mock Eth Investment");
        strategies[0] = address(s1);
        ratios[0] = 1000_000; // 1e6
        strategyManager = new StrategyManager(address(realVault), payable(assetVaultAddress), strategies, ratios);

        epoch0 = block.timestamp;
    }

    // function test_assetVaultdeposit() public {
    //     deal(address(realVault), 1 ether);
    //     vm.startPrank(address(realVault));
    //     assetsVault.deposit{value: 1 ether}();
    //     vm.stopPrank();
    //     assertEq(address(assetsVault).balance, 1 ether);
    // }

    // function test_deposit() public {
    //     deal(user.addr, 10 ether);
    //     vm.startPrank(user.addr);
    //     realVault.deposit{value: 1 ether}();
    //     vm.stopPrank();

    //     assertEq(address(realVault).balance, 0 ether);
    //     assertEq(address(assetsVault).balance, 1 ether);
    //     assertEq(real.balanceOf(user.addr), 1 ether);
    // }

    // // function test_requestWithdrawFail() public {
    // //     deal(user.addr, 10 ether);
    // //     vm.startPrank(user.addr);

    // //     // Deposit in Round#0
    // //     realVault.deposit{value: 1 ether}();

    // //     // Request Withraw in Round#0
    // //     // vm.expectRevert(bytes("RealVault__WithdrawInstantly()"));
    // //     // vm.expectRevert(abi.encodeWithSelector(RealVault.RealVault__WithdrawInstantly.selector));
    // //     // vm.expectRevert(abi.encodeWithSignature("Error(string)", "RealVault__WithdrawInstantly()"));
    // //     realVault.requestWithdraw(real.balanceOf(user.addr));
    // //     vm.stopPrank();
    // // }

    // function test_round0InstantWithdraw() public {
    //     deal(user.addr, 2 ether);
    //     vm.startPrank(user.addr);

    //     // Deposit in Round#0
    //     realVault.deposit{value: 1 ether}();

    //     assertEq(address(assetsVault).balance, 1 ether);
    //     assertEq(user.addr.balance, 1 ether);

    //     // Instant withdraw in Round#0
    //     realVault.instantWithdraw(0, real.balanceOf(user.addr));
    //     vm.stopPrank();

    //     assertEq(real.balanceOf(user.addr), 0 ether);
    //     assertEq(address(assetsVault).balance, 0 ether);
    //     assertEq(user.addr.balance, 2 ether);
    // }

    // function test_round0InstantWithdraw() public {
    //     deal(user.addr, 2 ether);
    //     vm.startPrank(user.addr);

    //     // Deposit in Round#0
    //     realVault.deposit{value: 1 ether}();

    //     // increment the time to the next round
    //     vm.warp(epoch0 + realVault.rebaseTimeInterval());

    //     // roll epoch to next round
    //     realVault.rollToNextRound();
    //     vm.stopPrank();

    //     assertEq(address(assetsVault).balance, 0 ether);
    //     assertEq(strategyManager.getAllStrategiesValue(), 1 ether);
    // }

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
}
