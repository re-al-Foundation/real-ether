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

contract StrategyManagerTest is Test {
    error OwnableUnauthorizedAccount(address);

    uint256 PRECISION = 10 ** 18;
    uint256 MIN_SHARES = 1_00;

    Real public real;
    Minter public minter;
    RealVault public realVault;
    StrategyManager public strategyManager;
    AssetsVault public assetsVault;
    TestEthStrategy public s1;
    TestEthStrategy2 public s2;

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

    function testShouldPayUserFromStrategyManagerIfStrategyManagerHasEnoughEth() public {
        deal(user.addr, 2 ether);
        vm.startPrank(user.addr);
        uint256 shares = realVault.deposit{value: 1 ether}();
        vm.stopPrank();

        vm.warp(epoch0 + realVault.rebaseTimeInterval());
        realVault.rollToNextRound();

        vm.startPrank(user.addr);
        real.approve(address(realVault), shares);

        assertEq(address(assetsVault).balance, 0);
        deal(address(strategyManager), 1 ether);

        realVault.instantWithdraw(0, shares);
        assertEq(user.addr.balance, 2 ether);

        assertEq(address(assetsVault).balance, 0);
        vm.stopPrank();
    }

    function testShouldOnlyRebaseStrategies() public {
        strategyManager.onlyRebaseStrategies();
    }

    function testShouldFailWhenInAndOutValuesAreNonZero() external {
        vm.startPrank(address(realVault));
        vm.expectRevert("only deposit or withdraw");
        strategyManager.rebaseStrategies(2 ether, 2 ether);
        vm.stopPrank();
    }

    function testShouldWithdrawMaxFromStrategiesIfOutValueIsAboveTotalEthInStrategies() external {
        deal(user.addr, 2 ether);
        vm.startPrank(user.addr);

        realVault.deposit{value: 1 ether}();
        vm.stopPrank();

        vm.warp(epoch0 + realVault.rebaseTimeInterval());
        realVault.rollToNextRound();

        assertEq(address(assetsVault).balance, 0);
        vm.startPrank(address(realVault));
        strategyManager.rebaseStrategies(0, 2 ether);

        assertEq(address(assetsVault).balance, 1 ether);
        vm.stopPrank();
    }

    function testShouldFailIfMangerIsNotStrategyManager() external {
        s2 = new TestEthStrategy2(payable(address(1)), "Mock Eth Investment");
        address[] memory strategies = new address[](1);
        uint256[] memory ratios = new uint256[](1);

        strategies[0] = address(s2);
        ratios[0] = 1000_000; // 1e6

        vm.startPrank(proposal.addr);
        vm.expectRevert(abi.encodeWithSelector(StrategyManager.StrategyManager__InvalidManager.selector));
        realVault.updateInvestmentPortfolio(strategies, ratios);
        vm.stopPrank();
    }

    function testShouldFailIfRatioExceedMaxPercentage() external {
        s2 = new TestEthStrategy2(payable(address(strategyManagerAddress)), "Mock Eth Investment");
        TestEthStrategy2 s3 = new TestEthStrategy2(payable(address(strategyManagerAddress)), "Mock Eth Investment");

        address[] memory strategies = new address[](2);
        uint256[] memory ratios = new uint256[](2);

        strategies[0] = address(s2);
        strategies[1] = address(s3);
        ratios[0] = 1000_000;
        ratios[1] = 1000_000;

        vm.startPrank(proposal.addr);
        vm.expectRevert(abi.encodeWithSelector(StrategyManager.StrategyManager__InvalidPercentage.selector));
        realVault.updateInvestmentPortfolio(strategies, ratios);
        vm.stopPrank();
    }

    function testShouldIfCallerIsNotVault() external {
        vm.expectRevert(abi.encodeWithSelector(StrategyManager.StrategyManager__NotVault.selector));
        strategyManager.setNewVault(address(0));
    }

    function testShouldFailToDestoryActiveStrategy() external {
        vm.startPrank(address(realVault));
        vm.expectRevert(abi.encodeWithSelector(StrategyManager.StrategyManager__StillActive.selector, address(s1)));
        strategyManager.destroyStrategy(address(s1));
        vm.stopPrank();
    }

    function testShouldFailToSetStrategies() external {
        address[] memory strategies = new address[](2);
        uint256[] memory ratios = new uint256[](1);

        ratios[0] = 1 ether;
        strategies[0] = address(1);
        strategies[1] = address(2);

        vm.startPrank(address(realVault));
        vm.expectRevert(abi.encodeWithSelector(StrategyManager.StrategyManager__InvalidLength.selector));
        strategyManager.setStrategies(strategies, ratios);
        vm.stopPrank();
    }

    function testShouldIfNewVaultIsZeroAddress() external {
        vm.startPrank(address(realVault));
        vm.expectRevert(abi.encodeWithSelector(StrategyManager.StrategyManager__ZeroAddress.selector));
        strategyManager.setNewVault(address(0));
        vm.stopPrank();
    }

    function testShouldIStrategyAlreadyExist() external {
        vm.startPrank(address(realVault));
        vm.expectRevert(abi.encodeWithSelector(StrategyManager.StrategyManager__AlreadyExist.selector, address(s1)));
        strategyManager.addStrategy(address(s1));
        vm.stopPrank();
    }
}
