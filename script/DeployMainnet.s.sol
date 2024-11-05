// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {Real} from "src/token/Real.sol";
import {Minter} from "src/token/Minter.sol";
// import {RealVaultMigrator} from "src/mock/RealVaultMigrator.sol";
import {TransparentUpgradeableProxy} from "oz/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployMainnet is Script {
    address admin = 0xeB658c4Ea908aC4dAF9c309D8f883d6aD758b3A3;
    address deployer = 0xeB658c4Ea908aC4dAF9c309D8f883d6aD758b3A3;

    address realAddress;
    address minterAddress;
    address realVaultAddress;
    address realVaultProxyAddress;

    Real real;
    Minter minter;
    // RealVaultMigrator realVault;
    TransparentUpgradeableProxy realVaultProxy;

    function setUp() public {}

    function run() public {
        uint256 _pk = uint256(vm.envBytes32("PRIVATE_KEY"));
        // bytes32 _salt = keccak256(abi.encodePacked("real.ether"));

        vm.startBroadcast(_pk);

        require(msg.sender == deployer, "!deployer");

        //deploy new vault with strategyManager

        uint64 n = vm.getNonce(deployer);
        realAddress = vm.computeCreateAddress(deployer, n);
        minterAddress = vm.computeCreateAddress(deployer, n + 1);
        realVaultAddress = vm.computeCreateAddress(deployer, n + 2);
        realVaultProxyAddress = vm.computeCreateAddress(deployer, n + 3);

        // realAddress = 0x9801EEB848987c0A8d6443912827bD36C288F8FB;
        // minterAddress = 0x0C68a3C11FB3550e50a4ed8403e873D367A8E361;
        // realVaultProxyAddress = 0xfF2b3C6f4f5e913b2d41cCB20f6D759273350034;

        real = new Real(minterAddress);
        minter = new Minter(address(real), payable(realVaultProxyAddress));
        // realVault = new RealVaultMigrator();
        // bytes memory data = abi.encodeWithSignature("initialize(address,address)", deployer, address(minter));
        // realVaultProxy = new TransparentUpgradeableProxy(address(realVault), admin, data);
        // console2.log("Transparent Proxy Address:", address(realVaultProxy));

        _matchPrecompute();
        vm.stopBroadcast();
    }

    function _matchPrecompute() internal view {
        require(realAddress == address(real), "!real");
        require(minterAddress == address(minter), "!minter");
        require(realVaultProxyAddress == address(realVaultProxy), "!realVault");
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
