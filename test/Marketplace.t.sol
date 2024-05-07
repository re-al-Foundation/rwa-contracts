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
import { RevenueStreamETH } from "../src/RevenueStreamETH.sol";
import { CommonErrors } from "../src/interfaces/CommonErrors.sol";

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
    RevenueStreamETH public revStream;

    // helper
    ERC20Mock public mockToken;

    // proxies
    ERC1967Proxy public veRWAProxy;
    ERC1967Proxy public vestingProxy;
    ERC1967Proxy public rwaTokenProxy;
    ERC1967Proxy public marketplaceProxy;
    ERC1967Proxy public revDistributorProxy;

    // global
    uint256 constant public newTokenDuration = 1 * 30 days;


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
        revStream = new RevenueStreamETH();

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

        // set votingEscrow on vesting contract
        vm.prank(ADMIN);
        vesting.setVotingEscrowContract(address(veRWA));

        // set marketplace address on veRWA
        vm.prank(ADMIN);
        veRWA.setMarketplace(address(marketplace));

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

        // mint Joe veRWA token
        vm.startPrank(actor);
        rwaToken.approve(address(veRWA), amountLock);
        tokenId = veRWA.mint(
            actor,
            uint208(amountLock),
            newTokenDuration
        );
        vm.stopPrank();
    }

    /// @dev This helper method handles creating a new shareholder (minting a new veRWA NFT) and listing
    /// the token on the marketplace. It also does all pre-state and post-state checks before and after the
    /// marketplace listing, respectively.
    function _createNewTokenAndList(address actor, uint256 amountLock, address paymentToken, uint256 price) internal returns (uint256 tokenId) {
        // ~ Config ~

        uint256 preBal = veRWA.balanceOf(actor);
        tokenId = _createStakeholder(actor, amountLock);

        uint256 itemTokenId;
        address itemSeller;
        address itemPaymentToken;
        uint256 itemPrice;
        uint256 remainingTime;
        bool itemListed;

        // ~ Pre-state check ~

        assertEq(veRWA.getRemainingVestingDuration(tokenId), newTokenDuration);

        assertEq(veRWA.balanceOf(actor), preBal + 1);
        assertEq(veRWA.ownerOf(tokenId), actor);

        (itemTokenId, itemSeller, itemPaymentToken, itemPrice, remainingTime, itemListed)
            = marketplace.idToMarketItem(tokenId);

        assertEq(itemTokenId, 0);
        assertEq(itemSeller, address(0));
        assertEq(itemPaymentToken, address(0));
        assertEq(itemPrice, 0);
        assertEq(remainingTime, 0);
        assertEq(itemListed, false);

        // ~ Joe lists NFT ~

        vm.startPrank(actor);
        veRWA.approve(address(marketplace), tokenId);
        marketplace.listMarketItem(tokenId, paymentToken, price);
        vm.stopPrank();

        // ~ Post-state check ~

        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);

        assertEq(veRWA.balanceOf(actor), preBal);
        assertEq(veRWA.ownerOf(tokenId), address(marketplace));

        (itemTokenId, itemSeller, itemPaymentToken, itemPrice, remainingTime, itemListed)
            = marketplace.idToMarketItem(tokenId);

        assertEq(itemTokenId, tokenId);
        assertEq(itemSeller, actor);
        assertEq(itemPaymentToken, paymentToken);
        assertEq(itemPrice, price);
        assertEq(remainingTime, newTokenDuration);
        assertEq(itemListed, true);
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
        _createNewTokenAndList(JOE, 1_000 ether, address(rwaToken), 100_000 ether);
    }

    /// @dev This unit test verifies restrictions when Marketplace::listMarketItem is executed
    ///      with unacceptable arguments.
    function test_marketplace_listMarketItem_restrictions() public {
        uint256 tokenId = _createStakeholder(JOE, 1_000 ether);

        // Cannot use a unsupported purchase token
        vm.startPrank(JOE);
        vm.expectRevert(abi.encodeWithSelector(Marketplace.InvalidPaymentToken.selector, address(mockToken)));
        marketplace.listMarketItem(tokenId, address(mockToken), 100_000 ether);
        vm.stopPrank();

        // However, you can list an item with address(0) for payment token -> requesting Ether as payment
        vm.startPrank(JOE);
        veRWA.approve(address(marketplace), tokenId);
        marketplace.listMarketItem(tokenId, address(0), 100_000 ether);
        vm.stopPrank();
    }

    /// @dev This unit test verifies proper state when Marketplace::listMarketItem is executed
    ///      while `tokenId` is laready listed resulting in an update, not a new listing.
    function test_marketplace_listMarketItem_update() public {
        // ~ Config ~

        uint256 tokenId = _createNewTokenAndList(JOE, 1_000 ether, address(rwaToken), 100_000 ether);

        uint256 itemTokenId;
        address itemSeller;
        address itemPaymentToken;
        uint256 itemPrice;
        uint256 remainingTime;
        bool itemListed;

        // ~ Pre-state check ~

        assertEq(veRWA.getRemainingVestingDuration(tokenId), 0);

        assertEq(veRWA.ownerOf(tokenId), address(marketplace));

        (itemTokenId, itemSeller, itemPaymentToken, itemPrice, remainingTime, itemListed)
            = marketplace.idToMarketItem(tokenId);

        assertEq(itemTokenId, tokenId);
        assertEq(itemSeller, JOE);
        assertEq(itemPaymentToken, address(rwaToken));
        assertEq(itemPrice, 100_000 ether);
        assertEq(remainingTime, newTokenDuration);
        assertEq(itemListed, true);

        // ~ Joe updates listing ~

        vm.startPrank(JOE);
        marketplace.listMarketItem(tokenId, address(rwaToken), 200_000 ether);
        vm.stopPrank();

        // ~ Post-state check ~

        assertEq(veRWA.ownerOf(tokenId), address(marketplace));

        (itemTokenId, itemSeller, itemPaymentToken, itemPrice, remainingTime, itemListed)
            = marketplace.idToMarketItem(tokenId);

        assertEq(itemTokenId, tokenId);
        assertEq(itemSeller, JOE);
        assertEq(itemPaymentToken, address(rwaToken));
        assertEq(itemPrice, 200_000 ether);
        assertEq(remainingTime, newTokenDuration);
        assertEq(itemListed, true);
    }

    /// @dev This unit test verifies restrictions when Marketplace::listMarketItem is executed
    ///      while `tokenId` is laready listed resulting in an update, not a new listing.
    function test_marketplace_listMarketItem_update_restrictions() public {
        uint256 tokenId = _createNewTokenAndList(JOE, 1_000 ether, address(rwaToken), 100_000 ether);

        // Alice cannot edit Joe's listing.
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(Marketplace.CallerIsNotOwnerOrSeller.selector, ALICE));
        marketplace.listMarketItem(tokenId, address(rwaToken), 200_000 ether);
        vm.stopPrank();

        // Only Joe can edit his listing.
        vm.startPrank(JOE);
        marketplace.listMarketItem(tokenId, address(rwaToken), 200_000 ether);
        vm.stopPrank();
    }

    /// @dev This unit test verifies proper state when Marketplace::delistMarketItem is executed.
    function test_marketplace_delistMarketItem() public {
        // ~ Config ~

        uint256 tokenId = _createNewTokenAndList(JOE, 1_000 ether, address(rwaToken), 100_000 ether);

        uint256 itemTokenId;
        address itemSeller;
        address itemPaymentToken;
        uint256 itemPrice;
        uint256 remainingTime;
        bool itemListed;

        Marketplace.MarketItem[] memory items;

        uint256 preBal = veRWA.balanceOf(JOE);
        uint256 preVotingPower = veRWA.getAccountVotingPower(JOE);

        // ~ Pre-state check ~

        items = marketplace.fetchMarketItems(0, 10, true);
        assertEq(items.length, 1);
        assertEq(items[0].tokenId, tokenId);

        // ~ Joe delists his token ~

        vm.prank(JOE);
        marketplace.delistMarketItem(tokenId);

        // ~ Post-state check ~

        items = marketplace.fetchMarketItems(0, 10, true);
        assertEq(items.length, 0);

        assertEq(veRWA.getRemainingVestingDuration(tokenId), newTokenDuration);

        assertEq(veRWA.balanceOf(JOE), preBal + 1);
        assertEq(veRWA.ownerOf(tokenId), JOE);

        (itemTokenId, itemSeller, itemPaymentToken, itemPrice, remainingTime, itemListed)
            = marketplace.idToMarketItem(tokenId);

        assertEq(itemTokenId, 0);
        assertEq(itemSeller, address(0));
        assertEq(itemPaymentToken, address(0));
        assertEq(itemPrice, 0);
        assertEq(remainingTime, 0);
        assertEq(itemListed, false);

        assertGt(veRWA.getAccountVotingPower(JOE), preVotingPower);

        // A token can be re-listed
        vm.startPrank(JOE);
        veRWA.approve(address(marketplace), tokenId);
        marketplace.listMarketItem(tokenId, address(rwaToken), 1);
        vm.stopPrank();
    }

    /// @dev This unit test verifies restrictions when Marketplace::delistMarketItem is executed
    ///      with unacceptable conditions.
    function test_marketplace_delistMarketItem_restrictions() public {
        uint256 tokenId = 1;

        vm.prank(JOE);
        vm.expectRevert(abi.encodeWithSelector(Marketplace.InvalidTokenId.selector, tokenId));
        marketplace.delistMarketItem(tokenId);

        tokenId = _createNewTokenAndList(JOE, 1_000 ether, address(rwaToken), 100_000 ether);

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(Marketplace.CallerIsNotSeller.selector, ALICE));
        marketplace.delistMarketItem(tokenId);
    }

    /// @dev This unit test verifies proper state changes when Marketplace::purchaseMarketItem is executed
    ///      when the seller's preferred payment token is an ERC-20 token.
    function test_marketplace_purchaseMarketItem_Erc20() public {
        // ~ Config ~

        uint256 price = 100_000 ether;
        uint256 tokenId = _createNewTokenAndList(JOE, 1_000 ether, address(rwaToken), price);

        address itemSeller;
        address itemPaymentToken;
        uint256 itemPrice;
        uint256 remainingTime;
        bool itemListed;

        Marketplace.MarketItem[] memory items;

        uint256 preVotingPower = veRWA.getAccountVotingPower(ALICE);
        uint256 preBalSeller = rwaToken.balanceOf(JOE);

        // mint RWA for Alice
        rwaToken.mintFor(ALICE, price);

        // ~ Pre-state check ~

        items = marketplace.fetchMarketItems(0, 10, true);
        assertEq(items.length, 1);
        assertEq(items[0].tokenId, tokenId);

        assertEq(rwaToken.balanceOf(ALICE), price);
        assertEq(rwaToken.balanceOf(address(revDistributor)), 0);
        assertEq(rwaToken.balanceOf(JOE), preBalSeller);
        assertEq(veRWA.ownerOf(tokenId), address(marketplace));
        assertEq(veRWA.balanceOf(ALICE), 0);

        // ~ Alice purchases token ~

        vm.startPrank(ALICE);
        rwaToken.approve(address(marketplace), price);
        marketplace.purchaseMarketItem(tokenId);
        vm.stopPrank();

        // ~ Post-state check ~

        items = marketplace.fetchMarketItems(0, 10, true);
        assertEq(items.length, 0);

        uint256 feeTaken = price * marketplace.fee() / 1000;
        uint256 amountToSeller = price - feeTaken;

        assertEq(rwaToken.balanceOf(ALICE), 0);
        assertEq(rwaToken.balanceOf(address(revDistributor)), feeTaken);
        assertEq(rwaToken.balanceOf(JOE), preBalSeller + amountToSeller);
        assertEq(veRWA.ownerOf(tokenId), ALICE);
        assertEq(veRWA.balanceOf(ALICE), 1);

        assertEq(veRWA.getRemainingVestingDuration(tokenId), newTokenDuration);

        (, itemSeller, itemPaymentToken, itemPrice, remainingTime, itemListed)
            = marketplace.idToMarketItem(tokenId);

        assertEq(itemSeller, address(0));
        assertEq(itemPaymentToken, address(0));
        assertEq(itemPrice, 0);
        assertEq(remainingTime, 0);
        assertEq(itemListed, false);

        assertGt(veRWA.getAccountVotingPower(ALICE), preVotingPower);
    }

    /// @dev This unit test verifies restrictions when Marketplace::purchaseMarketItem is executed.
    function test_marketplace_purchaseMarketItem_Erc20_restrictions() public {
        uint256 price = 100_000 ether;
        uint256 tokenId = _createNewTokenAndList(JOE, 1_000 ether, address(rwaToken), price);

        // cannot purchase a token with insufficient balance
        vm.startPrank(ALICE);
        rwaToken.approve(address(marketplace), price);
        vm.expectRevert();
        marketplace.purchaseMarketItem(tokenId);
        vm.stopPrank();

        // cannot purchase a token that is not listed
        vm.startPrank(ALICE);
        rwaToken.approve(address(marketplace), price);
        vm.expectRevert(abi.encodeWithSelector(Marketplace.InvalidTokenId.selector, tokenId+1));
        marketplace.purchaseMarketItem(tokenId+1);
        vm.stopPrank();

        // cannot purchase a token with insufficient balance
        vm.startPrank(JOE);
        rwaToken.approve(address(marketplace), price);
        vm.expectRevert(abi.encodeWithSelector(Marketplace.SellerCantPurchaseToken.selector, JOE, tokenId));
        marketplace.purchaseMarketItem(tokenId);
        vm.stopPrank();
    }

    /// @dev This unit test uses fuzzing to verify proper state changes when Marketplace::purchaseMarketItem
    ///      is executed when the seller's preferred payment token is an ERC-20 token.
    function test_marketplace_purchaseMarketItem_Erc20_fuzzing(uint256 price) public {
        price = bound(price, .000000001 * 1e18, 10_000_000 ether);

        // ~ Config ~

        uint256 tokenId = _createNewTokenAndList(JOE, 1_000 ether, address(rwaToken), price);

        address itemSeller;
        address itemPaymentToken;
        uint256 itemPrice;
        uint256 remainingTime;
        bool itemListed;

        uint256 preVotingPower = veRWA.getAccountVotingPower(ALICE);
        uint256 preBalSeller = rwaToken.balanceOf(JOE);

        // mint RWA for Alice
        rwaToken.mintFor(ALICE, price);

        // ~ Pre-state check ~

        assertEq(rwaToken.balanceOf(ALICE), price);
        assertEq(rwaToken.balanceOf(address(revDistributor)), 0);
        assertEq(rwaToken.balanceOf(JOE), preBalSeller);
        assertEq(veRWA.ownerOf(tokenId), address(marketplace));
        assertEq(veRWA.balanceOf(ALICE), 0);

        // ~ Alice purchases token ~

        vm.startPrank(ALICE);
        rwaToken.approve(address(marketplace), price);
        marketplace.purchaseMarketItem(tokenId);
        vm.stopPrank();

        // ~ Post-state check ~

        uint256 feeTaken = price * marketplace.fee() / 1000;
        uint256 amountToSeller = price - feeTaken;

        assertEq(rwaToken.balanceOf(ALICE), 0);
        assertEq(rwaToken.balanceOf(address(revDistributor)), feeTaken);
        assertEq(rwaToken.balanceOf(JOE), preBalSeller + amountToSeller);
        assertEq(veRWA.ownerOf(tokenId), ALICE);
        assertEq(veRWA.balanceOf(ALICE), 1);

        assertEq(veRWA.getRemainingVestingDuration(tokenId), newTokenDuration);

        (, itemSeller, itemPaymentToken, itemPrice, remainingTime, itemListed)
            = marketplace.idToMarketItem(tokenId);

        assertEq(itemSeller, address(0));
        assertEq(itemPaymentToken, address(0));
        assertEq(itemPrice, 0);
        assertEq(remainingTime, 0);
        assertEq(itemListed, false);

        assertGt(veRWA.getAccountVotingPower(ALICE), preVotingPower);
    }

    /// @dev This unit test verifies proper state changes when Marketplace::purchaseMarketItem is executed
    ///      when the seller's preferred payment token is ETH.
    function test_marketplace_purchaseMarketItem_ETH() public {
        // ~ Config ~

        uint256 price = 100_000 ether;
        uint256 tokenId = _createNewTokenAndList(JOE, 1_000 ether, address(0), price);

        address itemSeller;
        address itemPaymentToken;
        uint256 itemPrice;
        uint256 remainingTime;
        bool itemListed;

        uint256 preVotingPower = veRWA.getAccountVotingPower(ALICE);
        uint256 preBalSeller = JOE.balance;

        // mint ETH for Alice
        deal(ALICE, price);

        // ~ Pre-state check ~

        assertEq(ALICE.balance, price);
        assertEq(address(revDistributor).balance, 0);
        assertEq(JOE.balance, preBalSeller);
        assertEq(veRWA.ownerOf(tokenId), address(marketplace));
        assertEq(veRWA.balanceOf(ALICE), 0);

        // ~ Alice purchases token ~

        vm.startPrank(ALICE);
        marketplace.purchaseMarketItem{value:price}(tokenId);
        vm.stopPrank();

        // ~ Post-state check ~

        uint256 feeTaken = price * marketplace.fee() / 1000;
        uint256 amountToSeller = price - feeTaken;

        assertEq(ALICE.balance, 0);
        assertEq(address(revDistributor).balance, feeTaken);
        assertEq(JOE.balance, preBalSeller + amountToSeller);
        assertEq(veRWA.ownerOf(tokenId), ALICE);
        assertEq(veRWA.balanceOf(ALICE), 1);

        assertEq(veRWA.getRemainingVestingDuration(tokenId), newTokenDuration);

        (, itemSeller, itemPaymentToken, itemPrice, remainingTime, itemListed)
            = marketplace.idToMarketItem(tokenId);

        assertEq(itemSeller, address(0));
        assertEq(itemPaymentToken, address(0));
        assertEq(itemPrice, 0);
        assertEq(remainingTime, 0);
        assertEq(itemListed, false);

        assertGt(veRWA.getAccountVotingPower(ALICE), preVotingPower);
    }

    /// @dev This unit test verifies restrictions when Marketplace::purchaseMarketItem is executed.
    function test_marketplace_purchaseMarketItem_ETH_restrictions() public {
        uint256 price = 100_000 ether;
        uint256 tokenId = _createNewTokenAndList(JOE, 1_000 ether, address(0), price);

        // mint ETH for Alice
        deal(ALICE, price);

        // cannot purchase a token with insufficient balance
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(Marketplace.InsufficientETH.selector, 0, price));
        marketplace.purchaseMarketItem{value:0}(tokenId);
        vm.stopPrank();

        // cannot purchase a token that is not listed
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(Marketplace.InvalidTokenId.selector, tokenId+1));
        marketplace.purchaseMarketItem{value:price}(tokenId+1);
        vm.stopPrank();

        // mint ETH for Joe
        deal(JOE, price);

        // cannot purchase a token with insufficient balance
        vm.startPrank(JOE);
        vm.expectRevert(abi.encodeWithSelector(Marketplace.SellerCantPurchaseToken.selector, JOE, tokenId));
        marketplace.purchaseMarketItem{value:price}(tokenId);
        vm.stopPrank();
    }

    /// @dev This unit test uses fuzzing to verify proper state changes when Marketplace::purchaseMarketItem
    ///      is executed when the seller's preferred payment token is ETH.
    function test_marketplace_purchaseMarketItem_ETH_fuzzing(uint256 price) public {
        price = bound(price, .000000001 * 1e18, 10_000 ether);

        // ~ Config ~

        uint256 tokenId = _createNewTokenAndList(JOE, 1_000 ether, address(0), price);

        address itemSeller;
        address itemPaymentToken;
        uint256 itemPrice;
        uint256 remainingTime;
        bool itemListed;

        uint256 preVotingPower = veRWA.getAccountVotingPower(ALICE);
        uint256 preBalSeller = JOE.balance;

        // mint ETH for Alice
        deal(ALICE, price);

        // ~ Pre-state check ~

        assertEq(ALICE.balance, price);
        assertEq(address(revDistributor).balance, 0);
        assertEq(JOE.balance, preBalSeller);
        assertEq(veRWA.ownerOf(tokenId), address(marketplace));
        assertEq(veRWA.balanceOf(ALICE), 0);

        // ~ Alice purchases token ~

        vm.startPrank(ALICE);
        marketplace.purchaseMarketItem{value:price}(tokenId);
        vm.stopPrank();

        // ~ Post-state check ~

        uint256 feeTaken = price * marketplace.fee() / 1000;
        uint256 amountToSeller = price - feeTaken;

        assertEq(ALICE.balance, 0);
        assertEq(address(revDistributor).balance, feeTaken);
        assertEq(JOE.balance, preBalSeller + amountToSeller);
        assertEq(veRWA.ownerOf(tokenId), ALICE);
        assertEq(veRWA.balanceOf(ALICE), 1);

        assertEq(veRWA.getRemainingVestingDuration(tokenId), newTokenDuration);

        (, itemSeller, itemPaymentToken, itemPrice, remainingTime, itemListed)
            = marketplace.idToMarketItem(tokenId);

        assertEq(itemSeller, address(0));
        assertEq(itemPaymentToken, address(0));
        assertEq(itemPrice, 0);
        assertEq(remainingTime, 0);
        assertEq(itemListed, false);

        assertGt(veRWA.getAccountVotingPower(ALICE), preVotingPower);
    }

    /// @dev This unit test verifies proper read data when Marketplace::fetchMarketItems is called.
    function test_marketplace_fetchMarketItems_single() public {
        uint256 tokenId = _createNewTokenAndList(JOE, 1_000 ether, address(rwaToken), 100_000 ether);
        Marketplace.MarketItem[] memory items = marketplace.fetchMarketItems(0, 10, true);
        assertEq(items.length, 1);
        assertEq(items[0].tokenId, tokenId);
        assertEq(items[0].seller, JOE);
        assertEq(items[0].paymentToken, address(rwaToken));
        assertEq(items[0].price, 100_000 ether);
        assertEq(items[0].remainingTime, newTokenDuration);
        assertEq(items[0].listed, true);
    }

    /// @dev This unit test verifies proper read data when Marketplace::fetchMarketItems is called.
    function test_marketplace_fetchMarketItems_multiple() public {
        uint256 amount = 10;
        uint256[] memory tokenIds = new uint256[](amount);

        // create tokens and list
        for (uint256 i; i < amount; ++i) {
            tokenIds[i] = _createNewTokenAndList(JOE, 1_000 ether, address(rwaToken), 100_000 ether);
        }

        // fetch items
        Marketplace.MarketItem[] memory items = marketplace.fetchMarketItems(0, amount, true);
        assertEq(items.length, amount);

        // verify data
        for (uint256 i; i < amount; ++i) {
            assertEq(items[i].tokenId, tokenIds[i]);
            assertEq(items[i].seller, JOE);
            assertEq(items[i].paymentToken, address(rwaToken));
            assertEq(items[i].price, 100_000 ether);
            assertEq(items[i].remainingTime, newTokenDuration);
            assertEq(items[i].listed, true);
        }
    }

    /// @dev This unit test verifies proper state changes when Marketplace::addPaymentToken is executed.
    function test_marketplace_addPaymentToken() public {
        // ~ Pre-state check ~

        assertEq(marketplace.isPaymentToken(address(mockToken)), false);

        // ~ Add new token ~ 

        vm.prank(ADMIN);
        marketplace.addPaymentToken(address(mockToken));

        // ~ Post-state check ~

        assertEq(marketplace.isPaymentToken(address(mockToken)), true);
    }

    /// @dev This unit test verifies restrictions when Marketplace::addPaymentToken is executed
    ///      with unacceptable conditions.
    function test_marketplace_addPaymentToken_restrictions() public {
        // Only callable by owner.
        vm.prank(JOE);
        vm.expectRevert();
        marketplace.addPaymentToken(address(mockToken));

        // Cannot input address(0).
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.InvalidZeroAddress.selector));
        marketplace.addPaymentToken(address(0));

        // Cannot add token that's already added.
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(Marketplace.InvalidPaymentToken.selector, address(rwaToken)));
        marketplace.addPaymentToken(address(rwaToken));
    }

    /// @dev This unit test verifies proper state changes when Marketplace::removePaymentToken is executed.
    function test_marketplace_removePaymentToken() public {
        // ~ Pre-state check ~

        assertEq(marketplace.isPaymentToken(address(rwaToken)), true);

        // ~ remove payment token ~ 

        vm.prank(ADMIN);
        marketplace.removePaymentToken(address(rwaToken));

        // ~ Post-state check ~

        assertEq(marketplace.isPaymentToken(address(rwaToken)), false);
    }

    /// @dev This unit test verifies restrictions when Marketplace::removePaymentToken is executed
    ///      with unacceptable conditions.
    function test_marketplace_removePaymentToken_restrictions() public {
        // Only callable by owner.
        vm.prank(JOE);
        vm.expectRevert();
        marketplace.removePaymentToken(address(rwaToken));

        // Cannot input address(0).
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.InvalidZeroAddress.selector));
        marketplace.removePaymentToken(address(0));

        // Cannot remove a token that is not supported.
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(Marketplace.InvalidPaymentToken.selector, address(mockToken)));
        marketplace.removePaymentToken(address(mockToken));
    }

    function test_setFee() public {}

    function test_setFee_restrictions() public {}

    function test_setRevDistributor() public {}

    function test_setRevDistributor_restrictions() public {}
}