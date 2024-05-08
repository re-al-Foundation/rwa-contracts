// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// foundry imports
import { Test, console2 } from "../lib/forge-std/src/Test.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Checkpoints } from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

// local imports
import { RevenueStream } from "../src/RevenueStream.sol";
import { RevenueDistributor } from "../src/RevenueDistributor.sol";
import { RWAVotingEscrow } from "../src/governance/RWAVotingEscrow.sol";
import { VotingEscrowVesting } from "../src/governance/VotingEscrowVesting.sol";
import { RWAToken } from "../src/RWAToken.sol";
import { DelegateFactory } from "../src/governance/DelegateFactory.sol";
import { Delegator } from "../src/governance/Delegator.sol";

// local helper imports
import { Utility } from "./utils/Utility.sol";
import { VotingMath } from "../src/governance/VotingMath.sol";
import "./utils/Constants.sol";

/**
 * @title RWARevenueStreamTest
 * @author @chasebrownn
 * @notice This test file contains the basic unit tests for the RevenueStream contract.
 */
contract RWARevenueStreamTest is Utility {
    using VotingMath for uint256;

    // ~ Contracts ~

    RevenueStream public revStream;
    RevenueDistributor public revDistributor;
    RWAVotingEscrow public veRWA;
    VotingEscrowVesting public vesting;
    RWAToken public rwaToken;
    DelegateFactory public delegateFactory;
    Delegator public delegator;

    // proxies
    ERC1967Proxy public revStreamProxy;
    ERC1967Proxy public revDistributorProxy;
    ERC1967Proxy public veRWAProxy;
    ERC1967Proxy public vestingProxy;
    ERC1967Proxy public rwaTokenProxy;
    ERC1967Proxy public delegateFactoryProxy;


    function setUp() public {

        // ~ $RWA Deployment ~

        // Deploy $RWA Token implementation
        rwaToken = new RWAToken();

        // Deploy proxy for $RWA Token
        rwaTokenProxy = new ERC1967Proxy(
            address(rwaToken),
            abi.encodeWithSelector(RWAToken.initialize.selector,
                ADMIN
            )
        );
        rwaToken = RWAToken(payable(address(rwaTokenProxy)));


        // ~ Vesting Deployment ~

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


        // ~ veRWA Deployment ~

        // Deploy veRWA implementation
        veRWA = new RWAVotingEscrow();

        // Deploy proxy for veRWA
        veRWAProxy = new ERC1967Proxy(
            address(veRWA),
            abi.encodeWithSelector(RWAVotingEscrow.initialize.selector,
                address(rwaToken),
                address(vesting),
                LAYER_Z, // Note: Layer Zero Endpoint -> For migration
                ADMIN
            )
        );
        veRWA = RWAVotingEscrow(address(veRWAProxy));


        // ~ Revenue Distributor Deployment ~

        // Deploy revDistributor contract
        revDistributor = new RevenueDistributor();

        // Deploy proxy for revDistributor
        revDistributorProxy = new ERC1967Proxy(
            address(revDistributor),
            abi.encodeWithSelector(RevenueDistributor.initialize.selector,
                ADMIN,
                address(veRWA),
                address(0)
            )
        );
        revDistributor = RevenueDistributor(payable(address(revDistributorProxy)));


        // ~ Revenue Stream Deployment ~

        // Deploy revStream contract
        revStream = new RevenueStream(address(rwaToken));

        // Deploy proxy for revStream
        revStreamProxy = new ERC1967Proxy(
            address(revStream),
            abi.encodeWithSelector(RevenueStream.initialize.selector,
                address(revDistributor),
                address(veRWA),
                ADMIN
            )
        );
        revStream = RevenueStream(address(revStreamProxy));


        // ~ Delegator Deployment ~

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
        vm.startPrank(ADMIN);
        vesting.setVotingEscrowContract(address(veRWA));
        revDistributor.addRevenueToken(address(rwaToken));
        revDistributor.setRevenueStreamForToken(address(rwaToken), address(revStream));

        // Grant minter role to address(this) & veRWA
        rwaToken.setVotingEscrowRWA(address(veRWA));
        rwaToken.setReceiver(address(this)); // for testing

        rwaToken.excludeFromFees(address(veRWA), true);
        rwaToken.excludeFromFees(JOE, true);
        rwaToken.excludeFromFees(address(revStream), true);
        vm.stopPrank();

        // Mint Joe $RWA tokens
        rwaToken.mintFor(JOE, 1_000 ether);
    }


    // ------------------
    // Initial State Test
    // ------------------

    /// @dev Verifies initial state of RevenueStream contract.
    function test_revStream_init_state() public {
        assertEq(address(revStream.votingEscrow()), address(veRWA));
        assertEq(address(revStream.revenueToken()), address(rwaToken));
        assertEq(revStream.owner(), ADMIN);
        assertEq(revStream.revenueDistributor(), address(revDistributor));
        assertEq(revStream.getCyclesArray().length, 1);
    }


    // ----------
    // Unit Tests
    // ----------

    // ~ deposit ~

    /// @dev Verifies proper state changes when RevenueStream::deposit() is executed.
    function test_revStream_deposit() public {
        
        // ~ Config ~

        uint256 amount = 1_000 ether;
        rwaToken.mintFor(address(revDistributor), amount);

        // ~ Pre-state check ~

        assertEq(rwaToken.balanceOf(address(revStream)), 0);
        assertEq(rwaToken.balanceOf(address(revDistributor)), amount);

        uint256[] memory cycles = revStream.getCyclesArray();
        assertEq(cycles.length, 1);
        assertEq(cycles[0], block.timestamp);

        // ~ Execute Deposit ~

        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amount);
        revStream.deposit(amount);
        vm.stopPrank();

        // ~ Post-state check ~

        assertEq(rwaToken.balanceOf(address(revStream)), amount);
        assertEq(rwaToken.balanceOf(address(revDistributor)), 0);

        assertEq(revStream.revenue(block.timestamp), amount);

        cycles = revStream.getCyclesArray();
        assertEq(cycles.length, 2);
        assertEq(cycles[0], block.timestamp);
        assertEq(cycles[1], block.timestamp);
    }

    /// @dev Verifies amount cannot be 0 when deposit() is called.
    function test_revStream_deposit_cantBe0() public {
        vm.prank(address(revDistributor));
        vm.expectRevert("RevenueStream: amount == 0");
        revStream.deposit(0);
    }

    // ~ claimable ~

    /// @dev Verifies proper return variable when RevenueStream::claimable() is called.
    function test_revStream_claimable_single() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 amountRevenue = 5_000 ether;
        uint256 duration = (1 * 30 days);

        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            duration
        );
        vm.stopPrank();

        // mint RWA to revDistributor
        rwaToken.mintFor(address(revDistributor), amountRevenue);

        // deposit revenue into RevStream contract
        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();
        
        // ~ Skip to avoid FutureLookup error ~

        skip(1);

        // ~ Call claimable ~

        uint256 claimable = revStream.claimable(JOE);

        // ~ Verify ~

        assertEq(claimable, amountRevenue);
    }

    /// @dev Verifies proper return variable when RevenueStream::claimableIncrement() is called.
    function test_revStream_claimable_single_increment() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 amountRevenue = 5_000 ether;
        uint256 duration = (1 * 30 days);

        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            duration
        );
        vm.stopPrank();

        // mint RWA to revDistributor
        rwaToken.mintFor(address(revDistributor), amountRevenue * 2);

        // deposit revenue into RevStream contract
        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();
        skip(1);
        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();
        
        // ~ Skip to avoid FutureLookup error ~

        skip(1);

        // ~ Verify ~

        assertEq(revStream.claimableIncrement(JOE, 1), amountRevenue);
        assertEq(revStream.claimableIncrement(JOE, 2), amountRevenue*2);
        assertEq(revStream.claimable(JOE), amountRevenue*2);
    }

    /// @dev Verifies proper return variable when RevenueStream::claimable() is called.
    function test_revStream_claimable_multiple() public {

        // ~ Config ~

        uint256 amount1 = 1_000 ether;
        // Mint Joe more$RWA tokens
        rwaToken.mintFor(JOE, amount1);

        uint256 amountRevenue = 5_000 ether;
        uint256 duration = (1 * 30 days);

        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount1);
        veRWA.mint(
            JOE,
            uint208(amount1),
            duration
        );
        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount1);
        veRWA.mint(
            JOE,
            uint208(amount1),
            duration
        );
        vm.stopPrank();

        // mint RWA to revDistributor
        rwaToken.mintFor(address(revDistributor), amountRevenue);

        // deposit revenue into RevStream contract
        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();

        // ~ Skip to avoid FutureLookup error ~

        skip(1);

        // ~ Call claimable ~

        uint256 claimableJoe = revStream.claimable(JOE);

        // ~ Verify ~

        assertEq(claimableJoe, amountRevenue);
    }

    /// @dev Verifies proper state changes when RevenueStream::claim() is executed.
    function test_revStream_claim_single() public {
        
        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 amountRevenue = 5_000 ether;
        uint256 duration = (1 * 30 days);

        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        veRWA.mint(
            JOE,
            uint208(amount),
            duration
        );
        vm.stopPrank();

        // mint RWA to revDistributor
        rwaToken.mintFor(address(revDistributor), amountRevenue * 3);

        // deposit revenue into RevStream contract
        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();
        skip(1);
        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();

        // Skip to avoid FutureLookup error (when querying voting power)
        skip(1);

        // ~ Pre-state check ~

        uint256 preBalJoe = rwaToken.balanceOf(JOE);

        assertEq(rwaToken.balanceOf(JOE), preBalJoe);
        assertEq(rwaToken.balanceOf(address(revStream)), amountRevenue * 2);
        assertEq(revStream.lastClaimIndex(JOE), 0);

        uint256 claimable = revStream.claimable(JOE);

        // ~ Execute claim ~

        vm.prank(JOE);
        revStream.claim(JOE);

        // ~ Post-state check 1 ~

        assertEq(claimable, amountRevenue * 2);
        assertEq(rwaToken.balanceOf(JOE), preBalJoe + amountRevenue * 2);
        assertEq(rwaToken.balanceOf(address(revStream)), 0);
        assertEq(revStream.lastClaimIndex(JOE), 2);

        assertEq(revStream.revenueClaimed(1), amountRevenue);
        assertEq(revStream.revenueClaimed(2), amountRevenue);

        // ~ Another deposit ~

        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();

        // Skip to avoid FutureLookup error (when querying voting power)
        skip(1);

        claimable = revStream.claimable(JOE);

        // ~ Execute claim ~

        vm.prank(JOE);
        revStream.claim(JOE);

        // ~ Post-state check 2 ~

        assertEq(claimable, amountRevenue);
        assertEq(rwaToken.balanceOf(JOE), preBalJoe + amountRevenue * 3);
        assertEq(rwaToken.balanceOf(address(revStream)), 0);
        assertEq(revStream.lastClaimIndex(JOE), 3);

        assertEq(revStream.revenueClaimed(3), amountRevenue);
    }

    /// @dev Verifies proper state changes when RevenueStream::claimIncrement() is executed.
    function test_revStream_claim_single_increment() public {
        
        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 amountRevenue = 5_000 ether;
        uint256 duration = (1 * 30 days);

        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        veRWA.mint(
            JOE,
            uint208(amount),
            duration
        );
        vm.stopPrank();

        // mint RWA to revDistributor
        rwaToken.mintFor(address(revDistributor), amountRevenue * 3);

        // deposit revenue into RevStream contract
        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();
        skip(1);
        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();

        // Skip to avoid FutureLookup error (when querying voting power)
        skip(1);

        // ~ Pre-state check ~

        uint256 preBalJoe = rwaToken.balanceOf(JOE);

        assertEq(rwaToken.balanceOf(JOE), preBalJoe);
        assertEq(rwaToken.balanceOf(address(revStream)), amountRevenue * 2);
        assertEq(revStream.lastClaimIndex(JOE), 0);

        assertEq(revStream.claimableIncrement(JOE, 1), amountRevenue);
        assertEq(revStream.claimableIncrement(JOE, 2), amountRevenue*2);
        assertEq(revStream.claimable(JOE), amountRevenue*2);

        // ~ Execute claim increment 1 ~

        vm.prank(JOE);
        revStream.claimIncrement(JOE, 1);

        // ~ Post-state check 1 ~

        assertEq(rwaToken.balanceOf(JOE), preBalJoe + amountRevenue);
        assertEq(rwaToken.balanceOf(address(revStream)), amountRevenue);
        assertEq(revStream.lastClaimIndex(JOE), 1);

        assertEq(revStream.revenueClaimed(1), amountRevenue);
        assertEq(revStream.revenueClaimed(2), 0);

        assertEq(revStream.claimableIncrement(JOE, 1), amountRevenue);
        assertEq(revStream.claimable(JOE), amountRevenue);

        // ~ Execute claim increment 2 ~

        vm.prank(JOE);
        revStream.claimIncrement(JOE, 2);

        // ~ Post-state check 2 ~

        assertEq(rwaToken.balanceOf(JOE), preBalJoe + amountRevenue * 2);
        assertEq(rwaToken.balanceOf(address(revStream)), 0);
        assertEq(revStream.lastClaimIndex(JOE), 2);

        assertEq(revStream.revenueClaimed(1), amountRevenue);
        assertEq(revStream.revenueClaimed(2), amountRevenue);

        // ~ Another deposit ~

        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();

        // Skip to avoid FutureLookup error (when querying voting power)
        skip(1);

        assertEq(revStream.claimableIncrement(JOE, 1), amountRevenue);
        assertEq(revStream.claimable(JOE), amountRevenue);

        // ~ Execute claim ~

        vm.prank(JOE);
        revStream.claimIncrement(JOE, 1);

        // ~ Post-state check 3 ~

        assertEq(rwaToken.balanceOf(JOE), preBalJoe + amountRevenue * 3);
        assertEq(rwaToken.balanceOf(address(revStream)), 0);
        assertEq(revStream.lastClaimIndex(JOE), 3);

        assertEq(revStream.revenueClaimed(3), amountRevenue);

        assertEq(revStream.claimableIncrement(JOE, 1), 0);
        assertEq(revStream.claimable(JOE), 0);
    }

    /// @dev Verifies proper state changes when RevenueStream::claim() is executed.
    function test_revStream_claim_multiple() public {

        // ~ Config ~

        uint256 amount1 = 1_000 ether;
        // Mint Joe more$RWA tokens
        rwaToken.mintFor(JOE, amount1);

        uint256 amountRevenue = 5_000 ether;
        uint256 duration = (1 * 30 days);

        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount1);
        veRWA.mint(
            JOE,
            uint208(amount1),
            duration
        );
        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount1);
        veRWA.mint(
            JOE,
            uint208(amount1),
            duration
        );
        vm.stopPrank();

        // mint RWA to revDistributor
        rwaToken.mintFor(address(revDistributor), amountRevenue);

        // deposit revenue into RevStream contract
        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();

        // ~ Skip to avoid FutureLookup error ~

        skip(1);

        // ~ Pre-state check ~

        uint256 preBalJoe = rwaToken.balanceOf(JOE);

        assertEq(rwaToken.balanceOf(JOE), preBalJoe);
        assertEq(rwaToken.balanceOf(address(revStream)), amountRevenue);
        assertEq(revStream.lastClaimIndex(JOE), 0);

        assertEq(revStream.claimable(JOE), amountRevenue);

        // ~ Execute claim ~

        vm.prank(JOE);
        revStream.claim(JOE);

        // ~ Post-state check ~

        assertEq(rwaToken.balanceOf(JOE), preBalJoe + amountRevenue);
        assertEq(rwaToken.balanceOf(address(revStream)), 0);
        assertEq(revStream.lastClaimIndex(JOE), 1);

        assertEq(revStream.claimable(JOE), 0);
    }

    /// @dev Verifies delegatees can claim rent. 
    function test_revStream_claim_delegate() public {
        
        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 amountRevenue = 5_000 ether;
        uint256 duration = (1 * 30 days);

        // Mint ADMIN $RWA tokens
        rwaToken.mintFor(ADMIN, amount);

        // mint ADMIN veRWA token
        vm.startPrank(ADMIN);
        rwaToken.approve(address(veRWA), amount);
        uint256 tokenId = veRWA.mint(
            ADMIN,
            uint208(amount),
            duration
        );

        // Admin delegates voting power to Joe for 1 month.
        vm.startPrank(ADMIN);
        veRWA.approve(address(delegateFactory), tokenId);
        address delegator = delegateFactory.deployDelegator(
            tokenId,
            JOE,
            (30 days)
        );
        vm.stopPrank();

        // mint RWA to revDistributor
        rwaToken.mintFor(address(revDistributor), amountRevenue);

        // deposit revenue into RevStream contract
        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();

        // Skip to avoid FutureLookup error (when querying voting power)
        skip(1);

        // ~ Pre-state check ~

        uint256 preBalJoe = rwaToken.balanceOf(JOE);

        assertEq(rwaToken.balanceOf(JOE), preBalJoe);
        assertEq(rwaToken.balanceOf(address(revStream)), amountRevenue);
        assertEq(revStream.lastClaimIndex(ADMIN), 0);
        assertEq(revStream.lastClaimIndex(JOE), 0);

        assertEq(revStream.claimable(JOE), amountRevenue);

        assertEq(veRWA.ownerOf(tokenId), address(delegator));
        assertEq(veRWA.getAccountVotingPower(ADMIN), 0);
        assertGt(veRWA.getAccountVotingPower(address(delegator)), 0);
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        assertEq(veRWA.getVotes(ADMIN), 0);
        assertEq(veRWA.getVotes(address(delegator)), 0);
        assertGt(veRWA.getVotes(JOE), 0);

        assertEq(veRWA.delegates(ADMIN), ADMIN);
        assertEq(veRWA.delegates(address(delegator)), JOE);

        // ~ Execute claim ~

        vm.prank(JOE);
        revStream.claim(JOE);

        // ~ Post-state check 1 ~

        assertEq(rwaToken.balanceOf(JOE), preBalJoe + amountRevenue);
        assertEq(rwaToken.balanceOf(address(revStream)), 0);
        assertEq(revStream.lastClaimIndex(JOE), 1);
    }


    // ~ expired revenue ~

    /// @dev Verifies proper return variable when RevenueStream::expiredRevenue() is called.
    function test_revStream_expiredRevenue_single() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 amountRevenue = 5_000 ether;
        uint256 duration = (1 * 30 days);

        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            duration
        );
        vm.stopPrank();

        // mint RWA to revDistributor
        rwaToken.mintFor(address(revDistributor), amountRevenue);

        // deposit revenue into RevStream contract
        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();
        
        // ~ Skip to avoid FutureLookup error ~

        skip(1);

        // ~ Pre-state check ~

        assertEq(revStream.claimable(JOE), amountRevenue);
        assertEq(revStream.expiredRevenue(), 0);

        // ~ Skip to expiration ~

        skip(revStream.timeUntilExpired());

        // ~ Post-state check ~

        assertEq(revStream.claimable(JOE), amountRevenue);
        assertEq(revStream.expiredRevenue(), amountRevenue);

        // ~ Joe claims ~

        vm.prank(JOE);
        revStream.claim(JOE);

        // ~ Post-state check 2 ~

        assertEq(revStream.claimable(JOE), 0);
        assertEq(revStream.expiredRevenue(), 0);
    }

    /// @dev Verifies proper return variable when RevenueStream::expiredRevenueIncrement() is called.
    function test_revStream_expiredRevenue_single_increment() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 amountRevenue = 5_000 ether;
        uint256 duration = (1 * 30 days);

        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            duration
        );
        vm.stopPrank();

        // mint RWA to revDistributor
        rwaToken.mintFor(address(revDistributor), amountRevenue*2);

        // deposit revenue into RevStream contract
        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();
        skip(1);
        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();
        
        // ~ Skip to avoid FutureLookup error ~

        skip(1);

        // ~ Pre-state check ~

        assertEq(revStream.claimable(JOE), amountRevenue*2);
        assertEq(revStream.expiredRevenue(), 0);

        // ~ Skip to expiration ~

        skip(revStream.timeUntilExpired()+1);

        // ~ Post-state check 1 ~

        assertEq(revStream.claimable(JOE), amountRevenue*2);
        assertEq(revStream.expiredRevenueIncrement(1), amountRevenue);
        assertEq(revStream.expiredRevenueIncrement(2), amountRevenue*2);
        assertEq(revStream.expiredRevenue(), amountRevenue*2);

        // ~ Joe claims in increment 1/2 ~

        vm.prank(JOE);
        revStream.claimIncrement(JOE, 1);

        // ~ Post-state check 2 ~

        assertEq(revStream.claimable(JOE), amountRevenue);
        assertEq(revStream.expiredRevenueIncrement(1), 0);
        assertEq(revStream.expiredRevenueIncrement(2), amountRevenue);
        assertEq(revStream.expiredRevenue(), amountRevenue);

        // ~ Joe claims in increment 2/2 ~

        vm.prank(JOE);
        revStream.claimIncrement(JOE, 1);

        // ~ Post-state check 3 ~

        assertEq(revStream.claimable(JOE), 0);
        assertEq(revStream.expiredRevenueIncrement(1), 0);
        assertEq(revStream.expiredRevenue(), 0);
    }

    /// @dev Verifies proper return variable when RevenueStream::expiredRevenue() is called.
    function test_revStream_expiredRevenue_multiple() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 amountRevenue = 5_000 ether;
        uint256 duration = (1 * 30 days);

        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            duration
        );
        vm.stopPrank();

        // mint RWA to revDistributor
        rwaToken.mintFor(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();

        skip(1);
        // mint RWA to revDistributor
        rwaToken.mintFor(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();

        skip(1);
        // mint RWA to revDistributor
        rwaToken.mintFor(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();
        
        // ~ Skip to avoid FutureLookup error ~

        skip(revStream.timeUntilExpired()-3);

        // ~ Pre-state check ~

        assertEq(revStream.claimable(JOE), amountRevenue * 3);
        assertEq(revStream.expiredRevenue(), 0);

        // ~ Skip to expiration 1 ~

        skip(1); // first deposit is now expired

        // ~ Post-state check 1 ~

        assertEq(revStream.claimable(JOE), amountRevenue * 3);
        assertEq(revStream.expiredRevenue(), amountRevenue);

        // ~ Skip to expiration 2 ~

        skip(1); // second deposit + first is now expired

        // ~ Post-state check 2 ~

        assertEq(revStream.claimable(JOE), amountRevenue * 3);
        assertEq(revStream.expiredRevenue(), amountRevenue * 2);

        // ~ Skip to expiration 3 ~

        skip(1); // third deposit + second + first is now expired

        // ~ Post-state check 3 ~

        assertEq(revStream.claimable(JOE), amountRevenue * 3);
        assertEq(revStream.expiredRevenue(), amountRevenue * 3);

        // ~ Joe claims ~

        vm.prank(JOE);
        revStream.claim(JOE);

        // ~ Post-state check 4 ~

        assertEq(revStream.claimable(JOE), 0);
        assertEq(revStream.expiredRevenue(), 0);
    }

    function test_revStream_skimExpiredRevenue_single() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 amountRevenue = 5_000 ether;
        uint256 duration = (1 * 30 days);

        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            duration
        );
        vm.stopPrank();

        // mint RWA to revDistributor
        rwaToken.mintFor(address(revDistributor), amountRevenue);

        // deposit revenue into RevStream contract
        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();
        
        // ~ Skip to avoid FutureLookup error ~

        skip(1);

        // ~ Pre-state check ~

        assertEq(revStream.claimable(JOE), amountRevenue);
        assertEq(revStream.expiredRevenue(), 0);

        // ~ Attempt to skim -> Revert ~

        vm.prank(ADMIN);
        vm.expectRevert("No expired revenue claimable");
        revStream.skimExpiredRevenue();

        // ~ Skip to expiration ~

        skip(revStream.timeUntilExpired());

        // ~ Post-state check ~

        assertEq(revStream.claimable(JOE), amountRevenue);
        assertEq(revStream.expiredRevenue(), amountRevenue);

        assertEq(rwaToken.balanceOf(address(revStream)), amountRevenue);
        assertEq(rwaToken.balanceOf(address(revDistributor)), 0);

        // ~ expired is skimmed ~

        vm.prank(ADMIN);
        revStream.skimExpiredRevenue();

        // ~ Post-state check 2 ~

        assertEq(revStream.claimable(JOE), 0);
        assertEq(revStream.expiredRevenue(), 0);

        assertEq(rwaToken.balanceOf(address(revStream)), 0);
        assertEq(rwaToken.balanceOf(address(revDistributor)), amountRevenue);
    }

    function test_revStream_skimExpiredRevenue_single_increment() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 amountRevenue = 5_000 ether;
        uint256 duration = (1 * 30 days);

        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            duration
        );
        vm.stopPrank();

        // mint RWA to revDistributor
        rwaToken.mintFor(address(revDistributor), amountRevenue*2);

        // deposit revenue into RevStream contract
        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();
        skip(1);
        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();
        
        // ~ Skip to avoid FutureLookup error ~

        skip(1);

        // ~ Pre-state check ~

        assertEq(revStream.claimable(JOE), amountRevenue*2);
        assertEq(revStream.expiredRevenue(), 0);

        // ~ Attempt to skim -> Revert ~

        vm.prank(ADMIN);
        vm.expectRevert("No expired revenue claimable");
        revStream.skimExpiredRevenue();

        // ~ Skip to expiration ~

        skip(revStream.timeUntilExpired()+1);

        // ~ Pre-state check ~

        assertEq(revStream.claimable(JOE), amountRevenue*2);
        assertEq(revStream.expiredRevenueIncrement(1), amountRevenue);
        assertEq(revStream.expiredRevenueIncrement(2), amountRevenue*2);
        assertEq(revStream.expiredRevenue(), amountRevenue*2);

        assertEq(rwaToken.balanceOf(address(revStream)), amountRevenue*2);
        assertEq(rwaToken.balanceOf(address(revDistributor)), 0);

        // ~ expired is skimmed in 1st increment~

        vm.prank(ADMIN);
        revStream.skimExpiredRevenueIncrement(1);

        // ~ Post-state check 1 ~

        assertEq(revStream.claimable(JOE), amountRevenue);
        assertEq(revStream.expiredRevenueIncrement(1), amountRevenue);
        assertEq(revStream.expiredRevenue(), amountRevenue);

        assertEq(rwaToken.balanceOf(address(revStream)), amountRevenue);
        assertEq(rwaToken.balanceOf(address(revDistributor)), amountRevenue);

        // ~ expired is skimmed in 2nd increment~

        vm.prank(ADMIN);
        revStream.skimExpiredRevenueIncrement(1);

        // ~ Post-state check 2 ~

        assertEq(revStream.claimable(JOE), 0);
        assertEq(revStream.expiredRevenue(), 0);

        assertEq(rwaToken.balanceOf(address(revStream)), 0);
        assertEq(rwaToken.balanceOf(address(revDistributor)), amountRevenue*2);
    }

    function test_revStream_skimExpiredRevenue_multiple() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 amountRevenue = 5_000 ether;
        uint256 duration = (1 * 30 days);

        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            duration
        );
        vm.stopPrank();

        // mint RWA to revDistributor
        rwaToken.mintFor(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();

        skip(1);
        // mint RWA to revDistributor
        rwaToken.mintFor(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();

        skip(1);
        // mint RWA to revDistributor
        rwaToken.mintFor(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();
        
        // ~ Skip to avoid FutureLookup error ~

        skip(revStream.timeUntilExpired()-3);

        // ~ Pre-state check ~

        assertEq(revStream.claimable(JOE), amountRevenue * 3);
        assertEq(revStream.expiredRevenue(), 0);

        assertEq(rwaToken.balanceOf(address(revStream)), amountRevenue * 3);
        assertEq(rwaToken.balanceOf(address(revDistributor)), 0);

        // ~ Skip to expiration 1 ~

        skip(1); // first deposit is now expired

        // ~ Post-state check 1 ~

        assertEq(revStream.claimable(JOE), amountRevenue * 3);
        assertEq(revStream.expiredRevenue(), amountRevenue);

        assertEq(rwaToken.balanceOf(address(revStream)), amountRevenue * 3);
        assertEq(rwaToken.balanceOf(address(revDistributor)), 0);

        // ~ Skip to expiration 2 ~

        vm.prank(ADMIN);
        revStream.skimExpiredRevenue();

        skip(1); // second deposit + first is now expired

        // ~ Post-state check 2 ~

        assertEq(revStream.claimable(JOE), amountRevenue * 2);
        assertEq(revStream.expiredRevenue(), amountRevenue);

        assertEq(rwaToken.balanceOf(address(revStream)), amountRevenue * 2);
        assertEq(rwaToken.balanceOf(address(revDistributor)), amountRevenue);

        // ~ Skip to expiration 3 ~

        vm.prank(ADMIN);
        revStream.skimExpiredRevenue();

        skip(1); // third deposit + second + first is now expired

        // ~ Post-state check 3 ~

        assertEq(revStream.claimable(JOE), amountRevenue);
        assertEq(revStream.expiredRevenue(), amountRevenue);

        assertEq(rwaToken.balanceOf(address(revStream)), amountRevenue);
        assertEq(rwaToken.balanceOf(address(revDistributor)), amountRevenue * 2);

        // ~ Admin skims last bit of revenue ~

        vm.prank(ADMIN);
        revStream.skimExpiredRevenue();

        // ~ Post-state check 4 ~

        assertEq(revStream.claimable(JOE), 0);
        assertEq(revStream.expiredRevenue(), 0);

        assertEq(rwaToken.balanceOf(address(revStream)), 0);
        assertEq(rwaToken.balanceOf(address(revDistributor)), amountRevenue * 3);
    }

    function test_revStream_skimExpiredRevenue_multipleHolders() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 amountRevenue = 3_000 ether;
        uint256 duration = (1 * 30 days);

        rwaToken.mintFor(BOB, amount);
        rwaToken.mintFor(ALICE, amount);

        // mint Joe veRWA token
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            duration
        );
        vm.stopPrank();

        // mint Bob veRWA token
        vm.startPrank(BOB);
        rwaToken.approve(address(veRWA), amount);
        veRWA.mint(
            BOB,
            uint208(rwaToken.balanceOf(BOB)),
            duration
        );
        vm.stopPrank();

        // mint Alice veRWA token
        vm.startPrank(ALICE);
        rwaToken.approve(address(veRWA), amount);
        veRWA.mint(
            ALICE,
            uint208(rwaToken.balanceOf(ALICE)),
            duration
        );
        vm.stopPrank();

        // mint RWA to revDistributor
        rwaToken.mintFor(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();

        skip(1);

        // mint RWA to revDistributor
        rwaToken.mintFor(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();

        skip(1); // skip to avoid future lookup error

        // ~ Pre-state check ~

        assertEq(revStream.claimable(JOE), amountRevenue*2/3);
        assertEq(revStream.claimable(BOB), amountRevenue*2/3);
        assertEq(revStream.claimable(ALICE), amountRevenue*2/3);
        assertEq(revStream.expiredRevenue(), 0);

        // ~ Joe and Bob claim their revenue ~

        vm.prank(JOE);
        revStream.claim(JOE);

        vm.prank(BOB);
        revStream.claim(BOB);
        
        // ~ Skip to expiration ~

        skip(revStream.timeUntilExpired());

        // ~ Post-state check 1 ~

        uint256 unclaimed = amountRevenue*2/3;

        assertEq(revStream.claimable(JOE), 0);
        assertEq(revStream.claimable(BOB), 0);
        assertEq(revStream.claimable(ALICE), unclaimed);
        assertEq(revStream.expiredRevenue(), unclaimed);

        // ~ Another deposit ~

        // mint RWA to revDistributor
        rwaToken.mintFor(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.startPrank(address(revDistributor));
        rwaToken.approve(address(revStream), amountRevenue);
        revStream.deposit(amountRevenue);
        vm.stopPrank();

        skip(1); // skip to avoid future lookup error

        // ~ Post-state check 2 ~

        assertEq(revStream.claimable(JOE), amountRevenue/3);
        assertEq(revStream.claimable(BOB), amountRevenue/3);
        assertEq(revStream.claimable(ALICE), amountRevenue/3 + unclaimed);
        assertEq(revStream.expiredRevenue(), unclaimed);

        // ~ Expired revenue is skimmed ~

        vm.prank(ADMIN);
        revStream.skimExpiredRevenue();

        skip(1);

        // ~ Post-state check 3 ~

        assertEq(revStream.claimable(JOE), amountRevenue/3);
        assertEq(revStream.claimable(BOB), amountRevenue/3);
        assertEq(revStream.claimable(ALICE), amountRevenue/3);
        assertEq(revStream.expiredRevenue(), 0);

        // ~ All claim ~

        vm.prank(JOE);
        revStream.claim(JOE);

        vm.prank(BOB);
        revStream.claim(BOB);

        vm.prank(ALICE);
        revStream.claim(ALICE);
    }
}