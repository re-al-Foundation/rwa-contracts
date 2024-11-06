// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// foundry imports
import { Test } from "../../lib/forge-std/src/Test.sol";

// local helper imports
import "./utils/RewardEscrow.setUp.sol";
import "../../src/interfaces/CommonErrors.sol";

/**
 * @title RewardEscrowClaimTest
 * @author @chasebrownn
 * @notice This test file contains unit tests for RewardEscrow::claim.
 */
contract RewardEscrowClaimTest is Test, RewardEscrowTestUtility {
    function setUp() public override {
        super.setUp();
    }


    // -------
    // Utility
    // -------

    //


    // ----------
    // Unit Tests
    // ----------

    /// @dev TODO
    function test_rewardEscrow_claim() public {
        // ~ Config ~

        //

        // ~ Execute deposit ~

        //

        // ~ Post-state check ~

        //
    }
}