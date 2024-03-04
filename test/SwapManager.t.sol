// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

import {IERC20} from "oz/token/ERC20/IERC20.sol";
import {SwapManager} from "src/utils/SwapManager.sol";
import {StrategyManager} from "src/StrategyManager.sol";
import {Test, console2 as console} from "forge-std/Test.sol";
import {LidoStEthStrategy} from "src/strategy/LidoStEthStrategy.sol";
import {TransferHelper} from "v3-periphery/libraries/TransferHelper.sol";

/**
 * @title Swap Manager Test Cases
 * @author c-n-o-t-e
 * @dev Contract is used to test out Swap Manager Contract by forking the Mainnet chain to interacts
 *         with the LidoStEthStrategy by swapping either with Uniswap and Curve contracts.
 *
 * Functionalities Tested:
 * - Swaping wstETH to ETH via Uniswap protocol.
 * - Swaping stETH to ETH via Curve protocol.
 */

contract SwapManagerTest is Test {
    SwapManager public swapManager;
    StrategyManager public strategyManager;
    LidoStEthStrategy public lidoStEthStrategy;

    address strategyManagerAddress;
    address lidoStEthStrategyAddress;

    address NULL = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address stETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address stETH_ETH = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address wstETH_ETH = 0x109830a1AAaD605BbF02a9dFA7B0B92EC2FB7dAa;
    address stEthHolder = 0xE53FFF67f9f384d20Ebea36F43b93DC49Ed22753;
    address v3SwapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address stETHWithdrawal = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        vm.createSelectFork(MAINNET_RPC_URL, 19340830);
        swapManager = new SwapManager(address(this), WETH9, NULL, v3SwapRouter);
        strategyManagerAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);

        uint256[] memory ratios = new uint256[](1);
        address[] memory strategies = new address[](1);

        lidoStEthStrategy = new LidoStEthStrategy(
            stETH,
            stETHWithdrawal,
            wstETH,
            WETH9,
            address(swapManager),
            payable(strategyManagerAddress),
            "Lido StEth Strategy Investment"
        );

        ratios[0] = 1000_000; // 1e6
        strategies[0] = address(lidoStEthStrategy);

        swapManager.setTokenSlippage(NULL, 995_000);
        swapManager.setTokenSlippage(WETH9, 995_000);

        swapManager.setWhitelistV3Pool(wstETH, wstETH_ETH, 1000_000);
        swapManager.setWhitelistCurvePool(stETH, stETH_ETH, 1000_000);

        strategyManager = new StrategyManager(address(1), payable(address(1)), strategies, ratios);
    }

    function test_swap() external {
        vm.startPrank(stEthHolder);
        IERC20(stETH).transfer(address(lidoStEthStrategy), 1 ether);
        vm.stopPrank();

        console.log(strategyManagerAddress.balance, "before");

        vm.startPrank(strategyManagerAddress);
        lidoStEthStrategy.instantWithdraw(1 ether);
        vm.stopPrank();

        console.log(strategyManagerAddress.balance, "after");

        /**
         * ETH gotten from Uniswap 999370385713494261
         * ETH gotten from Curve 999295693619713647
         */
    }

    function test_swapCurve() external {
        vm.startPrank(stEthHolder);
        IERC20(stETH).transfer(address(this), 1 ether);
        vm.stopPrank();

        uint256 balBeforeTx = address(this).balance;
        TransferHelper.safeApprove(stETH, address(swapManager), 1 ether);

        swapManager.swapCurve(stETH, 1 ether);
        uint256 balAfterTx = address(this).balance;

        console.log(balAfterTx - balBeforeTx);
    }

    function test_swapV3() external {
        address wstEthHolder = 0x5313b39bf226ced2332C81eB97BB28c6fD50d1a3;
        vm.startPrank(wstEthHolder);

        IERC20(wstETH).transfer(address(this), 1 ether);
        vm.stopPrank();

        uint256 balBeforeTx = address(this).balance;
        TransferHelper.safeApprove(wstETH, address(swapManager), 1 ether);

        swapManager.swapUinv3(wstETH, 1 ether);
        uint256 balAfterTx = address(this).balance;

        // For context the amount of ETH gotten here is above
        // the ETH gotten in test_swap cause wstETH amount are different.
        console.log(balAfterTx - balBeforeTx);
    }

    receive() external payable {}
}
