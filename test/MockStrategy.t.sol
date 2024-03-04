pragma solidity =0.8.21;

import {Test, console2 as console} from "forge-std/Test.sol";

import {Real} from "src/token/Real.sol";
import {Minter} from "src/token/Minter.sol";
import {RealVault} from "src/RealVault.sol";
import {StrategyManager} from "src/StrategyManager.sol";
import {AssetsVault} from "src/AssetsVault.sol";
import {TestEthStrategy} from "src/mock/TestEthStrategy.sol";

contract TestEthStrategyTest is Test {
    uint256 PRECISION = 10 ** 18;

    Real public real;
    Minter public minter;
    RealVault public realVault;
    StrategyManager public strategyManager;
    AssetsVault public assetsVault;
    TestEthStrategy public s1;

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

        s1 = new TestEthStrategy(payable(strategyManagerAddress), "Mock Eth Investment");
        strategies[0] = address(s1);
        ratios[0] = 1000_000; // 1e6
        strategyManager = new StrategyManager(address(realVault), payable(assetVaultAddress), strategies, ratios);

        epoch0 = block.timestamp;
    }

    function test_deposit() external {
        vm.deal(address(strategyManager), 1 ether);
        vm.startPrank(address(strategyManager));

        s1.deposit{value: 1 ether}();
        vm.stopPrank();
    }

    function test_withdraw() external {
        deal(address(s1), 1 ether);
        vm.deal(address(strategyManager), 1 ether);

        vm.startPrank(address(strategyManager));
        s1.deposit{value: 1 ether}();

        assertEq(address(strategyManager).balance, 0);
        s1.withdraw(2 ether);

        vm.stopPrank();
        assertEq(address(strategyManager).balance, 2 ether);
    }

    function test_clear() external {
        deal(address(s1), 1 ether);
        deal(address(strategyManager), 1 ether);
        vm.startPrank(address(strategyManager));

        s1.deposit{value: 1 ether}();

        assertEq(address(strategyManager).balance, 0);
        s1.clear();

        vm.stopPrank();
        assertEq(address(strategyManager).balance, 2 ether);
    }
}
