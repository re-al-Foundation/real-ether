// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

/**
 * @title CurvePool Interface
 * @dev Interface for interacting with a Curve.fi pool contract.
 */
interface ICurvePool {
    /**
     * @dev Exchanges one asset for another within the Curve pool.
     * @param from coin index of the asset to exchange from.
     * @param to coin index of the asset to exchange to.
     * @param input Amount of input asset to exchange.
     * @param minOutput Minimum acceptable amount of output asset to receive.
     * @return output The amount of output asset received.
     */
    function exchange(int128 from, int128 to, uint256 input, uint256 minOutput)
        external
        payable
        returns (uint256 output);

    /**
     * @dev Gets the virtual price of the pool.
     * @return price virtual price of the pool.
     */
    function get_virtual_price() external view returns (uint256 price);

    /**
     * @dev Gets the address of a coin within the pool.
     * @param index The index of the coin.
     * @return coin address of the coin.
     */
    function coins(uint256 index) external view returns (address coin);

    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
}
