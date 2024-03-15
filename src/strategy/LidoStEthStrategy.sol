// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

import {EnumerableSet} from "oz/utils/structs/EnumerableSet.sol";
import {Strategy} from "./Strategy.sol";

import {IStETH} from "../interfaces/IStETH.sol";
import {IWStETH} from "../interfaces/IWStETH.sol";
import {ISwapManager} from "../interfaces/ISwapManager.sol";
import {IStrategyManager} from "../interfaces/IStrategyManager.sol";
import {TransferHelper} from "v3-periphery/libraries/TransferHelper.sol";
import {IWithdrawalQueueERC721} from "../interfaces/IWithdrawalQueueERC721.sol";

error Strategy__StETHWrap();
error Strategy__ZeroAmount();
error Strategy__LidoDeposit();
error Strategy__ZeroAddress();
error Strategy__ZeroPoolLiquidity();
error Strategy__LidoSharesTransfer();
error Strategy__LidoRequestWithdraw();
error Strategy__InsufficientBalance();
error Strategy__TooLittleRecieved(uint256 amountOut, uint256 minAmountOut);

/**
 * @title LidoStEthStrategy
 * @author Mavvverick
 * @dev A strategy contract for generating eth yield by managing Lido staked ETH (stETH)
 */
contract LidoStEthStrategy is Strategy {
    using EnumerableSet for EnumerableSet.UintSet;

    /// @notice minimal amount of stETH that is possible to withdraw
    uint256 public constant MIN_STETH_WITHDRAWAL_AMOUNT = 1_00;

    /// @notice maximum amount of stETH that is possible to withdraw by a single request
    /// Prevents accumulating too much funds per single request fulfillment in the future.
    /// @dev To withdraw larger amounts, it's recommended to split it to several requests
    uint256 public constant MAX_STETH_WITHDRAWAL_AMOUNT = 1_000 * 10 ** 18;

    address public swapManager;
    IStETH public STETH; //strategy token
    address public WETH9; //swap token for uniV3
    address public WSTETH; //swap token for uniV3
    IWithdrawalQueueERC721 public stETHWithdrawalQueue;

    EnumerableSet.UintSet private withdrawQueue;

    /**
     * @param _stETHAdress The address of the stETH contract
     * @param _stETHWithdrawal The address of the stETH withdrawal contract
     * @param _wstETHAdress The address of the wrapped stETH (wstETH) contract
     * @param _weth9 The address of the WETH9 contract
     * @param _swapManager The address of the SwapManager contract
     * @param _manager The address of the strategy manager
     * @param _name The name of the strategy
     */
    constructor(
        address _stETHAdress,
        address _stETHWithdrawal,
        address _wstETHAdress,
        address _weth9,
        address _swapManager,
        address payable _manager,
        string memory _name
    ) Strategy(_manager, _name) {
        if (
            _stETHAdress == address(0) || _stETHWithdrawal == address(0) || _wstETHAdress == address(0)
                || _weth9 == address(0) || _swapManager == address(0)
        ) revert Strategy__ZeroAddress();

        STETH = IStETH(_stETHAdress);
        stETHWithdrawalQueue = IWithdrawalQueueERC721(_stETHWithdrawal);
        swapManager = _swapManager;
        WSTETH = _wstETHAdress;
        WETH9 = _weth9;
    }

    /**
     * @dev Internal function to perform an instant withdrawal of stETH using swap pools.
     * @param _amount The amount of stETH to withdraw
     * @return actualAmount The actual amount of ETH withdrawn
     */
    function _instantWithdraw(uint256 _amount) internal returns (uint256 actualAmount) {
        // swap stEth for eth
        actualAmount = _swapUsingFairQuote(_amount);
        TransferHelper.safeTransferETH(manager, address(this).balance);
    }

    /**
     * @dev Internal function to swap stETH for ETH using UniV3 or Curve.
     * @param _amountIn The amount of stETH to swap
     * @return actualAmount The actual amount of ETH received after swapping
     */
    function _swapUsingFairQuote(uint256 _amountIn) internal returns (uint256 actualAmount) {
        uint256 amountInForV3 = IWStETH(WSTETH).getWstETHByStETH(_amountIn);
        uint256 v3Out = ISwapManager(swapManager).estimateV3AmountOut(uint128(amountInForV3), WSTETH, WETH9);
        uint256 curveOut = ISwapManager(swapManager).estimateCurveAmountOut(_amountIn, address(STETH));

        if (v3Out == 0 && curveOut == 0) revert Strategy__ZeroPoolLiquidity();

        uint256 quoteAmount = v3Out > curveOut ? v3Out : curveOut;
        uint256 quoteAmountMin = ISwapManager(swapManager).getMinimumAmount(WETH9, quoteAmount);
        address tokenIn;

        if (v3Out > curveOut) {
            // wrap stETH for uniswap pool
            TransferHelper.safeApprove(address(STETH), WSTETH, _amountIn);
            _amountIn = IWStETH(WSTETH).wrap(_amountIn);

            if (_amountIn == 0) revert Strategy__StETHWrap();
            tokenIn = WSTETH;

            TransferHelper.safeApprove(tokenIn, swapManager, _amountIn);
            actualAmount = ISwapManager(swapManager).swapUinv3(tokenIn, _amountIn);
        } else {
            tokenIn = address(STETH);
            TransferHelper.safeApprove(tokenIn, swapManager, _amountIn);
            actualAmount = ISwapManager(swapManager).swapCurve(tokenIn, _amountIn);
        }

        // check recieved amount out using fairQuoteMin
        if (actualAmount < quoteAmountMin) revert Strategy__TooLittleRecieved(actualAmount, quoteAmountMin);
    }

    function _checkPendingAssets(uint256[] memory requestIds)
        internal
        view
        returns (uint256[] memory ids, uint256 totalClaimable, uint256 totalPending)
    {
        uint256 requestLen = requestIds.length;
        if (requestLen == 0) return (new uint256[](0), 0, 0);
        ids = new uint256[](requestLen);

        IWithdrawalQueueERC721.WithdrawalRequestStatus[] memory statuses =
            stETHWithdrawalQueue.getWithdrawalStatus(requestIds);

        uint256 index = 0;
        uint256 len = statuses.length;

        for (uint256 i = 0; i < len;) {
            IWithdrawalQueueERC721.WithdrawalRequestStatus memory status = statuses[i];
            if (status.isClaimed) continue;
            if (status.isFinalized) {
                ids[index++] = requestIds[i];
                totalClaimable += status.amountOfStETH;
            } else {
                totalPending += status.amountOfStETH;
            }

            unchecked {
                i++;
            }
        }

        assembly {
            mstore(ids, index)
        }
    }

    /**
     * @notice Deposit ETH into the Lido stETH contract.
     * @dev Only the strategy manager can call this function.
     */
    function deposit() external payable override onlyManager {
        if (msg.value == 0) revert Strategy__ZeroAmount();
        uint256 shares = STETH.submit{value: msg.value}(address(0));
        if (shares == 0) revert Strategy__LidoDeposit();
    }

    /**
     * @notice Initiate a withdrawal of a specific amount of stETH.
     * @dev Only the strategy manager can call this function.
     * @param _ethAmount The amount of stETH to withdraw.
     * @return actualAmount The actual amount of stETH withdrawn.
     */
    function withdraw(uint256 _ethAmount) external override onlyManager returns (uint256 actualAmount) {
        if (_ethAmount == 0) revert Strategy__ZeroAmount();
        if (STETH.balanceOf(address(this)) < _ethAmount) revert Strategy__InsufficientBalance();

        // default to the MIN_STETH_WITHDRAWAL_AMOUNT if the requested withdrawal amount is less than the minimum.
        if (MIN_STETH_WITHDRAWAL_AMOUNT > _ethAmount) _ethAmount = MIN_STETH_WITHDRAWAL_AMOUNT;

        //approve steth for WithdrawalQueueERC721
        TransferHelper.safeApprove(address(STETH), address(stETHWithdrawalQueue), _ethAmount);

        uint256 remainingBalance = _ethAmount;
        uint256 batchLen = (_ethAmount / MAX_STETH_WITHDRAWAL_AMOUNT) + 1;
        uint256[] memory requestedAmounts = new uint256[](batchLen);
        uint256 index;

        while (remainingBalance != 0) {
            if (remainingBalance > MAX_STETH_WITHDRAWAL_AMOUNT) {
                requestedAmounts[index] = MAX_STETH_WITHDRAWAL_AMOUNT;
            } else {
                requestedAmounts[index] = remainingBalance;
            }
            unchecked {
                remainingBalance -= requestedAmounts[index];
                index++;
            }
        }

        // reset the array length to remove empty values
        assembly {
            mstore(requestedAmounts, index)
        }

        //raise a withdraw request to WithdrawalQueueERC721
        uint256[] memory ids = stETHWithdrawalQueue.requestWithdrawals(requestedAmounts, address(this));

        uint256 idsLen = ids.length;
        if (idsLen == 0) revert Strategy__LidoRequestWithdraw();

        // push the withdraw request id
        for (uint256 i = 0; i < idsLen;) {
            withdrawQueue.add(ids[i]);
            unchecked {
                i++;
            }
        }

        actualAmount = _ethAmount;
        if (address(this).balance > 0) {
            TransferHelper.safeTransferETH(manager, address(this).balance);
        }
    }

    /**
     * @notice Claim all pending withdrawal assets from the stETH withdrawal queue.
     * @dev This function claims all pending withdrawal assets and transfers them to the assets vault.
     * The queue will always stay within bounds since withdrawal is requested once per rebase cycle,
     * which is 365 requests in a year for a 1-day epoch cycle or 52 requests in a year for a 7-day epoch cycle
     * If the queue expands to a level where withdrawQueue consumes excessive gas, use claimAllPendingAssetsByIds instead.
     */
    function claimAllPendingAssets() external {
        uint256[] memory withdrawIds = withdrawQueue.values();
        (uint256[] memory ids,,) = checkPendingAssets(withdrawIds);

        uint256 len = ids.length;
        for (uint256 i = 0; i < len;) {
            stETHWithdrawalQueue.claimWithdrawal(ids[i]);
            // remove claimed request Ids
            withdrawQueue.remove(ids[i]);
            unchecked {
                i++;
            }
        }

        TransferHelper.safeTransferETH(IStrategyManager(manager).assetsVault(), address(this).balance);
    }

    /**
     * @notice Redeems eth amount and deposit redeemed amount in the bridge
     * NB! Array of request ids should be sorted
     * @param claimableRequestIds An array of withdrawal request IDs that are claimable
     * @param hints Array of hints used to find required checkpoint for the request
     *  Reverts if requestIds and hints arrays length differs
     *  Reverts if any requestId or hint in arguments are not valid
     *  Reverts if any request is not finalized or already claimed
     */
    function claimAllPendingAssetsByIds(uint256[] memory claimableRequestIds, uint256[] memory hints) external {
        //calim withdrawal amount
        stETHWithdrawalQueue.claimWithdrawals(claimableRequestIds, hints);

        // remove claimed request Ids
        uint256 requestsLen = claimableRequestIds.length;
        for (uint256 i = 0; i < requestsLen;) {
            withdrawQueue.remove(claimableRequestIds[i]);
            unchecked {
                i++;
            }
        }

        // Transfer the claimed asset to the assets vault
        if (address(this).balance > 0) {
            TransferHelper.safeTransferETH(IStrategyManager(manager).assetsVault(), address(this).balance);
        }
    }

    /**
     * @notice Initiate an instant withdrawal of stETH using swap pools
     * @dev Only the strategy manager can call this function.
     * @param _amount The amount of stETH to withdraw.
     * @return actualAmount The actual amount of stETH withdrawn.
     */
    function instantWithdraw(uint256 _amount) external override onlyManager returns (uint256 actualAmount) {
        if (_amount == 0) return 0;
        actualAmount = _instantWithdraw(_amount);
    }

    /**
     * @notice Clear the strategy by withdrawing all stETH to the assets vault
     * @dev This function withdraws all stETH from the strategy and transfers them to the strategy manager's assets vault.
     * @return amount The amount of stETH withdrawn.
     */
    function clear() external override onlyManager returns (uint256 amount) {
        uint256 balance = STETH.balanceOf(address(this));
        // if stEth shares is zero return actualAmount = 0
        if (balance == 0) return 0;
        amount = _instantWithdraw(balance);

        // Transfer left over dust shares to the asset vault
        uint256 share = STETH.sharesOf(address(this));
        if (share > 0) {
            uint256 sharesValue = STETH.transferShares(IStrategyManager(manager).assetsVault(), share);
            if (sharesValue == 0) revert Strategy__LidoSharesTransfer();
        }
    }

    /**
     * @notice Check the pending withdrawal assets from the stETH withdrawal queue.
     * @dev This function retrieves the pending withdrawal assets and returns their IDs, total claimable amount, and total pending amount.
     * @return ids An array of withdrawal request IDs.
     * @return totalClaimable The total amount of claimable stETH.
     * @return totalPending The total amount of pending stETH.
     */
    function checkPendingAssets()
        public
        view
        returns (uint256[] memory ids, uint256 totalClaimable, uint256 totalPending)
    {
        uint256[] memory requestIds = withdrawQueue.values();
        (ids, totalClaimable, totalPending) = _checkPendingAssets(requestIds);
    }

    /**
     * @notice Check the pending withdrawal assets from the stETH withdrawal queue.
     * @dev This function retrieves the pending withdrawal assets and returns their IDs, total claimable amount, and total pending amount.
     * @param requestIds An array of withdrawal request IDs
     * @return ids An array of withdrawal request IDs.
     * @return totalClaimable The total amount of claimable stETH.
     * @return totalPending The total amount of pending stETH.
     */
    function checkPendingAssets(uint256[] memory requestIds)
        public
        view
        returns (uint256[] memory ids, uint256 totalClaimable, uint256 totalPending)
    {
        (ids, totalClaimable, totalPending) = _checkPendingAssets(requestIds);
    }

    /**
     * @notice Get the pending and executable assets amount
     * @dev This function retrieves the pending and executable assets from the stETH withdrawal queue.
     * @return pending The total amount of pending stETH.
     * @return executable The total amount of claimable stETH.
     */
    function checkPendingStatus() external view override returns (uint256 pending, uint256 executable) {
        (, executable, pending) = checkPendingAssets();
    }

    /**
     * @notice Retrieves the withdrawal request ids
     * @return requestIds An array of withdrawal request IDs
     */
    function getRequestIds() public view returns (uint256[] memory requestIds) {
        return withdrawQueue.values();
    }

    /**
     * @notice Retrieves the withdrawal status of stETH requests
     * @return requestIds An array of withdrawal request IDs
     * @return statuses An array of withdrawal request statuses
     */
    function getStETHWithdrawalStatus()
        public
        view
        returns (uint256[] memory requestIds, IWithdrawalQueueERC721.WithdrawalRequestStatus[] memory statuses)
    {
        requestIds = stETHWithdrawalQueue.getWithdrawalRequests(address(this));
        statuses = stETHWithdrawalQueue.getWithdrawalStatus(requestIds);
    }

    /**
     * @notice Retrieves the withdrawal status of stETH requests
     * NB! Array of request ids should be sorted
     * @param requestIds An array of stETH withdrawal request IDs for claim
     * @return statuses An array of withdrawal request statuses
     */
    function getStETHWithdrawalStatusForIds(uint256[] memory requestIds)
        public
        view
        returns (IWithdrawalQueueERC721.WithdrawalRequestStatus[] memory statuses)
    {
        statuses = stETHWithdrawalQueue.getWithdrawalStatus(requestIds);
    }

    /**
     * @notice Get the total value of assets managed by the strategy.
     * @dev This function retrieves the total value of assets managed by the strategy, including invested, claimable, and pending values.
     * @return value The total value of assets managed by the strategy.
     */
    function getAllValue() public view override returns (uint256 value) {
        value = getInvestedValue() + getClaimableAndPendingValue();
    }

    /**
     * @notice Get the invested value of assets managed by the strategy.
     * @dev This function retrieves the invested value of assets managed by the strategy.
     * @return value The invested value of assets managed by the strategy.
     */
    function getInvestedValue() public view override returns (uint256 value) {
        value = STETH.balanceOf(address(this));
    }

    /**
     * @notice Get the pending value of assets managed by the strategy.
     * @dev This function retrieves the pending value of assets managed by the strategy.
     * @return value The pending value of assets managed by the strategy.
     */
    function getPendingValue() public view override returns (uint256 value) {
        (,, value) = checkPendingAssets();
    }
    /**
     * @notice Get the claimable value of assets managed by the strategy.
     * @dev This function retrieves the claimable value of assets managed by the strategy.
     * @return value The claimable value of assets managed by the strategy.
     */

    function getClaimableValue() public view returns (uint256 value) {
        (, value,) = checkPendingAssets();
    }

    /**
     * @notice Get the total claimable and pending value of assets managed by the strategy.
     * @dev This function retrieves the total claimable and pending value of assets managed by the strategy.
     * @return value The total claimable and pending value of assets managed by the strategy.
     */
    function getClaimableAndPendingValue() public view returns (uint256 value) {
        (, uint256 claimableValue, uint256 pendingValue) = checkPendingAssets();
        value = claimableValue + pendingValue;
    }

    receive() external payable {}
}
