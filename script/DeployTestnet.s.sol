// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {Real} from "src/token/Real.sol";
import {Minter} from "src/token/Minter.sol";
import {RealVault} from "src/RealVault.sol";
import {StrategyManager} from "src/StrategyManager.sol";
import {AssetsVault} from "src/AssetsVault.sol";
import {TestEthStrategy} from "src/mock/TestEthStrategy.sol";

contract DeployTestnetScript is Script {
    address realAddress;
    address minterAddress;
    address realVaultAddress;
    address assetVaultAddress;
    address strategyManagerAddress;
    address _deployer;

    Real real;
    Minter minter;
    RealVault realVault;
    StrategyManager strategyManager;
    AssetsVault assetsVault;

    function setUp() public {}

    function run() public {
        uint256 _pk = uint256(vm.envBytes32("PRIVATE_KEY"));
        // bytes32 _salt = keccak256(abi.encodePacked("real.ether"));

        vm.startBroadcast(_pk);
        _deployer = vm.addr(_pk);

        require(msg.sender == _deployer, "!deployer");

        uint64 n = vm.getNonce(msg.sender);
        realAddress = vm.computeCreateAddress(_deployer, n);
        minterAddress = vm.computeCreateAddress(_deployer, n + 1);
        realVaultAddress = vm.computeCreateAddress(_deployer, n + 2);
        assetVaultAddress = vm.computeCreateAddress(_deployer, n + 3);
        strategyManagerAddress = vm.computeCreateAddress(_deployer, n + 5);

        real = new Real(minterAddress);
        minter = new Minter(address(real), payable(realVaultAddress));

        _createVaultAndStrategy();
        _matchPrecompute();
        _mintShareTo0xdead(0.001 ether);

        vm.stopBroadcast();
    }

    function _createVaultAndStrategy() internal {
        realVault = new RealVault(
            _deployer, minterAddress, payable(assetVaultAddress), payable(strategyManagerAddress), address(_deployer)
        );

        assetsVault = new AssetsVault(address(realVault), strategyManagerAddress);

        address[] memory strategies = new address[](1);
        uint256[] memory ratios = new uint256[](1);
        TestEthStrategy s1 = new TestEthStrategy(payable(strategyManagerAddress), "Eth Investment");
        strategies[0] = address(s1);
        ratios[0] = 1000_000; // 1e6
        strategyManager = new StrategyManager(address(realVault), payable(assetsVault), strategies, ratios);
    }

    function _mintShareTo0xdead(uint256 _value) internal {
        if (block.chainid != 31337) {
            realVault.depositFor{value: _value}(address(0xdead));
        }
    }

    function _matchPrecompute() internal view {
        require(realAddress == address(real), "!real");
        require(minterAddress == address(minter), "!minter");
        require(realVaultAddress == address(realVault), "!realVault");
        require(assetVaultAddress == address(assetsVault), "!assetsVault");
        require(strategyManagerAddress == address(strategyManager), "!strategyManager");
    }

    /**
     * @dev Checks whether a contract is deployed at a given address. This function is crucial for determining the
     * deployment status of contracts, particularly in the context of proxy deployment and upgrades.
     *
     * The check is performed using low-level assembly code to query the size of the code at the specified address:
     * 1. The 'extcodesize' opcode is used to obtain the size of the contract's bytecode at the given address.
     * 2. A non-zero size indicates that a contract is deployed at the address.
     *
     * @param contractAddress The address to check for the presence of a contract.
     * @return isDeployed A boolean indicating whether a contract is deployed at the specified address. Returns 'true'
     * if a contract is present, and 'false' otherwise.
     */
    function _isDeployed(address contractAddress) internal view returns (bool isDeployed) {
        // slither-disable-next-line assembly
        assembly {
            let cs := extcodesize(contractAddress)
            if iszero(iszero(cs)) { isDeployed := true }
        }
    }
}
