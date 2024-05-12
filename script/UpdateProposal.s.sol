// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2 as console} from "forge-std/Script.sol";

import {IRealVault} from "src/interfaces/IRealVault.sol";
import {IStETH} from "src/interfaces/IStETH.sol";
import {IStrategyManager} from "src/interfaces/IStrategyManager.sol";
import {IWithdrawalQueueERC721} from "src/interfaces/IWithdrawalQueueERC721.sol";

contract UpdateProposalScript is Script {
    function setUp() public {}

    address vault = 0x0C8a308f05dBdFc29268fC599ad6CA56d2B27A39;
    address stETHAdress = 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034;
    address stETHWithdrawal = 0xc7cc160b58F8Bb0baC94b80847E2CF2800565C50;
    address lidoStrategy = 0x32243729AEefE0Bf3eD4fa1af915A29a66FC6622;

    function run() public {
        uint256 _pk = uint256(vm.envBytes32("PRIVATE_KEY"));
        // bytes32 _salt = keccak256(abi.encodePacked("real.ether"));

        vm.startBroadcast(_pk);
        address _deployer = vm.addr(_pk);

        require(msg.sender == _deployer, "!deployer");

        address[] memory _strategies = new address[](1);
        _strategies[0] = lidoStrategy;

        uint256[] memory _ratios = new uint256[](1);
        _ratios[0] = 1;

        console.log("Before", IStETH(stETHAdress).balanceOf(_strategies[0]));
        IRealVault(vault).updateInvestmentPortfolio(_strategies, _ratios);
        IRealVault(vault).rollToNextRound();
        console.log("After", IStETH(stETHAdress).balanceOf(_strategies[0]));
        uint256[] memory requestsIds = IWithdrawalQueueERC721(stETHWithdrawal).getWithdrawalRequests(lidoStrategy);
        console.log("requestsIds", requestsIds[0]);

        vm.stopBroadcast();
    }
}
