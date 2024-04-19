// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

contract StETHVCurveMockPool {
    mapping(uint256 => address) coinsIndex;
    uint256 amountOut;

    constructor(address coin0, address coin1) {
        coinsIndex[0] = coin0;
        coinsIndex[1] = coin1;
    }

    function coins(uint256 index) external view returns (address coin) {
        coin = coinsIndex[index];
    }

    function get_dy(int128, int128, uint256) external view returns (uint256) {
        return amountOut;
    }

    function exchange(int128, int128, uint256, uint256) external payable returns (uint256 output) {
        output = amountOut;
    }

    function updateTokens(address _coin0, address _coin1) external {
        coinsIndex[0] = _coin0;
        coinsIndex[1] = _coin1;
    }

    function setAmountOut(uint256 _amount) external returns (uint256) {
        amountOut = _amount;
    }

    function test() public {}
}
