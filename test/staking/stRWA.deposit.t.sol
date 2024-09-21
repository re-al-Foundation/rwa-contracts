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

    /// @dev Verifies proper state changes when stRWA::deposit is called when rebaseIndex == 1.
    function test_stakedRWA_deposit_static() public {
        // ~ Config ~

        uint256 amountTokens = 10_000 ether;
        deal(address(rwaToken), JOE, amountTokens);

        // ~ Pre-state check ~

        assertEq(rwaToken.balanceOf(JOE), amountTokens);
        assertEq(stRWA.balanceOf(JOE), 0);
        assertEq(rwaVotingEscrow.balanceOf(address(tokenSilo)), 0);
        assertEq(tokenSilo.masterTokenId(), 0);
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), 0);

        // ~ Execute deposit ~

        uint256 preview = stRWA.previewDeposit(amountTokens);

        vm.startPrank(JOE);
        rwaToken.approve(address(stRWA), amountTokens);
        stRWA.deposit(amountTokens, JOE);
        vm.stopPrank();

        // ~ Post-state check ~

        assertEq(preview, amountTokens);

        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(stRWA.balanceOf(JOE), amountTokens);
        assertEq(rwaVotingEscrow.balanceOf(address(tokenSilo)), 1);
        assertNotEq(tokenSilo.masterTokenId(), 0);
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), amountTokens);
    }

    /// @dev Verifies proper state changes when stRWA::deposit is called when rebaseIndex != 1.
    function test_stakedRWA_deposit_rebaseIndexNot1_static() public {
        // ~ Config ~

        _setRebaseIndex(1.2 * 1e18);
        uint256 amountTokens = 10_000 ether;
        deal(address(rwaToken), JOE, amountTokens);

        // ~ Pre-state check ~

        assertEq(rwaToken.balanceOf(JOE), amountTokens);
        assertEq(stRWA.balanceOf(JOE), 0);
        assertEq(rwaVotingEscrow.balanceOf(address(tokenSilo)), 0);
        assertEq(tokenSilo.masterTokenId(), 0);
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), 0);

        // ~ Execute deposit ~

        uint256 preview = stRWA.previewDeposit(amountTokens);
        emit log_named_uint("preview", preview);

        vm.startPrank(JOE);
        rwaToken.approve(address(stRWA), amountTokens);
        stRWA.deposit(amountTokens, JOE);
        vm.stopPrank();

        // ~ Post-state check ~

        assertEq(rwaToken.balanceOf(JOE), 0);
        assertApproxEqAbs(stRWA.balanceOf(JOE), preview, 1);
        assertEq(rwaVotingEscrow.balanceOf(address(tokenSilo)), 1);
        assertNotEq(tokenSilo.masterTokenId(), 0);
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), amountTokens);
    }

    /// @dev Verifies proper state changes when stRWA::deposit using fuzzing
    function test_stakedRWA_deposit_fuzzing(uint256 amountTokens) public {
        // ~ Config ~

        amountTokens = bound(amountTokens, 0.0001 * 1e18, 1_000_000 * 1e18);
        deal(address(rwaToken), JOE, amountTokens);

        // ~ Pre-state check ~

        assertEq(rwaToken.balanceOf(JOE), amountTokens);
        assertEq(stRWA.balanceOf(JOE), 0);
        assertEq(rwaVotingEscrow.balanceOf(address(tokenSilo)), 0);
        assertEq(tokenSilo.masterTokenId(), 0);
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), 0);

        // ~ Execute deposit ~

        uint256 preview = stRWA.previewDeposit(amountTokens);

        vm.startPrank(JOE);
        rwaToken.approve(address(stRWA), amountTokens);
        stRWA.deposit(amountTokens, JOE);
        vm.stopPrank();

        // ~ Post-state check ~

        assertEq(preview, amountTokens);

        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(stRWA.balanceOf(JOE), amountTokens);
        assertEq(rwaVotingEscrow.balanceOf(address(tokenSilo)), 1);
        assertNotEq(tokenSilo.masterTokenId(), 0);
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), amountTokens);
    }

    /// @dev Verifies proper state changes when stRWA::deposit is called when rebaseIndex != 1 with fuzzing.
    function test_stakedRWA_deposit_rebaseIndexNot1_fuzzing(uint256 amountTokens) public {
        // ~ Config ~

        _setRebaseIndex(1.2 * 1e18);
        amountTokens = bound(amountTokens, 0.0001 * 1e18, 1_000_000 * 1e18);
        deal(address(rwaToken), JOE, amountTokens);

        // ~ Pre-state check ~

        assertEq(rwaToken.balanceOf(JOE), amountTokens);
        assertEq(stRWA.balanceOf(JOE), 0);
        assertEq(rwaVotingEscrow.balanceOf(address(tokenSilo)), 0);
        assertEq(tokenSilo.masterTokenId(), 0);
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), 0);

        // ~ Execute deposit ~

        uint256 preview = stRWA.previewDeposit(amountTokens);

        vm.startPrank(JOE);
        rwaToken.approve(address(stRWA), amountTokens);
        stRWA.deposit(amountTokens, JOE);
        vm.stopPrank();

        // ~ Post-state check ~

        assertEq(rwaToken.balanceOf(JOE), 0);
        assertApproxEqAbs(stRWA.balanceOf(JOE), preview, 1);
        assertEq(rwaVotingEscrow.balanceOf(address(tokenSilo)), 1);
        assertNotEq(tokenSilo.masterTokenId(), 0);
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), amountTokens);
    }
}