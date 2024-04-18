// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

import {Test, console2} from "forge-std/Test.sol";

import {Real} from "src/token/Real.sol";
import {Minter} from "src/token/Minter.sol";
import {RealVault} from "src/RealVault.sol";
import {AssetsVault} from "src/AssetsVault.sol";

contract AssetsVaultTest is Test {
    error AssetsVault__InvalidAmount();
    error AssetsVault__ZeroAddress();

    uint256 PRECISION = 10 ** 18;
    uint256 MIN_SHARES = 1_00;

    Real public real;
    Minter public minter;
    RealVault public realVault;
    AssetsVault public assetsVault;

    address minterAddress;
    address realVaultAddress;
    address strategyManagerAddress;
    address assetVaultAddress;

    Account public user;
    Account public user2;
    Account public deployer;
    Account public owner;
    Account public proposal;

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
    }

    function test_deposit() public {
        vm.expectRevert();
        assetsVault.deposit{value: 0}();
    }

    function test_SetNewVault() public {
        vm.startPrank(address(realVault));
        vm.expectRevert();
        assetsVault.setNewVault(address(0));

        assetsVault.setNewVault(user.addr);
        assertEq(assetsVault.realVault(), user.addr);
        vm.stopPrank();
    }
}
