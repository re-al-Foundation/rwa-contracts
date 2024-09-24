// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// foundry imports
import { Test } from "../../lib/forge-std/src/Test.sol";

// local helper imports
import "./utils/stRWA.setUp.sol";
import "../../src/interfaces/CommonErrors.sol";

/**
 * @title StakedRWADepositTest
 * @author @chasebrownn
 * @notice This test file contains unit tests for stRWA::deposit.
 */
contract StakedRWADepositTest is Test, StakedRWATestUtility {
    function setUp() public override {
        super.setUp();
    }


    // -------
    // Utility
    // -------

    /// @dev Utility function for calling stRWA::deposit. Contains state checks.
    function _deposit(uint256 amount) internal {
        uint256 preBal1 = rwaToken.balanceOf(JOE);
        uint256 preBal2 = stRWA.balanceOf(JOE);
        uint256 preBal3 = rwaVotingEscrow.balanceOf(address(tokenSilo));
        uint256 vp = rwaVotingEscrow.getAccountVotingPower(address(tokenSilo));
        uint256 preview = stRWA.previewDeposit(amount);
        uint256 locked = tokenSilo.getLockedAmount();

        vm.startPrank(JOE);
        rwaToken.approve(address(stRWA), amount);
        stRWA.deposit(amount, JOE);
        vm.stopPrank();

        assertEq(preview, amount);
        assertEq(rwaToken.balanceOf(JOE), preBal1 - amount);
        assertApproxEqAbs(stRWA.balanceOf(JOE), preBal2 + amount, 1);
        if (preBal3 == 0) {
            assertEq(rwaVotingEscrow.balanceOf(address(tokenSilo)), preBal3 + 1);
        } else {
            assertEq(rwaVotingEscrow.balanceOf(address(tokenSilo)), preBal3);
        }
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), vp + amount);
        assertEq(tokenSilo.getLockedAmount(), locked + amount);
        assertEq(rwaVotingEscrow.getLockedAmount(tokenSilo.masterTokenId()), tokenSilo.getLockedAmount());
    }


    // ----------
    // Unit Tests
    // ----------

    /// @dev Verifies proper state changes when stRWA::deposit is called when rebaseIndex == 1.
    function test_stakedRWA_deposit_static() public {
        // ~ Config ~

        uint256 amountTokens = 10_000 ether;
        deal(address(rwaToken), JOE, amountTokens);

        // ~ Execute deposit ~

        _deposit(amountTokens);

        // ~ Post-state check ~

        assertNotEq(tokenSilo.masterTokenId(), 0);
    }

    /// @dev Verifies proper state changes when stRWA::deposit is called when rebaseIndex != 1.
    function test_stakedRWA_deposit_rebaseIndexNot1_static() public {
        // ~ Config ~

        _setRebaseIndex(1.2 * 1e18);
        uint256 amountTokens = 10_000 ether;
        deal(address(rwaToken), JOE, amountTokens);

        // ~ Execute deposit ~

        _deposit(amountTokens);

        // ~ Post-state check ~

        assertNotEq(tokenSilo.masterTokenId(), 0);
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), amountTokens);
    }

    /// @dev Verifies proper state changes when stRWA::deposit using fuzzing
    function test_stakedRWA_deposit_fuzzing(uint256 amountTokens) public {
        // ~ Config ~

        amountTokens = bound(amountTokens, 0.0001 * 1e18, 1_000_000 * 1e18);
        deal(address(rwaToken), JOE, amountTokens);

        // ~ Execute deposit ~

        _deposit(amountTokens);

        // ~ Post-state check ~

        assertNotEq(tokenSilo.masterTokenId(), 0);
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), amountTokens);
    }

    /// @dev Verifies proper state changes when stRWA::deposit is called when rebaseIndex != 1 with fuzzing.
    function test_stakedRWA_deposit_rebaseIndexNot1_fuzzing(uint256 amountTokens) public {
        // ~ Config ~

        _setRebaseIndex(1.2 * 1e18);
        amountTokens = bound(amountTokens, 0.0001 * 1e18, 1_000_000 * 1e18);
        deal(address(rwaToken), JOE, amountTokens);

        // ~ Execute deposit ~

        _deposit(amountTokens);

        // ~ Post-state check ~

        assertNotEq(tokenSilo.masterTokenId(), 0);
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), amountTokens);
    }

    /// @dev Verifies proper state changes when stRWA::deposit is called sequentially.
    function test_stakedRWA_deposit_sequential() public {
        // ~ Config ~

        uint256 amount1 = 10_000 ether;
        uint256 amount2 = 10_000 ether;
        deal(address(rwaToken), JOE, amount1 + amount2);

        // ~ Execute deposit ~

        _deposit(amount1);

        // ~ State check 1 ~

        uint256 masterToken = tokenSilo.masterTokenId();
        assertNotEq(masterToken, 0);
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), amount1);

        // ~ Execute deposit ~

        _deposit(amount2);

        // ~ State check 2 ~

        assertEq(tokenSilo.masterTokenId(), masterToken);
        assertEq(rwaVotingEscrow.getAccountVotingPower(address(tokenSilo)), amount1 + amount2);
    }

    /// @dev Verifies expected revert when stRWA::deposit is called with invalid params.
    function test_stakedRWA_deposit_assets_is_zero() public {
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueUnchanged.selector));
        stRWA.deposit(0, JOE);
    }

    /// @dev Verifies expected revert when stRWA::deposit is called with invalid params.
    function test_stakedRWA_deposit_receiver_is_zeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.InvalidZeroAddress.selector));
        stRWA.deposit(1, address(0));
    }
}