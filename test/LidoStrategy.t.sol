// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Real} from "src/token/Real.sol";
import {Minter} from "src/token/Minter.sol";
import {RealVault} from "src/RealVault.sol";
import {AssetsVault} from "src/AssetsVault.sol";
import {IStETH} from "src/interfaces/IStETH.sol";
import {ShareMath} from "src/libraries/ShareMath.sol";
import {StrategyManager} from "src/StrategyManager.sol";
import {SwapManager} from "src/utils/SwapManager.sol";
import {Test, console2 as console} from "forge-std/Test.sol";
import {TestEthStrategy} from "src/mock/TestEthStrategy.sol";
import {LidoStEthStrategy} from "src/strategy/LidoStEthStrategy.sol";
import {IWithdrawalQueueERC721} from "src/interfaces/IWithdrawalQueueERC721.sol";

/**
 * @title Lido Strategy Test Cases
 * @author c-n-o-t-e, Mavvverick
 * @dev Contract is used to test out Lido Strategy Contract by forking the
 *         Mainnet chain to interact with Lido contracts and  Real Vault contract locally.
 *
 * Functionalities Tested:
 * - Depositing into Lido.
 * - Request Withdrawal from Lido.
 * - Withdraw from Lido.
 * - Add Lido Strategy in Real Vault.
 * - Roll Over Multiple Strategies in Real Vault.
 * - Clear Strateg In Round 0 in Real Vault.
 * - Clear Strategy in Real Vault.
 * - Destory Strategy In Round 0 in Real Vault.
 * - Destory Lido Strategy in Real Vault.
 * - Destory Other Strategy in Real Vault.
 * - Force Withdraw By Real Vault.
 */
contract LidoStrategyTest is Test {
    uint256 PRECISION = 10 ** 18;

    Real public real;
    Minter public minter;
    RealVault public realVault;
    AssetsVault public assetsVault;
    StrategyManager public strategyManager;
    LidoStEthStrategy public lidoStEthStrategy;
    TestEthStrategy public testEthStrategy;
    SwapManager swapManager;

    address minterAddress;
    address realVaultAddress;
    address strategyManagerAddress;
    address assetVaultAddress;
    address swapManagerAddress;

    address stETHAdress = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address wstETHAdress = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address stETHWithdrawal = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;

    address NULL = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address stETH_ETH = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address wstETH_ETH = 0x109830a1AAaD605BbF02a9dFA7B0B92EC2FB7dAa;

    Account public user;
    Account public user2;
    Account public owner;
    Account public deployer;
    Account public proposal;
    Account public deadShares;

    uint256 epoch0;
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        vm.createSelectFork(MAINNET_RPC_URL, 19340830);

        user = makeAccount("user");
        user2 = makeAccount("user2");
        owner = makeAccount("owner");
        deployer = makeAccount("deployer");
        proposal = makeAccount("proposal");
        deadShares = makeAccount("deadShares");

        minterAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        realVaultAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 2);
        assetVaultAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 3);
        strategyManagerAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 5);
        swapManagerAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 6);

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

        lidoStEthStrategy = new LidoStEthStrategy(
            stETHAdress,
            stETHWithdrawal,
            wstETHAdress,
            WETH9,
            swapManagerAddress,
            payable(strategyManagerAddress),
            "Lido StEth Strategy Investment"
        );

        strategies[0] = address(lidoStEthStrategy);
        ratios[0] = 1000_000; // 1e6

        strategyManager = new StrategyManager(address(realVault), payable(assetVaultAddress), strategies, ratios);

        swapManager = new SwapManager(address(this), WETH9, NULL, 0xE592427A0AEce92De3Edee1F18E0157C05861564);
        swapManager.setWhitelistV3Pool(wstETHAdress, wstETH_ETH, 1000_000);
        swapManager.setWhitelistCurvePool(stETHAdress, stETH_ETH, 1000_000);
        swapManager.setTokenSlippage(WETH9, 995_000);
        swapManager.setTokenSlippage(NULL, 995_000);

        testEthStrategy = new TestEthStrategy(payable(strategyManagerAddress), "Mock Eth Investment");

        epoch0 = block.timestamp;

        deal(deadShares.addr, 1 ether);
        vm.startPrank(deadShares.addr);

        realVault.deposit{value: 1 ether}();
        vm.stopPrank();
    }

    function test_deposit() external {
        deal(user.addr, 1 ether);
        vm.startPrank(user.addr);

        realVault.deposit{value: 1 ether}();
        vm.stopPrank();

        assertEq(IStETH(stETHAdress).balanceOf(address(lidoStEthStrategy)), 0);
        vm.warp(block.timestamp + 1 days);

        realVault.rollToNextRound();
        assertApproxEqAbs(IStETH(stETHAdress).balanceOf(address(lidoStEthStrategy)), 2 ether, 1);
    }

    function test_requestWithdrawals() external {
        deal(user.addr, 1 ether);
        vm.startPrank(user.addr);

        uint256 shares = realVault.deposit{value: 1 ether}();
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        realVault.rollToNextRound();
        vm.startPrank(user.addr);

        real.approve(address(realVault), 1 ether);
        realVault.requestWithdraw(1 ether);

        vm.stopPrank();
        (,, uint256 totalPending) = lidoStEthStrategy.checkPendingAssets();

        assertEq(totalPending, 0);
        assertApproxEqAbs(IStETH(stETHAdress).balanceOf(address(lidoStEthStrategy)), 2 ether, 1);

        vm.warp(block.timestamp + 1 days);
        realVault.rollToNextRound();

        uint256 withdrawAmount = ShareMath.sharesToAsset(shares, realVault.roundPricePerShare(1));
        (,, totalPending) = lidoStEthStrategy.checkPendingAssets();

        assertEq(totalPending, withdrawAmount);
        assertApproxEqAbs(IStETH(stETHAdress).balanceOf(address(lidoStEthStrategy)), 1 ether, 1);
    }

    function test_withdraw() external {
        deal(user.addr, 1 ether);
        vm.startPrank(user.addr);

        uint256 shares = realVault.deposit{value: 1 ether}();
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        realVault.rollToNextRound();
        vm.startPrank(user.addr);

        real.approve(address(realVault), 1 ether);
        realVault.requestWithdraw(1 ether);

        vm.stopPrank();
        vm.warp(block.timestamp + 1 days);

        realVault.rollToNextRound();
        uint256 withdrawAmount = ShareMath.sharesToAsset(shares, realVault.roundPricePerShare(1));

        (, uint256 totalClaimableBeforeTx, uint256 totalPendingBeforeTx) = lidoStEthStrategy.checkPendingAssets();

        assertEq(withdrawAmount, totalPendingBeforeTx);
        assertEq(totalClaimableBeforeTx, 0);

        address finalizer = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; //stETH token
        uint256 lastRequestId = IWithdrawalQueueERC721(stETHWithdrawal).getLastRequestId();

        uint256[] memory batches = new uint256[](1);
        batches[0] = lastRequestId;

        (uint256 ethToLock, uint256 sharesToBurn) = IWithdrawalQueueERC721(stETHWithdrawal).prefinalize(batches, 1e27);

        // update the eth balance in stETH
        deal(finalizer, 95_00 ether);

        vm.startPrank(finalizer);
        uint256 sharesToBurnWithPrecision = sharesToBurn * 1e27;
        IWithdrawalQueueERC721(stETHWithdrawal).finalize{value: ethToLock}(lastRequestId, sharesToBurnWithPrecision);
        vm.stopPrank();

        (uint256[] memory idsAfterTx0, uint256 totalClaimableAfterTx0, uint256 totalPendingAfterTx0) =
            lidoStEthStrategy.checkPendingAssets();

        assertEq(totalPendingAfterTx0, 0);
        assertEq(batches[0], idsAfterTx0[0]);

        console.log(assetsVault.getBalance(), "before");

        assertEq(totalClaimableAfterTx0, totalPendingBeforeTx);
        lidoStEthStrategy.claimAllPendingAssets();

        (uint256[] memory idsAfterTx1, uint256 totalClaimableAfterTx1,) = lidoStEthStrategy.checkPendingAssets();
        assertEq(0, idsAfterTx1.length);

        assertEq(totalClaimableAfterTx1, 0);

        console.log(assetsVault.getBalance(), totalPendingBeforeTx, "after");
    }

    function test_AddLidoStrategy() external {
        vm.startPrank(proposal.addr);
        address[] memory strategies = new address[](1);
        uint256[] memory ratios = new uint256[](1);
        //test eth strategy
        strategies[0] = address(testEthStrategy);
        ratios[0] = 100_00_00; //100%
        // update strategy
        realVault.updateInvestmentPortfolio(strategies, ratios);
        vm.stopPrank();

        vm.startPrank(owner.addr);
        realVault.destroyStrategy(address(lidoStEthStrategy));
        vm.stopPrank();

        // increment the time to the next round
        vm.warp(epoch0 + realVault.rebaseTimeInterval());
        // roll epoch to Round#1
        realVault.rollToNextRound();

        vm.startPrank(proposal.addr);
        address[] memory strategiesNew = new address[](2);
        uint256[] memory ratiosNew = new uint256[](2);
        //add eth strategy
        strategiesNew[0] = address(testEthStrategy);
        ratiosNew[0] = 50_00_00; //100%
        //add lido strategy
        strategiesNew[1] = address(lidoStEthStrategy);
        ratiosNew[1] = 50_00_00; //100%
        // update strategy
        realVault.updateInvestmentPortfolio(strategiesNew, ratiosNew);
        vm.stopPrank();

        // increment the time to the next round
        vm.warp(block.timestamp + realVault.rebaseTimeInterval());
        // roll epoch to Round#2
        realVault.rollToNextRound();

        assertEq(address(testEthStrategy).balance, 0.5 ether);
        assertApproxEqAbs(IStETH(stETHAdress).balanceOf(address(lidoStEthStrategy)), 0.5 ether, 1);
    }

    function test_rollOverMultipleStrategies() external {
        vm.startPrank(proposal.addr);
        address[] memory strategies = new address[](2);
        uint256[] memory ratios = new uint256[](2);

        //test eth strategy
        strategies[0] = address(testEthStrategy);
        ratios[0] = 50_00_00; //100%
        strategies[1] = address(lidoStEthStrategy);
        ratios[1] = 50_00_00; //100%
        // update strategy
        realVault.updateInvestmentPortfolio(strategies, ratios);
        vm.stopPrank();

        // increment the time to the next round
        vm.warp(epoch0 + realVault.rebaseTimeInterval());
        // roll epoch to Round#2
        realVault.rollToNextRound();

        // increment the time to the next round
        vm.warp(block.timestamp + realVault.rebaseTimeInterval());
        // roll epoch to Round#3
        realVault.rollToNextRound();

        (uint256 idleAmount, uint256 investedAmount) = realVault.getVaultAvailableAmount();

        assertApproxEqAbs(idleAmount, 0, 1);
        assertEq(investedAmount, 999999999999999998);
        assertEq(address(testEthStrategy).balance, 499999999999999999);
        assertApproxEqAbs(IStETH(stETHAdress).balanceOf(address(lidoStEthStrategy)), 0.5 ether, 1);
    }

    function test_clearStrategInRound0() external {
        vm.startPrank(owner.addr);
        realVault.clearStrategy(address(lidoStEthStrategy));
        vm.stopPrank();
        assertEq(address(assetsVault).balance, 1 ether);
    }

    function test_clearStrategy() external {
        deal(user2.addr, 2 ether);
        vm.startPrank(user2.addr);
        // deposit in Round#1 by user1 at 0.909090 pps
        realVault.deposit{value: 1 ether}();
        vm.stopPrank();

        // increment the time to the next round
        vm.warp(epoch0 + realVault.rebaseTimeInterval());
        // roll epoch to Round#2
        realVault.rollToNextRound();

        vm.startPrank(owner.addr);
        realVault.clearStrategy(address(lidoStEthStrategy));
        vm.stopPrank();

        // assets vault recieved less eth due to fee deducted by swap pool
        assertEq(address(assetsVault).balance, 1998740702841916233);
        assertApproxEqAbs(IStETH(stETHAdress).balanceOf(address(lidoStEthStrategy)), 0 ether, 1);
    }

    function test_destoryStrategyInRound0() external {
        vm.startPrank(proposal.addr);
        address[] memory strategies = new address[](1);
        uint256[] memory ratios = new uint256[](1);
        //test eth strategy
        strategies[0] = address(testEthStrategy);
        ratios[0] = 100_00_00; //100%
        // update strategy
        realVault.updateInvestmentPortfolio(strategies, ratios);
        vm.stopPrank();

        vm.startPrank(owner.addr);
        realVault.clearStrategy(address(lidoStEthStrategy));
        realVault.destroyStrategy(address(lidoStEthStrategy));
        vm.stopPrank();

        assertEq(address(assetsVault).balance, 1 ether);
    }

    function test_destoryLidoStrategy() external {
        deal(user.addr, 2 ether);
        deal(user2.addr, 2 ether);

        // increment the time to the next round
        vm.warp(epoch0 + realVault.rebaseTimeInterval());
        // roll epoch to Round#2
        realVault.rollToNextRound();

        deal(address(assetsVault), 0.1 ether);
        assertApproxEqAbs(IStETH(stETHAdress).balanceOf(address(lidoStEthStrategy)), 1 ether, 1);

        vm.startPrank(user2.addr);
        // deposit in Round#1 by user1 at 0.909090 pps
        realVault.deposit{value: 1 ether}();
        vm.stopPrank();

        assertApproxEqAbs(real.balanceOf(user2.addr), 909090909090909090, 1); //0.9090

        vm.startPrank(proposal.addr);
        address[] memory strategies = new address[](1);
        uint256[] memory ratios = new uint256[](1);
        //test eth strategy
        strategies[0] = address(testEthStrategy);
        ratios[0] = 100_00_00; //100%
        // update strategy
        realVault.updateInvestmentPortfolio(strategies, ratios);
        vm.stopPrank();

        // increment the time to the next round
        vm.warp(block.timestamp + realVault.rebaseTimeInterval());
        // roll epoch to Round#3
        realVault.rollToNextRound();

        (uint256 idleAmount, uint256 investedAmount) = realVault.getVaultAvailableAmount();

        assertEq(idleAmount, 0);
        assertEq(investedAmount, 2099370385713494260);
        assertEq(address(lidoStEthStrategy).balance, 0 ether);
        assertEq(address(testEthStrategy).balance, 2099370385713494260);
    }

    function test_destoryOtherStrategy() external {
        vm.startPrank(proposal.addr);
        address[] memory strategiesNew = new address[](2);
        uint256[] memory ratiosNew = new uint256[](2);
        //add eth strategy
        strategiesNew[0] = address(testEthStrategy);
        ratiosNew[0] = 50_00_00; //100%
        //add lido strategy
        strategiesNew[1] = address(lidoStEthStrategy);
        ratiosNew[1] = 50_00_00; //100%
        // update strategy
        realVault.updateInvestmentPortfolio(strategiesNew, ratiosNew);
        vm.stopPrank();

        // increment the time to the next round
        vm.warp(epoch0 + realVault.rebaseTimeInterval());
        // roll epoch to Round#1
        realVault.rollToNextRound();

        deal(address(testEthStrategy), 0.6 ether);
        deal(user2.addr, 2 ether);

        vm.startPrank(user2.addr);
        // deposit in Round#1 by user1 at 0.909090 pps
        realVault.deposit{value: 1 ether}();
        vm.stopPrank();

        // increment the time to the next round
        vm.warp(block.timestamp + realVault.rebaseTimeInterval());
        // roll epoch to Round#2
        realVault.rollToNextRound();

        // remove the testEthStrategy portfolio allocation
        vm.startPrank(proposal.addr);
        address[] memory strategies = new address[](1);
        uint256[] memory ratios = new uint256[](1);
        //test eth strategy
        strategies[0] = address(lidoStEthStrategy);
        ratios[0] = 100_00_00; //100%
        // update strategy
        realVault.updateInvestmentPortfolio(strategies, ratios);
        vm.stopPrank();

        // clear and destory testEthStrategy
        vm.startPrank(owner.addr);
        realVault.clearStrategy(address(testEthStrategy));
        realVault.destroyStrategy(address(testEthStrategy));
        vm.stopPrank();

        assertEq(address(testEthStrategy).balance, 0 ether);
        assertEq(address(assetsVault).balance, 1.05 ether);
        assertApproxEqAbs(IStETH(stETHAdress).balanceOf(address(lidoStEthStrategy)), 1.05 ether, 2);
    }

    function test_forceWithdraw() external {
        deal(user2.addr, 2 ether);
        vm.startPrank(user2.addr);
        // deposit in Round#1 by user1 at 0.909090 pps
        realVault.deposit{value: 1 ether}();
        vm.stopPrank();

        // increment the time to the next round
        vm.warp(epoch0 + realVault.rebaseTimeInterval());
        // roll epoch to Round#2
        realVault.rollToNextRound();

        assertEq(address(assetsVault).balance, 0 ether);

        vm.startPrank(address(realVault));
        strategyManager.forceWithdraw(2 ether);
        vm.stopPrank();

        // 0.001259297158 deducted as swap fees
        assertApproxEqAbs(address(assetsVault).balance, 2 ether, 0.0015 ether);
    }
}
