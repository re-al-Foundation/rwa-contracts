// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// foundry imports
import { Test } from "../../lib/forge-std/src/Test.sol";

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

    function test_stRWA_updateRebaseIndexManager() public {}

    function test_tokenSilo_setFundsManager() public {}

    function test_tokenSilo_setRebaseController() public {}
    
}