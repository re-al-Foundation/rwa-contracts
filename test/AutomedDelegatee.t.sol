// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// foundry imports
import { Test, console2 } from "../lib/forge-std/src/Test.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { RevenueStreamETH } from "../src/RevenueStreamETH.sol";
import { RWAVotingEscrow } from "../src/governance/RWAVotingEscrow.sol";
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
    RWAVotingEscrow public constant VE_RWA = RWAVotingEscrow(0xa7B4E29BdFf073641991b44B283FD77be9D7c0F4);
    RevenueStreamETH public constant REV_STREAM = RevenueStreamETH(0xf4e03D77700D42e13Cd98314C518f988Fd6e287a);
    DelegateFactory public constant DELEGATE_FACTORY = DelegateFactory(0x4Bc715a61dF515944907C8173782ea83d196D0c9);
    VotingEscrowRWAAPI public constant API = VotingEscrowRWAAPI(0x42EfcE5C2DcCFD45aA441D9e57D8331382ee3725);

    address public constant REV_DISTRIBUTOR = 0x7a2E4F574C0c28D6641fE78197f1b460ce5E4f6C;
    uint256 public constant delegatedTokenId = 1555;

    AutomatedDelegatee public automatedDelegatee;

    // Actors
    address public constant DELEGATOR_ADMIN = 0x946C569791De3283f33372731d77555083c329da;
    address public constant DELEGATEE       = address(bytes20(bytes("DELEGATEE")));

    function setUp() public {
        vm.createSelectFork(REAL_RPC_URL, 165700);

        // deploy AutomatedDelegatee
        automatedDelegatee = new AutomatedDelegatee();
        ERC1967Proxy automatedDelegateeProxy = new ERC1967Proxy(
            address(automatedDelegatee),
            abi.encodeWithSelector(AutomatedDelegatee.initialize.selector,
                ADMIN,
                DELEGATEE
            )
        );
        automatedDelegatee = AutomatedDelegatee(payable(address(automatedDelegateeProxy)));

        // create delegation to automatedDelegatee
        vm.startPrank(DELEGATOR_ADMIN);
        VE_RWA.approve(address(DELEGATE_FACTORY), delegatedTokenId);
        DELEGATE_FACTORY.deployDelegator(
            delegatedTokenId,
            address(automatedDelegatee),
            (30 days)
        );
        vm.stopPrank();

        // upgrade RevenueStreamETH -> claimable now returns index data
        vm.startPrank(DELEGATOR_ADMIN);
        RevenueStreamETH newRevStream = new RevenueStreamETH();
        REV_STREAM.upgradeToAndCall(address(newRevStream), "");
        vm.stopPrank();
    }

    /// @dev Verifies proper state changes when AutomatedDelegatee::claimRewards is called.
    function test_automatedDelegatee_claimRewards() public {
        // ~ Config ~

        uint256 amount = 1_000 ether;
        vm.deal(REV_DISTRIBUTOR, amount);

        assertEq(automatedDelegatee.claimable(), 0);

        vm.prank(REV_DISTRIBUTOR);
        REV_STREAM.depositETH{value: amount}();
        skip(1);

        // ~ Pre-state check ~

        uint256 preBal = DELEGATEE.balance;
        uint256 claimable = automatedDelegatee.claimable();
        assertGt(claimable, 0);

        // ~ Execute claimRewards ~

        vm.expectRevert(abi.encodeWithSelector(AutomatedDelegatee.InvalidAmount.selector, claimable));
        automatedDelegatee.claimRewards(1_000 ether);

        uint256 claimed = automatedDelegatee.claimRewards(.03 ether);

        // ~ Post-state check ~

        assertEq(claimed, claimable);
        assertEq(DELEGATEE.balance, preBal + claimable);
        assertEq(automatedDelegatee.claimable(), 0);
    }

    /// @dev Verifies proper state changes when AutomatedDelegatee::claimRewardsIncrement is called.
    function test_automatedDelegatee_claimRewardsIncrement() public {
        // ~ Config ~

        uint256 numIndexes = 1000;
        uint256 amount = 1_000 ether;
        vm.deal(REV_DISTRIBUTOR, amount);

        assertEq(automatedDelegatee.claimable(), 0);

        vm.prank(REV_DISTRIBUTOR);
        REV_STREAM.depositETH{value: amount}();
        skip(1);

        // ~ Pre-state check ~

        uint256 preBal = DELEGATEE.balance;
        (uint256 claimable,,, uint256 num, uint256 preIndexes) = REV_STREAM.claimable(address(automatedDelegatee));
        emit log_named_uint("indexes", preIndexes); // 1475
        emit log_named_uint("num", num); // 1 (last index)

        // ~ Execute claimRewardsIncrement ~

        uint256 claimed = automatedDelegatee.claimRewardsIncrement(numIndexes);

        // ~ Post-state check 1 ~

        assertEq(claimed, 0);
        
        (,,,, uint256 postIndexes) = REV_STREAM.claimable(address(automatedDelegatee));
        emit log_named_uint("indexes", postIndexes); // 475

        assertEq(preIndexes, postIndexes + numIndexes);

        // ~ Execute claimRewardsIncrement ~

        claimed = automatedDelegatee.claimRewardsIncrement(numIndexes);

        // ~ Post-state check 2 ~

        assertEq(claimed, claimable);
        assertEq(DELEGATEE.balance, preBal + claimable);
        
        (claimable,,,, postIndexes) = REV_STREAM.claimable(address(automatedDelegatee));
        assertEq(postIndexes, 0);
        assertEq(claimable, 0);
    }
}