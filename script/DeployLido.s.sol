// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2 as console} from "forge-std/Script.sol";

import {Real} from "src/token/Real.sol";
import {RealVault} from "src/RealVault.sol";
import {StrategyManager} from "src/StrategyManager.sol";
import {AssetsVault} from "src/AssetsVault.sol";
import {LidoStEthStrategy} from "src/strategy/LidoStEthStrategy.sol";
import {SwapManager} from "src/utils/SwapManager.sol";
import {IMinter} from "src/interfaces/IMinter.sol";
import {IStETH} from "src/interfaces/IStETH.sol";
import {IRealVault} from "src/interfaces/IRealVault.sol";

contract DeployLidoScript is Script {
    address realVaultAddress;
    address assetVaultAddress;
    address strategyManagerAddress;
    address _deployer;

    RealVault realVault;
    StrategyManager strategyManager;
    AssetsVault assetsVault;
    LidoStEthStrategy lidoStrategy;
    SwapManager swapManager;

    address realAddress = 0xC0Cc5eA00cAe0894B441E3B5a3Bb57aa92F15421;
    address minterAddress = 0x655756824385F8903AC8cFDa17B656cc26f7C7da;
    address oldVaultAddress = 0xA5E77aDCdC2F1c55e7894A4021763B4D63C54638;

    address admin = 0xeB658c4Ea908aC4dAF9c309D8f883d6aD758b3A3;
    address proposal = 0xeB658c4Ea908aC4dAF9c309D8f883d6aD758b3A3;

    /// @dev  addresses
    address stETHAdress = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address wstETHAdress = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address stETHWithdrawal = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;
    address WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address v3SwapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address NULL = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address wstETHV3Pool = 0x109830a1AAaD605BbF02a9dFA7B0B92EC2FB7dAa;
    address stETHCurvePool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;

    function setUp() public {}

    function run() public {
        uint256 _pk = uint256(vm.envBytes32("PRIVATE_KEY"));

        vm.startBroadcast(_pk);
        _deployer = vm.addr(_pk);

        require(msg.sender == _deployer, "!deployer");

        uint64 n = vm.getNonce(msg.sender);
        realVaultAddress = vm.computeCreateAddress(_deployer, n);
        assetVaultAddress = vm.computeCreateAddress(_deployer, n + 1);
        strategyManagerAddress = vm.computeCreateAddress(_deployer, n + 4);

        _createVaultAndStrategy();
        _setPoolWhiteList();
        _matchPrecompute();
        _migrateVault();

        vm.stopBroadcast();
    }

    function _createVaultAndStrategy() internal {
        realVault = new RealVault(
            admin, minterAddress, payable(assetVaultAddress), payable(strategyManagerAddress), address(proposal)
        ); // nonce

        assetsVault = new AssetsVault(address(realVault), strategyManagerAddress); // nonce + 1

        address[] memory strategies = new address[](1);
        uint256[] memory ratios = new uint256[](1);

        swapManager = new SwapManager(admin, WETH9, NULL, v3SwapRouter); // nonce + 2
        lidoStrategy = new LidoStEthStrategy(
            stETHAdress,
            stETHWithdrawal,
            wstETHAdress,
            WETH9,
            address(swapManager),
            payable(strategyManagerAddress),
            "Lido Investment Strategy"
        ); // nonce + 3

        strategies[0] = address(lidoStrategy);
        ratios[0] = 1000_000; // 1e6
        strategyManager = new StrategyManager(address(realVault), payable(assetsVault), strategies, ratios); // nonce + 4
    }

    function _matchPrecompute() internal view {
        require(realVaultAddress == address(realVault), "!realVault");
        require(assetVaultAddress == address(assetsVault), "!assetsVault");
        require(strategyManagerAddress == address(strategyManager), "!strategyManager");
    }

    function _migrateVault() internal {
        uint256 BalanceBefore = oldVaultAddress.balance;
        IRealVault(oldVaultAddress).migrateVault(address(realVault));

        require(IMinter(minterAddress).vault() == address(realVault), "!realVault");
        require(assetsVault.realVault() == address(realVault), "!realVault");
        require(assetsVault.strategyManager() == address(strategyManager), "!strategyManager");
        require(address(assetsVault) == strategyManager.assetsVault(), "!assetsVault");
        require(BalanceBefore == address(assetsVault).balance, "!balance");

        console.log("Balance", oldVaultAddress.balance, address(assetsVault).balance);
        console.log("Vault", IMinter(minterAddress).vault(), assetsVault.realVault(), strategyManager.realVault());
        console.log("AssetVault", realVault.assetsVault(), strategyManager.assetsVault());
        console.log("strategyManager", realVault.strategyManager(), assetsVault.strategyManager());
        console.log("Owner", realVault.owner(), realVault.proposal(), swapManager.owner());

        // realVault.deposit{value: 0.1 ether}(0);
        // realVault.rollToNextRound();
        // realVault.instantWithdraw(0, 0.1 ether);
    }

    function _setPoolWhiteList() internal {
        swapManager.setWhitelistV3Pool(wstETHAdress, wstETHV3Pool, 0);
        swapManager.setWhitelistCurvePool(stETHAdress, stETHCurvePool, 0); 
        swapManager.setTokenSlippage(WETH9, 1_00_00); // 1% slippage
    }

    function test() public {}
}
