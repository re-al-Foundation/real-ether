// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import {Handler} from "./Handler.sol";
import {Real} from "src/token/Real.sol";
import {Minter} from "src/token/Minter.sol";
import {RealVault} from "src/RealVault.sol";
import {AssetsVault} from "src/AssetsVault.sol";
import {StrategyManager} from "src/StrategyManager.sol";
import {Test, console2 as console} from "forge-std/Test.sol";
import {TestEthStrategy} from "src/mock/TestEthStrategy.sol";
import {TestEthClaimableStrategy} from "src/mock/TestEthClaimableStrategy.sol";

/**
 * @title Real Vault Invariants
 * @author c-n-o-t-e
 * @dev Contract is used to test out Real Vault Contract by simulating exposed functions
 *         in the handler contract to different scenarios from different actors.
 *
 * Functions Exposed:
 * - deposit()
 * - rollToNextRound()
 * - cancelWithdrawal()
 * - instantWithdrawal()
 * - requestWithdrawal()
 */

contract RealVaultInvariants is Test {
    Real public real;
    Minter public minter;
    Handler public handler;
    TestEthStrategy public s1;
    RealVault public realVault;
    AssetsVault public assetsVault;
    StrategyManager public strategyManager;

    address minterAddress;
    address realVaultAddress;
    address assetVaultAddress;
    address strategyManagerAddress;

    Account public owner;
    Account public proposal;

    function setUp() public {
        owner = makeAccount("owner");
        proposal = makeAccount("proposal");

        minterAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        realVaultAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 2);
        assetVaultAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 3);
        strategyManagerAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 5);

        real = new Real(minterAddress);
        minter = new Minter(address(real), payable(realVaultAddress));
        deal(realVaultAddress, 0.001 ether);

        realVault = new RealVault(
            address(owner.addr),
            minterAddress,
            payable(assetVaultAddress),
            payable(strategyManagerAddress),
            address(proposal.addr)
        );

        assetsVault = new AssetsVault(address(realVault), strategyManagerAddress);

        uint256[] memory ratios = new uint256[](1);
        address[] memory strategies = new address[](1);

        s1 = new TestEthStrategy(payable(strategyManagerAddress), "Mock Eth Investment");
        strategies[0] = address(s1);

        ratios[0] = 1000_000; // 1e6
        strategyManager = new StrategyManager(address(realVault), payable(assetVaultAddress), strategies, ratios);

        vm.startPrank(address(0xdead));
        realVault.instantWithdraw(0, 0.001 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        realVault.rollToNextRound();

        handler = new Handler(realVault, real);
        bytes4[] memory selectors = new bytes4[](5);

        selectors[0] = Handler.deposit.selector;
        selectors[1] = Handler.requestWithdraw.selector;

        selectors[2] = Handler.cancelWithdraw.selector;
        selectors[3] = Handler.rollToNextRound.selector;

        selectors[4] = Handler.instantWithdraw.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_totalBalance() public {
        uint256 sumOfBalances;
        address[] memory actors = handler.actors();

        for (uint256 i; i < actors.length; ++i) {
            sumOfBalances += real.balanceOf(actors[i]);
        }

        uint256 totalBalance = sumOfBalances + real.balanceOf(address(realVault));
        assertEq(real.totalSupply(), totalBalance);
    }

    function invariant_amountInPastIsSame() public {
        assertEq(realVault.withdrawableAmountInPast(), handler.ghost_withdrawableAmountInPast());
    }

    function invariant_sharesInPastIsSame() public {
        assertEq(realVault.withdrawingSharesInPast(), handler.ghost_withdrawingSharesInPast());
    }

    function invariant_ethBalance() public {
        assertEq(
            strategyManager.getAllStrategiesValue() + assetsVault.getBalance(),
            handler.ghost_ethInVault() + handler.ghost_amountInStrategy()
        );
    }

    function invariant_vaultBalance() public {
        assertEq(
            real.balanceOf(address(realVault)), handler.ghost_TokenInRealVault() - handler.ghost_tokenBurntInRealVault()
        );
    }

    function invariant_callSummary() public view {
        handler.callSummary();
    }

    receive() external payable {}
}
