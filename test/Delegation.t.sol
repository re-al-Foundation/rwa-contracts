// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// foundry imports
import { Test, console2 } from "../lib/forge-std/src/Test.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Checkpoints } from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

// passive income nft imports
import { PassiveIncomeCalculator } from "../src/refs/PassiveIncomeCalculator.sol";

// local imports
import { TangibleERC20Mock } from "./utils/TangibleERC20Mock.sol";
import { RWAVotingEscrow } from "../src/governance/RWAVotingEscrow.sol";
import { VotingEscrowVesting } from "../src/governance/VotingEscrowVesting.sol";
import { RWAToken } from "../src/RWAToken.sol";
import { MarketplaceMock } from "./utils/MarketplaceMock.sol";
import { PassiveIncomeNFT } from "../src/refs/PassiveIncomeNFT.sol";
import { VotingMath } from "../src/governance/VotingMath.sol";
import { DelegateFactory } from "../src/governance/DelegateFactory.sol";
import { Delegator } from "../src/governance/Delegator.sol";

// local helper imports
import "./utils/Utility.sol";
import "./utils/Constants.sol";

/**
 * @title DelegationTest
 * @author @chasebrownn
 * @notice This test file contains the basic unit testing for the DelegateFactory and Delegator contract
 */
contract DelegationTest is Utility {
    using VotingMath for uint256;

    // ~ Contracts ~

    PassiveIncomeNFT public passiveIncomeNFTV1;
    PassiveIncomeCalculator public piCalculator;
    TangibleERC20Mock public tngblToken;
    RWAVotingEscrow public veRWA;
    VotingEscrowVesting public vesting;
    RWAToken public rwaToken;
    MarketplaceMock public marketplace;
    DelegateFactory public delegateFactory;
    Delegator public delegator;

    // helper
    ERC20Mock public mockRevToken;

    // proxies
    ERC1967Proxy public veRWAProxy;
    ERC1967Proxy public vestingProxy;
    ERC1967Proxy public rwaTokenProxy;
    ERC1967Proxy public delegateFactoryProxy;

    function setUp() public {

        // ~ Deploy Contracts ~

        // Deploy mock rev token
        mockRevToken = new ERC20Mock();

        // Deploy $TNGBL token
        tngblToken = new TangibleERC20Mock();

        // Deploy piCalculator
        piCalculator = new PassiveIncomeCalculator();

        // Deploy passiveIncomeNFT
        passiveIncomeNFTV1 = new PassiveIncomeNFT(
            address(tngblToken),
            address(piCalculator),
            block.timestamp
        );

        // Deploy Marketplace
        marketplace = new MarketplaceMock();

        // Deploy $RWA Token implementation
        rwaToken = new RWAToken();

        // Deploy proxy for $RWA Token
        rwaTokenProxy = new ERC1967Proxy(
            address(rwaToken),
            abi.encodeWithSelector(RWAToken.initialize.selector,
                ADMIN,
                address(0),
                address(0)
            )
        );
        rwaToken = RWAToken(payable(address(rwaTokenProxy)));

        // Deploy vesting contract
        vesting = new VotingEscrowVesting();

        // Deploy proxy for vesting contract
        vestingProxy = new ERC1967Proxy(
            address(vesting),
            abi.encodeWithSelector(VotingEscrowVesting.initialize.selector,
                ADMIN
            )
        );
        vesting = VotingEscrowVesting(address(vestingProxy));

        // Deploy veRWA implementation
        veRWA = new RWAVotingEscrow();

        // Deploy proxy for veRWA
        veRWAProxy = new ERC1967Proxy(
            address(veRWA),
            abi.encodeWithSelector(RWAVotingEscrow.initialize.selector,
                address(rwaToken),
                address(vesting),
                address(0), // Note: For migration
                ADMIN
            )
        );
        veRWA = RWAVotingEscrow(address(veRWAProxy));

        // Deploy Delegator implementation
        delegator = new Delegator();

        // Deploy DelegateFactory
        delegateFactory = new DelegateFactory();

        // Deploy DelegateFactory proxy
        delegateFactoryProxy = new ERC1967Proxy(
            address(delegateFactory),
            abi.encodeWithSelector(DelegateFactory.initialize.selector,
                address(veRWA),
                address(delegator),
                ADMIN
            )
        );
        delegateFactory = DelegateFactory(address(delegateFactoryProxy));

        // ~ Config ~

        // set votingEscrow on vesting contract
        vm.prank(ADMIN);
        vesting.setVotingEscrowContract(address(veRWA));

        // set marketplace on PassiveIncomeNFT
        passiveIncomeNFTV1.setMarketplaceContract(address(marketplace));

        // Grant minter role to address(this) & veRWA
        vm.startPrank(ADMIN);
        rwaToken.setVotingEscrowRWA(address(veRWA));
        rwaToken.setReceiver(address(this)); // for testing
        vm.stopPrank();

        tngblToken.grantRole(MINTER_ROLE, address(this));
        tngblToken.grantRole(MINTER_ROLE, address(passiveIncomeNFTV1));

        // Mint Admin $RWA tokens
        rwaToken.mintFor(ADMIN, 1_000 ether);
    }


    // ------------------
    // Initial State Test
    // ------------------

    /// @notice Initial state test.
    function test_delegation_init_state() public {
        assertEq(address(delegateFactory.veRWA()), address(veRWA));
        assertEq(delegateFactory.getDelegatorsArray().length, 0);
    }


    // ----------
    // Unit Tests
    // ----------

    /// @notice Verifies state when RWAVotingEscrow::delegate is executed.
    function test_delegation_delegate() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 totalDuration = (36 * 30 days); // lock for max

        Checkpoints.Trace208 memory delegateCheckpoints;

        vm.startPrank(ADMIN);
        rwaToken.approve(address(veRWA), amount);
        uint256 tokenId = veRWA.mint(
            ADMIN,
            uint208(amount),
            totalDuration
        );
        vm.stopPrank();

        // ~ Pre-state check ~

        uint256 votingPower = amount.calculateVotingPower(totalDuration);
        emit log_named_uint("max duration MAX Voting Power", votingPower);

        assertEq(veRWA.ownerOf(tokenId), ADMIN);
        assertEq(veRWA.getAccountVotingPower(ADMIN), votingPower);
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        assertEq(veRWA.getVotes(ADMIN), votingPower);
        assertEq(veRWA.getVotes(JOE), 0);

        assertEq(veRWA.delegates(ADMIN), ADMIN);

        delegateCheckpoints = veRWA.getDelegatesCheckpoints(ADMIN);
        assertEq(delegateCheckpoints._checkpoints.length, 1);
        assertEq(delegateCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(delegateCheckpoints._checkpoints[0]._value, votingPower);

        delegateCheckpoints = veRWA.getDelegatesCheckpoints(JOE);
        assertEq(delegateCheckpoints._checkpoints.length, 0);

        // ~ Admin delegates to Joe ~

        skip(1);

        vm.prank(ADMIN);
        veRWA.delegate(JOE);

        // ~ Post-state check 1 ~

        assertEq(veRWA.ownerOf(tokenId), ADMIN);
        assertEq(veRWA.getAccountVotingPower(ADMIN), votingPower);
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        assertEq(veRWA.getVotes(ADMIN), 0);
        assertEq(veRWA.getVotes(JOE), votingPower);

        assertEq(veRWA.delegates(ADMIN), JOE);

        delegateCheckpoints = veRWA.getDelegatesCheckpoints(ADMIN);
        assertEq(delegateCheckpoints._checkpoints.length, 2);
        assertEq(delegateCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(delegateCheckpoints._checkpoints[0]._value, votingPower);
        assertEq(delegateCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(delegateCheckpoints._checkpoints[1]._value, 0);

        delegateCheckpoints = veRWA.getDelegatesCheckpoints(JOE);
        assertEq(delegateCheckpoints._checkpoints.length, 1);
        assertEq(delegateCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(delegateCheckpoints._checkpoints[0]._value, votingPower);

        // ~ Admin delegates to himself ~

        skip(1);

        vm.prank(ADMIN);
        veRWA.delegate(ADMIN);

        // ~ Post-state check 2 ~

        assertEq(veRWA.ownerOf(tokenId), ADMIN);
        assertEq(veRWA.getAccountVotingPower(ADMIN), votingPower);
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        assertEq(veRWA.getVotes(ADMIN), votingPower);
        assertEq(veRWA.getVotes(JOE), 0);

        assertEq(veRWA.delegates(ADMIN), ADMIN);

        delegateCheckpoints = veRWA.getDelegatesCheckpoints(ADMIN);
        assertEq(delegateCheckpoints._checkpoints.length, 3);
        assertEq(delegateCheckpoints._checkpoints[0]._key, block.timestamp - 2);
        assertEq(delegateCheckpoints._checkpoints[0]._value, votingPower);
        assertEq(delegateCheckpoints._checkpoints[1]._key, block.timestamp - 1);
        assertEq(delegateCheckpoints._checkpoints[1]._value, 0);
        assertEq(delegateCheckpoints._checkpoints[2]._key, block.timestamp);
        assertEq(delegateCheckpoints._checkpoints[2]._value, votingPower);

        delegateCheckpoints = veRWA.getDelegatesCheckpoints(JOE);
        assertEq(delegateCheckpoints._checkpoints.length, 2);
        assertEq(delegateCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(delegateCheckpoints._checkpoints[0]._value, votingPower);
        assertEq(delegateCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(delegateCheckpoints._checkpoints[1]._value, 0);
    }

    /// @notice Verifies state when DelegateFactory::deployDelegator is executed.
    function test_delegation_deployDelegator() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 totalDuration = (36 * 30 days); // lock for max

        Checkpoints.Trace208 memory delegateCheckpoints;

        vm.startPrank(ADMIN);
        rwaToken.approve(address(veRWA), amount);
        uint256 tokenId = veRWA.mint(
            ADMIN,
            uint208(amount),
            totalDuration
        );

        // ~ Pre-state check ~

        uint256 votingPower = amount.calculateVotingPower(totalDuration);
        emit log_named_uint("max duration MAX Voting Power", votingPower);

        assertEq(veRWA.ownerOf(tokenId), ADMIN);
        assertEq(veRWA.getAccountVotingPower(ADMIN), votingPower);
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        assertEq(veRWA.getVotes(ADMIN), votingPower);
        assertEq(veRWA.getVotes(JOE), 0);

        assertEq(veRWA.delegates(ADMIN), ADMIN);

        delegateCheckpoints = veRWA.getDelegatesCheckpoints(ADMIN);
        assertEq(delegateCheckpoints._checkpoints.length, 1);
        assertEq(delegateCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(delegateCheckpoints._checkpoints[0]._value, votingPower);

        delegateCheckpoints = veRWA.getDelegatesCheckpoints(JOE);
        assertEq(delegateCheckpoints._checkpoints.length, 0);

        // ~ Execute deployDelegator ~

        skip(1);

        // Admin delegates voting power to Joe for 1 month.
        vm.startPrank(ADMIN);
        veRWA.approve(address(delegateFactory), tokenId);
        address delegator = delegateFactory.deployDelegator(
            tokenId,
            JOE,
            (30 days)
        );
        vm.stopPrank();

        // ~ Post-state check ~

        assertEq(veRWA.ownerOf(tokenId), address(delegator));
        assertEq(veRWA.getAccountVotingPower(ADMIN), 0);
        assertEq(veRWA.getAccountVotingPower(address(delegator)), votingPower);
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        assertEq(veRWA.getVotes(ADMIN), 0);
        assertEq(veRWA.getVotes(address(delegator)), 0);
        assertEq(veRWA.getVotes(JOE), votingPower);

        assertEq(veRWA.delegates(ADMIN), ADMIN);
        assertEq(veRWA.delegates(address(delegator)), JOE);

        delegateCheckpoints = veRWA.getDelegatesCheckpoints(ADMIN);
        assertEq(delegateCheckpoints._checkpoints.length, 2);
        assertEq(delegateCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(delegateCheckpoints._checkpoints[0]._value, votingPower);
        assertEq(delegateCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(delegateCheckpoints._checkpoints[1]._value, 0);

        delegateCheckpoints = veRWA.getDelegatesCheckpoints(address(delegator));
        assertEq(delegateCheckpoints._checkpoints.length, 1);
        assertEq(delegateCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(delegateCheckpoints._checkpoints[0]._value, 0);

        delegateCheckpoints = veRWA.getDelegatesCheckpoints(JOE);
        assertEq(delegateCheckpoints._checkpoints.length, 1);
        assertEq(delegateCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(delegateCheckpoints._checkpoints[0]._value, votingPower);
    }

    /// @notice Verifies state when DelegateFactory::revokeExpiredDelegators is called
    function test_delegation_revokeAndDelete() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 totalDuration = (36 * 30 days); // lock for max

        vm.startPrank(ADMIN);
        rwaToken.approve(address(veRWA), amount);
        uint256 tokenId = veRWA.mint(
            ADMIN,
            uint208(amount),
            totalDuration
        );

        uint256 votingPower = amount.calculateVotingPower(totalDuration);

        // Admin delegates voting power to Joe for 1 month.
        vm.startPrank(ADMIN);
        veRWA.approve(address(delegateFactory), tokenId);
        address delegator = delegateFactory.deployDelegator(
            tokenId,
            JOE,
            (30 days)
        );
        vm.stopPrank();

        // ~ Pre-state check ~

        assertEq(delegateFactory.getDelegatorsArray().length, 1);
        assertEq(delegateFactory.delegatorExpiration(delegator), block.timestamp + (30 days));
        assertEq(delegateFactory.isDelegator(delegator), true);
        assertEq(delegateFactory.expiredDelegatorExists(), false);
        assertEq(delegateFactory.isExpiredDelegator(delegator), false);

        assertEq(veRWA.ownerOf(tokenId), address(delegator));
        assertEq(veRWA.getAccountVotingPower(ADMIN), 0);
        assertEq(veRWA.getAccountVotingPower(address(delegator)), votingPower);
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        assertEq(veRWA.getVotes(ADMIN), 0);
        assertEq(veRWA.getVotes(address(delegator)), 0);
        assertEq(veRWA.getVotes(JOE), votingPower);

        assertEq(veRWA.delegates(ADMIN), ADMIN);
        assertEq(veRWA.delegates(address(delegator)), JOE);

        // ~ Skip to expiration and check ~

        skip(30 days);

        assertEq(delegateFactory.expiredDelegatorExists(), true);
        assertEq(delegateFactory.isExpiredDelegator(delegator), true);

        // ~ Execute revokeExpiredDelegators ~

        delegateFactory.revokeExpiredDelegators();

        // ~ Post-state check ~

        assertEq(delegateFactory.getDelegatorsArray().length, 0);
        assertEq(delegateFactory.delegatorExpiration(delegator), 0);
        assertEq(delegateFactory.isDelegator(delegator), false);
        assertEq(delegateFactory.expiredDelegatorExists(), false);

        assertEq(veRWA.ownerOf(tokenId), ADMIN);
        assertEq(veRWA.getAccountVotingPower(ADMIN), votingPower);
        assertEq(veRWA.getAccountVotingPower(address(delegator)), 0);
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        assertEq(veRWA.getVotes(ADMIN), votingPower);
        assertEq(veRWA.getVotes(address(delegator)), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        assertEq(veRWA.delegates(ADMIN), ADMIN);
        assertEq(veRWA.delegates(address(delegator)), address(delegator));

        // restrictions test -> random address will return false
        assertEq(delegateFactory.isExpiredDelegator(address(1)), false);
    }

    /// @notice Verifies state when DelegateFactory::revokeExpiredDelegators is called to revoke multiple delegators
    function test_delegation_revokeAndDelete_multiple() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 numDelegators = 4;
        uint256 totalDuration = (36 * 30 days); // lock for max

        uint256[] memory tokenIds = new uint256[](numDelegators);
        address[] memory delegators = new address[](numDelegators);

        // Mint Admin $RWA tokens
        rwaToken.mintFor(ADMIN, amount * numDelegators);

        for (uint256 i; i < numDelegators; ++i) {
            vm.startPrank(ADMIN);
            rwaToken.approve(address(veRWA), amount);
            tokenIds[i] = veRWA.mint(
                ADMIN,
                uint208(amount),
                totalDuration
            );
            vm.stopPrank();
        }

        uint256 votingPower = amount.calculateVotingPower(totalDuration);

        // Admin delegates voting power to Joe for 1 month.
        for (uint256 i; i < numDelegators; ++i) {
            vm.startPrank(ADMIN);
            veRWA.approve(address(delegateFactory), tokenIds[i]);
            delegators[i] = delegateFactory.deployDelegator(
                tokenIds[i],
                JOE,
                (30 days)
            );
            vm.stopPrank();
        }

        // ~ Pre-state check ~

        assertEq(delegateFactory.getDelegatorsArray().length, numDelegators);
        
        for (uint256 i; i < numDelegators; ++i) {
            assertEq(delegateFactory.delegatorExpiration(delegators[i]), block.timestamp + (30 days));
            assertEq(delegateFactory.isDelegator(delegators[i]), true);
            assertEq(delegateFactory.expiredDelegatorExists(), false);
            assertEq(delegateFactory.isExpiredDelegator(delegators[i]), false);

            assertEq(veRWA.ownerOf(tokenIds[i]), delegators[i]);
            assertEq(veRWA.getAccountVotingPower(delegators[i]), votingPower);
            assertEq(veRWA.getVotes(delegators[i]), 0);
            assertEq(veRWA.delegates(delegators[i]), JOE);
        }

        assertEq(veRWA.getAccountVotingPower(ADMIN), 0);
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        assertEq(veRWA.getVotes(ADMIN), 0);
        assertEq(veRWA.getVotes(JOE), votingPower * numDelegators);

        // ~ Skip to expiration and check ~

        skip(30 days);

        assertEq(delegateFactory.expiredDelegatorExists(), true);
        for (uint256 i; i < numDelegators; ++i) {
            assertEq(delegateFactory.isExpiredDelegator(delegators[i]), true);
        }

        // ~ Execute revokeExpiredDelegators ~

        delegateFactory.revokeExpiredDelegators();

        // ~ Post-state check ~

        assertEq(veRWA.getVotes(ADMIN), votingPower * numDelegators);
        assertEq(veRWA.getVotes(address(delegator)), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        assertEq(veRWA.delegates(ADMIN), ADMIN);

        assertEq(delegateFactory.getDelegatorsArray().length, 0);
        
        for (uint256 i; i < numDelegators; ++i) {
            assertEq(delegateFactory.delegatorExpiration(delegators[i]), 0);
            assertEq(delegateFactory.isDelegator(delegators[i]), false);
            assertEq(delegateFactory.expiredDelegatorExists(), false);

            assertEq(veRWA.ownerOf(tokenIds[i]), ADMIN);
            assertEq(veRWA.getAccountVotingPower(delegators[i]), 0);
            assertEq(veRWA.getVotes(delegators[i]), 0);
            assertEq(veRWA.delegates(delegators[i]), delegators[i]);
        }

        assertEq(veRWA.getAccountVotingPower(ADMIN), votingPower * numDelegators);
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        assertEq(veRWA.getVotes(ADMIN), votingPower * numDelegators);
        assertEq(veRWA.getVotes(JOE), 0);
    }

}