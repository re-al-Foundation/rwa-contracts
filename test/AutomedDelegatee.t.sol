// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// foundry imports
import { Test, console2 } from "../lib/forge-std/src/Test.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { RevenueStreamETH } from "../src/RevenueStreamETH.sol";
import { DelegateFactory } from "../src/governance/DelegateFactory.sol";
import { Delegator } from "../src/governance/Delegator.sol";

// helpers
import { VotingEscrowRWAAPI } from "../src/helpers/VotingEscrowRWAAPI.sol";
import { AutomatedDelegatee } from "../src/helpers/AutomatedDelegatee.sol";

// local helper imports
import "./utils/Utility.sol";
import "./utils/Constants.sol";

/**
 * @title AutomatedDelegateeTest
 * @author @chasebrownn
 * @notice This test file contains integration tests for the AutomatedDelegatee contract.
 */
contract AutomatedDelegateeTest is Utility {

    // Contracts
    RevenueStreamETH public constant REV_STREAM = RevenueStreamETH(0xf4e03D77700D42e13Cd98314C518f988Fd6e287a);
    DelegateFactory public constant DELEGATE_FACTORY = DelegateFactory(0x4Bc715a61dF515944907C8173782ea83d196D0c9);
    VotingEscrowRWAAPI public constant API = VotingEscrowRWAAPI(0x42EfcE5C2DcCFD45aA441D9e57D8331382ee3725);

    AutomatedDelegatee public automatedDelegatee;

    function setUp() public {
        vm.createSelectFork(REAL_RPC_URL, 165700);
    }

    function test_automatedDelegatee_claimRewards() public {}

    function test_automatedDelegatee_claimRewardsIncrement() public {}
}