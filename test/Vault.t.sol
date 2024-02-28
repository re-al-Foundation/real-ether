// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Test, console2} from "forge-std/Test.sol";

import {Real} from "src/token/Real.sol";
import {Minter} from "src/token/Minter.sol";
import {RealVault} from "src/RealVault.sol";
import {StrategyManager} from "src/StrategyManager.sol";
import {AssetsVault} from "src/AssetsVault.sol";

contract VaultTest is Test {
    Real public real;
    Minter public minter;
    RealVault public realVault;
    StrategyManager public strategyManager;
    AssetsVault public assetsVault;

    address minterAddress;
    address realVaultAddress;
    address strategyManagerAddress;
    address assetVaultAddress;

    Account public user;
    Account public deployer;
    Account public owner;
    Account public proposal;

    function setUp() public {
        user = makeAccount("user");
        deployer = makeAccount("deployer");
        owner = makeAccount("owner");
        proposal = makeAccount("proposal");

        minterAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        realVaultAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 2);
        assetVaultAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 3);
        strategyManagerAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 4);

        real = new Real(minterAddress);
        minter = new Minter(address(real), payable(realVaultAddress));
        realVault =
            new RealVault(address(owner.addr), minterAddress, payable(assetVaultAddress), address(proposal.addr));
        assetsVault = new AssetsVault(address(realVault), strategyManagerAddress);
    }

    function test_assetVaultdeposit() public {
        deal(address(realVault), 1 ether);
        vm.startPrank(address(realVault));
        assetsVault.deposit{value: 1 ether}();
        vm.stopPrank();
        assertEq(address(assetsVault).balance, 1 ether);
    }

    function test_deposit() public {
        deal(address(user.addr), 10 ether);
        vm.startPrank(address(user.addr));
        realVault.deposit{value: 1 ether}();
        vm.stopPrank();

        assertEq(address(realVault).balance, 0 ether);
        assertEq(address(assetsVault).balance, 1 ether);
        assertEq(real.balanceOf(user.addr), 1 ether);
    }
}
