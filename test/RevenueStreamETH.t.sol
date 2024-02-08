// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// foundry imports
import { Test, console2 } from "../lib/forge-std/src/Test.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Checkpoints } from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

// local imports
import { RevenueStream } from "../src/RevenueStream.sol";
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

    RevenueStream public revStreamBeacon;
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
                ADMIN,
                address(0),
                address(0)
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

        revStreamBeacon = new RevenueStream();

        // Deploy revDistributor contract
        revDistributor = new RevenueDistributor();

        // Deploy proxy for revDistributor
        revDistributorProxy = new ERC1967Proxy(
            address(revDistributor),
            abi.encodeWithSelector(RevenueDistributor.initialize.selector,
                ADMIN,
                address(revStreamBeacon),
                address(veRWA)
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
        vm.prank(ADMIN);
        vesting.setVotingEscrowContract(address(veRWA));

        // Grant minter role to address(this) & veRWA
        vm.startPrank(ADMIN);
        rwaToken.grantRole(MINTER_ROLE, address(this)); // for testing
        rwaToken.grantRole(MINTER_ROLE, address(veRWA)); // for RWAVotingEscrow:migrate
        rwaToken.grantRole(BURNER_ROLE, address(veRWA)); // for RWAVotingEscrow:migrate
        vm.stopPrank();

        vm.startPrank(ADMIN);
        rwaToken.excludeFromFees(address(veRWA), true);
        rwaToken.excludeFromFees(JOE, true);
        vm.stopPrank();

        // Mint Joe $RWA tokens
        rwaToken.mintFor(JOE, 1_000 ether);
    }


    // ------------------
    // Initial State Test
    // ------------------

    /// @dev Verifies initial state of RevenueStreamETH contract.
    function test_revStreamETH_init_state() public {
        assertEq(address(revStream.votingEscrow()), address(veRWA));
        assertEq(revStream.hasRole(0x00, ADMIN), true);
        assertEq(revStream.hasRole(DEPOSITOR_ROLE, address(revDistributor)), true);
        assertEq(revStream.getCyclesArray().length, 1);
    }


    // ----------
    // Unit Tests
    // ----------

    // ~ depositETH ~

    /// @dev Verifies proper state changes when RevenueStreamETH::depositETH() is executed.
    function test_revStreamETH_depositETH() public {
        
        // ~ Config ~

        uint256 amount = 1_000 ether;
        vm.deal(address(revDistributor), amount);

        // ~ Pre-state check ~

        assertEq(address(revStream).balance, 0);
        assertEq(address(revDistributor).balance, amount);

        uint256[] memory cycles = revStream.getCyclesArray();
        assertEq(cycles.length, 1);
        assertEq(cycles[0], block.timestamp);

        // ~ Execute Deposit ~

        vm.prank(address(revDistributor));
        revStream.depositETH{value: amount}();

        // ~ Post-state check ~

        assertEq(address(revStream).balance, amount);
        assertEq(address(revDistributor).balance, 0);

        assertEq(revStream.revenue(block.timestamp), amount);

        cycles = revStream.getCyclesArray();
        assertEq(cycles.length, 2);
        assertEq(cycles[0], block.timestamp);
        assertEq(cycles[1], block.timestamp);
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

        uint256 claimable = revStream.claimable(JOE);

        // ~ Verify ~

        assertEq(claimable, amountRevenue);
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

        uint256 claimableJoe = revStream.claimable(JOE);

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
        assertEq(revStream.lastClaim(JOE), 0);

        uint256 claimable = revStream.claimable(JOE);

        // ~ Execute claim ~

        vm.prank(JOE);
        revStream.claimETH(JOE);

        // ~ Post-state check 1 ~

        assertEq(claimable, amountRevenue * 2);
        assertEq(JOE.balance, amountRevenue * 2);
        assertEq(address(revStream).balance, 0);
        assertEq(revStream.lastClaim(JOE), block.timestamp - 1);

        assertEq(revStream.revenueClaimed(1), amountRevenue);
        assertEq(revStream.revenueClaimed(2), amountRevenue);

        // ~ Another deposit ~

        vm.prank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();

        // Skip to avoid FutureLookup error (when querying voting power)
        skip(1);

        claimable = revStream.claimable(JOE);

        // ~ Execute claim ~

        vm.prank(JOE);
        revStream.claimETH(JOE);

        // ~ Post-state check 2 ~

        assertEq(claimable, amountRevenue);
        assertEq(JOE.balance, amountRevenue * 3);
        assertEq(address(revStream).balance, 0);
        assertEq(revStream.lastClaim(JOE), block.timestamp - 1);

        assertEq(revStream.revenueClaimed(3), amountRevenue);
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
        assertEq(revStream.lastClaim(JOE), 0);

        assertEq(revStream.claimable(JOE), amountRevenue);

        // ~ Execute claim ~

        vm.prank(JOE);
        revStream.claimETH(JOE);

        // ~ Post-state check ~

        assertEq(JOE.balance, amountRevenue);
        assertEq(address(revStream).balance, 0);
        assertEq(revStream.lastClaim(JOE), block.timestamp - 1);

        assertEq(revStream.claimable(JOE), 0);
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
        address delegator = delegateFactory.deployDelegator(
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
        assertEq(revStream.lastClaim(ADMIN), 0);
        assertEq(revStream.lastClaim(JOE), 0);

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
        revStream.claimETH(JOE);

        // ~ Post-state check 1 ~

        assertEq(JOE.balance, amountRevenue);
        assertEq(address(revStream).balance, 0);
        assertEq(revStream.lastClaim(JOE), block.timestamp - 1);
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

        assertEq(revStream.claimable(JOE), amountRevenue);
        assertEq(revStream.expiredRevenue(), 0);

        // ~ Skip to expiration ~

        skip(revStream.timeUntilExpired());

        // ~ Post-state check ~

        assertEq(revStream.claimable(JOE), amountRevenue);
        assertEq(revStream.expiredRevenue(), amountRevenue);

        // ~ Joe claims ~

        vm.prank(JOE);
        revStream.claimETH(JOE);

        // ~ Post-state check 2 ~

        assertEq(revStream.claimable(JOE), 0);
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
        revStream.claimETH(JOE);

        // ~ Post-state check 4 ~

        assertEq(revStream.claimable(JOE), 0);
        assertEq(revStream.expiredRevenue(), 0);
    }

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

        assertEq(address(revStream).balance, amountRevenue);
        assertEq(address(revDistributor).balance, 0);

        // ~ expired is skimmed ~

        vm.prank(ADMIN);
        revStream.skimExpiredRevenue();

        // ~ Post-state check 2 ~

        assertEq(revStream.claimable(JOE), 0);
        assertEq(revStream.expiredRevenue(), 0);

        assertEq(address(revStream).balance, 0);
        assertEq(address(revDistributor).balance, amountRevenue);
    }

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

        assertEq(revStream.claimable(JOE), amountRevenue * 3);
        assertEq(revStream.expiredRevenue(), 0);

        assertEq(address(revStream).balance, amountRevenue * 3);
        assertEq(address(revDistributor).balance, 0);

        // ~ Skip to expiration 1 ~

        skip(1); // first deposit is now expired

        // ~ Post-state check 1 ~

        assertEq(revStream.claimable(JOE), amountRevenue * 3);
        assertEq(revStream.expiredRevenue(), amountRevenue);

        assertEq(address(revStream).balance, amountRevenue * 3);
        assertEq(address(revDistributor).balance, 0);

        // ~ Skip to expiration 2 ~

        vm.prank(ADMIN);
        revStream.skimExpiredRevenue();

        skip(1); // second deposit + first is now expired

        // ~ Post-state check 2 ~

        assertEq(revStream.claimable(JOE), amountRevenue * 2);
        assertEq(revStream.expiredRevenue(), amountRevenue);

        assertEq(address(revStream).balance, amountRevenue * 2);
        assertEq(address(revDistributor).balance, amountRevenue);

        // ~ Skip to expiration 3 ~

        vm.prank(ADMIN);
        revStream.skimExpiredRevenue();

        skip(1); // third deposit + second + first is now expired

        // ~ Post-state check 3 ~

        assertEq(revStream.claimable(JOE), amountRevenue);
        assertEq(revStream.expiredRevenue(), amountRevenue);

        assertEq(address(revStream).balance, amountRevenue);
        assertEq(address(revDistributor).balance, amountRevenue * 2);

        // ~ Admin skims last bit of revenue ~

        vm.prank(ADMIN);
        revStream.skimExpiredRevenue();

        // ~ Post-state check 4 ~

        assertEq(revStream.claimable(JOE), 0);
        assertEq(revStream.expiredRevenue(), 0);

        assertEq(address(revStream).balance, 0);
        assertEq(address(revDistributor).balance, amountRevenue * 3);
    }

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

        assertEq(revStream.claimable(JOE), amountRevenue*2/3);
        assertEq(revStream.claimable(BOB), amountRevenue*2/3);
        assertEq(revStream.claimable(ALICE), amountRevenue*2/3);
        assertEq(revStream.expiredRevenue(), 0);

        // ~ Joe and Bob claim their revenue ~

        vm.prank(JOE);
        revStream.claimETH(JOE);

        vm.prank(BOB);
        revStream.claimETH(BOB);
        
        // ~ Skip to expiration ~

        skip(revStream.timeUntilExpired());

        // ~ Post-state check 1 ~

        uint256 unclaimed = amountRevenue*2/3;

        assertEq(revStream.claimable(JOE), 0);
        assertEq(revStream.claimable(BOB), 0);
        assertEq(revStream.claimable(ALICE), unclaimed);
        assertEq(revStream.expiredRevenue(), unclaimed);

        // ~ Another deposit ~

        // deal ETH to revDistributor
        vm.deal(address(revDistributor), amountRevenue);
        // deposit revenue into RevStream contract
        vm.prank(address(revDistributor));
        revStream.depositETH{value: amountRevenue}();

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
        revStream.claimETH(JOE);

        vm.prank(BOB);
        revStream.claimETH(BOB);

        vm.prank(ALICE);
        revStream.claimETH(ALICE);
    }
}