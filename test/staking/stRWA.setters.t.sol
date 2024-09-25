// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// foundry imports
import { Test } from "../../lib/forge-std/src/Test.sol";

// local
import { stRWA as StakedRWA } from "../../src/staking/stRWA.sol";

// local helper imports
import "./utils/stRWA.setUp.sol";
import "../../src/interfaces/CommonErrors.sol";

/**
 * @title StakedRWASettersTest
 * @author @chasebrownn
 * @notice This test file contains unit tests for various setters used in the staking contracts.
 */
contract StakedRWASettersTest is Test, StakedRWATestUtility {
    function setUp() public override {
        super.setUp();
    }


    // ----------
    // Unit Tests
    // ----------

    /// @dev Verifies proper state changes when stRWA::updateRebaseIndexManager is executed.
    function test_stakedRWA_stRWA_updateRebaseIndexManager() public {
        // ~ Pre-state check ~

        assertEq(stRWA.rebaseIndexManager(), address(0));

        // ~ Execute updateRebaseIndexManager ~

        vm.expectRevert(abi.encodeWithSelector(StakedRWA.NotAuthorized.selector, address(this)));
        stRWA.updateRebaseIndexManager(BOB);

        vm.prank(MULTISIG);
        stRWA.updateRebaseIndexManager(BOB);

        // ~ Post-state check ~

        assertEq(stRWA.rebaseIndexManager(), BOB);
    }

    /// @dev Verifies proper state changes when tokenSilo::setFundsManager is executed.
    function test_stakedRWA_tokenSilo_setFundsManager() public {
        // ~ Pre-state check ~

        assertEq(tokenSilo.isFundsManager(BOB), false);

        // ~ Execute updateRebaseIndexManager ~

        vm.expectRevert();
        tokenSilo.setFundsManager(BOB, true);

        vm.prank(MULTISIG);
        tokenSilo.setFundsManager(BOB, true);

        // ~ Post-state check ~

        assertEq(tokenSilo.isFundsManager(BOB), true);
    }

    function test_stakedRWA_tokenSilo_setRebaseController() public {
        // ~ Pre-state check ~

        assertEq(tokenSilo.rebaseController(), address(0));

        // ~ Execute updateRebaseIndexManager ~

        vm.expectRevert();
        tokenSilo.setRebaseController(BOB);

        vm.prank(MULTISIG);
        tokenSilo.setRebaseController(BOB);

        // ~ Post-state check ~

        assertEq(tokenSilo.rebaseController(), BOB);
    }
    
}