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
    error Strategy__ZeroAddress();
    error Strategy__ZeroAmount();
    error Strategy__LidoDeposit();
    error Strategy__InsufficientBalance();
    error Strategy__ZeroPoolLiquidity();

    uint256 public constant ZERO_VALUE = 0;
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
        swapManager.setWhitelistV3Pool(wstETHAdress, wstETH_ETH, 0);
        swapManager.setWhitelistCurvePool(stETHAdress, stETH_ETH, 0);
        swapManager.setTokenSlippage(WETH9, 5_00_00); // 5%
        swapManager.setTokenSlippage(NULL, 5_00_00); // 5%

        testEthStrategy = new TestEthStrategy(payable(strategyManagerAddress), "Mock Eth Investment");

        epoch0 = block.timestamp;

        deal(deadShares.addr, 1 ether);
        vm.startPrank(deadShares.addr);

        realVault.deposit{value: 1 ether}(ZERO_VALUE);
        vm.stopPrank();

        vm.startPrank(address(0xdead));
        realVault.instantWithdraw(0, 0.001 ether);
        vm.stopPrank();
    }

    function test_instantWithdrawForDifferentUsers() public {
        LidoStEthStrategy[3] memory lido;

        for (uint256 i = 0; i < 3; i++) {
            lido[i] = new LidoStEthStrategy(
                stETHAdress,
                stETHWithdrawal,
                wstETHAdress,
                WETH9,
                swapManagerAddress,
                payable(strategyManagerAddress),
                "Lido StEth Strategy Investment"
            );
        }

        address[] memory strategies = new address[](4);
        uint256[] memory ratios = new uint256[](4);

        strategies[0] = address(lidoStEthStrategy);
        ratios[0] = 20_00_00; //20%
        strategies[1] = address(lido[0]);
        ratios[1] = 30_00_00; //30%
        strategies[2] = address(lido[1]);
        ratios[2] = 25_00_00; //25%
        strategies[3] = address(lido[2]);
        ratios[3] = 10_00_00; //10%

        vm.startPrank(proposal.addr);
        realVault.updateInvestmentPortfolio(strategies, ratios);
        vm.stopPrank();

        deal(user.addr, 10 ether);
        vm.startPrank(user.addr);
        realVault.deposit{value: 10 ether}(ZERO_VALUE);
        vm.stopPrank();

        deal(deployer.addr, 10 ether);
        vm.startPrank(deployer.addr);
        realVault.deposit{value: 10 ether}(ZERO_VALUE);
        vm.stopPrank();

        deal(user2.addr, 10 ether);
        vm.startPrank(user2.addr);
        realVault.deposit{value: 10 ether}(ZERO_VALUE);
        vm.stopPrank();

        // increment the time to the next round
        vm.warp(epoch0 + realVault.rebaseTimeInterval());

        uint256 totalBal = address(assetsVault).balance;

        // roll epoch to next round
        realVault.rollToNextRound();

        address[3] memory users = [user.addr, deployer.addr, user2.addr];

        for (uint256 i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            realVault.instantWithdraw(0, real.balanceOf(users[i]));
            vm.stopPrank();

            assertApproxEqAbs(users[i].balance, 10 ether, 0.5 ether);
        }

        uint256 balLeftInPool = IStETH(stETHAdress).sharesOf(address(lidoStEthStrategy))
            + IStETH(stETHAdress).sharesOf(address(lido[0])) + IStETH(stETHAdress).sharesOf(address(lido[1]))
            + IStETH(stETHAdress).sharesOf(address(lido[2]));

        uint256 balLeftInPoolInETH = IStETH(stETHAdress).getPooledEthByShares(balLeftInPool);
        assertApproxEqAbs(balLeftInPoolInETH, real.balanceOf(deadShares.addr), 20);
    }

    function test_deposit() external {
        deal(user.addr, 1 ether);
        vm.startPrank(user.addr);

        realVault.deposit{value: 1 ether}(ZERO_VALUE);
        vm.stopPrank();

        assertEq(IStETH(stETHAdress).balanceOf(address(lidoStEthStrategy)), 0);
        vm.warp(block.timestamp + 1 days);

        realVault.rollToNextRound();
        assertApproxEqAbs(IStETH(stETHAdress).balanceOf(address(lidoStEthStrategy)), 2 ether, 1);
    }

    function test_requestWithdrawals() external {
        deal(user.addr, 1 ether);
        vm.startPrank(user.addr);

        uint256 shares = realVault.deposit{value: 1 ether}(ZERO_VALUE);
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

        uint256 shares = realVault.deposit{value: 1 ether}(ZERO_VALUE);
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
        realVault.deposit{value: 1 ether}(ZERO_VALUE);
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
        realVault.deposit{value: 1 ether}(ZERO_VALUE);
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
        realVault.deposit{value: 1 ether}(ZERO_VALUE);
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
        realVault.deposit{value: 1 ether}(ZERO_VALUE);
        vm.stopPrank();

        // increment the time to the next round
        vm.warp(epoch0 + realVault.rebaseTimeInterval());
        // roll epoch to Round#2
        realVault.rollToNextRound();

        assertEq(address(assetsVault).balance, 0 ether);

        vm.startPrank(address(realVault));
        strategyManager.forceWithdraw(1999999999999999999);
        vm.stopPrank();

        // 0.001259297158 deducted as swap fees
        assertApproxEqAbs(address(assetsVault).balance, 2 ether, 0.0015 ether);
    }

    function test_WithdrawalQueue() external {
        deal(user.addr, 10 ether);
        vm.startPrank(user.addr);

        uint256 shares = realVault.deposit{value: 10 ether}(ZERO_VALUE);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        realVault.rollToNextRound();

        vm.startPrank(proposal.addr);
        address[] memory strategies = new address[](1);
        uint256[] memory ratios = new uint256[](1);
        //test eth strategy
        strategies[0] = address(lidoStEthStrategy);
        ratios[0] = 60_00_00; //60%
        // update strategy
        realVault.updateInvestmentPortfolio(strategies, ratios);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        realVault.rollToNextRound();

        assertEq(lidoStEthStrategy.getRequestIds()[0], 28235);

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

        (, uint256 totalClaimableAfterTx0,) = lidoStEthStrategy.checkPendingAssets();
        assertEq(totalClaimableAfterTx0, 4.4 ether);

        lidoStEthStrategy.claimAllPendingAssets();
        assertEq(address(assetsVault).balance, 4.4 ether);
        assertEq(lidoStEthStrategy.getRequestIds().length, 0);
    }

    function test_WithdrawalQueueWithEthTransfer() external {
        deal(user.addr, 2_000 ether);
        vm.startPrank(user.addr);

        uint256 shares = realVault.deposit{value: 2_000 ether}(ZERO_VALUE);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        realVault.rollToNextRound();

        vm.startPrank(proposal.addr);
        address[] memory strategies = new address[](1);
        uint256[] memory ratios = new uint256[](1);
        //test eth strategy
        strategies[0] = address(lidoStEthStrategy);
        ratios[0] = 20_00_00; //20%
        // update strategy
        realVault.updateInvestmentPortfolio(strategies, ratios);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        realVault.rollToNextRound();

        assertEq(lidoStEthStrategy.getRequestIdsLen(), 2);
        assertEq(lidoStEthStrategy.getRequestIds()[0], 28235);

        uint256[] memory rIds = new uint256[](2);
        rIds[0] = 28235;
        rIds[1] = 28236;
        lidoStEthStrategy.checkPendingAssets(rIds);

        address finalizer = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; //stETH token
        uint256 lastRequestId = IWithdrawalQueueERC721(stETHWithdrawal).getLastRequestId();

        uint256[] memory batches = new uint256[](1);
        batches[0] = lastRequestId;

        (uint256 ethToLock, uint256 sharesToBurn) = IWithdrawalQueueERC721(stETHWithdrawal).prefinalize(batches, 1e27);

        // update the eth balance in stETH
        deal(finalizer, 95_000 ether);

        vm.startPrank(finalizer);
        uint256 sharesToBurnWithPrecision = sharesToBurn * 1e27;
        IWithdrawalQueueERC721(stETHWithdrawal).finalize{value: ethToLock}(lastRequestId, sharesToBurnWithPrecision);
        vm.stopPrank();

        (, uint256 totalClaimableAfterTx0,) = lidoStEthStrategy.checkPendingAssets();
        assertEq(totalClaimableAfterTx0, 1600.8 ether);

        uint256[] memory _requestsIds = new uint256[](1);
        _requestsIds[0] = 28235;
        IWithdrawalQueueERC721(stETHWithdrawal).getWithdrawalRequests(address(lidoStEthStrategy));
        uint256[] memory _hintIds = IWithdrawalQueueERC721(stETHWithdrawal).findCheckpointHints(
            _requestsIds, 1, IWithdrawalQueueERC721(stETHWithdrawal).getLastCheckpointIndex()
        );

        lidoStEthStrategy.claimAllPendingAssetsByIds(_requestsIds, _hintIds);
        assertEq(address(assetsVault).balance, 1000 ether);

        // check
        lidoStEthStrategy.checkPendingStatus();
        lidoStEthStrategy.checkPendingAssets(rIds);
        lidoStEthStrategy.getStETHWithdrawalStatus();
        lidoStEthStrategy.getStETHWithdrawalStatusForIds(rIds);

        // check the invested values
        assertEq(lidoStEthStrategy.getTotalValue(), 1001 ether);
        assertEq(lidoStEthStrategy.getClaimableAndPendingValue(), 600.8 ether);
        assertEq(lidoStEthStrategy.getClaimableValue(), 600.8 ether);

        //donate eth
        deal(address(lidoStEthStrategy), 0.1 ether);
        _requestsIds[0] = 28236;
        IWithdrawalQueueERC721(stETHWithdrawal).getWithdrawalRequests(address(lidoStEthStrategy));
        _hintIds = IWithdrawalQueueERC721(stETHWithdrawal).findCheckpointHints(
            _requestsIds, 1, IWithdrawalQueueERC721(stETHWithdrawal).getLastCheckpointIndex()
        );
        lidoStEthStrategy.claimAllPendingAssetsByIds(_requestsIds, _hintIds);
        assertEq(address(assetsVault).balance, 1600.9 ether);
        assertEq(lidoStEthStrategy.getRequestIds().length, 0);
    }

    function test_WithdrawalQueueMax() external {
        deal(user.addr, 1_000_000 ether);
        vm.startPrank(user.addr);

        uint256 shares = realVault.deposit{value: 1_00_00 ether}(ZERO_VALUE);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        realVault.rollToNextRound();

        vm.startPrank(proposal.addr);
        address[] memory strategies = new address[](1);
        uint256[] memory ratios = new uint256[](1);
        //test eth strategy
        strategies[0] = address(lidoStEthStrategy);
        ratios[0] = 20_00_00; //20%
        // update strategy
        realVault.updateInvestmentPortfolio(strategies, ratios);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        realVault.rollToNextRound();

        assertEq(lidoStEthStrategy.getRequestIds().length, 9);

        address finalizer = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; //stETH token
        uint256 lastRequestId = IWithdrawalQueueERC721(stETHWithdrawal).getLastRequestId();

        uint256[] memory batches = new uint256[](1);
        batches[0] = lastRequestId;

        (uint256 ethToLock, uint256 sharesToBurn) = IWithdrawalQueueERC721(stETHWithdrawal).prefinalize(batches, 1e27);

        // update the eth balance in stETH
        deal(finalizer, 250_00 ether);

        vm.startPrank(finalizer);
        uint256 sharesToBurnWithPrecision = sharesToBurn * 1e27;
        IWithdrawalQueueERC721(stETHWithdrawal).finalize{value: ethToLock}(lastRequestId, sharesToBurnWithPrecision);
        vm.stopPrank();

        (, uint256 totalClaimableAfterTx0,) = lidoStEthStrategy.checkPendingAssets();
        assertEq(totalClaimableAfterTx0, 8000.8 ether); //80% of 10,000 ETH as claimable

        lidoStEthStrategy.claimAllPendingAssets();
        assertEq(lidoStEthStrategy.getRequestIds().length, 0);

        (, uint256 totalClaimable,) = lidoStEthStrategy.checkPendingAssets();
        assertEq(totalClaimable, 0);
    }

    function test_WithdrawalQueueMin() external {
        deal(user.addr, 1_000_000 ether);
        vm.startPrank(user.addr);

        uint256 shares = realVault.deposit{value: 1_00_00 ether}(ZERO_VALUE);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        realVault.rollToNextRound();

        vm.startPrank(address(strategyManager));
        lidoStEthStrategy.withdraw(10); //10wei

        (,, uint256 totalPending) = lidoStEthStrategy.checkPendingAssets();
        assertEq(totalPending, 0); // MIN_STETH_WITHDRAWAL_AMOUNT

        vm.stopPrank();
    }

    function test_SetGovernance() external {
        vm.expectRevert(abi.encodeWithSelector(Strategy__ZeroAddress.selector));
        lidoStEthStrategy.setGovernance(address(0));

        lidoStEthStrategy.setGovernance(user.addr);
        assertEq(lidoStEthStrategy.governance(), user.addr);
    }

    function test_depositFail() public {
        vm.startPrank(strategyManagerAddress);
        deal(strategyManagerAddress, 1 ether);
        vm.expectRevert(Strategy__LidoDeposit.selector);
        lidoStEthStrategy.deposit{value: 1}();

        vm.expectRevert(Strategy__ZeroAmount.selector);
        lidoStEthStrategy.deposit{value: 0}();
        vm.stopPrank();
    }

    function test_withdrawFail() public {
        vm.startPrank(strategyManagerAddress);
        deal(strategyManagerAddress, 1 ether);
        vm.expectRevert(Strategy__ZeroAmount.selector);
        lidoStEthStrategy.withdraw(0);

        vm.expectRevert(Strategy__InsufficientBalance.selector);
        lidoStEthStrategy.withdraw(1 ether);

        // return zero
        lidoStEthStrategy.instantWithdraw(0);

        vm.expectRevert(Strategy__ZeroPoolLiquidity.selector);
        lidoStEthStrategy.instantWithdraw(1);

        lidoStEthStrategy.clear();

        uint256[] memory ids;
        (ids,,) = lidoStEthStrategy.checkPendingAssets(ids);
        assertEq(ids.length, 0);

        uint256[] memory ids2 = new uint256[](1);
        ids2[0] = 123456;
        vm.expectRevert();
        lidoStEthStrategy.checkPendingAssets(ids2);
        vm.stopPrank();
    }

    function test_TransferETHDuringWithdraw() external {
        deal(user.addr, 1_000_000 ether);
        vm.startPrank(user.addr);

        uint256 shares = realVault.deposit{value: 1_00_00 ether}(ZERO_VALUE);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        realVault.rollToNextRound();

        vm.startPrank(address(strategyManager));
        deal(address(lidoStEthStrategy), 0.1 ether);
        lidoStEthStrategy.withdraw(1_000); //1000wei
        assertEq(address(assetsVault).balance, 0); // MIN_STETH_WITHDRAWAL_AMOUNT

        vm.stopPrank();
    }
}
