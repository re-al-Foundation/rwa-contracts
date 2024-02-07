// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "./interfaces/IRouter.sol";
import "./utils/Collection.sol";
import "./utils/SafeCollection.sol";
import "./PassiveIncomeNFT.sol";

contract Marketplace is IMarketplace, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeCollection for Collection;
    using SafeCollection for mapping(address => Collection);

    struct MarketItem {
        uint256 tokenId;
        address seller;
        address owner;
        address paymentToken;
        uint256 price;
        bool listed;
    }

    IERC20 public immutable USDC;
    PassiveIncomeNFT public immutable nftContract;
    IRouter public immutable router;

    uint256 public fee = 0; // 0%

    address public feeCollector;

    mapping(address => bool) _isPaymentToken;
    mapping(uint256 => MarketItem) public _idToMarketItem;
    mapping(address => Collection) public _itemsByOwner;
    mapping(address => address[]) private _routerPaths;

    address[] private _paymentTokens;

    Collection private _listedItems;

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

    constructor(
        address usdcAddress,
        address nftContractAddress,
        address routerAddress
    ) {
        USDC = IERC20(usdcAddress);
        _paymentTokens.push(usdcAddress);
        _isPaymentToken[usdcAddress] = true;
        nftContract = PassiveIncomeNFT(nftContractAddress);
        _listedItems = new Collection();
        router = IRouter(routerAddress);
    }

    /**
     * @dev Sets the TX fee that is applied to each purchase.
     */
    function setFee(uint256 fee_) external onlyOwner {
        require(feeCollector != address(0), "fee collector not set");
        require(fee_ <= 10000, "invalid fee");
        fee = fee_;
    }

    /**
     * @dev Sets the address where TX fees are being sent to.
     */
    function setFeeCollector(address feeCollector_) external onlyOwner {
        require(
            feeCollector_ != address(0) || fee == 0,
            "invalid fee collector"
        );
        feeCollector = feeCollector_;
    }

    /**
     * @dev Adds a new token as payment option.
     */
    function addPaymentToken(address tokenAddress, address[] memory routerPath)
        external
        onlyOwner
    {
        require(
            (tokenAddress == address(USDC) && routerPath.length == 0) ||
                (tokenAddress != address(USDC) &&
                    routerPath[0] == tokenAddress &&
                    routerPath[routerPath.length - 1] == address(USDC)),
            "invalid route"
        );
        if (!_isPaymentToken[tokenAddress]) {
            _paymentTokens.push(tokenAddress);
            _isPaymentToken[tokenAddress] = true;
        }
        _routerPaths[tokenAddress] = routerPath;
    }

    /**
     * @dev Removes a token from payment options.
     */
    function removePaymentToken(address tokenAddress) external onlyOwner {
        require(tokenAddress != address(USDC));
        delete _isPaymentToken[tokenAddress];
        delete _routerPaths[tokenAddress];
        uint256 len = _paymentTokens.length;
        bool shift;
        for (uint256 i = 0; i < len; i++) {
            if (shift) {
                _paymentTokens[i - 1] = _paymentTokens[i];
            } else if (_paymentTokens[i] == tokenAddress) {
                shift = true;
            }
        }
        if (shift) _paymentTokens.pop();
    }

    /**
     * @dev Returns all valid payment tokens.
     */
    function getPaymentTokens() external view returns (address[] memory) {
        return _paymentTokens;
    }

    /**
     * @dev Returns the swap route for the given token.
     */
    function getSwapRoute(address tokenAddress)
        external
        view
        returns (address[] memory)
    {
        return _routerPaths[tokenAddress];
    }

    /**
     * @dev Lists an item for sale on the marketplace.
     * The item itself will be transferred to the marketplace.
     */
    function listMarketItem(
        uint256 tokenId,
        address paymentToken,
        uint256 price
    ) external nonReentrant {
        require(_isPaymentToken[paymentToken], "invalid payment token");
        address seller = msg.sender;
        address owner = nftContract.ownerOf(tokenId);
        require(
            owner == seller ||
                (owner == address(this) &&
                    _idToMarketItem[tokenId].seller == seller),
            "caller is not the owner"
        );

        _idToMarketItem[tokenId] = MarketItem(
            tokenId,
            seller,
            address(this),
            paymentToken,
            price,
            true
        );

        if (seller == owner) {
            nftContract.transferFrom(seller, address(this), tokenId);
            emit MarketItemCreated(tokenId, seller, paymentToken, price);
        } else {
            emit MarketItemUpdated(tokenId, seller, paymentToken, price);
        }
    }

    /**
     * @dev Delists an item from the marketplace.
     * The item itself will be transferred back to the seller.
     */
    function delistMarketItem(uint256 tokenId) external nonReentrant {
        MarketItem storage item = _idToMarketItem[tokenId];

        address seller = item.seller;

        require(item.tokenId == tokenId, "unlisted token");
        require(seller == msg.sender, "caller is not the seller");

        nftContract.transferFrom(address(this), seller, tokenId);

        item.seller = address(0);
        item.owner = seller;
        item.listed = false;

        emit MarketItemDelisted(tokenId);
    }

    /**
     * @dev Sells the market item.
     * Funds will be transferred to the seller.
     * The ownership of the item will be transferred to the buyer.
     */
    function purchaseMarketItem(uint256 tokenId) external nonReentrant {
        MarketItem storage item = _idToMarketItem[tokenId];

        require(item.tokenId == tokenId && item.listed, "invalid item");

        address buyer = msg.sender;
        uint256 price = item.price;
        uint256 feeAmount;

        if (price > 0) {
            IERC20 paymentToken = IERC20(item.paymentToken);
            paymentToken.safeTransferFrom(buyer, address(this), price);
            address[] storage path = _routerPaths[item.paymentToken];
            feeAmount = (price * fee) / 10000;
            uint256 payout = price - feeAmount;
            if (fee > 0 && path.length > 0) {
                paymentToken.approve(address(router), feeAmount);
                uint256[] memory amounts = router.swapExactTokensForTokens(
                    feeAmount,
                    0,
                    path,
                    address(this),
                    block.timestamp
                );
                feeAmount = amounts[amounts.length - 1];
            }
            if (feeAmount > 0) {
                paymentToken.transfer(feeCollector, feeAmount);
            }
            paymentToken.transfer(item.seller, payout);
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
     * @dev Called by NFT contract after a token was burned.
     */
    function afterBurnToken(uint256 tokenId) external override {
        require(_isBurned(tokenId), "token is not burned");
        delete _idToMarketItem[tokenId];
    }

    /**
     * @dev Returns the market item for the provided id.
     */
    function getMarketItem(uint256 itemId)
        external
        view
        returns (MarketItem memory)
    {
        return _idToMarketItem[itemId];
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
            items[i] = _idToMarketItem[current.itemId];
            current = _listedItems.getNext(current, ascending);
        }
    }

    /**
     * @dev Returns a page of listed market items.
     */
    function fetchItemsByOwner(
        address owner,
        uint256 lastItemId,
        uint256 pageSize,
        bool ascending
    ) public view returns (MarketItem[] memory items) {
        Collection collection = _itemsByOwner[owner];
        if (address(collection) != address(0)) {
            (
                Collection.Item memory first,
                uint256 numItems
            ) = _countRemainingItems(
                    collection,
                    lastItemId,
                    ascending,
                    pageSize
                );
            items = new MarketItem[](numItems);
            Collection.Item memory current = first;
            for (uint256 i = 0; i < numItems; i++) {
                items[i] = _idToMarketItem[current.itemId];
                current = collection.getNext(current, ascending);
            }
        }
    }

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
                items[i] = _idToMarketItem[itemIds[i]];
            }
        }
    }

    /**
     * @dev Returns the total value for all items of the given owner.
     */
    function totalValueByOwner(address owner)
        external
        view
        returns (uint256 totalValue, uint256 freeClaimable)
    {
        uint256 numTokens = nftContract.balanceOf(owner);
        for (uint256 i = 0; i < numTokens; i++) {
            uint256 tokenId = nftContract.tokenOfOwnerByIndex(owner, i);
            (
                ,
                ,
                uint256 lockedAmount,
                ,
                uint256 claimed,
                uint256 maxPayout
            ) = nftContract.locks(tokenId);
            totalValue += lockedAmount + maxPayout - claimed;
            (uint256 free, ) = nftContract.claimableIncome(tokenId);
            freeClaimable += free;
        }
    }

    function updateTokenOwner(
        uint256 tokenId,
        address from,
        address to
    ) external override {
        require(
            msg.sender == address(nftContract),
            "caller is not the NFT contract"
        );
        if (from != address(0)) {
            _itemsByOwner[from].safeRemove(tokenId);
        }
        if (to != address(0)) {
            _itemsByOwner.safeAdd(to, tokenId);
        }
    }

    function _countRemainingItems(
        Collection collection,
        uint256 lastItemId,
        bool ascending,
        uint256 limit
    )
        private
        view
        returns (Collection.Item memory firstItem, uint256 numItems)
    {
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
}
