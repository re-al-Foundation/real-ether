// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

import {IERC20} from "oz/token/ERC20/IERC20.sol";
import {SwapManager} from "src/utils/SwapManager.sol";
import {StrategyManager} from "src/StrategyManager.sol";
import {Test, console2 as console} from "forge-std/Test.sol";
import {LidoStEthStrategy} from "src/strategy/LidoStEthStrategy.sol";
import {TransferHelper} from "v3-periphery/libraries/TransferHelper.sol";
import {StETHVCurveMockPool} from "src/mock/StETHVCurveMockPool.sol";
import {WstETHV3MockPool} from "src/mock/WstETHV3MockPool.sol";
import {v3SwapRouterMock} from "src/mock/v3SwapRouterMock.sol";
import {LidoStEthStrategy} from "src/strategy/LidoStEthStrategy.sol";
import {IWStETH} from "src/interfaces/IWStETH.sol";

/**
 * @title Swap Manager Mock Test Cases
 * @author c-n-o-t-e
 * @dev Contract is used to test out Swap Manager Contract by forking the Mainnet chain to interacts
 *         with the LidoStEthStrategy by swapping either with Uniswap and Curve contracts.
 *
 * Functionalities Tested:
 * - Swaping wstETH to ETH via Uniswap protocol.
 * - Swaping stETH to ETH via Curve protocol.
 */
contract SwapManagerMockTest is Test {
    error SwapManager__NoLiquidity();
    error SwapManager__NoPool();

    SwapManager public swapManager;
    StrategyManager public strategyManager;
    LidoStEthStrategy public lidoStEthStrategy;
    StETHVCurveMockPool public stETH_ETH;
    WstETHV3MockPool public wstETH_ETH;
    v3SwapRouterMock public v3SwapRouter;

    address strategyManagerAddress;
    address lidoStEthStrategyAddress;

    address NULL = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address stETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address stEthHolder = 0xE53FFF67f9f384d20Ebea36F43b93DC49Ed22753;
    address stETHWithdrawal = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        vm.createSelectFork(MAINNET_RPC_URL, 19340830);
        v3SwapRouter = new v3SwapRouterMock();
        swapManager = new SwapManager(address(this), WETH9, NULL, address(v3SwapRouter));
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

        strategyManager = new StrategyManager(address(1), payable(address(1)), strategies, ratios);

        wstETH_ETH = new WstETHV3MockPool(wstETH, WETH9, 100);
        stETH_ETH = new StETHVCurveMockPool(stETH, NULL);

        swapManager.setWhitelistV3Pool(wstETH, address(wstETH_ETH), 0);
        swapManager.setWhitelistCurvePool(stETH, address(stETH_ETH), 0);
    }

    function test_RevertPools() public {
        // SwapManager__NoPool
        vm.expectRevert();
        swapManager.swapUinv3(stETH, 0);

        // SwapManager__NoPool
        vm.expectRevert();
        swapManager.swapCurve(wstETH, 0);

        // SwapManager__SlippageNotSet
        vm.expectRevert();
        swapManager.swapUinv3(wstETH, 0);

        vm.expectRevert();
        swapManager.swapCurve(stETH, 0);

        swapManager.setTokenSlippage(NULL, 5_00_00); //5%
        swapManager.setTokenSlippage(WETH9, 5_00_00); //5%

        // SwapManager__NoLiquidity
        vm.expectRevert();
        swapManager.swapUinv3(wstETH, 0);

        vm.expectRevert();
        swapManager.swapCurve(stETH, 0);

        deal(wstETH, address(this), 2 ether);
        v3SwapRouter.setAmountOut(0.94 ether);
        IERC20(wstETH).approve(address(swapManager), 1 ether);
        vm.expectRevert();
        swapManager.swapUinv3(wstETH, 1 ether);

        v3SwapRouter.setAmountOut(0.99 ether);
        IERC20(wstETH).approve(address(swapManager), 1 ether);
        swapManager.swapUinv3(wstETH, 1 ether);
        assertEq(address(this).balance, 79228162514264337593543950335);

        deal(WETH9, address(swapManager), 1 ether);
        v3SwapRouter.setAmountOut(0.99 ether);
        IERC20(wstETH).approve(address(swapManager), 1 ether);
        swapManager.swapUinv3(wstETH, 1 ether);
        assertEq(address(this).balance, 79228162515264337593543950335);
    }

    function test_RevertWhitelistV3Pool() public {
        vm.expectRevert();
        swapManager.setWhitelistV3Pool(address(0), address(0), 0);

        vm.expectRevert();
        swapManager.setWhitelistV3Pool(stETH, address(wstETH_ETH), 6_00_00);

        vm.expectRevert();
        swapManager.setWhitelistV3Pool(stETH, address(wstETH_ETH), 5_00_00);

        wstETH_ETH.updateTokens(WETH9, wstETH);
        vm.expectRevert();
        swapManager.setWhitelistV3Pool(stETH, address(wstETH_ETH), 5_00_00);
    }

    function test_RevertWhitelistCurvePool() public {
        vm.expectRevert();
        swapManager.setWhitelistCurvePool(address(0), address(0), 0);

        vm.expectRevert();
        swapManager.setWhitelistCurvePool(wstETH, address(stETH_ETH), 6_00_00);

        vm.expectRevert();
        swapManager.setWhitelistCurvePool(wstETH, address(stETH_ETH), 5_00_00);

        stETH_ETH.updateTokens(NULL, stETH);
        vm.expectRevert();
        swapManager.setWhitelistCurvePool(wstETH, address(stETH_ETH), 5_00_00);
    }

    function test_RevertSetTokenSlippage() public {
        vm.expectRevert();
        swapManager.setTokenSlippage(stETH, 6_00_00);
    }

    function test_RevertSetTwapDuration() public {
        vm.expectRevert();
        swapManager.setTwapDuration(180);

        swapManager.setTwapDuration(64_00);
        assertEq(swapManager.twapDuration(), 64_00);
    }

    function test_EstimateV3AmountOut() public {
        wstETH_ETH.setTickCumulatives(-6000, -8000);
        uint256 amount = swapManager.estimateV3AmountOut(1 ether, wstETH, WETH9);
        assertEq(amount, 999900009999000099);

        wstETH_ETH.setTickCumulatives(0, 1897089600);
        amount = swapManager.estimateV3AmountOut(1 ether, wstETH, WETH9);
        assertEq(amount, 76705880768030338428159535831433241511516);
    }

    function test_RevertInstantWithdraw() public {
        swapManager.setTokenSlippage(NULL, 5_00_00); //5%
        swapManager.setTokenSlippage(WETH9, 5_00_00); //5%

        vm.startPrank(address(lidoStEthStrategy));
        deal(wstETH, address(lidoStEthStrategy), 2 ether);
        IWStETH(wstETH).unwrap(2 ether);
        vm.stopPrank();

        vm.startPrank(address(strategyManager));
        deal(WETH9, address(swapManager), 1 ether);
        v3SwapRouter.setAmountOut(0.99 ether);
        lidoStEthStrategy.instantWithdraw(1 ether);
        assertEq(address(this).balance, 79228162514264337593543950335);

        vm.startPrank(address(strategyManager));
        deal(WETH9, address(swapManager), 0.8 ether);
        v3SwapRouter.setAmountOut(0.99 ether);
        vm.expectRevert();
        lidoStEthStrategy.instantWithdraw(1 ether);

        deal(WETH9, address(swapManager), 1 ether);
        deal(address(swapManager), 1 ether);
        v3SwapRouter.setAmountOut(0.1 ether);
        stETH_ETH.setAmountOut(0.99 ether);
        lidoStEthStrategy.instantWithdraw(1 ether);
        assertEq(address(this).balance, 79228162514264337593543950335);
        vm.stopPrank();
    }

    function test_RevertClear() public {
        swapManager.setTokenSlippage(NULL, 5_00_00); //5%
        swapManager.setTokenSlippage(WETH9, 5_00_00); //5%

        vm.startPrank(address(lidoStEthStrategy));
        deal(wstETH, address(lidoStEthStrategy), 1 ether);
        IWStETH(wstETH).unwrap(1 ether);
        vm.stopPrank();

        vm.startPrank(address(strategyManager));
        deal(address(swapManager), 1 ether);
        v3SwapRouter.setAmountOut(0.98 ether);
        stETH_ETH.setAmountOut(0.99 ether);
        lidoStEthStrategy.clear();
        assertEq(address(1).balance, 56759646223094277158);
        vm.stopPrank();
    }

    receive() external payable {}
}
