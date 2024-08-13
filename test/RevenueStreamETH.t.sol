// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// foundry imports
import { Test, console2 } from "../lib/forge-std/src/Test.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Checkpoints } from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

// local imports
import { RevenueStreamETH } from "../src/RevenueStreamETH.sol";
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
 * @title RWARevenueStreamETHTest
 * @author @chasebrownn
 * @notice This test file contains the basic unit tests for the RevenueStreamETH contract.
 */
contract RWARevenueStreamETHTest is Utility {
    using VotingMath for uint256;

    // ~ Contracts ~

    RevenueStreamETH public revStream;
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
        revStream = new RevenueStreamETH();

        // Deploy proxy for revStream
        revStreamProxy = new ERC1967Proxy(
            address(revStream),
            abi.encodeWithSelector(RevenueStreamETH.initialize.selector,
                address(revDistributor),
                address(veRWA),
                ADMIN
            )
        );
        revStream = RevenueStreamETH(payable(address(revStreamProxy)));


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
        revDistributor.updateRevenueStream(payable(address(revStream)));

        // Grant minter role to address(this) & veRWA
        rwaToken.setVotingEscrowRWA(address(veRWA));
        rwaToken.setReceiver(address(this)); // for testing

        rwaToken.excludeFromFees(address(veRWA), true);
        rwaToken.excludeFromFees(JOE, true);
        vm.stopPrank();

        // Mint Joe $RWA tokens
        rwaToken.mintFor(JOE, 1_000 ether);
    }


    // -------
    // Utility
    // -------

    /// @dev Returns the amount claimable from the RevenueStreamETH contract, given an account.
    function _getClaimable(address account) internal view returns (uint256 claimable) {
        (claimable,,,,) = revStream.claimable(account);
    }

    /// @dev Returns the amount claimable from the RevenueStreamETH contract, given an account and a number of indexes.
    function _getClaimableIncrement(address account, uint256 numIndexes) internal view returns (uint256 claimable) {
        (claimable,,,,) = revStream.claimableIncrement(account, numIndexes);
    }


    // ------------------
    // Initial State Test
    // ------------------

    /// @dev Verifies initial state of RevenueStreamETH contract.
    function test_revStreamETH_init_state() public {
        assertEq(address(revStream.votingEscrow()), address(veRWA));
        assertEq(revStream.owner(), ADMIN);
        assertEq(revStream.revenueDistributor(), address(revDistributor));
        assertEq(revStream.getCyclesArray().length, 1);
    }


    // ----------
    // Unit Tests
    // ----------

    // ~ initialize ~

    /// @dev Verifies restrictions when initializing a new RevenueStreamETH contract
    function test_revStreamETH_initialize_restrictions() public {
        RevenueStreamETH newRevStream = new RevenueStreamETH();

        // distributor cannot be address(0)
        vm.expectRevert();
        new ERC1967Proxy(
            address(newRevStream),
            abi.encodeWithSelector(RevenueStreamETH.initialize.selector,
                address(0),
                address(veRWA),
                ADMIN
            )
        );

        // veRWA cannot be address(0)
        vm.expectRevert();
        new ERC1967Proxy(
            address(newRevStream),
            abi.encodeWithSelector(RevenueStreamETH.initialize.selector,
                address(revDistributor),
                address(0),
                ADMIN
            )
        );

        // admin cannot be address(0)
        vm.expectRevert();
        new ERC1967Proxy(
            address(newRevStream),
            abi.encodeWithSelector(RevenueStreamETH.initialize.selector,
                address(revDistributor),
                address(veRWA),
                address(0)
            )
        );
    }

    // ~ depositETH ~

    /// @dev Verifies proper state changes when RevenueStreamETH::depositETH() is executed.
    function test_revStreamETH_depositETH() public {
        
        // ~ Config ~

        uint256 amount = 1_000 ether;
        vm.deal(address(revDistributor), amount);

        // ~ Pre-state check ~

        assertEq(address(revStream).balance, 0);
        assertEq(revStream.getContractBalanceETH(), 0);
        assertEq(address(revDistributor).balance, amount);

        uint256[] memory cycles = revStream.getCyclesArray();
        assertEq(cycles.length, 1);
        assertEq(cycles[0], block.timestamp);

        // ~ Execute Deposit ~

        vm.prank(address(revDistributor));
        revStream.depositETH{value: amount}();

        // ~ Post-state check ~

        assertEq(address(revStream).balance, amount);
        assertEq(revStream.getContractBalanceETH(), amount);
        assertEq(address(revDistributor).balance, 0);

        assertEq(revStream.revenue(block.timestamp), amount);

        cycles = revStream.getCyclesArray();
        assertEq(cycles.length, 2);
        assertEq(cycles[0], block.timestamp);
        assertEq(cycles[1], block.timestamp);
    }

    /// @dev Verifies proper state changes when RevenueStreamETH::depositETH() is executed twice
    /// at the same time.
    function test_revStreamETH_depositETH_multiple() public {
        
        // ~ Config ~

        uint256 amount = 1_000 ether;
        vm.deal(address(revDistributor), amount);

        // ~ Execute Deposit 1 ~

        vm.prank(address(revDistributor));
        revStream.depositETH{value: amount/2}();

        // ~ Post-state check 1 ~

        assertEq(revStream.revenue(block.timestamp), amount/2);

        // ~ Execute Deposit 2 ~

        vm.prank(address(revDistributor));
        revStream.depositETH{value: amount/2}();

        // ~ Post-state check 2 ~

        assertEq(revStream.revenue(block.timestamp), amount);
    }

    /// @dev Verifies restrictions when RevenueStreamETH::depositETH is called with
    /// unacceptable conditions.
    function test_revStreamETH_depositETH_restrictions() public {
        vm.deal(JOE, 1);

        // amount cant be 0
        vm.prank(address(revDistributor));
        vm.expectRevert("RevenueStreamETH: msg.value == 0");
        revStream.depositETH{value: 0}();

        // only revenue distributor can call
        vm.prank(JOE);
        vm.expectRevert("RevenueStreamETH: Not authorized");
        revStream.depositETH{value: 1}();
    }

    // ~ claimable ~

    /// @dev Verifies proper return variable when RevenueStreamETH::claimable() is called.
    function test_revStreamETH_claimable_single() public {

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

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);

        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();
        
        // ~ Skip to avoid FutureLookup error ~

        skip(1);

        // ~ Call claimable ~

        uint256 claimable = _getClaimable(JOE);

        // ~ Verify ~

        assertEq(claimable, amountRevenue);
    }

    /// @dev Verifies proper return variable when RevenueStreamETH::claimableIncrement() is called.
    function test_revStreamETH_claimable_single_increment() public {

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

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue * 2);

        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();
        skip(1);
        vm.prank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();
        
        // ~ Skip to avoid FutureLookup error ~

        skip(1);

        // ~ Verify ~

        assertEq(_getClaimableIncrement(JOE, 1), amountRevenue);
        assertEq(_getClaimableIncrement(JOE, 2), amountRevenue*2);
        assertEq(_getClaimable(JOE), amountRevenue*2);
    }

    /// @dev Verifies proper return variable when RevenueStreamETH::claimable() is called.
    function test_revStreamETH_claimable_multiple() public {

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

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);

        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();
        

        // ~ Skip to avoid FutureLookup error ~

        skip(1);

        // ~ Call claimable ~

        uint256 claimableJoe = _getClaimable(JOE);

        // ~ Verify ~

        assertEq(claimableJoe, amountRevenue);
    }

    /// @dev Verifies proper state changes when RevenueStreamETH::claim() is executed.
    function test_revStreamETH_claim_single() public {
        
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

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue * 3);

        // deposit revenue into RevStream contract
        vm.startPrank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();
        skip(1);
        revStream.depositETH{value: amountRevenue}();
        vm.stopPrank();

        // Skip to avoid FutureLookup error (when querying voting power)
        skip(1);

        // ~ Pre-state check ~

        assertEq(JOE.balance, 0);
        assertEq(address(revStream).balance, amountRevenue * 2);
        assertEq(revStream.lastClaimIndex(JOE), 0);

        uint256 claimable = _getClaimable(JOE);

        // ~ Execute claim ~

        vm.prank(JOE);
        revStream.claimETH();

        // ~ Post-state check 1 ~

        assertEq(claimable, amountRevenue * 2);
        assertEq(JOE.balance, amountRevenue * 2);
        assertEq(address(revStream).balance, 0);
        assertEq(revStream.lastClaimIndex(JOE), 2);

        assertEq(revStream.revenueClaimed(1), amountRevenue);
        assertEq(revStream.revenueClaimed(2), amountRevenue);

        // ~ Another deposit ~

        vm.prank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();

        // Skip to avoid FutureLookup error (when querying voting power)
        skip(1);

        claimable = _getClaimable(JOE);

        // ~ Execute claim ~

        vm.prank(JOE);
        revStream.claimETH();

        // ~ Post-state check 2 ~

        assertEq(claimable, amountRevenue);
        assertEq(JOE.balance, amountRevenue * 3);
        assertEq(address(revStream).balance, 0);
        assertEq(revStream.lastClaimIndex(JOE), 3);

        assertEq(revStream.revenueClaimed(3), amountRevenue);
    }

    /// @dev Verifies proper state changes when RevenueStreamETH::claimETHIncrement() is executed.
    function test_revStreamETH_claim_single_increment() public {
        
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

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue * 3);

        // deposit revenue into RevStream contract
        vm.startPrank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();
        skip(1);
        revStream.depositETH{value: amountRevenue}();
        vm.stopPrank();

        // Skip to avoid FutureLookup error (when querying voting power)
        skip(1);

        // ~ Pre-state check ~

        assertEq(JOE.balance, 0);
        assertEq(address(revStream).balance, amountRevenue * 2);
        assertEq(revStream.lastClaimIndex(JOE), 0);

        assertEq(_getClaimableIncrement(JOE, 1), amountRevenue);
        assertEq(_getClaimableIncrement(JOE, 2), amountRevenue*2);
        assertEq(_getClaimable(JOE), amountRevenue*2);

        // ~ Execute claim increment 1 ~

        // restrictions check -> numIndexes cannot be 0
        vm.prank(JOE);
        vm.expectRevert("RevenueStreamETH: numIndexes cant be 0");
        revStream.claimETHIncrement(0);

        vm.prank(JOE);
        revStream.claimETHIncrement(1);

        // ~ Post-state check 1 ~

        assertEq(JOE.balance, amountRevenue);
        assertEq(address(revStream).balance, amountRevenue);
        assertEq(revStream.lastClaimIndex(JOE), 1);

        assertEq(revStream.revenueClaimed(1), amountRevenue);
        assertEq(revStream.revenueClaimed(2), 0);

        assertEq(_getClaimableIncrement(JOE, 1), amountRevenue);
        assertEq(_getClaimable(JOE), amountRevenue);

        // ~ Execute claim increment 2 ~

        vm.prank(JOE);
        revStream.claimETHIncrement(2);

        // ~ Post-state check 2 ~

        assertEq(JOE.balance, amountRevenue * 2);
        assertEq(address(revStream).balance, 0);
        assertEq(revStream.lastClaimIndex(JOE), 2);

        assertEq(revStream.revenueClaimed(1), amountRevenue);
        assertEq(revStream.revenueClaimed(2), amountRevenue);

        // ~ Another deposit ~

        vm.prank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();

        // Skip to avoid FutureLookup error (when querying voting power)
        skip(1);

        assertEq(_getClaimableIncrement(JOE, 1), amountRevenue);
        assertEq(_getClaimable(JOE), amountRevenue);

        // ~ Execute claim ~

        vm.prank(JOE);
        revStream.claimETHIncrement(1);

        // ~ Post-state check 3 ~

        assertEq(JOE.balance, amountRevenue * 3);
        assertEq(address(revStream).balance, 0);
        assertEq(revStream.lastClaimIndex(JOE), 3);

        assertEq(revStream.revenueClaimed(3), amountRevenue);

        assertEq(_getClaimableIncrement(JOE, 1), 0);
        assertEq(_getClaimable(JOE), 0);
    }

    /// @dev Verifies proper state changes when RevenueStreamETH::claim() is executed.
    function test_revStreamETH_claim_multiple() public {

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

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);

        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();

        // ~ Skip to avoid FutureLookup error ~

        skip(1);

        // ~ Pre-state check ~

        assertEq(JOE.balance, 0);
        assertEq(address(revStream).balance, amountRevenue);
        assertEq(revStream.lastClaimIndex(JOE), 0);

        assertEq(_getClaimable(JOE), amountRevenue);

        // ~ Execute claim ~

        vm.prank(JOE);
        revStream.claimETH();

        // ~ Post-state check ~

        assertEq(JOE.balance, amountRevenue);
        assertEq(address(revStream).balance, 0);
        assertEq(revStream.lastClaimIndex(JOE), 1);

        assertEq(_getClaimable(JOE), 0);
    }

    /// @dev Verifies delegatees can claim rent. 
    function test_revStreamETH_claim_delegate() public {
        
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
        address newDelegator = delegateFactory.deployDelegator(
            tokenId,
            JOE,
            (30 days)
        );
        vm.stopPrank();

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);

        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();

        // Skip to avoid FutureLookup error (when querying voting power)
        skip(1);

        // ~ Pre-state check ~

        assertEq(ADMIN.balance, 0);
        assertEq(JOE.balance, 0);
        assertEq(address(revStream).balance, amountRevenue);
        assertEq(revStream.lastClaimIndex(ADMIN), 0);
        assertEq(revStream.lastClaimIndex(JOE), 0);

        assertEq(_getClaimable(JOE), amountRevenue);

        assertEq(veRWA.ownerOf(tokenId), address(newDelegator));
        assertEq(veRWA.getAccountVotingPower(ADMIN), 0);
        assertGt(veRWA.getAccountVotingPower(address(newDelegator)), 0);
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        assertEq(veRWA.getVotes(ADMIN), 0);
        assertEq(veRWA.getVotes(address(newDelegator)), 0);
        assertGt(veRWA.getVotes(JOE), 0);

        assertEq(veRWA.delegates(ADMIN), ADMIN);
        assertEq(veRWA.delegates(address(newDelegator)), JOE);

        // ~ Execute claim ~

        vm.prank(JOE);
        revStream.claimETH();

        // ~ Post-state check 1 ~

        assertEq(JOE.balance, amountRevenue);
        assertEq(address(revStream).balance, 0);
        assertEq(revStream.lastClaimIndex(JOE), 1);
    }


    // ~ expired revenue ~

    /// @dev Verifies proper return variable when RevenueStreamETH::expiredRevenue() is called.
    function test_revStreamETH_expiredRevenue_single() public {

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

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);

        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();
        
        // ~ Skip to avoid FutureLookup error ~

        skip(1);

        // ~ Pre-state check ~

        assertEq(_getClaimable(JOE), amountRevenue);
        assertEq(revStream.expiredRevenue(), 0);

        // ~ Skip to expiration ~

        skip(revStream.timeUntilExpired());

        // ~ Post-state check ~

        assertEq(_getClaimable(JOE), amountRevenue);
        assertEq(revStream.expiredRevenue(), amountRevenue);

        // ~ Joe claims ~

        vm.prank(JOE);
        revStream.claimETH();

        // ~ Post-state check 2 ~

        assertEq(_getClaimable(JOE), 0);
        assertEq(revStream.expiredRevenue(), 0);
    }

    /// @dev Verifies proper return variable when RevenueStreamETH::expiredRevenueIncrement() is called.
    function test_revStreamETH_expiredRevenue_single_increment() public {

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

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue*2);

        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();
        skip(1);
        vm.prank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();
        
        // ~ Skip to avoid FutureLookup error ~

        skip(1);

        // ~ Pre-state check ~

        assertEq(_getClaimable(JOE), amountRevenue*2);
        assertEq(revStream.expiredRevenue(), 0);

        // ~ Skip to expiration ~

        skip(revStream.timeUntilExpired()+1);

        // ~ Post-state check 1 ~

        assertEq(_getClaimable(JOE), amountRevenue*2);
        assertEq(revStream.expiredRevenueIncrement(1), amountRevenue);
        assertEq(revStream.expiredRevenueIncrement(2), amountRevenue*2);
        assertEq(revStream.expiredRevenue(), amountRevenue*2);

        // ~ Joe claims in increment 1/2 ~

        vm.prank(JOE);
        revStream.claimETHIncrement(1);

        // ~ Post-state check 2 ~

        assertEq(_getClaimable(JOE), amountRevenue);
        assertEq(revStream.expiredRevenueIncrement(1), 0);
        assertEq(revStream.expiredRevenueIncrement(2), amountRevenue);
        assertEq(revStream.expiredRevenue(), amountRevenue);

        // ~ Joe claims in increment 2/2 ~

        vm.prank(JOE);
        revStream.claimETHIncrement(1);

        // ~ Post-state check 3 ~

        assertEq(_getClaimable(JOE), 0);
        assertEq(revStream.expiredRevenueIncrement(1), 0);
        assertEq(revStream.expiredRevenue(), 0);
    }

    /// @dev Verifies proper return variable when RevenueStreamETH::expiredRevenue() is called.
    function test_revStreamETH_expiredRevenue_multiple() public {

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

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();

        skip(1);
        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();

        skip(1);
        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();
        
        // ~ Skip to avoid FutureLookup error ~

        skip(revStream.timeUntilExpired()-3);

        // ~ Pre-state check ~

        assertEq(_getClaimable(JOE), amountRevenue * 3);
        assertEq(revStream.expiredRevenue(), 0);

        // ~ Skip to expiration 1 ~

        skip(1); // first deposit is now expired

        // ~ Post-state check 1 ~

        assertEq(_getClaimable(JOE), amountRevenue * 3);
        assertEq(revStream.expiredRevenue(), amountRevenue);

        // ~ Skip to expiration 2 ~

        skip(1); // second deposit + first is now expired

        // ~ Post-state check 2 ~

        assertEq(_getClaimable(JOE), amountRevenue * 3);
        assertEq(revStream.expiredRevenue(), amountRevenue * 2);

        // ~ Skip to expiration 3 ~

        skip(1); // third deposit + second + first is now expired

        // ~ Post-state check 3 ~

        assertEq(_getClaimable(JOE), amountRevenue * 3);
        assertEq(revStream.expiredRevenue(), amountRevenue * 3);

        // ~ Joe claims ~

        vm.prank(JOE);
        revStream.claimETH();

        // ~ Post-state check 4 ~

        assertEq(_getClaimable(JOE), 0);
        assertEq(revStream.expiredRevenue(), 0);
    }

    /// @dev Verifies proper state changes when RevenueStreamETH::skimExpiredRevenue() is called.
    function test_revStreamETH_skimExpiredRevenue_single() public {

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

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);

        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();
        
        // ~ Skip to avoid FutureLookup error ~

        skip(1);

        // ~ Pre-state check ~

        assertEq(_getClaimable(JOE), amountRevenue);
        assertEq(revStream.expiredRevenue(), 0);

        // ~ Attempt to skim -> Revert ~

        vm.prank(ADMIN);
        vm.expectRevert("No expired revenue claimable");
        revStream.skimExpiredRevenue();

        // ~ Skip to expiration ~

        skip(revStream.timeUntilExpired());

        // ~ Post-state check ~

        assertEq(_getClaimable(JOE), amountRevenue);
        assertEq(revStream.expiredRevenue(), amountRevenue);

        assertEq(address(revStream).balance, amountRevenue);
        assertEq(address(revDistributor).balance, 0);

        // ~ expired is skimmed ~

        vm.prank(ADMIN);
        revStream.skimExpiredRevenue();

        // ~ Post-state check 2 ~

        assertEq(_getClaimable(JOE), 0);
        assertEq(revStream.expiredRevenue(), 0);

        assertEq(address(revStream).balance, 0);
        assertEq(address(revDistributor).balance, amountRevenue);
    }

    /// @dev Verifies proper state changes when RevenueStreamETH::skimExpiredRevenue() is called.
    function test_revStreamETH_skimExpiredRevenue_single_increment() public {

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

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue*2);

        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();
        skip(1);
        vm.prank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();
        
        // ~ Skip to avoid FutureLookup error ~

        skip(1);

        // ~ Pre-state check ~

        assertEq(_getClaimable(JOE), amountRevenue*2);
        assertEq(revStream.expiredRevenue(), 0);

        // ~ Attempt to skim -> Revert ~

        vm.prank(ADMIN);
        vm.expectRevert("No expired revenue claimable");
        revStream.skimExpiredRevenue();

        // ~ Skip to expiration ~

        skip(revStream.timeUntilExpired()+1);

        // ~ Pre-state check ~

        assertEq(_getClaimable(JOE), amountRevenue*2);
        assertEq(revStream.expiredRevenueIncrement(1), amountRevenue);
        assertEq(revStream.expiredRevenueIncrement(2), amountRevenue*2);
        assertEq(revStream.expiredRevenue(), amountRevenue*2);

        assertEq(address(revStream).balance, amountRevenue*2);
        assertEq(address(revDistributor).balance, 0);

        // ~ expired is skimmed in 1st increment~

        vm.prank(ADMIN);
        revStream.skimExpiredRevenueIncrement(1);

        // ~ Post-state check 1 ~

        assertEq(_getClaimable(JOE), amountRevenue);
        assertEq(revStream.expiredRevenueIncrement(1), amountRevenue);
        assertEq(revStream.expiredRevenue(), amountRevenue);

        assertEq(address(revStream).balance, amountRevenue);
        assertEq(address(revDistributor).balance, amountRevenue);

        // ~ expired is skimmed in 2nd increment~

        vm.prank(ADMIN);
        revStream.skimExpiredRevenueIncrement(1);

        // ~ Post-state check 2 ~

        assertEq(_getClaimable(JOE), 0);
        assertEq(revStream.expiredRevenue(), 0);

        assertEq(address(revStream).balance, 0);
        assertEq(address(revDistributor).balance, amountRevenue*2);
    }

    /// @dev Verifies proper state changes when RevenueStreamETH::skimExpiredRevenue() is called
    /// with multiple deposit cycles.
    function test_revStreamETH_skimExpiredRevenue_multiple() public {

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

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();

        skip(1);
        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();

        skip(1);
        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();
        
        // ~ Skip to avoid FutureLookup error ~

        skip(revStream.timeUntilExpired()-3);

        // ~ Pre-state check ~

        assertEq(_getClaimable(JOE), amountRevenue * 3);
        assertEq(revStream.expiredRevenue(), 0);

        assertEq(address(revStream).balance, amountRevenue * 3);
        assertEq(address(revDistributor).balance, 0);

        // ~ Skip to expiration 1 ~

        skip(1); // first deposit is now expired

        // ~ Post-state check 1 ~

        assertEq(_getClaimable(JOE), amountRevenue * 3);
        assertEq(revStream.expiredRevenue(), amountRevenue);

        assertEq(address(revStream).balance, amountRevenue * 3);
        assertEq(address(revDistributor).balance, 0);

        // ~ Skip to expiration 2 ~

        vm.prank(ADMIN);
        revStream.skimExpiredRevenue();

        skip(1); // second deposit + first is now expired

        // ~ Post-state check 2 ~

        assertEq(_getClaimable(JOE), amountRevenue * 2);
        assertEq(revStream.expiredRevenue(), amountRevenue);

        assertEq(address(revStream).balance, amountRevenue * 2);
        assertEq(address(revDistributor).balance, amountRevenue);

        // ~ Skip to expiration 3 ~

        vm.prank(ADMIN);
        revStream.skimExpiredRevenue();

        skip(1); // third deposit + second + first is now expired

        // ~ Post-state check 3 ~

        assertEq(_getClaimable(JOE), amountRevenue);
        assertEq(revStream.expiredRevenue(), amountRevenue);

        assertEq(address(revStream).balance, amountRevenue);
        assertEq(address(revDistributor).balance, amountRevenue * 2);

        // ~ Admin skims last bit of revenue ~

        vm.prank(ADMIN);
        revStream.skimExpiredRevenue();

        // ~ Post-state check 4 ~

        assertEq(_getClaimable(JOE), 0);
        assertEq(revStream.expiredRevenue(), 0);

        assertEq(address(revStream).balance, 0);
        assertEq(address(revDistributor).balance, amountRevenue * 3);
    }

    /// @dev Verifies proper state changes when RevenueStreamETH::skimExpiredRevenue() is called
    /// with multiple holders.
    function test_revStreamETH_skimExpiredRevenue_multipleHolders() public {

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

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();

        skip(1);

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();

        skip(1); // skip to avoid future lookup error

        // ~ Pre-state check ~

        assertEq(_getClaimable(JOE), amountRevenue*2/3);
        assertEq(_getClaimable(BOB), amountRevenue*2/3);
        assertEq(_getClaimable(ALICE), amountRevenue*2/3);
        assertEq(revStream.expiredRevenue(), 0);

        // ~ Joe and Bob claim their revenue ~

        vm.prank(JOE);
        revStream.claimETH();

        vm.prank(BOB);
        revStream.claimETH();
        
        // ~ Skip to expiration ~

        skip(revStream.timeUntilExpired());

        // ~ Post-state check 1 ~

        uint256 unclaimed = amountRevenue*2/3;

        assertEq(_getClaimable(JOE), 0);
        assertEq(_getClaimable(BOB), 0);
        assertEq(_getClaimable(ALICE), unclaimed);
        assertEq(revStream.expiredRevenue(), unclaimed);

        // ~ Another deposit ~

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();

        skip(1); // skip to avoid future lookup error

        // ~ Post-state check 2 ~

        assertEq(_getClaimable(JOE), amountRevenue/3);
        assertEq(_getClaimable(BOB), amountRevenue/3);
        assertEq(_getClaimable(ALICE), amountRevenue/3 + unclaimed);
        assertEq(revStream.expiredRevenue(), unclaimed);

        // ~ Expired revenue is skimmed ~

        vm.prank(ADMIN);
        revStream.skimExpiredRevenue();

        skip(1);

        // ~ Post-state check 3 ~

        assertEq(_getClaimable(JOE), amountRevenue/3);
        assertEq(_getClaimable(BOB), amountRevenue/3);
        assertEq(_getClaimable(ALICE), amountRevenue/3);
        assertEq(revStream.expiredRevenue(), 0);

        // ~ All claim ~

        vm.prank(JOE);
        revStream.claimETH();

        vm.prank(BOB);
        revStream.claimETH();

        vm.prank(ALICE);
        revStream.claimETH();
    }

    /// @dev Verifies proper state changes when RevenueStream::setExpirationForRevenue() is executed.
    function test_revStream_setExpirationForRevenue() public {

        // ~ Pre-state check ~

        assertEq(revStream.timeUntilExpired(), 6 * (30 days));

        // ~ Execute setExpirationForRevenue ~

        vm.prank(ADMIN);
        revStream.setExpirationForRevenue(1 days);

        // ~ Post-state check ~

        assertEq(revStream.timeUntilExpired(), 1 days);
    }
}