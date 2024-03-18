// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

import {TransferHelper} from "v3-periphery/libraries/TransferHelper.sol";

contract UnderlyingYieldGenerator {
    error EthYield__ZeroAmount();
    error EthYield__InsufficientBalance();

    address public assetVault;

    constructor(address _assetVault) {
        assetVault = _assetVault;
    }

    function deposit() external payable {
        if (msg.value == 0) revert EthYield__ZeroAmount();
    }

    function withdraw(uint256 _ethAmount) external returns (uint256 actualAmount) {
        if (_ethAmount == 0) revert EthYield__ZeroAmount();
        if (_ethAmount > address(this).balance) revert EthYield__InsufficientBalance();
        actualAmount = _ethAmount;
        // inflate the vault eth
        TransferHelper.safeTransferETH(assetVault, 10 ether);
    }

    receive() external payable {}
}
