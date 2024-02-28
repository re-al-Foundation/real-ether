// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Strategy} from "./Strategy.sol";
import {IStETH} from "../interface/IStETH.sol";
import {IWithdrawalQueueERC721} from "../interface/IWithdrawalQueueERC721.sol";
import {IStrategyManager} from "../interface/IStrategyManager.sol";
import {ISwapManager} from "../interface/ISwapManager.sol";
import {TransferHelper} from "v3-periphery/libraries/TransferHelper.sol";

error Strategy__ZeroAmount();
error Strategy__InsufficientBalance();
error Strategy__LidoDeposit();
error Strategy__LidoRequestWithdraw();

contract LidoStEthStrategy is Strategy {
    IStETH public STETH;
    IWithdrawalQueueERC721 public stETHWithdrawalQueue;
    address public swapManager;

    constructor(
        address _stETHAdress,
        address _stETHWithdrawal,
        address _swapManager,
        address payable _manager,
        string memory _name
    ) Strategy(_manager, _name) {
        STETH = IStETH(_stETHAdress);
        stETHWithdrawalQueue = IWithdrawalQueueERC721(_stETHWithdrawal);
        swapManager = _swapManager;
    }

    function _instantWithdraw(uint256 _amount) internal returns (uint256 actualAmount) {
        // uint256 balance = STETH.balanceOf(address(this));
        TransferHelper.safeApprove(address(STETH), swapManager, _amount);
        actualAmount = ISwapManager(swapManager).swap(address(STETH), _amount);
        uint256 share = STETH.sharesOf(address(this));
        STETH.transferShares(IStrategyManager(manager).assetsVault(), share);
        TransferHelper.safeTransferETH(manager, address(this).balance);
    }

    function deposit() public payable override onlyManager {
        if (msg.value == 0) revert Strategy__ZeroAmount();
        uint256 shares = STETH.submit{value: msg.value}(address(0));
        if (shares == 0) revert Strategy__LidoDeposit();
    }

    function withdraw(uint256 _ethAmount) public override onlyManager returns (uint256 actualAmount) {
        if (_ethAmount == 0) revert Strategy__ZeroAmount();
        if (STETH.balanceOf(address(this)) < _ethAmount) revert Strategy__InsufficientBalance();

        //approve steth for WithdrawalQueueERC721
        STETH.approve(address(stETHWithdrawalQueue), _ethAmount);

        uint256[] memory requestedAmounts = new uint256[](1);
        requestedAmounts[0] = _ethAmount;

        //raise a withdraw request to WithdrawalQueueERC721
        uint256[] memory ids = stETHWithdrawalQueue.requestWithdrawals(requestedAmounts, address(this));
        if (ids.length == 0) revert Strategy__LidoRequestWithdraw();

        actualAmount = _ethAmount;
        // if (address(this).balance > 0) {
        //     TransferHelper.safeTransferETH(manager, address(this).balance);
        // }
    }

    function claimAllPendingAssets() public {
        (uint256[] memory ids,,) = checkPendingAssets();

        uint256 len = ids.length;

        for (uint256 i = 0; i < len;) {
            stETHWithdrawalQueue.claimWithdrawal(ids[i]);
            unchecked {
                i++;
            }
        }
        TransferHelper.safeTransferETH(IStrategyManager(manager).assetsVault(), address(this).balance);
    }

    /**
     * @notice Redeems eth amount and deposit redeemed amount in the bridge
     * NB! Array of request ids should be sorted
     * @param requestIds An array of withdrawal request ids
     * @return claimableRequestIds An array of withdrawal request IDs that are claimable
     */
    function claimAllPendingAssetsByIds(uint256[] memory requestIds) external returns (uint256[] memory) {
        // Array of request ids must be sorted
        IWithdrawalQueueERC721.WithdrawalRequestStatus[] memory statuses = getStETHWithdrawalStatusForIds(requestIds);
        uint256[] memory claimableRequestIds = new uint256[](requestIds.length);

        uint256 index = 0;
        bool isFinalised;
        for (uint256 i = 0; i < statuses.length;) {
            IWithdrawalQueueERC721.WithdrawalRequestStatus memory status = statuses[i];
            if (status.isFinalized && !status.isClaimed) {
                //accumulate the claimable request id
                claimableRequestIds[index++] = requestIds[i];
                isFinalised = true;
            }
            unchecked {
                i++;
            }
        }

        // remove the empty zeros
        assembly {
            mstore(claimableRequestIds, index)
        }

        if (isFinalised) {
            uint256[] memory hints = stETHWithdrawalQueue.findCheckpointHints(
                claimableRequestIds, 1, stETHWithdrawalQueue.getLastCheckpointIndex()
            );

            //calim withdrawal amount
            stETHWithdrawalQueue.claimWithdrawals(claimableRequestIds, hints);

            // Transfer the claimed asset to the assets vault
            TransferHelper.safeTransferETH(IStrategyManager(manager).assetsVault(), address(this).balance);
        }

        return claimableRequestIds;
    }

    function instantWithdraw(uint256 _amount) public override onlyManager returns (uint256 actualAmount) {
        actualAmount = _instantWithdraw(_amount);
    }

    function clear() public override onlyManager returns (uint256 amount) {
        uint256 balance = STETH.balanceOf(address(this));
        amount = _instantWithdraw(balance);
    }

    function checkPendingAssets()
        public
        view
        returns (uint256[] memory ids, uint256 totalClaimable, uint256 totalPending)
    {
        uint256[] memory requestIds = stETHWithdrawalQueue.getWithdrawalRequests(address(this));
        if (requestIds.length == 0) return (new uint256[](0), 0, 0);
        ids = new uint256[](requestIds.length);

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

    function getAllValue() public view override returns (uint256 value) {
        value = getInvestedValue() + getClaimableAndPendingValue();
    }

    function getInvestedValue() public view override returns (uint256 value) {
        value = STETH.balanceOf(address(this));
    }

    function getPendingValue() public view override returns (uint256 value) {
        (,, value) = checkPendingAssets();
    }

    function getClaimableValue() public view returns (uint256 value) {
        (, value,) = checkPendingAssets();
    }

    function getClaimableAndPendingValue() public view returns (uint256 value) {
        (, uint256 claimableValue, uint256 pendingValue) = checkPendingAssets();
        value = claimableValue + pendingValue;
    }
}
