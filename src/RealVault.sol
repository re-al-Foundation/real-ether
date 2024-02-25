// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC4626.sol

contract RealVault {
    constructor() {}

    function currentSharePrice() public returns (uint256 price) {}

    receive() external payable {}
}
