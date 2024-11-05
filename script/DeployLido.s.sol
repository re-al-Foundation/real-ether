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

    address realAddress = 0x0C68a3C11FB3550e50a4ed8403e873D367A8E361;
    address minterAddress = 0x6254c71Eae8476BE8fd0B9F14AEB61d578422991;

    /// @dev  addresses
    address stETHAdress = 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034;
    address wstETHAdress = 0x8d09a4502Cc8Cf1547aD300E066060D043f6982D;
    address stETHWithdrawal = 0xc7cc160b58F8Bb0baC94b80847E2CF2800565C50;
    address WETH9 = 0x6B5817E7091BC0C747741E96820b0199388245EA;

    address v3SwapRouter = 0x0a42599e0840aa292C76620dC6d4DAfF23DB5236;
    address NULL = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address wstETHV3Pool = 0x746ac36c280E9b1c9b61B73daE3E8433C90cA013;
    address stETHCurvePool = 0xE6B65B8282807422ff0E31fD914457C4BE4Fa7Ef;

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
        _matchPrecompute();
        _migrateVault();
    }

    function _createVaultAndStrategy() internal {
        realVault = new RealVault(
            _deployer, minterAddress, payable(assetVaultAddress), payable(strategyManagerAddress), address(_deployer)
        ); // nonce

        assetsVault = new AssetsVault(address(realVault), strategyManagerAddress); // nonce + 1

        address[] memory strategies = new address[](1);
        uint256[] memory ratios = new uint256[](1);

        swapManager = new SwapManager(_deployer, WETH9, NULL, v3SwapRouter); // nonce + 2
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
        RealVault oldVault = RealVault(payable(0x0C8a308f05dBdFc29268fC599ad6CA56d2B27A39));
        address oldAVault = 0x2884c41ef12a2967e3E182294754e7239eC30316;

        oldVault.migrateVault(address(realVault));

        require(IMinter(0x6254c71Eae8476BE8fd0B9F14AEB61d578422991).vault() == address(realVault), "!realVault");
        require(assetsVault.realVault() == address(realVault), "!realVault");
        require(assetsVault.strategyManager() == address(strategyManager), "!strategyManager");
        require(address(assetsVault) == strategyManager.assetsVault(), "!assetsVault");

        uint256 BalanceBefore = address(oldAVault).balance;
        // migrate asset to new asset Vault
        realVault.migrateOldAssetVault(oldAVault);
        require(BalanceBefore == address(assetsVault).balance, "!balance");

        realVault.setRebaseInterval(36_00);

        vm.stopBroadcast();
    }

    function test() public {}
}
