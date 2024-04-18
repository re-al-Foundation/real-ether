// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

contract WstETHV3MockPool {
    address public token0;
    address public token1;
    uint24 public fee;

    int56[] tickCumulativesList;

    constructor(address _token0, address _token1, uint24 _fee) {
        token0 = _token0;
        token1 = _token1;
        fee = _fee;

        tickCumulativesList.push(0);
        tickCumulativesList.push(0);
    }

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        tickCumulatives = tickCumulativesList;
        secondsPerLiquidityCumulativeX128s = new uint160[](secondsAgos.length);
    }

    function swap(address, bool, int256, uint160, bytes calldata)
        external
        pure
        returns (int256 amount0, int256 amount1)
    {
        amount0 = 0;
        amount1 = 0;
    }

    function updateTokens(address _token0, address _token1) external {
        token0 = _token0;
        token1 = _token1;
    }

    function setTickCumulatives(int56 tick0, int56 tick1) external {
        tickCumulativesList[0] = tick0;
        tickCumulativesList[1] = tick1;
    }

    function test() public {}
}
