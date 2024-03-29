// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// foundry imports
import { Test, console2 } from "../lib/forge-std/src/Test.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

// local imports
import { RWAVotingEscrow } from "../src/governance/RWAVotingEscrow.sol";
import { VotingEscrowVesting } from "../src/governance/VotingEscrowVesting.sol";
import { RWAToken } from "../src/RWAToken.sol";
import { Marketplace } from "../src/Marketplace.sol";
import { VotingMath } from "../src/governance/VotingMath.sol";
import { RevenueDistributor } from "../src/RevenueDistributor.sol";
import { RevenueStream } from "../src/RevenueStream.sol";

// local helper imports
import "./utils/Utility.sol";
import "./utils/Constants.sol";

/**
 * @title MarketplaceTest
 * @author @chasebrownn
 * @notice This test file contains the basic unit testing for the Marketplace contract.
 */
contract MarketplaceTest is Utility {
    using VotingMath for uint256;

    // ~ Contracts ~

    RWAVotingEscrow public veRWA;
    VotingEscrowVesting public vesting;
    RWAToken public rwaToken;
    Marketplace public marketplace;
    RevenueDistributor public revDistributor;
    RevenueStream public revStream;

    // helper
    ERC20Mock public mockToken;

    // proxies
    ERC1967Proxy public veRWAProxy;
    ERC1967Proxy public vestingProxy;
    ERC1967Proxy public rwaTokenProxy;
    ERC1967Proxy public marketplaceProxy;
    ERC1967Proxy public revDistributorProxy;


    function setUp() public {

        // ~ Deploy Contracts ~

        // Deploy mock rev token
        mockToken = new ERC20Mock();

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

        // Deploy rev stream implementation
        revStream = new RevenueStream();

        // Deploy revDistributor contract
        revDistributor = new RevenueDistributor();

        // Deploy proxy for revDistributor
        revDistributorProxy = new ERC1967Proxy(
            address(revDistributor),
            abi.encodeWithSelector(RevenueDistributor.initialize.selector,
                ADMIN,
                address(revStream), // rev stream
                address(veRWA),
                address(0)
            )
        );
        revDistributor = RevenueDistributor(payable(address(revDistributorProxy)));

        // Deploy marketplace
        marketplace = new Marketplace();

        // Deploy Marketplace proxy
        marketplaceProxy = new ERC1967Proxy(
            address(marketplace),
            abi.encodeWithSelector(Marketplace.initialize.selector,
                address(rwaToken), // RWA for testing, but will be USTB
                address(veRWA),
                address(revDistributor),
                ADMIN
            )
        );
        marketplace = Marketplace(address(marketplaceProxy));

        // ~ Config ~

        // add RWA as payment token on marketplace
        vm.prank(ADMIN);
        marketplace.addPaymentToken(address(rwaToken));

        // set votingEscrow on vesting contract
        vm.prank(ADMIN);
        vesting.setVotingEscrowContract(address(veRWA));

        // Grant minter role to address(this) & veRWA
        vm.startPrank(ADMIN);
        rwaToken.setVotingEscrowRWA(address(veRWA));
        rwaToken.setReceiver(address(this)); // for testing
        vm.stopPrank();

        // Mint Joe $RWA tokens
        rwaToken.mintFor(JOE, 1_000 ether);
    }

    // -------
    // Utility
    // -------

    /// @dev Used to create a veRWA holder.
    function _createStakeholder(address actor, uint256 amountLock) internal returns (uint256 tokenId) {
        // Mint Joe more$RWA tokens
        rwaToken.mintFor(actor, amountLock);

        uint256 duration = (1 * 30 days);

        // mint Joe veRWA token
        vm.startPrank(actor);
        rwaToken.approve(address(veRWA), amountLock);
        tokenId = veRWA.mint(
            actor,
            uint208(amountLock),
            duration
        );
        vm.stopPrank();
    }


    // ------------------
    // Initial State Test
    // ------------------

    /// @notice Initial state test.
    function test_marketplace_init_state() public {}


    // ----------
    // Unit Tests
    // ----------

    /// @dev This unit test verifies proper state when Marketplace::listMarketItem is executed
    ///      while the msg.sender is the NFT owner.
    function test_marketplace_listMarketItem() public {

        // ~ Config ~

        uint256 preBal = veRWA.balanceOf(JOE);
        uint256 tokenId = _createStakeholder(JOE, 1_000 ether);

        uint256 itemTokenId;
        address itemSeller;
        address itemOwner;
        address itemPaymentToken;
        uint256 itemPrice;
        bool itemListed;

        // ~ Pre-state check ~

        assertEq(veRWA.balanceOf(JOE), preBal + 1);
        assertEq(veRWA.ownerOf(tokenId), JOE);

        (itemTokenId, itemSeller, itemOwner, itemPaymentToken, itemPrice, itemListed)
            = marketplace.idToMarketItem(tokenId);

        assertEq(itemTokenId, 0);
        assertEq(itemSeller, address(0));
        assertEq(itemOwner, address(0));
        assertEq(itemPaymentToken, address(0));
        assertEq(itemPrice, 0);
        assertEq(itemListed, false);

        // ~ Joe lists NFT ~

        vm.startPrank(JOE);
        veRWA.approve(address(marketplace), tokenId);
        marketplace.listMarketItem(tokenId, address(rwaToken), 100_000 ether);
        vm.stopPrank();

        // ~ Post-state check ~

        assertEq(veRWA.balanceOf(JOE), preBal);
        assertEq(veRWA.ownerOf(tokenId), address(marketplace));

        (itemTokenId, itemSeller, itemOwner, itemPaymentToken, itemPrice, itemListed)
            = marketplace.idToMarketItem(tokenId);

        assertEq(itemTokenId, tokenId);
        assertEq(itemSeller, JOE);
        assertEq(itemOwner, address(marketplace));
        assertEq(itemPaymentToken, address(rwaToken));
        assertEq(itemPrice, 100_000 ether);
        assertEq(itemListed, true);
    }

    /// @dev This unit test verifies proper state when Marketplace::listMarketItem is executed
    ///      while `tokenId` is laready listed resulting in an update, not a new listing.
    function test_marketplace_listMarketItem_update() public {

        // ~ Config ~

        uint256 tokenId = _createStakeholder(JOE, 1_000 ether);

        uint256 itemTokenId;
        address itemSeller;
        address itemOwner;
        address itemPaymentToken;
        uint256 itemPrice;
        bool itemListed;

        vm.startPrank(JOE);
        veRWA.approve(address(marketplace), tokenId);
        marketplace.listMarketItem(tokenId, address(rwaToken), 100_000 ether);
        vm.stopPrank();

        // ~ Pre-state check ~

        assertEq(veRWA.ownerOf(tokenId), address(marketplace));

        (itemTokenId, itemSeller, itemOwner, itemPaymentToken, itemPrice, itemListed)
            = marketplace.idToMarketItem(tokenId);

        assertEq(itemTokenId, tokenId);
        assertEq(itemSeller, JOE);
        assertEq(itemOwner, address(marketplace));
        assertEq(itemPaymentToken, address(rwaToken));
        assertEq(itemPrice, 100_000 ether);
        assertEq(itemListed, true);

        // ~ Joe updates listing ~

        vm.startPrank(JOE);
        marketplace.listMarketItem(tokenId, address(rwaToken), 200_000 ether);
        vm.stopPrank();

        // ~ Post-state check ~

        assertEq(veRWA.ownerOf(tokenId), address(marketplace));

        (itemTokenId, itemSeller, itemOwner, itemPaymentToken, itemPrice, itemListed)
            = marketplace.idToMarketItem(tokenId);

        assertEq(itemTokenId, tokenId);
        assertEq(itemSeller, JOE);
        assertEq(itemOwner, address(marketplace));
        assertEq(itemPaymentToken, address(rwaToken));
        assertEq(itemPrice, 200_000 ether);
        assertEq(itemListed, true);
    }

    function test_marketplace_delistMarketItem() public {}

    function test_marketplace_purchaseMarketItem_Erc20() public { // TODO Finish

        // ~ Config ~

        uint256 tokenId = _createStakeholder(JOE, 1_000 ether);

        uint256 price = 100_000 ether;

        uint256 itemTokenId;
        address itemSeller;
        address itemOwner;
        address itemPaymentToken;
        uint256 itemPrice;
        bool itemListed;

        vm.startPrank(JOE);
        veRWA.approve(address(marketplace), tokenId);
        marketplace.listMarketItem(tokenId, address(rwaToken), price);
        vm.stopPrank();

        rwaToken.mintFor(ALICE, price);

        // ~ Pre-state check ~

        assertEq(veRWA.ownerOf(tokenId), address(marketplace));
        assertEq(rwaToken.balanceOf(ALICE), price);

        (itemTokenId, itemSeller, itemOwner, itemPaymentToken, itemPrice, itemListed)
            = marketplace.idToMarketItem(tokenId);

        assertEq(itemTokenId, tokenId);
        assertEq(itemSeller, JOE);
        assertEq(itemOwner, address(marketplace));
        assertEq(itemPaymentToken, address(rwaToken));
        assertEq(itemPrice, price);
        assertEq(itemListed, true);

        // ~ Joe updates listing ~

        vm.startPrank(ALICE);
        rwaToken.approve(address(marketplace), price);
        marketplace.purchaseMarketItem(tokenId);
        vm.stopPrank();

        // ~ Post-state check ~

        assertEq(veRWA.ownerOf(tokenId), ALICE);
        assertEq(rwaToken.balanceOf(ALICE), 0);

        (,,,,,itemListed) = marketplace.idToMarketItem(tokenId);
        assertEq(itemListed, false);
    }

    
}