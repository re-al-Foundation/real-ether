pragma solidity =0.8.21;

import {Test, console2 as console} from "forge-std/Test.sol";

import {Real} from "src/token/Real.sol";
import {Minter} from "src/token/Minter.sol";
import {RealVault} from "src/RealVault.sol";
import {StrategyManager} from "src/StrategyManager.sol";
import {AssetsVault} from "src/AssetsVault.sol";
import {TestEthStrategyInflate} from "src/mock/test/TestEthStrategyInflate.sol";
import {UnderlyingYieldGenerator} from "src/mock/test/UnderlyingYieldGenerator.sol";

contract TestEthStrategyTest is Test {
    uint256 public constant ZERO_VALUE = 0;
    uint256 PRECISION = 10 ** 18;

    Real public real;
    Minter public minter;
    RealVault public realVault;
    StrategyManager public strategyManager;
    AssetsVault public assetsVault;
    TestEthStrategyInflate public s1;
    UnderlyingYieldGenerator public underlying;

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
        strategyManagerAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 6);

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
        assetsVault = new AssetsVault(address(realVault), strategyManagerAddress);

        underlying = new UnderlyingYieldGenerator(address(assetsVault));

        address[] memory strategies = new address[](1);
        uint256[] memory ratios = new uint256[](1);

        s1 = new TestEthStrategyInflate(payable(strategyManagerAddress), "Mock Eth Investment", address(underlying));
        strategies[0] = address(s1);
        ratios[0] = 1000_000; // 1e6
        strategyManager = new StrategyManager(address(realVault), payable(assetVaultAddress), strategies, ratios);

        epoch0 = block.timestamp;

        vm.startPrank(address(0xdead));
        realVault.instantWithdraw(0, 0.001 ether);
        vm.stopPrank();
    }

    function test_InflatePPS() external {
        deal(address(underlying), 20 ether);
        deal(user.addr, 50 ether);
        deal(user2.addr, 50 ether);

        vm.startPrank(address(user.addr));
        realVault.deposit{value: 50 ether}(ZERO_VALUE);
        vm.stopPrank();

        vm.startPrank(address(user2.addr));
        realVault.deposit{value: 30 ether}(ZERO_VALUE);
        vm.stopPrank();

        // increment the time to the next round
        vm.warp(epoch0 + realVault.rebaseTimeInterval());
        // roll epoch to Round#2
        realVault.rollToNextRound();

        vm.startPrank(address(user.addr));
        real.approve(address(realVault), 10 ether);
        realVault.requestWithdraw(10 ether);
        vm.stopPrank();

        // increment the time to the next round
        vm.warp(block.timestamp + realVault.rebaseTimeInterval());
        // roll epoch to Round#2
        realVault.rollToNextRound();
        assertEq(realVault.currentSharePrice(), 1.125 ether);
    }
}
