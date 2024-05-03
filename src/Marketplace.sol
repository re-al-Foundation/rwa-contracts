// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

// oz imports
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// oz upgradeable imports
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// local imports
import { RWAVotingEscrow } from "./governance/RWAVotingEscrow.sol";
import { CommonErrors } from "./interfaces/CommonErrors.sol";
import { CommonValidations } from "./libraries/CommonValidations.sol";
import "./interfaces/IRouter.sol";
import "./utils/Collection.sol";
import "./utils/SafeCollection.sol";

/**
 * @title Marketplace
 * @author @chasebrownn
 * @notice This marketplace contract facilitates the listing and purchase of RWAVotingEscrow Tokens.
 */
contract Marketplace is OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using SafeCollection for Collection;
    using SafeCollection for mapping(address => Collection);
    using CommonValidations for *;

    // ---------------
    // State Variables
    // ---------------

    struct MarketItem {
        uint256 tokenId;
        address seller;
        address paymentToken;
        uint256 price;
        uint256 remainingTime;
        bool listed;
    }

    //IERC20 public USDC;
    RWAVotingEscrow public nftContract;
    IRouter public router;

    uint256 public fee;

    address public revDistributor; // TODO: RevDistributor?

    mapping(address => bool) public isPaymentToken; // TODO: Multiple payment tokens?
    mapping(uint256 => MarketItem) public idToMarketItem;
    //mapping(address => Collection) public _itemsByOwner;
    mapping(address => address[]) private _routerPaths;

    address[] public paymentTokens;

    Collection private _listedItems;


    // ------
    // Events
    // ------

    event MarketItemCreated(
        uint256 indexed tokenId,
        address indexed seller,
        address paymentToken,
        uint256 price
    );

    event MarketItemUpdated(
        uint256 indexed tokenId,
        address indexed seller,
        address paymentToken,
        uint256 price
    );

    event MarketItemSold(
        uint256 indexed tokenId,
        address indexed seller,
        address indexed buyer,
        address paymentToken,
        uint256 price,
        uint256 feeAmount
    );

    event MarketItemDelisted(uint256 indexed tokenId);

    // ------
    // Errors
    // ------

    error InvalidPaymentToken(address token);

    error InvalidTokenId(uint256 tokenId);

    error CallerIsNotOwner(address caller);

    error CallerIsNotSeller(address caller);


    // -----------
    // Constructor
    // -----------

    constructor() {
        _disableInitializers();
    }


    // -----------
    // Initializer
    // -----------

    function initialize(
        address _usdcAddress, // TODO: Are we still using USDC?
        address _nftContractAddress, // veRWA
        address _revDist, // revenue distributor
        address _admin
    ) external initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(_admin);

        fee = 25; // 2.5%

        //USDC = IERC20(_usdcAddress);
        paymentTokens.push(_usdcAddress);
        isPaymentToken[_usdcAddress] = true;
        nftContract = RWAVotingEscrow(_nftContractAddress);
        _listedItems = new Collection();
        revDistributor = _revDist;

    } 


    // ----------------
    // External Methods
    // ----------------

    /**
     * @dev Lists an item for sale on the marketplace.
     * The item itself will be transferred to the marketplace.
     */
    function listMarketItem(uint256 tokenId, address paymentToken, uint256 price) external nonReentrant {
        if (!isPaymentToken[paymentToken] && paymentToken == address(0)) revert InvalidPaymentToken(paymentToken);
        address owner = nftContract.ownerOf(tokenId);
        if (
            owner != msg.sender && // If caller is not owner
            (owner == address(this) && idToMarketItem[tokenId].seller != msg.sender) // and the listing isnt being updated
        ) revert CallerIsNotOwner(msg.sender);

        idToMarketItem[tokenId] = MarketItem(
            tokenId,
            msg.sender,
            paymentToken,
            price,
            nftContract.getRemainingVestingDuration(tokenId),
            true
        );

        if (msg.sender == owner) {
            nftContract.transferFrom(msg.sender, address(this), tokenId);
            nftContract.updateVestingDuration(tokenId, 0); // marketplace should not have voting power
            emit MarketItemCreated(tokenId, msg.sender, paymentToken, price);
        } else {
            emit MarketItemUpdated(tokenId, msg.sender, paymentToken, price);
        }
    }

    /**
     * @dev Delists an item from the marketplace.
     * The item itself will be transferred back to the seller.
     */
    function delistMarketItem(uint256 tokenId) external nonReentrant {
        MarketItem storage item = idToMarketItem[tokenId];

        address seller = item.seller;

        require(seller == msg.sender, "caller is not the seller");

        if (item.tokenId != tokenId) revert InvalidTokenId(tokenId);
        if (seller != msg.sender) revert CallerIsNotSeller(msg.sender);

        nftContract.updateVestingDuration(tokenId, item.remainingTime);
        nftContract.transferFrom(address(this), msg.sender, tokenId);

        item.seller = address(0);
        item.listed = false;

        emit MarketItemDelisted(tokenId);
    }

    /**
     * @dev Sells the market item.
     * Funds will be transferred to the seller.
     * The ownership of the item will be transferred to the buyer.
     */
    function purchaseMarketItem(uint256 tokenId) payable external nonReentrant {
        MarketItem storage item = idToMarketItem[tokenId];

        require(item.tokenId == tokenId && item.listed, "invalid item");

        address buyer = msg.sender;
        uint256 price = item.price;
        address paymentToken = item.paymentToken;
        uint256 feeAmount;

        if (price > 0) {
            if (paymentToken == address(0)) { // ETH
                require(msg.value == price, "Insufficient amount");

                feeAmount = (price * fee) / 1000; // TODO test: Should result in 2.5% penalty 
                uint256 payout = price - feeAmount;
                
                if (feeAmount > 0) {
                    (bool sent,) = revDistributor.call{value: feeAmount}("");
                    require(sent, "Failed to send ETH to rev distributor");
                }
                (bool sent,) = item.seller.call{value: payout}("");
                require(sent, "Failed to send ETH to seller");

            } else { // ERC-20 payment token
                IERC20(paymentToken).safeTransferFrom(buyer, address(this), price);

                feeAmount = (price * fee) / 1000; // TODO test: Should result in 2.5% penalty 
                uint256 payout = price - feeAmount;
                
                if (feeAmount > 0) {
                    IERC20(paymentToken).safeTransfer(revDistributor, feeAmount);
                }
                IERC20(paymentToken).safeTransfer(item.seller, payout);
            }
        }

        // transfer NFT to new owner
        nftContract.safeTransferFrom(address(this), buyer, item.tokenId);

        item.listed = false;

        emit MarketItemSold(
            item.tokenId,
            item.seller,
            buyer,
            item.paymentToken,
            item.price,
            feeAmount
        );
    }

    /**
     * @dev Adds a new token as payment option.
     */
    function addPaymentToken(address tokenAddress) external onlyOwner {
        // require(
        //     (tokenAddress == address(USDC) && routerPath.length == 0) ||
        //         (tokenAddress != address(USDC) &&
        //             routerPath[0] == tokenAddress &&
        //             routerPath[routerPath.length - 1] == address(USDC)),
        //     "invalid route"
        // );
        if (!isPaymentToken[tokenAddress]) {
            paymentTokens.push(tokenAddress);
            isPaymentToken[tokenAddress] = true;
        }
        //_routerPaths[tokenAddress] = routerPath;
    }

    /**
     * @dev Removes a token from payment options.
     */
    function removePaymentToken(address tokenAddress) external onlyOwner {
        require(isPaymentToken[tokenAddress], "payment token does not exist");
        delete isPaymentToken[tokenAddress];

        uint256 len = paymentTokens.length;
        for (uint256 i; i < len;) {
            if (paymentTokens[i] == tokenAddress) {
                paymentTokens[i] = paymentTokens[len - 1];
                paymentTokens.pop();
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Sets the TX fee that is applied to each purchase.
     */
    function setFee(uint256 fee_) external onlyOwner {
        require(revDistributor != address(0), "fee collector not set");
        require(fee_ <= 10000, "invalid fee");
        fee = fee_;
    }

    /**
     * @dev Sets the address where TX fees are being sent to.
     */
    function setRevDistributor(address revDistributor_) external onlyOwner {
        require(
            revDistributor_ != address(0) || fee == 0,
            "invalid fee collector"
        );
        revDistributor = revDistributor_;
    }

    /**
     * @dev Called by NFT contract after a token was burned.
     */
    function afterBurnToken(uint256 tokenId) external { // TODO: call from veRWA post-burn
        require(_isBurned(tokenId), "token is not burned");
        delete idToMarketItem[tokenId];
    }

    /**
     * @dev Returns the swap route for the given token.
     */
    // function getSwapRoute(address tokenAddress) external view returns (address[] memory) {
    //     return _routerPaths[tokenAddress];
    // }

    /**
     * @dev Returns all valid payment tokens.
     */
    function getPaymentTokens() external view returns (address[] memory) {
        return paymentTokens;
    }

    /**
     * @dev Returns the market item for the provided id.
     */
    function getMarketItem(uint256 itemId) external view returns (MarketItem memory) {
        return idToMarketItem[itemId];
    }

    /**
     * @dev Returns a page of listed market items.
     */
    function fetchMarketItems(
        uint256 lastItemId,
        uint256 pageSize,
        bool ascending
    ) external view returns (MarketItem[] memory items) {
        (Collection.Item memory first, uint256 numItems) = _countRemainingItems(
            _listedItems,
            lastItemId,
            ascending,
            pageSize
        );
        items = new MarketItem[](numItems);
        Collection.Item memory current = first;
        for (uint256 i = 0; i < numItems; i++) {
            items[i] = idToMarketItem[current.itemId];
            current = _listedItems.getNext(current, ascending);
        }
    }

    /**
     * @dev Returns the total value for all items of the given owner.
     */
    function totalValueByOwner(address owner) external view returns (uint256 totalValue, uint256 freeClaimable) {
        uint256 numTokens = nftContract.balanceOf(owner);
        for (uint256 i = 0; i < numTokens; i++) {
            uint256 tokenId = nftContract.tokenOfOwnerByIndex(owner, i);
            totalValue += nftContract.getLockedAmount(tokenId);
            // (uint256 free, ) = nftContract.claimableIncome(tokenId);
            // freeClaimable += free; TODO Rework
        }
    }

    // function updateTokenOwner(uint256 tokenId, address from, address to) external {
    //     require(
    //         msg.sender == address(nftContract),
    //         "caller is not the NFT contract"
    //     );
    //     if (from != address(0)) {
    //         _itemsByOwner[from].safeRemove(tokenId);
    //     }
    //     if (to != address(0)) {
    //         _itemsByOwner.safeAdd(to, tokenId);
    //     }
    // }


    // --------------
    // Public Methods
    // --------------

    // /**
    //  * @dev Returns a page of listed market items.
    //  */
    // function fetchItemsByOwner(
    //     address owner,
    //     uint256 lastItemId,
    //     uint256 pageSize,
    //     bool ascending
    // ) public view returns (MarketItem[] memory items) {
    //     Collection collection = _itemsByOwner[owner];
    //     if (address(collection) != address(0)) {
    //         (
    //             Collection.Item memory first,
    //             uint256 numItems
    //         ) = _countRemainingItems(
    //                 collection,
    //                 lastItemId,
    //                 ascending,
    //                 pageSize
    //             );
    //         items = new MarketItem[](numItems);
    //         Collection.Item memory current = first;
    //         for (uint256 i = 0; i < numItems; i++) {
    //             items[i] = idToMarketItem[current.itemId];
    //             current = collection.getNext(current, ascending);
    //         }
    //     }
    // }

    /**
     * @dev Returns a list of items.
     */
    function fetchItems(uint256[] calldata itemIds)
        public
        view
        returns (MarketItem[] memory items)
    {
        uint256 len = itemIds.length;
        if (len > 0) {
            items = new MarketItem[](len);
            for (uint256 i = 0; i < len; i++) {
                items[i] = idToMarketItem[itemIds[i]];
            }
        }
    }


    // ---------------
    // Private Methods
    // ---------------

    function _countRemainingItems(
        Collection collection,
        uint256 lastItemId,
        bool ascending,
        uint256 limit
    ) private view returns (Collection.Item memory firstItem, uint256 numItems) {
        firstItem = lastItemId == 0
            ? collection.first(ascending)
            : collection.getNext(collection.get(lastItemId), ascending);
        Collection.Item memory current = firstItem;
        for (uint256 i = limit; i > 0 && current.itemId != 0; i--) {
            numItems++;
            current = collection.getNext(current, ascending);
        }
    }

    function _isBurned(uint256 tokenId) private view returns (bool) {
        try IERC721(nftContract).ownerOf(tokenId) returns (address owner) {
            return owner == address(0);
        } catch {
            return true;
        }
    }


    // ---------------
    // Internal Methods
    // ---------------

    /**
     * @notice Overriden from UUPSUpgradeable
     * @dev Restricts ability to upgrade contract to `DEFAULT_ADMIN_ROLE`
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
