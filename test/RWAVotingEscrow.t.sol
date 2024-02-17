// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// foundry imports
import { Test, console2 } from "../lib/forge-std/src/Test.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Checkpoints } from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

// local imports
import { RWAVotingEscrow } from "../src/governance/RWAVotingEscrow.sol";
import { VotingEscrowVesting } from "../src/governance/VotingEscrowVesting.sol";
import { RWAToken } from "../src/RWAToken.sol";

import { VotingEscrowRWAAPI } from "../src/helpers/VotingEscrowRWAAPI.sol";

// local helper imports
import { Utility } from "./utils/Utility.sol";
import { VotingMath } from "../src/governance/VotingMath.sol";
import "./utils/Constants.sol";

/**
 * @title RWAVotingEscrowTest
 * @author @chasebrownn
 * @notice This test file contains the basic unit testing for the RWAVotingEscrow contract.
 */
contract RWAVotingEscrowTest is Utility {
    using VotingMath for uint256;

    // ~ Contracts ~

    RWAVotingEscrow public veRWA;
    VotingEscrowVesting public vesting;
    RWAToken public rwaToken;
    VotingEscrowRWAAPI public api;

    // proxies
    ERC1967Proxy public veRWAProxy;
    ERC1967Proxy public vestingProxy;
    ERC1967Proxy public rwaTokenProxy;
    ERC1967Proxy public apiProxy;

    function setUp() public {

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
                LAYER_Z, // Note: Layer Zero Endpoint -> For migration
                ADMIN
            )
        );
        veRWA = RWAVotingEscrow(address(veRWAProxy));

        // Deploy API
        api = new VotingEscrowRWAAPI();

        // Deploy api proxy
        apiProxy = new ERC1967Proxy(
            address(api),
            abi.encodeWithSelector(VotingEscrowRWAAPI.initialize.selector,
                ADMIN,
                address(veRWA),
                address(vesting),
                address(0)
            )
        );
        api = VotingEscrowRWAAPI(address(apiProxy));

        // set votingEscrow on vesting contract
        vm.prank(ADMIN);
        vesting.setVotingEscrowContract(address(veRWA));

        // Grant minter role to address(this) & veRWA
        vm.startPrank(ADMIN);
        rwaToken.setVotingEscrowRWA(address(veRWA));
        vm.stopPrank();

        // Exclude necessary addresses from RWA fees.
        vm.startPrank(ADMIN);
        rwaToken.excludeFromFees(address(veRWA), true);
        rwaToken.excludeFromFees(JOE, true);
        rwaToken.excludeFromFees(ALICE, true);
        vm.stopPrank();

        // Mint Joe $RWA tokens
        deal(address(rwaToken), JOE, 1_000 ether);
    }


    // ------------------
    // Initial State Test
    // ------------------

    /// @notice Initial state test.
    function test_votingEscrow_init_state() public {
        // veRWA
        assertEq(veRWA.name(), "RWA Voting Escrow");
        assertEq(veRWA.symbol(), "veRWA");
        assertEq(veRWA.owner(), ADMIN);
        assertEq(address(veRWA.getLockedToken()), address(rwaToken));
        assertEq(veRWA.vestingContract(), address(vesting));
        assertEq(veRWA.getTokenId(), 0);

        // rwaToken
        assertEq(rwaToken.name(), "re.al");
        assertEq(rwaToken.symbol(), "RWA");
        assertEq(rwaToken.owner(), ADMIN);
        assertEq(rwaToken.balanceOf(JOE), 1_000 ether);
        assertEq(rwaToken.totalSupply(), 1_000 ether);

        emit log_named_uint("max duration", veRWA.MAX_VESTING_DURATION());
    }


    // -------
    // Utility
    // -------

    /// @notice Helper method for calculate early-burn fees.
    function _calculateFee(uint256 duration) internal view returns (uint16 fee) {
        fee = uint16((veRWA.getMaxEarlyUnlockFee() * duration) / veRWA.MAX_VESTING_DURATION());
    }

    /// @notice Helper method for calculate early-burn penalties post fee.
    function _calculatePenalty(uint256 amount, uint256 duration) internal view returns (uint256 penalty) {
        penalty = (amount * _calculateFee(duration) / 100_00);
    }


    // ----------
    // Unit Tests
    // ----------

    // ~ RWAVotingEscrow::mint ~

    /**
     * @notice This unit test verifies proper state changes when RWAVotingEscrow::mint() is called.
     * @dev State changes:
     *    - contract takes locked tokens ✅
     *    - creates a new lock instance ✅
     *    - user is minted an NFT representing position ✅
     */
    function test_votingEscrow_mint() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 tokenId = veRWA.getTokenId();
        tokenId++;

        uint256 totalDuration = (1 * 30 days); // lock for one month

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        // ~ Pre-state check ~

        assertEq(tokenId, veRWA.getTokenId() + 1);
        assertEq(rwaToken.balanceOf(JOE), amount);
        assertEq(rwaToken.balanceOf(address(veRWA)), 0);

        assertEq(veRWA.getLockedAmount(tokenId), 0);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 0);
        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 0);
        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        // ~ Joe executes mint ~

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            totalDuration
        );

        // ~ Post-state check ~

        uint256 votingPower = amount.calculateVotingPower(totalDuration);
        emit log_named_uint("1mo MAX Voting Power", votingPower);

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount);
        
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, votingPower);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, votingPower);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), totalDuration);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), votingPower);
        assertEq(veRWA.getVotes(JOE), votingPower);
    }

    /**
     * @notice This unit test verifies proper state changes when RWAVotingEscrow::mint() is called with max duration.
     * @dev State changes:
     *    - voting power is 1-to-1 with amount tokens locked ✅
     */
    function test_votingEscrow_mint_max() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 tokenId = veRWA.getTokenId();
        tokenId++;

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        // ~ Pre-state check ~

        assertEq(tokenId, veRWA.getTokenId() + 1);
        assertEq(rwaToken.balanceOf(JOE), amount);
        assertEq(rwaToken.balanceOf(address(veRWA)), 0);

        assertEq(veRWA.getLockedAmount(tokenId), 0);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 0);
        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 0);
        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        // ~ Joe executes mint ~

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            36 * 30 days // max lock time
        );

        // ~ Post-state check ~

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount);
        
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, amount);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, amount);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 36 * 30 days);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), amount);
        assertEq(veRWA.getVotes(JOE), amount);
    }

    /**
     * @notice This unit test verifies proper state changes when there are consecutive mints.
     * @dev State Changes:
     *    - getTotalVotingPowerCheckpoints will contain 1 large checkpoint ✅
     */
    function test_votingEscrow_mint_multiple() public {

        // ~ Config ~

        uint256 amount1 = 600 ether;
        uint256 amount2 = 400 ether;
        uint256 tokenId = veRWA.getTokenId();

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        // ~ Pre-state check ~

        assertEq(rwaToken.balanceOf(JOE), amount1 + amount2);
        assertEq(rwaToken.balanceOf(address(veRWA)), 0);

        assertEq(veRWA.getLockedAmount(tokenId), 0);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 0);
        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 0);
        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        // ~ Joe executes mint ~

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount1);
        veRWA.mint(
            JOE,
            uint208(amount1),
            36 * 30 days // max lock time
        );
        vm.stopPrank();

        // ~ Post-state check 1 ~

        tokenId++;

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(rwaToken.balanceOf(JOE), amount2);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount1);
        
        assertEq(veRWA.getLockedAmount(tokenId), amount1);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, amount1);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, amount1);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 36 * 30 days);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), amount1);
        assertEq(veRWA.getVotes(JOE), amount1);

        // ~ Joe executes mint (again) ~

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount2);
        veRWA.mint(
            JOE,
            uint208(amount2),
            36 * 30 days // max lock time
        );
        vm.stopPrank();

        // ~ Post-state check 2 ~

        tokenId++;

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount1 + amount2);
        
        assertEq(veRWA.getLockedAmount(tokenId), amount2);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, amount2);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, amount1 + amount2); // 1_000

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 36 * 30 days);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), amount1 + amount2); // 1_000
        assertEq(veRWA.getVotes(JOE), amount1 + amount2);
    }

    /**
     * @notice This unit test verifies proper state changes when there are consecutive mints after
     *         time has past. This should create another element in `_totalVotingPowerCheckpoints`.
     * @dev State Changes:
     *    - getTotalVotingPowerCheckpoints will contain 2 checkpoints instead of 1 ✅
     */
    function test_votingEscrow_mint_multiple_skip() public {

        // ~ Config ~

        uint256 amount1 = 600 ether;
        uint256 amount2 = 400 ether;
        uint256 tokenId = veRWA.getTokenId();

        uint256 timestamp = block.timestamp;

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        // ~ Pre-state check ~

        assertEq(rwaToken.balanceOf(JOE), amount1 + amount2);
        assertEq(rwaToken.balanceOf(address(veRWA)), 0);

        assertEq(veRWA.getLockedAmount(tokenId), 0);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 0);
        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 0);
        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        // ~ Joe executes mint ~

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount1);
        veRWA.mint(
            JOE,
            uint208(amount1),
            36 * 30 days // max lock time
        );
        vm.stopPrank();

        // ~ Post-state check 1 ~

        tokenId++;

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(rwaToken.balanceOf(JOE), amount2);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount1);
        
        assertEq(veRWA.getLockedAmount(tokenId), amount1);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, amount1);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, amount1);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 36 * 30 days);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), amount1);
        assertEq(veRWA.getVotes(JOE), amount1);

        // ~ Joe executes mint (again) ~

        skip(10);

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount2);
        veRWA.mint(
            JOE,
            uint208(amount2),
            36 * 30 days // max lock time
        );
        vm.stopPrank();

        // ~ Post-state check 2 ~

        tokenId++;

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount1 + amount2);
        
        assertEq(veRWA.getLockedAmount(tokenId), amount2);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, timestamp + 10);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, amount2);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, amount1); // 600
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, timestamp + 10);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, amount1 + amount2); // 1_000

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 36 * 30 days);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), amount1 + amount2); // 1_000
        assertEq(veRWA.getVotes(JOE), amount1 + amount2);
    }

    // ~ VotingEscrowVesting::deposit ~

    /**
     * @notice This unit test verifies proper state changes when VotingEscrowVesting::deposit() is called.
     * @dev State changes:
     *    - contract takes VE NFT ✅
     *    - VE lock instance (on veRWA) is updated ✅
     *    - vesting contract is updated appropriately ✅
     */
    function test_votingEscrow_deposit() public {

        // ~ Config ~

        uint256 amountTokens = 1_000 ether;
        uint256 tokenId = veRWA.getTokenId();
        tokenId++;

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amountTokens);
        veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            36 * 30 days // max lock time
        );

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        uint256 start;
        uint256 end;
        uint256 amount;

        uint256[] memory depositedTokens;

        // ~ Pre-state check ~

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(veRWA.getLockedAmount(tokenId), amountTokens);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, amountTokens);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, amountTokens);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 36 * 30 days);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), amountTokens);
        assertEq(veRWA.getVotes(JOE), amountTokens);

        // check vesting schedule data
        (start, end, amount) = vesting.vestingSchedules(tokenId);
        assertEq(start, 0);
        assertEq(end, 0);
        assertEq(amount, 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 0);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), address(0));

        // ~ Joe executes deposit ~

        vm.startPrank(JOE);
        veRWA.approve(address(vesting), tokenId);
        vesting.deposit(tokenId);
        vm.stopPrank();

        // ~ Post-state check ~

        assertEq(veRWA.ownerOf(tokenId), address(vesting));
        assertEq(veRWA.getLockedAmount(tokenId), amountTokens);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check vesting schedule data
        (start, end, amount) = vesting.vestingSchedules(tokenId);
        assertEq(start, block.timestamp);
        assertEq(end, block.timestamp + (36 * 30 days));
        assertEq(amount, amountTokens);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 1);
        assertEq(depositedTokens[0], tokenId);

        assertEq(vesting.depositedTokensIndex(tokenId), 0);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), JOE);

        (,VotingEscrowVesting.VestingSchedule[] memory schedule) = api.getVestedTokensByOwnerWithData(JOE);
        assertEq(schedule[0].startTime, block.timestamp);
        assertEq(schedule[0].endTime, block.timestamp + (36 * 30 days));
        assertEq(schedule[0].amount, amountTokens);
    }

    // ~ VotingEscrowVesting::withdraw ~

    /**
     * @notice This unit test verifies proper state changes when VotingEscrowVesting::withdraw() is called.
     * @dev State changes:
     *    - contract sends user VE NFT ✅
     *    - calculates a remainting time and updates veRWA ✅
     *    - vesting contract is updated appropriately ✅
     */
    function test_votingEscrow_withdraw() public {

        // ~ Config ~

        uint256 amountTokens = 1_000 ether;
        uint256 tokenId = veRWA.getTokenId();
        tokenId++;

        uint256 totalDuration = (2 * 30 days);
        uint256 skipTo = (1 * 30 days);

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amountTokens);
        veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            totalDuration // 2 month lock time
        );

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        uint256 startTime;
        uint256 endTime;
        uint256 amount;

        uint256[] memory depositedTokens;

        vm.startPrank(JOE);
        veRWA.approve(address(vesting), tokenId);
        vesting.deposit(tokenId);
        vm.stopPrank();

        // ~ Sanity check ~

        assertEq(veRWA.ownerOf(tokenId), address(vesting));
        assertEq(veRWA.getLockedAmount(tokenId), amountTokens);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check vesting schedule data
        (startTime, endTime, amount) = vesting.vestingSchedules(tokenId);
        assertEq(startTime, block.timestamp);
        assertEq(endTime, block.timestamp + totalDuration);
        assertEq(amount, amountTokens);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 1);
        assertEq(depositedTokens[0], tokenId);

        assertEq(vesting.depositedTokensIndex(tokenId), 0);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), JOE);

        // ~ Skip ~

        skip(skipTo);

        // ~ Pre-state check ~

        assertEq(veRWA.ownerOf(tokenId), address(vesting));
        assertEq(veRWA.getLockedAmount(tokenId), amountTokens);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - skipTo);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - skipTo);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);

        // check vesting schedule data
        (startTime, endTime, amount) = vesting.vestingSchedules(tokenId);
        assertEq(startTime, block.timestamp - skipTo);
        assertEq(endTime, block.timestamp + skipTo);
        assertEq(amount, amountTokens);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 1);
        assertEq(depositedTokens[0], tokenId);

        assertEq(vesting.depositedTokensIndex(tokenId), 0);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), JOE);

        // ~ withdraw ~

        vm.prank(JOE);
        vesting.withdraw(JOE, tokenId);

        uint256 votingPower = amount.calculateVotingPower(totalDuration - skipTo);
        emit log_named_uint("MAX VOTING POWER", amount.calculateVotingPower(totalDuration));
        emit log_named_uint("WITHDRAW VOTING POWER", votingPower);

        // ~ Post-state check ~

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(veRWA.getLockedAmount(tokenId), amountTokens);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - skipTo);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, 0);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, votingPower);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - skipTo);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, 0);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, votingPower);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), totalDuration - skipTo);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), votingPower);
        assertEq(veRWA.getVotes(JOE), votingPower);

        // check vesting schedule data
        (startTime, endTime, amount) = vesting.vestingSchedules(tokenId);
        assertEq(startTime, 0);
        assertEq(endTime, 0);
        assertEq(amount, 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 0);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), address(0));
    }

    /**
     * @notice This unit test verifies proper state changes when RWAVotingEscrow::burn() is called.
     * @dev State changes:
     *    - a token that is deposited for the entire promised duration can withdraw and burn ✅
     *    - proper state changes for vesting and veRWA ✅
     *    - NFT no longer exists once burn() is executed ✅
     *    - actor (Joe) receives 100% of locked tokens ✅
     */
    function test_votingEscrow_withdrawThenBurn() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 duration = 36 * 30 days;

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        uint256 tokenId = veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            duration
        );

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        uint256[] memory depositedTokens;

        uint256 maxVotingPower = amount.calculateVotingPower(duration);

        // ~ Sanity check ~

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount);
        
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), duration);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), amount);
        assertEq(veRWA.getVotes(JOE), amount);
        
        // ~ Skip to create new checkpoint ~

        vm.warp(block.timestamp + 1);

        // ~ Deposit ~

        vm.startPrank(JOE);
        veRWA.approve(address(vesting), tokenId);
        vesting.deposit(tokenId);
        vm.stopPrank();

        // ~ Pre-state check ~

        assertEq(veRWA.ownerOf(tokenId), address(vesting));
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 1);
        assertEq(depositedTokens[0], tokenId);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), JOE);

        // ~ Skip to end of vesting ~

        vm.warp(block.timestamp + duration);

        // ~ Withdraw ~

        vm.startPrank(JOE);
        vesting.withdraw(JOE, tokenId);

        // ~ Post-state check 1 ~

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - duration - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp - duration);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - duration - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp - duration);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 0);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), address(0));

        // ~ Burn ~

        vm.startPrank(JOE);
        veRWA.burn(JOE, tokenId);
        vm.stopPrank();

        // ~ Post-state check 2 ~

        vm.expectRevert();
        veRWA.ownerOf(tokenId);

        assertEq(rwaToken.balanceOf(JOE), amount);
        assertEq(rwaToken.balanceOf(address(veRWA)), 0);

        assertEq(veRWA.getLockedAmount(tokenId), 0);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - duration - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp - duration);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - duration - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp - duration);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 0);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), address(0));
    }

    /**
     * @notice This unit test verifies proper state changes when RWAVotingEscrow::burn() is called before
     *         the end of the lock period is reached.
     * @dev State changes:
     *    - actor (Joe) receives 50% of locked tokens ✅
     *    - penalized tokens are burned ✅
     *    - early unlock == fee ✅
     */
    function test_votingEscrow_burn_early() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 duration = 36 * 30 days;

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        uint256 tokenId = veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            duration
        );

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        uint256[] memory depositedTokens;

        uint256 maxVotingPower = amount.calculateVotingPower(duration);

        uint256 preSupply = rwaToken.totalSupply();

        // ~ Pre-state check ~

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount);
        
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), duration);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), amount);
        assertEq(veRWA.getVotes(JOE), amount);
        
        // ~ Skip to create new checkpoint ~

        skip(1);

        // ~ Burn ~

        vm.startPrank(JOE);
        veRWA.burn(JOE, tokenId);
        vm.stopPrank();

        uint256 feeTaken = _calculatePenalty(amount, duration);

        // ~ Post-state check 2 ~

        vm.expectRevert();
        veRWA.ownerOf(tokenId);

        assertEq(rwaToken.balanceOf(JOE), (amount / 2));
        assertEq(rwaToken.balanceOf(address(veRWA)), 0);

        assertNotEq(preSupply, rwaToken.totalSupply());
        assertEq(feeTaken + rwaToken.balanceOf(JOE), preSupply);
        assertEq(rwaToken.totalSupply(), rwaToken.balanceOf(JOE));

        assertEq(veRWA.getLockedAmount(tokenId), 0);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 0);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), address(0));
    }

    /**
     * @notice This unit test verifies proper state changes when RWAVotingEscrow::burn() is called before
     *         the end of the lock period is reached.
     * @dev State changes:
     *    - actor (Joe) receives 75% of locked tokens ✅
     *    - penalized tokens are burned ✅
     *    - early unlock == fee ✅
     */
    function test_votingEscrow_withdrawThenBurn_early() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 duration = 36 * 30 days;
        uint256 skipTo = duration / 2;

        uint256 penalty = _calculatePenalty(amount, skipTo);

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        uint256 tokenId = veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            duration
        );

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        uint256[] memory depositedTokens;

        uint256 maxVotingPower = amount.calculateVotingPower(duration);

        // ~ Sanity check ~

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount);
        
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), duration);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), amount);
        assertEq(veRWA.getVotes(JOE), amount);
        
        // ~ Skip to create new checkpoint ~

        skip(1);

        // ~ Deposit ~

        vm.startPrank(JOE);
        veRWA.approve(address(vesting), tokenId);
        vesting.deposit(tokenId);
        vm.stopPrank();

        // ~ Pre-state check ~

        assertEq(veRWA.ownerOf(tokenId), address(vesting));
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 1);
        assertEq(depositedTokens[0], tokenId);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), JOE);

        // ~ Skip to middle of vesting ~

        skip(skipTo);

        // ~ Withdraw ~

        vm.startPrank(JOE);
        vesting.withdraw(JOE, tokenId);

        // ~ Post-state check 1 ~

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 3);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - skipTo - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp - skipTo);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);
        assertEq(votingPowerCheckpoints._checkpoints[2]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[2]._value, maxVotingPower/2);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 3);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - skipTo - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp - skipTo);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);
        assertEq(totalVotingPowerCheckpoints._checkpoints[2]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[2]._value, maxVotingPower/2);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), duration - skipTo);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), maxVotingPower/2);
        assertEq(veRWA.getVotes(JOE), maxVotingPower/2);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 0);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), address(0));

        // ~ Burn ~

        vm.startPrank(JOE);
        veRWA.burn(JOE, tokenId);
        vm.stopPrank();

        // ~ Post-state check 2 ~

        vm.expectRevert();
        veRWA.ownerOf(tokenId);

        assertEq(rwaToken.balanceOf(JOE), amount - penalty);
        assertEq(rwaToken.balanceOf(address(veRWA)), 0);

        assertEq(veRWA.getLockedAmount(tokenId), 0);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 3);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - skipTo - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp - skipTo);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);
        assertEq(votingPowerCheckpoints._checkpoints[2]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[2]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 3);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - skipTo - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp - skipTo);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);
        assertEq(totalVotingPowerCheckpoints._checkpoints[2]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[2]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 0);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), address(0));
    }

    /**
     * @notice This unit test verifies proper state changes when RWAVotingEscrow::burn() is called before
     *         the end of the lock period is reached.
     * @dev State changes:
     *    - all fees within range are arithmetically accepted and dont result in an overflow/underflow✅
     */
    function test_votingEscrow_withdrawThenBurn_early_fuzzing(uint256 skipTo) public {
        skipTo = bound(skipTo, 0, veRWA.MAX_VESTING_DURATION() - 1);

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 duration = 36 * 30 days;

        uint256 penalty = _calculatePenalty(amount, duration - skipTo);

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        uint256 tokenId = veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            duration
        );

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        uint256[] memory depositedTokens;

        uint256 maxVotingPower = amount.calculateVotingPower(duration);

        // ~ Sanity check ~

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount);
        
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), duration);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), amount);
        assertEq(veRWA.getVotes(JOE), amount);
        
        // ~ Skip to create new checkpoint ~

        skip(1);

        // ~ Deposit ~

        vm.startPrank(JOE);
        veRWA.approve(address(vesting), tokenId);
        vesting.deposit(tokenId);
        vm.stopPrank();

        // ~ Pre-state check ~

        assertEq(veRWA.ownerOf(tokenId), address(vesting));
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 1);
        assertEq(depositedTokens[0], tokenId);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), JOE);

        // ~ Skip to middle of vesting ~

        skip(skipTo);

        // ~ Withdraw ~

        vm.startPrank(JOE);
        vesting.withdraw(JOE, tokenId);

        // ~ Burn ~

        vm.startPrank(JOE);
        veRWA.burn(JOE, tokenId);
        vm.stopPrank();

        // ~ Post-state check ~

        vm.expectRevert();
        veRWA.ownerOf(tokenId);

        assertEq(rwaToken.balanceOf(JOE), amount - penalty);
        assertEq(rwaToken.balanceOf(address(veRWA)), 0);
        assertEq(veRWA.getLockedAmount(tokenId), 0);

        if (skipTo == 0) {
            // get voting power checkpoints for token
            votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
            assertEq(votingPowerCheckpoints._checkpoints.length, 2);
            assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - skipTo - 1);
            assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
            assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp - skipTo);
            assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);

            // get total voting power checkpoints
            totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
            assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
            assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - skipTo - 1);
            assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
            assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp - skipTo);
            assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);
        }
        else {
            // get voting power checkpoints for token
            votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
            assertEq(votingPowerCheckpoints._checkpoints.length, 3);
            assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - skipTo - 1);
            assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
            assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp - skipTo);
            assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);
            assertEq(votingPowerCheckpoints._checkpoints[2]._key, block.timestamp);
            assertEq(votingPowerCheckpoints._checkpoints[2]._value, 0);

            // get total voting power checkpoints
            totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
            assertEq(totalVotingPowerCheckpoints._checkpoints.length, 3);
            assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - skipTo - 1);
            assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
            assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp - skipTo);
            assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);
            assertEq(totalVotingPowerCheckpoints._checkpoints[2]._key, block.timestamp);
            assertEq(totalVotingPowerCheckpoints._checkpoints[2]._value, 0);
        }

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);
    }

    // ~ VotingEscrowVesting::claim ~

    /**
     * @notice This unit test verifies proper state changes when VotingEscrowVesting::claim() is called.
     * @dev State changes:
     *    - a token that is deposited for the entire promised duration can claim ✅
     *    - proper state changes for vesting and veRWA ✅
     *    - NFT no longer exists once claim() is executed ✅
     */
    function test_votingEscrow_claim() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 duration = 36 * 30 days;

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        uint256 tokenId = veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            duration
        );

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        uint256[] memory depositedTokens;

        uint256 maxVotingPower = amount.calculateVotingPower(duration);

        // ~ Sanity check ~

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount);
        
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), duration);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), amount);
        assertEq(veRWA.getVotes(JOE), amount);
        
        // ~ Skip to create new checkpoint ~

        vm.warp(block.timestamp + 1);

        // ~ Deposit ~

        vm.startPrank(JOE);
        veRWA.approve(address(vesting), tokenId);
        vesting.deposit(tokenId);
        vm.stopPrank();

        // ~ Pre-state check ~

        assertEq(veRWA.ownerOf(tokenId), address(vesting));
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 1);
        assertEq(depositedTokens[0], tokenId);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), JOE);

        // ~ Skip to end of vesting ~

        vm.warp(block.timestamp + duration);

        // ~ Claim ~

        vm.prank(JOE);
        vesting.claim(JOE, tokenId);

        // ~ Post-state check ~

        vm.expectRevert();
        veRWA.ownerOf(tokenId);

        assertEq(rwaToken.balanceOf(JOE), amount);
        assertEq(rwaToken.balanceOf(address(veRWA)), 0);

        assertEq(veRWA.getLockedAmount(tokenId), 0);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - duration - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp - duration);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - duration - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp - duration);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 0);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), address(0));
    }

    /**
     * @notice This unit test verifies proper state changes when VotingEscrowVesting::claim() is called before
     *         the end of the lock period is reached.
     * @dev State changes:
     *    - a fee is applied ✅
     */
    function test_votingEscrow_claim_early() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 duration = 36 * 30 days;

        uint256 penalty = _calculatePenalty(amount, duration);

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        uint256 tokenId = veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            duration
        );

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        uint256[] memory depositedTokens;

        uint256 maxVotingPower = amount.calculateVotingPower(duration);

        // ~ Sanity check ~

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount);
        
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), duration);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), amount);
        assertEq(veRWA.getVotes(JOE), amount);
        
        // ~ Skip to create new checkpoint ~

        skip(1);

        // ~ Deposit ~

        vm.startPrank(JOE);
        veRWA.approve(address(vesting), tokenId);
        vesting.deposit(tokenId);
        vm.stopPrank();

        // ~ Pre-state check ~

        assertEq(veRWA.ownerOf(tokenId), address(vesting));
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 1);
        assertEq(depositedTokens[0], tokenId);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), JOE);

        // ~ claim ~

        vm.startPrank(JOE);
        vesting.claim(JOE, tokenId);
        vm.stopPrank();

        // ~ Post-state check ~

        vm.expectRevert();
        veRWA.ownerOf(tokenId);

        assertEq(rwaToken.balanceOf(JOE), amount - penalty);
        assertEq(rwaToken.balanceOf(address(veRWA)), 0);

        assertEq(veRWA.getLockedAmount(tokenId), 0);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 0);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), address(0));
    }

    /**
     * @notice This unit test verifies proper state changes when VotingEscrowVesting::claim() is called before
     *         the end of the lock period is reached. We expect a fee to be applied. Using fuzzing.
     * @dev State changes:
     *    - a fee is applied ✅
     *    - no evidence of potential arithmetic errors ✅
     */
    function test_votingEscrow_claim_early_fuzzing(uint256 skipTo) public {
        skipTo = bound(skipTo, 0, veRWA.MAX_VESTING_DURATION() - 1);

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 duration = 36 * 30 days;

        uint256 penalty = _calculatePenalty(amount, duration - skipTo);

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        uint256 tokenId = veRWA.mint(
            JOE,
            uint208(rwaToken.balanceOf(JOE)),
            duration
        );

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        uint256[] memory depositedTokens;

        uint256 maxVotingPower = amount.calculateVotingPower(duration);

        // ~ Sanity check ~

        assertEq(veRWA.ownerOf(tokenId), JOE);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount);
        
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), duration);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), amount);
        assertEq(veRWA.getVotes(JOE), amount);
        
        // ~ Skip to create new checkpoint ~

        skip(1);

        // ~ Deposit ~

        vm.startPrank(JOE);
        veRWA.approve(address(vesting), tokenId);
        vesting.deposit(tokenId);
        vm.stopPrank();

        // ~ Pre-state check ~

        assertEq(veRWA.ownerOf(tokenId), address(vesting));
        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 1);
        assertEq(depositedTokens[0], tokenId);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), JOE);

        // ~ Skip to middle of vesting ~

        skip(skipTo);

        // ~ claim ~

        vm.startPrank(JOE);
        vesting.claim(JOE, tokenId);
        vm.stopPrank();

        // ~ Post-state check ~

        vm.expectRevert();
        veRWA.ownerOf(tokenId);

        assertEq(rwaToken.balanceOf(JOE), amount - penalty);
        assertEq(rwaToken.balanceOf(address(veRWA)), 0);
        assertEq(veRWA.getLockedAmount(tokenId), 0);

        if (skipTo == 0) {
            // get voting power checkpoints for token
            votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
            assertEq(votingPowerCheckpoints._checkpoints.length, 2);
            assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
            assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
            assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
            assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);

            // get total voting power checkpoints
            totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
            assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
            assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
            assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
            assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
            assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);
        }
        else {
            // get voting power checkpoints for token
            votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
            assertEq(votingPowerCheckpoints._checkpoints.length, 3);
            assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - skipTo - 1);
            assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
            assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp - skipTo);
            assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);
            assertEq(votingPowerCheckpoints._checkpoints[2]._key, block.timestamp);
            assertEq(votingPowerCheckpoints._checkpoints[2]._value, 0);

            // get total voting power checkpoints
            totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
            assertEq(totalVotingPowerCheckpoints._checkpoints.length, 3);
            assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - skipTo - 1);
            assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
            assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp - skipTo);
            assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, 0);
            assertEq(totalVotingPowerCheckpoints._checkpoints[2]._key, block.timestamp);
            assertEq(totalVotingPowerCheckpoints._checkpoints[2]._value, 0);
        }

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // check deposited tokens by JOE on vesting contract
        depositedTokens = vesting.getDepositedTokens(JOE);
        assertEq(depositedTokens.length, 0);

        // check depositors mapping
        assertEq(vesting.depositors(tokenId), address(0));
    }

    // ~ RWAVotingEscrow::depositFor ~

    /**
     * @notice This unit test verifies proper state changes when RWAVotingEscrow::depositFor() is called.
     * @dev State changes:
     *    - cannot deposit tokens for a token that does not exist ✅
     *    - lock instance is updated correctly ✅
     */
    function test_votingEscrow_depositFor() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 duration = 2 * 30 days;
        uint256 skipTo = 1 * 30 days;

        // Mint Joe $RWA tokens
        rwaToken.mintFor(JOE, amount);

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        uint256 tokenId = veRWA.mint(
            JOE,
            uint208(amount),
            duration
        );
        vm.stopPrank();

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        uint256 maxVotingPower = amount.calculateVotingPower(duration);

        // ~ Pre-state check ~

        assertEq(rwaToken.balanceOf(JOE), amount);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount);

        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), duration);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), maxVotingPower);
        assertEq(veRWA.getVotes(JOE), maxVotingPower);

        // ~ Skip ~

        skip(skipTo);

        // ~ depositFor ~

        // Joe tries to deposit for a token that is not minted -> revert
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        vm.expectRevert();
        veRWA.depositFor(tokenId + 1, amount);
        vm.stopPrank();

        // Joe deposits
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount);
        veRWA.depositFor(tokenId, amount);
        vm.stopPrank();

        uint256 newMaxVotingPower = (amount*2).calculateVotingPower(duration);

        // ~ Post-state check ~

        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount * 2);

        assertEq(veRWA.getLockedAmount(tokenId), amount * 2);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - skipTo);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, newMaxVotingPower);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - skipTo);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, newMaxVotingPower);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), duration);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), newMaxVotingPower);
        assertEq(veRWA.getVotes(JOE), newMaxVotingPower);
    }

    // ~ RWAVotingEscrow::merge ~

    /**
     * @notice This unit test verifies proper state changes when RWAVotingEscrow::merge() is called.
     * @dev State changes:
     *    - token1 lock data is set to 0 then burned ✅
     *    - token2 lock duration is set to greater duration between 2 tokens ✅
     *    - token2 locked tokens are combined with token1's locked tokens ✅
     */
    function test_votingEscrow_merge() public {

        // ~ Config ~

        uint256 amount1 = 1_000 ether;
        uint256 amount2 = 1_000 ether;

        uint256 duration1 = 1 * 30 days;
        uint256 duration2 = 2 * 30 days;

        // Mint Alice $RWA tokens
        rwaToken.mintFor(ALICE, amount2);

        // Mint Joe VE NFT
        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amount1);
        uint256 tokenId1 = veRWA.mint(
            JOE,
            uint208(amount1),
            duration1
        );
        vm.stopPrank();

        // Mint Alice VE NFT
        vm.startPrank(ALICE);
        rwaToken.approve(address(veRWA), amount2);
        uint256 tokenId2 = veRWA.mint(
            ALICE,
            uint208(amount2),
            duration2
        );
        vm.stopPrank();

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        uint256 maxVotingPower1 = amount1.calculateVotingPower(duration1);
        uint256 maxVotingPower2 = amount2.calculateVotingPower(duration2);

        // ~ Pre-state check ~

        assertEq(veRWA.ownerOf(tokenId1), JOE);
        assertEq(veRWA.ownerOf(tokenId2), ALICE);
        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(ALICE), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount1 + amount2);
        
        assertEq(veRWA.getLockedAmount(tokenId1), amount1);
        assertEq(veRWA.getLockedAmount(tokenId2), amount2);
        // get voting power checkpoints for tokenId1
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId1);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower1);
        // get voting power checkpoints for tokenId2
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId2);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower2);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower1 + maxVotingPower2);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId1), duration1);
        assertEq(veRWA.getRemainingVestingDuration(tokenId2), duration2);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), maxVotingPower1);
        assertEq(veRWA.getVotes(JOE), maxVotingPower1);
        assertEq(veRWA.getAccountVotingPower(ALICE), maxVotingPower2);
        assertEq(veRWA.getVotes(ALICE), maxVotingPower2);

        // ~ Skip to create checkpoint ~

        skip(1);

        // ~ Merge ~

        // Joe sends NFT to Alice
        vm.prank(JOE);
        veRWA.transferFrom(JOE, ALICE, tokenId1);

        // Verify Alice holds total voting power (even with tokens not merged yet)
        assertEq(veRWA.ownerOf(tokenId1), ALICE);
        assertEq(veRWA.ownerOf(tokenId2), ALICE);
        assertEq(veRWA.getAccountVotingPower(ALICE), maxVotingPower1 + maxVotingPower2);
        assertEq(veRWA.getVotes(ALICE), maxVotingPower1 + maxVotingPower2);

        // Alice merges both tokens
        vm.prank(ALICE);
        veRWA.merge(tokenId1, tokenId2);

        uint256 combinedVotingPower = (amount1 + amount2).calculateVotingPower(duration2);

        // ~ Post-state check ~

        vm.expectRevert();
        veRWA.ownerOf(tokenId1); // token n longer exists

        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(ALICE), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount1 + amount2);
        
        assertEq(veRWA.getLockedAmount(tokenId1), 0);
        assertEq(veRWA.getLockedAmount(tokenId2), amount1 + amount2);
        // get voting power checkpoints for tokenId1
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId1);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower1);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);
        // get voting power checkpoints for tokenId2
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId2);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower2);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, combinedVotingPower);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower1 + maxVotingPower2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, combinedVotingPower);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId2), duration2);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);
        assertEq(veRWA.getAccountVotingPower(ALICE), combinedVotingPower);
        assertEq(veRWA.getVotes(ALICE), combinedVotingPower);
    }

    // ~ RWAVotingEscrow::split ~

    /**
     * @notice This unit test verifies proper state changes when RWAVotingEscrow::split() is called.
     * @dev State changes:
     *    - token locked balance is split according to specified proportion ✅
     *    - locked duration stays the same for all tokens ✅
     *    - 
     */
    function test_votingEscrow_split() public {

        // ~ Config ~

        uint256 amountTokens = 1_000 ether;
        uint256 duration = 1 * 30 days;

        // should yield 2 equal tokens
        uint256[] memory shares = new uint256[](2);
        shares[0] = 1;
        shares[1] = 1;

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amountTokens);
        uint256 tokenId = veRWA.mint(
            JOE,
            uint208(amountTokens),
            duration
        );
        vm.stopPrank();

        uint256 maxVotingPower = amountTokens.calculateVotingPower(duration);
        uint256 maxVotingPowerSplit = (amountTokens/2).calculateVotingPower(duration);

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        // ~ Pre-state check ~

        assertEq(veRWA.getAccountVotingPower(JOE), maxVotingPower);
        assertEq(veRWA.getVotes(JOE), maxVotingPower);

        // ~ Skip to create new checkpoint ~

        skip(1);

        // ~ Split ~

        vm.prank(JOE);
        uint256[] memory tokenIds = veRWA.split(tokenId, shares);

        // ~ Post-state check ~

        assertEq(tokenIds[0], tokenId);
        assertEq(tokenIds.length, shares.length);
        
        assertEq(veRWA.getLockedAmount(tokenIds[0]), amountTokens/2);
        assertEq(veRWA.getLockedAmount(tokenIds[1]), amountTokens/2);
        // get voting power checkpoints for tokenId1
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenIds[0]);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, maxVotingPowerSplit);
        // get voting power checkpoints for tokenId2
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenIds[1]);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPowerSplit);

        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 2);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[1]._value, maxVotingPower - 1);

        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenIds[0]), duration);
        assertEq(veRWA.getRemainingVestingDuration(tokenIds[1]), duration);
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), maxVotingPower - 1);
        assertEq(veRWA.getVotes(JOE), maxVotingPower - 1);
    }

    // ~ RWAVotingEscrow::migrate ~

    /**
     * @notice This unit test verifies proper state changes when RWAVotingEscrow::migrate() is called.
     * @dev State changes:
     *    - Method can only be called by layer zero endpoint ✅
     *    - $RWA tokens are minted to VE contract 1-to-1 with lockedBalance ✅
     *    - Receiver is minted a VE NFT representing specified position ✅
     */
    function test_votingEscrow_migrate() public {

        // ~ Config ~

        uint256 amount = 1_000 ether;
        uint256 duration = 1 * 30 days;

        uint256 preSupply = rwaToken.totalSupply();
        uint256 tokenId = veRWA.getTokenId();
        tokenId++;

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        uint256 maxVotingPower = amount.calculateVotingPower(duration);

        // ~ Pre-state check ~

        assertEq(rwaToken.balanceOf(NIK), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), 0);

        assertEq(veRWA.getLockedAmount(tokenId), 0);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 0);
        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 0);
        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);
        // check NIK's voting power
        assertEq(veRWA.getAccountVotingPower(NIK), 0);
        assertEq(veRWA.getVotes(NIK), 0);

        // ~ Migrate ~

        // Joe tries calling migrate -> revert
        vm.prank(JOE);
        vm.expectRevert(abi.encodeWithSelector(RWAVotingEscrow.NotAuthorized.selector, JOE));
        veRWA.migrate(NIK, amount, duration);

        vm.prank(LAYER_Z);
        uint256 _tokenId = veRWA.migrate(NIK, amount, duration);

        // ~ Post-state check ~

        assertEq(tokenId, _tokenId);
        assertEq(rwaToken.totalSupply(), preSupply + amount);

        assertEq(rwaToken.balanceOf(NIK), 0);
        assertEq(rwaToken.balanceOf(address(veRWA)), amount);

        assertEq(veRWA.getLockedAmount(tokenId), amount);
        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        // get total voting power checkpoints
        totalVotingPowerCheckpoints = veRWA.getTotalVotingPowerCheckpoints();
        assertEq(totalVotingPowerCheckpoints._checkpoints.length, 1);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._key, block.timestamp);
        assertEq(totalVotingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        // check remaining vesting duration for token
        assertEq(veRWA.getRemainingVestingDuration(tokenId), duration);
        // check NIK's voting power
        assertEq(veRWA.getAccountVotingPower(NIK), maxVotingPower);
        assertEq(veRWA.getVotes(NIK), maxVotingPower);
    }

    /**
     * @notice This unit test verifies proper values when RWAVotingEscrow::getPastVotingPower() is called.
     * @dev State changes:
     *    - getPastVotingPower always pulls the most recent updated key-value pair for a token ✅
     */
    function test_votingEscrow_getPastVotingPower() public {
        // mint token, deposit, skip, withdraw, deposit, skip, withdraw
        // to create checkpoints, checking state each time a withdraw happens

        // ~ Config ~

        uint256 amountTokens = 1_000 ether;
        uint256 duration = 4 * 30 days;

        vm.startPrank(JOE);
        rwaToken.approve(address(veRWA), amountTokens);
        uint256 tokenId = veRWA.mint(
            JOE,
            uint208(amountTokens),
            duration
        );
        vm.stopPrank();

        uint256 maxVotingPower = amountTokens.calculateVotingPower(duration);

        Checkpoints.Trace208 memory votingPowerCheckpoints;
        Checkpoints.Trace208 memory totalVotingPowerCheckpoints;

        // ~ Skip ~

        skip(1);

        // ~ Voting power check 1 ~

        // verify voting power via upperLookup
        assertEq(veRWA.getPastVotingPower(tokenId, block.timestamp - 1), maxVotingPower);
        assertEq(veRWA.getPastTotalVotingPower(block.timestamp - 1), maxVotingPower);

        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 1);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);

        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), maxVotingPower);
        assertEq(veRWA.getVotes(JOE), maxVotingPower);

        // ~ Deposit ~

        vm.startPrank(JOE);
        veRWA.approve(address(vesting), tokenId);
        vesting.deposit(tokenId);
        vm.stopPrank();

        // ~ Skip ~

        skip(1);

        // ~ Voting power check 2 ~

        // verify voting power via upperLookup
        assertEq(veRWA.getPastVotingPower(tokenId, block.timestamp - 1), 0);
        assertEq(veRWA.getPastTotalVotingPower(block.timestamp - 1), 0);

        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 2);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp - 1);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);
        
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), 0);
        assertEq(veRWA.getVotes(JOE), 0);

        // ~ Withdraw ~ 

        vm.startPrank(JOE);
        vesting.withdraw(JOE, tokenId);

        uint256 vpAfter1 = amountTokens.calculateVotingPower(duration - 1);

        // ~ Skip ~

        skip(1);

        // ~ Voting power check 3 ~

        assertLt(vpAfter1, maxVotingPower);

        // verify voting power via upperLookup
        assertEq(veRWA.getPastVotingPower(tokenId, block.timestamp - 1), vpAfter1);
        assertEq(veRWA.getPastTotalVotingPower(block.timestamp - 1), vpAfter1);

        // get voting power checkpoints for token
        votingPowerCheckpoints = veRWA.getVotingPowerCheckpoints(tokenId);
        assertEq(votingPowerCheckpoints._checkpoints.length, 3);
        assertEq(votingPowerCheckpoints._checkpoints[0]._key, block.timestamp - 3);
        assertEq(votingPowerCheckpoints._checkpoints[0]._value, maxVotingPower);
        assertEq(votingPowerCheckpoints._checkpoints[1]._key, block.timestamp - 2);
        assertEq(votingPowerCheckpoints._checkpoints[1]._value, 0);
        assertEq(votingPowerCheckpoints._checkpoints[2]._key, block.timestamp - 1);
        assertEq(votingPowerCheckpoints._checkpoints[2]._value, vpAfter1);
        
        // check Joe's voting power
        assertEq(veRWA.getAccountVotingPower(JOE), vpAfter1);
        assertEq(veRWA.getVotes(JOE), vpAfter1);
    }

}