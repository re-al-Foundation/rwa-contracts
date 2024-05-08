// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// foundry imports
import { Test, console2 } from "../lib/forge-std/src/Test.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Checkpoints } from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// local imports
import { RevenueStreamETH } from "../src/RevenueStreamETH.sol";
import { RevenueDistributor } from "../src/RevenueDistributor.sol";
import { RWAVotingEscrow } from "../src/governance/RWAVotingEscrow.sol";
import { VotingEscrowVesting } from "../src/governance/VotingEscrowVesting.sol";
import { RWAToken } from "../src/RWAToken.sol";
import { RoyaltyHandler } from "../src/RoyaltyHandler.sol";
import { DelegateFactory } from "../src/governance/DelegateFactory.sol";
import { Delegator } from "../src/governance/Delegator.sol";

// local helper imports
import { Utility } from "./utils/Utility.sol";
import "./utils/Constants.sol";
import { VotingMath } from "../src/governance/VotingMath.sol";
import { IUniswapV2Router02 } from "../src/interfaces/IUniswapV2Router02.sol";
import { IUniswapV2Router01 } from "../src/interfaces/IUniswapV2Router01.sol";
import { IUniswapV2Pair } from "../src/interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Factory } from "../src/interfaces/IUniswapV2Factory.sol";
import { IQuoterV2 } from "../src/interfaces/IQuoterV2.sol";

/**
 * @title RWATokenTest
 * @author @chasebrownn
 * @notice Contains unit tests for $RWA token. Tests focus on transaction taxes.
 */
contract RWATokenTest is Utility {
    using VotingMath for uint256;

    // ~ Contracts ~

    RevenueStreamETH public revStream;
    RevenueDistributor public revDistributor;
    RWAVotingEscrow public veRWA;
    VotingEscrowVesting public vesting;
    RWAToken public rwaToken;
    RoyaltyHandler public royaltyHandler;
    DelegateFactory public delegateFactory;
    Delegator public delegator;

    // ~ Variables ~

    address public WETH;

    address internal pair;

    function setUp() public {

        vm.createSelectFork(UNREAL_RPC_URL);

        WETH = UNREAL_WETH;

        // ~ $RWA Deployment ~

        // Deploy $RWA Token implementation
        rwaToken = new RWAToken();

        // Deploy proxy for $RWA Token
        ERC1967Proxy rwaTokenProxy = new ERC1967Proxy(
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
        ERC1967Proxy vestingProxy = new ERC1967Proxy(
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
        ERC1967Proxy veRWAProxy = new ERC1967Proxy(
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
        ERC1967Proxy revDistributorProxy = new ERC1967Proxy(
            address(revDistributor),
            abi.encodeWithSelector(RevenueDistributor.initialize.selector,
                ADMIN,
                address(veRWA),
                address(0)
            )
        );
        revDistributor = RevenueDistributor(payable(address(revDistributorProxy)));


        // ~ Royalty Handler Deployment ~

        // Deploy royaltyHandler base
        royaltyHandler = new RoyaltyHandler();

        // Deploy proxy for royaltyHandler
        ERC1967Proxy royaltyHandlerProxy = new ERC1967Proxy(
            address(royaltyHandler),
            abi.encodeWithSelector(RoyaltyHandler.initialize.selector,
                ADMIN,
                address(revDistributor),
                address(rwaToken),
                WETH,
                MUMBAI_UNIV2_ROUTER,
                address(0),
                address(0)
            )
        );
        royaltyHandler = RoyaltyHandler(payable(address(royaltyHandlerProxy)));


        // ~ Delegator Deployment ~

        // Deploy Delegator implementation
        delegator = new Delegator();

        // Deploy DelegateFactory
        delegateFactory = new DelegateFactory();

        // Deploy DelegateFactory proxy
        ERC1967Proxy delegateFactoryProxy = new ERC1967Proxy(
            address(delegateFactory),
            abi.encodeWithSelector(DelegateFactory.initialize.selector,
                address(veRWA),
                address(delegator),
                ADMIN
            )
        );
        delegateFactory = DelegateFactory(address(delegateFactoryProxy));


        // ~ Config ~

        // vm.prank(ADMIN);
        // revStream = RevenueStreamETH(revDistributor.createNewRevStream(address(rwaToken)));

        // set votingEscrow on vesting contract
        vm.prank(ADMIN);
        vesting.setVotingEscrowContract(address(veRWA));

        //vm.prank(ADMIN);
        //rwaToken.setRevenueDistributor(address(revDistributor));

        // Grant minter role to address(this) & veRWA
        vm.startPrank(ADMIN);
        rwaToken.setRoyaltyHandler(address(royaltyHandler));
        rwaToken.setVotingEscrowRWA(address(veRWA));
        rwaToken.setReceiver(address(this)); // for testing
        // whitelist
        rwaToken.excludeFromFees(address(veRWA), true);
        rwaToken.excludeFromFees(address(this), true); // for testing
        vm.stopPrank();

        // Mint Joe $RWA tokens
        //rwaToken.mintFor(JOE, 1_000 ether);

        _createLabels();
    }


    // -------
    // Utility
    // -------

    function _createLabels() internal {
        vm.label(JOE, "JOE");
        vm.label(address(rwaToken), "RWAToken");
        vm.label(address(royaltyHandler), "RoyaltyHandler");
    }


    // ------------------
    // Initial State Test
    // ------------------

    /// @dev Verifies initial state of RWAToken contract.
    function test_rwaToken_init_state() public {
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0);
    }


    // ----------
    // Unit Tests
    // ----------

    /// @dev Verifies the initial state variables of a new RWAToken instance.
    function test_rwaToken_initializer() public {
        RWAToken newRWAToken = new RWAToken();
        ERC1967Proxy newRWATokenProxy = new ERC1967Proxy(
            address(newRWAToken),
            abi.encodeWithSelector(RWAToken.initialize.selector,
                ADMIN
            )
        );
        newRWAToken = RWAToken(address(newRWATokenProxy));

        assertEq(newRWAToken.name(), "re.al");
        assertEq(newRWAToken.symbol(), "RWA");
        assertEq(newRWAToken.owner(), ADMIN);

        assertEq(newRWAToken.isExcludedFromFees(address(newRWAToken)), true);
        assertEq(newRWAToken.isExcludedFromFees(ADMIN), true);
        assertEq(newRWAToken.isExcludedFromFees(address(0)), true);

        assertEq(newRWAToken.fee(), 5);
    }

    /// @dev Verifies restrictions during initialization of a new RWAToken instance.
    function test_rwaToken_initializer_restrictions() public {
        RWAToken newRWAToken = new RWAToken();

        vm.expectRevert();
        new ERC1967Proxy(
            address(newRWAToken),
            abi.encodeWithSelector(RWAToken.initialize.selector,
                address(0)
            )
        );
    }

    /// @dev Verifies proper state changes when a user transfer tokens to another user.
    ///      Normal pier to pier transfers will result in 0 tax.
    function test_rwaToken_transfer() public {

        // ~ Config ~

        uint256 amountTokens = 10_000 ether;
        deal(address(rwaToken), JOE, amountTokens);

        // ~ Pre-state check ~

        assertEq(rwaToken.balanceOf(JOE), amountTokens);
        assertEq(rwaToken.balanceOf(ALICE), 0);
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0);

        // ~ Execute transfer ~

        vm.prank(JOE);
        rwaToken.transfer(ALICE, amountTokens);

        // ~ Post-state check ~

        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(ALICE), amountTokens);
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0);
    }

    /// @dev Verifies restrictions when the RWAToken::transfer function is initiated.
    function test_rwaToken_transfer_restrictions() public {
        uint256 amountTokens = 10_000 ether;
        deal(address(rwaToken), JOE, amountTokens);

        vm.prank(ADMIN);
        rwaToken.setAutomatedMarketMakerPair(ALICE, true);

        vm.store(address(rwaToken), bytes32(uint256(6)), bytes32(uint256(uint160(address(0)))));
        assertEq(rwaToken.royaltyHandler(), address(0));

        // A tax cannot be applied if there's no RoyaltyHandler assigned.
        vm.prank(JOE);
        vm.expectRevert(abi.encodeWithSelector(RWAToken.RoyaltyHandlerNotAssigned.selector));
        rwaToken.transfer(ALICE, amountTokens);
    }

    /// @dev Verifies proper state changes when a user transfers tokens to an AMM
    ///      or receives tokens from an AMM. When this occurs, a tax is applied.
    function test_rwaToken_transfer_fees() public {

        // ~ Config ~

        uint256 amountTokens = 100;
        deal(address(rwaToken), JOE, amountTokens);

        vm.prank(ADMIN);
        rwaToken.setAutomatedMarketMakerPair(ALICE, true);

        // ~ Pre-state check ~

        assertEq(rwaToken.balanceOf(JOE), amountTokens);
        assertEq(rwaToken.balanceOf(ALICE), 0);
        assertEq(rwaToken.balanceOf(address(royaltyHandler)), 0);

        // ~ Execute transfer to AMM ~

        vm.prank(JOE);
        rwaToken.transfer(ALICE, amountTokens);

        // ~ Post-state check ~

        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(ALICE), 95);
        assertEq(rwaToken.balanceOf(address(royaltyHandler)), 5);

        // ~ Execute transfer from AMM ~

        vm.prank(ALICE);
        rwaToken.transfer(JOE, 95);

        // ~ Post-state check ~

        assertLt(rwaToken.balanceOf(JOE), 95);
        assertEq(rwaToken.balanceOf(ALICE), 0);
        assertGt(rwaToken.balanceOf(address(royaltyHandler)), 5);
    }

    /// @dev Verifies proper state changes when a user is blacklisted
    function test_rwaToken_transfer_BL() public {

        uint256 amountTokens = 10_000 ether;
        deal(address(rwaToken), JOE, amountTokens);

        vm.prank(ADMIN);
        rwaToken.modifyBlacklist(JOE, true);

        // blacklisted address cannot send tokens anywhere else but the owner
        vm.startPrank(JOE);
        vm.expectRevert(abi.encodeWithSelector(RWAToken.Blacklisted.selector, JOE));
        rwaToken.transfer(ALICE, amountTokens);
        rwaToken.transfer(ADMIN, amountTokens);
        vm.stopPrank();

        deal(address(rwaToken), JOE, amountTokens);

        vm.startPrank(ADMIN);
        rwaToken.modifyBlacklist(JOE, false);
        rwaToken.modifyBlacklist(ALICE, true);
        vm.stopPrank();

        // blacklisted address cannot receive tokens
        vm.prank(JOE);
        vm.expectRevert(abi.encodeWithSelector(RWAToken.Blacklisted.selector, ALICE));
        rwaToken.transfer(ALICE, amountTokens);
    }

    /// @dev Verifies proper state changes when a user transfer tokens to another user.
    ///      Normal pier to pier transfers will result in 0 tax.
    ///      Whitelisted users also receive no tax on transfer.
    function test_rwaToken_transfer_WL() public {

        // ~ Config ~

        vm.prank(ADMIN);
        rwaToken.excludeFromFees(JOE, true);

        uint256 amountTokens = 10_000 ether;
        deal(address(rwaToken), JOE, amountTokens);

        // ~ Pre-state check ~

        assertEq(rwaToken.balanceOf(JOE), amountTokens);
        assertEq(rwaToken.balanceOf(ALICE), 0);
        assertEq(rwaToken.balanceOf(address(royaltyHandler)), 0);

        // ~ Execute transfer ~

        vm.prank(JOE);
        rwaToken.transfer(ALICE, amountTokens);

        // ~ Post-state check

        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(ALICE), amountTokens);
        assertEq(rwaToken.balanceOf(address(royaltyHandler)), 0);
    }

    /// @dev Uses fuzzing to verify proper state changes when a user transfer tokens to another user.
    ///      Normal pier to pier transfers will result in 0 tax.
    function test_rwaToken_transfer_fuzzing(uint256 amountTokens) public {
        amountTokens = bound(amountTokens, 0.000000001 ether, 500_000 ether); // Range 0.000000001 -> 500k tokens

        // ~ Config ~

        deal(address(rwaToken), JOE, amountTokens);

        // ~ Pre-state check ~

        assertEq(rwaToken.balanceOf(JOE), amountTokens);
        assertEq(rwaToken.balanceOf(ALICE), 0);
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0);

        // ~ Execute transfer ~

        vm.prank(JOE);
        rwaToken.transfer(ALICE, amountTokens);

        // ~ Post-state check

        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.balanceOf(ALICE), amountTokens);
        assertEq(rwaToken.balanceOf(address(rwaToken)), 0);
    }

    /// @dev Verifies proper state changes when updateDistribution is executed.
    function test_rwaToken_royaltyHandler_updateDistribution() public {

        // ~ Pre-state check ~

        assertEq(royaltyHandler.burnPortion(), 2);
        assertEq(royaltyHandler.revSharePortion(), 2);
        assertEq(royaltyHandler.lpPortion(), 1);

        // ~ Execute updateDistribution ~

        vm.prank(ADMIN);
        royaltyHandler.updateDistribution(4, 4, 2);

        // ~ Post-state check ~

        assertEq(royaltyHandler.burnPortion(), 4);
        assertEq(royaltyHandler.revSharePortion(), 4);
        assertEq(royaltyHandler.lpPortion(), 2);
    }

    /// @dev Verifies proper state changes when RWAToken::updateFees is called.
    function test_rwaToken_updateFees() public {

        // ~ Pre-state check ~

        assertEq(rwaToken.fee(), 5);

        // ~ Admin executes updateFees ~

        vm.prank(ADMIN);
        rwaToken.updateFee(7);

        // ~ Post-state check ~

        assertEq(rwaToken.fee(), 7);
    }

    /// @dev Verifies restrictions when RWAToken::updateFees is called with unaccepted args.
    function test_rwaToken_updateFees_restrictions() public {
        // Only owner can call
        vm.prank(JOE);
        vm.expectRevert();
        rwaToken.updateFee(7);

        // Fee cannot exceed 10
        vm.prank(ADMIN);
        vm.expectRevert();
        rwaToken.updateFee(11);
    }

    /// @dev Verifies proper state changes when RWAToken::setRoyaltyHandler is called.
    function test_rwaToken_setRoyaltyHandler() public {

        // ~ Pre-state check ~

        assertEq(rwaToken.royaltyHandler(), address(royaltyHandler));
        assertEq(rwaToken.isExcludedFromFees(address(royaltyHandler)), true);
        assertEq(rwaToken.canBurn(address(royaltyHandler)), true);
        assertEq(rwaToken.isExcludedFromFees(JOE), false);
        assertEq(rwaToken.canBurn(JOE), false);

        // ~ Admin executes setRoyaltyHandler ~

        vm.prank(ADMIN);
        rwaToken.setRoyaltyHandler(JOE);

        // ~ Post-state check ~

        assertEq(rwaToken.royaltyHandler(), JOE);
        assertEq(rwaToken.isExcludedFromFees(address(royaltyHandler)), false);
        assertEq(rwaToken.canBurn(address(royaltyHandler)), false);
        assertEq(rwaToken.isExcludedFromFees(JOE), true);
        assertEq(rwaToken.canBurn(JOE), true);
    }

    /// @dev Verifies restrictions when RWAToken::setRoyaltyHandler is called with unaccepted args.
    function test_rwaToken_setRoyaltyHandler_restrictions() public {
        // Only owner can call
        vm.prank(JOE);
        vm.expectRevert();
        rwaToken.setRoyaltyHandler(JOE);

        // Input cannot be address(0)
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(RWAToken.ZeroAddress.selector));
        rwaToken.setRoyaltyHandler(address(0));
    }

    /// @dev Verifies proper state changes when RWAToken::setReceiver is called.
    function test_rwaToken_setReceiver() public {

        // ~ Pre-state check ~

        assertEq(rwaToken.lzReceiver(), address(this));
        assertEq(rwaToken.isExcludedFromFees(address(this)), true);
        assertEq(rwaToken.canMint(address(this)), true);
        assertEq(rwaToken.isExcludedFromFees(JOE), false);
        assertEq(rwaToken.canMint(JOE), false);

        // ~ Admin executes setReceiver ~

        vm.prank(ADMIN);
        rwaToken.setReceiver(JOE);

        // ~ Post-state check ~

        assertEq(rwaToken.lzReceiver(), JOE);
        assertEq(rwaToken.isExcludedFromFees(address(this)), false);
        assertEq(rwaToken.canMint(address(this)), false);
        assertEq(rwaToken.isExcludedFromFees(JOE), true);
        assertEq(rwaToken.canMint(JOE), true);
    }

    /// @dev Verifies restrictions when RWAToken::setReceiver is called with unaccepted args.
    function test_rwaToken_setReceiver_restrictions() public {
        // Only owner can call
        vm.prank(JOE);
        vm.expectRevert();
        rwaToken.setReceiver(JOE);

        // Input cannot be address(0)
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(RWAToken.ZeroAddress.selector));
        rwaToken.setReceiver(address(0));
    }

    /// @dev Verifies proper state changes when RWAToken::setVotingEscrowRWA is called.
    function test_rwaToken_setVotingEscrowRWA() public {

        // ~ Pre-state check ~

        assertEq(rwaToken.votingEscrowRWA(), address(veRWA));
        assertEq(rwaToken.isExcludedFromFees(address(veRWA)), true);
        assertEq(rwaToken.canMint(address(veRWA)), true);
        assertEq(rwaToken.canBurn(address(veRWA)), true);
        assertEq(rwaToken.isExcludedFromFees(JOE), false);
        assertEq(rwaToken.canMint(JOE), false);
        assertEq(rwaToken.canBurn(JOE), false);

        // ~ Admin executes setVotingEscrowRWA ~

        vm.prank(ADMIN);
        rwaToken.setVotingEscrowRWA(JOE);

        // ~ Post-state check ~

        assertEq(rwaToken.votingEscrowRWA(), JOE);
        assertEq(rwaToken.isExcludedFromFees(address(veRWA)), false);
        assertEq(rwaToken.canMint(address(veRWA)), false);
        assertEq(rwaToken.canBurn(address(veRWA)), false);
        assertEq(rwaToken.isExcludedFromFees(JOE), true);
        assertEq(rwaToken.canMint(JOE), true);
        assertEq(rwaToken.canBurn(JOE), true);
    }

    /// @dev Verifies restrictions when RWAToken::setVotingEscrowRWA is called with unaccepted args.
    function test_rwaToken_setVotingEscrowRWA_restrictions() public {
        // Only owner can call
        vm.prank(JOE);
        vm.expectRevert();
        rwaToken.setVotingEscrowRWA(JOE);

        // Input cannot be address(0)
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(RWAToken.ZeroAddress.selector));
        rwaToken.setVotingEscrowRWA(address(0));
    }

    /// @dev Verifies proper state changes when RWAToken::setAutomatedMarketMakerPair is called.
    function test_rwaToken_setAutomatedMarketMakerPair() public {

        // ~ Pre-state check ~

        assertEq(rwaToken.automatedMarketMakerPairs(JOE), false);

        // ~ Admin executes setAutomatedMarketMakerPair ~

        vm.prank(ADMIN);
        rwaToken.setAutomatedMarketMakerPair(JOE, true);

        // ~ Post-state check ~

        assertEq(rwaToken.automatedMarketMakerPairs(JOE), true);
    }

    /// @dev Verifies restrictions when RWAToken::setAutomatedMarketMakerPair is called with unaccepted args.
    function test_rwaToken_setAutomatedMarketMakerPair_restrictions() public {
        // Only owner can call
        vm.prank(JOE);
        vm.expectRevert();
        rwaToken.setAutomatedMarketMakerPair(JOE, true);

        // Input cannot be address(0)
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(RWAToken.ZeroAddress.selector));
        rwaToken.setAutomatedMarketMakerPair(address(0), true);

        // Cannot set a pair that's already set
        vm.prank(ADMIN);
        vm.expectRevert();
        rwaToken.setAutomatedMarketMakerPair(JOE, false);
    }

    /// @dev Verifies proper state changes when RWAToken::modifyBlacklist is called.
    function test_rwaToken_modifyBlacklist() public {

        // ~ Pre-state check ~

        assertEq(rwaToken.isBlacklisted(JOE), false);

        // ~ Admin executes modifyBlacklist ~

        vm.prank(ADMIN);
        rwaToken.modifyBlacklist(JOE, true);

        // ~ Post-state check ~

        assertEq(rwaToken.isBlacklisted(JOE), true);
    }

    /// @dev Verifies restrictions when RWAToken::modifyBlacklist is called with unaccepted args.
    function test_rwaToken_modifyBlacklist_restrictions() public {
        // Only owner can call
        vm.prank(JOE);
        vm.expectRevert();
        rwaToken.modifyBlacklist(JOE, true);

        // Input cannot be address(0)
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(RWAToken.ZeroAddress.selector));
        rwaToken.modifyBlacklist(address(0), true);
    }

    /// @dev Verifies proper state changes when RWAToken::burn is called.
    function test_rwaToken_burn() public {
        uint256 amount = 10;
        rwaToken.mintFor(address(veRWA), amount);

        // ~ Pre-state check ~

        assertEq(rwaToken.balanceOf(address(veRWA)), amount);
        assertEq(rwaToken.totalSupply(), amount);

        // ~ Admin executes burn ~

        vm.prank(address(veRWA));
        rwaToken.burn(amount);

        // ~ Post-state check ~

        assertEq(rwaToken.balanceOf(address(veRWA)), 0);
        assertEq(rwaToken.totalSupply(), 0);
    }

    /// @dev Verifies restrictions when RWAToken::burn is called with unaccepted args.
    function test_rwaToken_burn_restrictions() public {
        // Only owner can call
        vm.prank(JOE);
        vm.expectRevert(abi.encodeWithSelector(RWAToken.NotAuthorized.selector, JOE));
        rwaToken.burn(1);
    }

    /// @dev Verifies proper state changes when RWAToken::mint is called.
    function test_rwaToken_mint() public {
        uint256 amount = 10;

        // ~ Pre-state check ~

        assertEq(rwaToken.balanceOf(address(this)), 0);
        assertEq(rwaToken.totalSupply(), 0);

        // ~ Admin executes mint ~

        rwaToken.mint(amount);

        // ~ Post-state check ~

        assertEq(rwaToken.balanceOf(address(this)), amount);
        assertEq(rwaToken.totalSupply(), amount);
    }

    /// @dev Verifies restrictions when RWAToken::mint is called with unaccepted args.
    function test_rwaToken_mint_restrictions() public {
        // Only owner can call
        vm.prank(JOE);
        vm.expectRevert(abi.encodeWithSelector(RWAToken.NotAuthorized.selector, JOE));
        rwaToken.mint(1);

        // Cannot mint over max supply
        uint256 max = rwaToken.MAX_SUPPLY();
        vm.expectRevert(abi.encodeWithSelector(RWAToken.MaxSupplyExceeded.selector));
        rwaToken.mint(max + 1);
    }

    /// @dev Verifies proper state changes when RWAToken::mintFor is called.
    function test_rwaToken_mintFor() public {
        uint256 amount = 10;

        // ~ Pre-state check ~

        assertEq(rwaToken.balanceOf(JOE), 0);
        assertEq(rwaToken.totalSupply(), 0);

        // ~ Admin executes mintFor ~

        rwaToken.mintFor(JOE, amount);

        // ~ Post-state check ~

        assertEq(rwaToken.balanceOf(JOE), amount);
        assertEq(rwaToken.totalSupply(), amount);
    }

    /// @dev Verifies restrictions when RWAToken::mintFor is called with unaccepted args.
    function test_rwaToken_mintFor_restrictions() public {
        // Only owner can call
        vm.prank(JOE);
        vm.expectRevert(abi.encodeWithSelector(RWAToken.NotAuthorized.selector, JOE));
        rwaToken.mintFor(JOE, 1);
    } 
}