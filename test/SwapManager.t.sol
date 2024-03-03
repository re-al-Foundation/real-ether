// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

import {IERC20} from "oz/token/ERC20/IERC20.sol";
import {SwapManager} from "src/utils/SwapManager.sol";
import {StrategyManager} from "src/StrategyManager.sol";
import {Test, console2 as console} from "forge-std/Test.sol";
import {LidoStEthStrategy} from "src/strategy/LidoStEthStrategy.sol";

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
    address stETHWithdrawal = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        vm.createSelectFork(MAINNET_RPC_URL, 19340830);

        // lidoStEthStrategyAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        strategyManagerAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 2);

        swapManager = new SwapManager(address(this), WETH9, NULL, 0xE592427A0AEce92De3Edee1F18E0157C05861564);

        address[] memory strategies = new address[](1);
        uint256[] memory ratios = new uint256[](1);

        lidoStEthStrategy = new LidoStEthStrategy(
            stETH,
            stETHWithdrawal,
            wstETH,
            WETH9,
            address(swapManager),
            payable(strategyManagerAddress),
            "Lido StEth Strategy Investment"
        );

        strategies[0] = address(lidoStEthStrategy);
        ratios[0] = 1000_000; // 1e6

        strategyManager = new StrategyManager(address(1), payable(address(1)), strategies, ratios);

        swapManager.setWhitelistV3Pool(wstETH, wstETH_ETH, 1000_000);
        swapManager.setWhitelistCurvePool(stETH, stETH_ETH, 1000_000);

        swapManager.setTokenSlippage(WETH9, 995_000);
        swapManager.setTokenSlippage(NULL, 995_000);
    }

    function test_swap() external {
        address stEthHolder = 0xE53FFF67f9f384d20Ebea36F43b93DC49Ed22753;
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

    receive() external payable {}
}
