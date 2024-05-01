// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.21;

import {IERC20} from "oz/token/ERC20/IERC20.sol";
import {IERC20Permit} from "oz/token/ERC20/extensions/IERC20Permit.sol";

/// @notice Interface defining a Lido liquid staking pool
/// @dev see also [Lido liquid staking pool core contract](https://docs.lido.fi/contracts/lido)
interface IStETH is IERC20, IERC20Permit {
    /**
     * @notice Send funds to the pool with optional _referral parameter
     * @dev This function is alternative way to submit funds. Supports optional referral address.
     * @return Amount of StETH shares generated
     */
    function submit(address _referral) external payable returns (uint256);

    /**
     * @return the amount of shares owned by `_account`.
     */
    function sharesOf(address _account) external view returns (uint256);

    /**
     * @notice Moves `_sharesAmount` token shares from the caller's account to the `_recipient` account.
     *
     * @return amount of transferred tokens.
     * Emits a `TransferShares` event.
     * Emits a `Transfer` event.
     *
     * Requirements:
     *
     * - `_recipient` cannot be the zero address.
     * - the caller must have at least `_sharesAmount` shares.
     * - the contract must not be paused.
     *
     * @dev The `_sharesAmount` argument is the amount of shares, not tokens.
     */
    function transferShares(address _recipient, uint256 _sharesAmount) external returns (uint256);

    /**
     * @return the amount of shares that corresponds to `_ethAmount` protocol-controlled Ether.
     */
    function getSharesByPooledEth(uint256 _pooledEthAmount) external view returns (uint256);

    /**
     * @return the amount of Ether that corresponds to `_sharesAmount` token shares.
     */
    function getPooledEthByShares(uint256 _sharesAmount) external view returns (uint256);
}
