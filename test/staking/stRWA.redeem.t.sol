// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// foundry imports
import { Test } from "../../lib/forge-std/src/Test.sol";

// local helper imports
import "./utils/stRWA.setUp.sol";

/**
 * @title StakedRWATest
 * @author @chasebrownn
 * @notice TODO
 */
contract StakedRWATest is Test, StakedRWATestUtility {

    function setUp() public override {
        super.setUp();
    }


    // ----------
    // Unit Tests
    // ----------

    /// @dev Verifies proper state changes when stRWA::redeem is called when rebaseIndex == 1.
    function test_stakedRWA_redeem_static() public {
        // ~ Config ~

        uint256 amountTokens = 10_000 ether;
        deal(address(rwaToken), JOE, amountTokens);

        vm.startPrank(JOE);
        rwaToken.approve(address(stRWA), amountTokens);
        stRWA.deposit(amountTokens, JOE);
        vm.stopPrank();

        // ~ Pre-state check ~

        assertEq(stRWA.balanceOf(JOE), amountTokens);
        assertEq(rwaVotingEscrow.balanceOf(address(tokenSilo)), 1);
        assertEq(rwaVotingEscrow.balanceOf(JOE), 0);
        assertNotEq(tokenSilo.masterTokenId(), 0);
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), amountTokens);
        assertEq(rwaVotingEscrow.getAccountVotingPower(JOE), 0);

        // ~ Execute redeem ~

        uint256 preview = stRWA.previewRedeem(amountTokens);

        vm.prank(JOE);
        stRWA.redeem(amountTokens, JOE, JOE);

        // ~ Post-state check ~

        assertEq(stRWA.balanceOf(JOE), 0);
        assertEq(rwaVotingEscrow.balanceOf(address(tokenSilo)), 0);
        assertEq(rwaVotingEscrow.balanceOf(JOE), 1);
        assertEq(tokenSilo.masterTokenId(), 0);
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), 0);
        assertEq(rwaVotingEscrow.getAccountVotingPower(JOE), preview);
    }

    /// @dev Verifies proper state changes when stRWA::redeem is called when rebaseIndex != 1.
    /// But the rebaseIndex is updated before the first deposit, resulting in no change in redemption power.
    function test_stakedRWA_redeem_rebaseIndexNot1_preDeposit_static() public {
        // ~ Config ~

        uint256 newRebaseIndex = 1.2 * 1e18;
        _setRebaseIndex(newRebaseIndex);

        uint256 amountTokens = 10_000 ether;
        deal(address(rwaToken), JOE, amountTokens);

        uint256 preview = stRWA.previewDeposit(amountTokens);

        vm.startPrank(JOE);
        rwaToken.approve(address(stRWA), amountTokens);
        stRWA.deposit(amountTokens, JOE);
        vm.stopPrank();

        // ~ Pre-state check ~

        //assertEq(preview, amountTokens * newRebaseIndex / 1e18);
        assertEq(preview, amountTokens);

        assertApproxEqAbs(stRWA.balanceOf(JOE), preview, 1);
        assertEq(rwaVotingEscrow.balanceOf(address(tokenSilo)), 1);
        assertEq(rwaVotingEscrow.balanceOf(JOE), 0);
        assertNotEq(tokenSilo.masterTokenId(), 0);
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), amountTokens);
        assertEq(rwaVotingEscrow.getAccountVotingPower(JOE), 0);

        // ~ Execute redeem ~

        uint256 bal = stRWA.balanceOf(JOE);

        vm.prank(JOE);
        stRWA.redeem(bal, JOE, JOE);

        // ~ Post-state check ~

        assertEq(stRWA.balanceOf(JOE), 0);
        assertApproxEqAbs(rwaVotingEscrow.balanceOf(address(tokenSilo)), 0, 1);
        assertApproxEqAbs(rwaVotingEscrow.balanceOf(JOE), 1, 1);
        assertApproxEqAbs(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), 0, 1);
        assertApproxEqAbs(rwaVotingEscrow.getAccountVotingPower(JOE), amountTokens, 1);
    }

    /// @dev Verifies proper state changes when stRWA::redeem is called when rebaseIndex != 1.
    /// But in this case, the rebaseIndex is increased after the deposit, resulting in increased
    /// redemption power.
    function test_stakedRWA_redeem_rebaseIndexNot1_postDeposit_static() public {
        // ~ Config ~

        uint256 amountTokens = 10_000 ether;
        deal(address(rwaToken), JOE, amountTokens);

        vm.startPrank(JOE);
        rwaToken.approve(address(stRWA), amountTokens);
        stRWA.deposit(amountTokens, JOE);
        vm.stopPrank();

        // ~ Pre-state check ~

        assertEq(stRWA.balanceOf(JOE), amountTokens);
        assertEq(rwaVotingEscrow.balanceOf(address(tokenSilo)), 1);
        assertEq(rwaVotingEscrow.balanceOf(JOE), 0);
        assertNotEq(tokenSilo.masterTokenId(), 0);
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), amountTokens);
        assertEq(rwaVotingEscrow.getAccountVotingPower(JOE), 0);

        // ~ Execute redeem ~

        uint256 newRebaseIndex = 1.2 * 1e18;
        _setRebaseIndex(newRebaseIndex);

        uint256 newBal = stRWA.balanceOf(JOE);
        assertEq(newBal, amountTokens * newRebaseIndex / 1e18);

        vm.prank(JOE);
        stRWA.redeem(newBal, JOE, JOE);

        // ~ Post-state check ~

        assertEq(stRWA.balanceOf(JOE), 0);
        assertEq(rwaVotingEscrow.balanceOf(address(tokenSilo)), 0);
        assertEq(rwaVotingEscrow.balanceOf(JOE), 1);
        assertEq(tokenSilo.masterTokenId(), 0);
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), 0);
        assertEq(rwaVotingEscrow.getAccountVotingPower(JOE), amountTokens);
    }

    /// @dev Verifies proper state changes when stRWA::redeem is called when rebaseIndex == 1 with fuzzing.
    function test_stakedRWA_redeem_fuzzing(uint256 amountTokens) public {
        // ~ Config ~

        amountTokens = bound(amountTokens, 0.0001 * 1e18, 1_000_000 * 1e18);
        deal(address(rwaToken), JOE, amountTokens);

        vm.startPrank(JOE);
        rwaToken.approve(address(stRWA), amountTokens);
        stRWA.deposit(amountTokens, JOE);
        vm.stopPrank();

        // ~ Pre-state check ~

        assertEq(stRWA.balanceOf(JOE), amountTokens);
        assertEq(rwaVotingEscrow.balanceOf(address(tokenSilo)), 1);
        assertEq(rwaVotingEscrow.balanceOf(JOE), 0);
        assertNotEq(tokenSilo.masterTokenId(), 0);
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), amountTokens);
        assertEq(rwaVotingEscrow.getAccountVotingPower(JOE), 0);

        // ~ Execute redeem ~

        uint256 preview = stRWA.previewRedeem(amountTokens);

        vm.prank(JOE);
        stRWA.redeem(amountTokens, JOE, JOE);

        // ~ Post-state check ~

        assertEq(stRWA.balanceOf(JOE), 0);
        assertEq(rwaVotingEscrow.balanceOf(address(tokenSilo)), 0);
        assertEq(rwaVotingEscrow.balanceOf(JOE), 1);
        assertEq(tokenSilo.masterTokenId(), 0);
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), 0);
        assertEq(rwaVotingEscrow.getAccountVotingPower(JOE), preview);
    }

    /// @dev Verifies proper state changes when stRWA::redeem is called when rebaseIndex != 1 with fuzzing.
    /// But the rebaseIndex is updated before the first deposit, resulting in no change in redemption power.
    function test_stakedRWA_redeem_rebaseIndexNot1_preDeposit_fuzzing(uint256 amountTokens) public {
        // ~ Config ~

        uint256 newRebaseIndex = 1.2 * 1e18;
        _setRebaseIndex(newRebaseIndex);

        amountTokens = bound(amountTokens, 0.0001 * 1e18, 1_000_000 * 1e18);
        deal(address(rwaToken), JOE, amountTokens);

        uint256 preview = stRWA.previewDeposit(amountTokens);

        vm.startPrank(JOE);
        rwaToken.approve(address(stRWA), amountTokens);
        stRWA.deposit(amountTokens, JOE);
        vm.stopPrank();

        // ~ Pre-state check ~

        //assertEq(preview, amountTokens * newRebaseIndex / 1e18);
        assertEq(preview, amountTokens);

        assertApproxEqAbs(stRWA.balanceOf(JOE), preview, 1);
        assertEq(rwaVotingEscrow.balanceOf(address(tokenSilo)), 1);
        assertEq(rwaVotingEscrow.balanceOf(JOE), 0);
        assertNotEq(tokenSilo.masterTokenId(), 0);
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), amountTokens);
        assertEq(rwaVotingEscrow.getAccountVotingPower(JOE), 0);

        // ~ Execute redeem ~

        uint256 balance = stRWA.balanceOf(JOE);
        preview = stRWA.previewRedeem(balance);
        assertApproxEqAbs(preview, amountTokens, 3);

        vm.prank(JOE);
        stRWA.redeem(balance, JOE, JOE);

        // ~ Post-state check ~

        assertApproxEqAbs(stRWA.balanceOf(JOE), 0, 1);
        assertApproxEqAbs(rwaVotingEscrow.balanceOf(JOE), 1, 1);

        if (preview >= amountTokens) {
            assertEq(tokenSilo.masterTokenId(), 0);
            assertEq(rwaVotingEscrow.balanceOf(address(tokenSilo)), 0);
        } else {
            assertNotEq(tokenSilo.masterTokenId(), 0);
        }

        assertApproxEqAbs(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), 0, 3);
        assertApproxEqAbs(rwaVotingEscrow.getAccountVotingPower(JOE), amountTokens, 3);
    }

    /// @dev Verifies proper state changes when stRWA::redeem is called when rebaseIndex != 1 with fuzzing.
    /// But in this case, the rebaseIndex is increased after the deposit, resulting in increased
    /// redemption power.
    function test_stakedRWA_redeem_rebaseIndexNot1_postDeposit_fuzzing(uint256 amountTokens) public {
        // ~ Config ~

        amountTokens = bound(amountTokens, 0.0001 * 1e18, 1_000_000 * 1e18);
        deal(address(rwaToken), JOE, amountTokens);

        uint256 preview = stRWA.previewDeposit(amountTokens);

        vm.startPrank(JOE);
        rwaToken.approve(address(stRWA), amountTokens);
        stRWA.deposit(amountTokens, JOE);
        vm.stopPrank();

        // ~ Pre-state check ~

        assertApproxEqAbs(stRWA.balanceOf(JOE), preview, 1);
        assertEq(rwaVotingEscrow.balanceOf(address(tokenSilo)), 1);
        assertEq(rwaVotingEscrow.balanceOf(JOE), 0);
        assertNotEq(tokenSilo.masterTokenId(), 0);
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), amountTokens);
        assertEq(rwaVotingEscrow.getAccountVotingPower(JOE), 0);

        // ~ Execute redeem ~

        uint256 newRebaseIndex = 1.2 * 1e18;
        _setRebaseIndex(newRebaseIndex);

        uint256 balance = stRWA.balanceOf(JOE);
        preview = stRWA.previewRedeem(balance);
        assertEq(preview, amountTokens * stRWA.rebaseIndex() / 1e18);

        vm.prank(JOE);
        stRWA.redeem(balance, JOE, JOE);

        // ~ Post-state check ~

        assertApproxEqAbs(stRWA.balanceOf(JOE), 0, 1);
        assertApproxEqAbs(rwaVotingEscrow.balanceOf(JOE), 1, 1);

        if (preview >= amountTokens) {
            assertEq(tokenSilo.masterTokenId(), 0);
            assertEq(rwaVotingEscrow.balanceOf(address(tokenSilo)), 0);
        } else {
            assertNotEq(tokenSilo.masterTokenId(), 0);
        }
    }
}