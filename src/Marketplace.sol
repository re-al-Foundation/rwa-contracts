// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

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

    RWAVotingEscrow public nftContract;
    IRouter public router;

    uint256 public fee;

    address public revDistributor;

    mapping(address => bool) public isPaymentToken; // TODO: Multiple payment tokens?
    mapping(uint256 => MarketItem) public idToMarketItem; // tokenId to listing object 
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

    event PaymentTokenAdded(address indexed paymentToken);

    event PaymentTokenRemoved(address indexed paymentToken);

    event FeeSet(uint256 newFee);

    event RevenueDistributorSet(address indexed newRevenueDistributor);

    // ------
    // Errors
    // ------

    error InvalidPaymentToken(address token);

    error InvalidTokenId(uint256 tokenId);

    error CallerIsNotOwnerOrSeller(address caller);

    error CallerIsNotSeller(address caller);

    error InsufficientETH(uint256 amountApproved, uint256 price);

    error LowLevelCallFailed(address recipient, uint256 amount);

    error SellerCantPurchaseToken(address seller, uint256 tokenId);


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
        address _initialPaymentToken,
        address _nftContractAddress, // veRWA
        address _revDist, // revenue distributor
        address _admin
    ) external initializer {
        _nftContractAddress.requireNonZeroAddress();
        _revDist.requireNonZeroAddress();
        _admin.requireNonZeroAddress();

        __UUPSUpgradeable_init();
        __Ownable_init(_admin);

        fee = 25; // 2.5%

        if (_initialPaymentToken != address(0)) {
            paymentTokens.push(_initialPaymentToken);
            isPaymentToken[_initialPaymentToken] = true;
        }
        nftContract = RWAVotingEscrow(_nftContractAddress);
        _listedItems = new Collection();
        revDistributor = _revDist;
    } 


    // ----------------
    // External Methods
    // ----------------

    /**
     * @notice This method allows a veRWA holder to list their NFT for sale at a specified price for a specific payment token.
     * @dev The paymentToken chosen must be supported by this contract. It's also important to mention, the marketplace
     * will set the remaining vesting duration of the veRWA token to 0 to stop all yields. The marketplace will not
     * receive any yield and neither will the seller while the token is listed on the marketplace. This is similar
     * to how the vesting contact works except the token's vesting schedule is not affected while the token is listed.
     * AKA the token's lock duration is NOT being vesting while it is listed for sale.
     * If the tokenId is already listed, the paymentToken and price can be used to update a current listing.
     * msg.sender must be the seller of the token to update listing info.
     *
     * @param tokenId Token identifier of veRWA token.
     * @param paymentToken ERC-20 payment method the seller prefers. If == address(0) it will default to ETH.
     * @param price Amount of paymentToken the buyer must pay in order to purchase the token being listed.
     *
     * @custom:error InvalidPaymentToken Thrown if paymentToken is not supported.
     * @custom:error CallerIsNotOwnerOrSeller Thrown if the msg.sender is not owner nor seller.
     * @custom:event MarketItemCreated If the token being listed is a new listing.
     * @custom:event MarketItemUpdated If the token is already listed and is being updated.
     */
    function listMarketItem(uint256 tokenId, address paymentToken, uint256 price) external nonReentrant {
        if (!isPaymentToken[paymentToken] && paymentToken != address(0)) revert InvalidPaymentToken(paymentToken);
        address owner = nftContract.ownerOf(tokenId);
        if (
            owner != msg.sender && // If caller is not owner
            (owner == address(this) && idToMarketItem[tokenId].seller != msg.sender) // and the listing isnt being updated
        ) revert CallerIsNotOwnerOrSeller(msg.sender);

        uint256 remainingVestingDuration;

        if (msg.sender == owner) { // new listing
            emit MarketItemCreated(tokenId, msg.sender, paymentToken, price);
            remainingVestingDuration = nftContract.getRemainingVestingDuration(tokenId);
            _listedItems.append(tokenId);

            nftContract.transferFrom(msg.sender, address(this), tokenId);
            // marketplace should not have voting power
            nftContract.updateVestingDuration(tokenId, 0);

        } else { // current listing is being updated
            emit MarketItemUpdated(tokenId, msg.sender, paymentToken, price);
            remainingVestingDuration = idToMarketItem[tokenId].remainingTime;
        }

        idToMarketItem[tokenId] = MarketItem(
            tokenId,
            msg.sender,
            paymentToken,
            price,
            remainingVestingDuration,
            true
        );
    }

    /**
     * @notice This method allows an extsing seller to delist their veRWA token from the marketplace.
     * @dev The veRWA token will be transferred back into the custody of the seller. The original remaining vesting duration
     * the veRWA token held prior to listing will be restored with the same value. Allowing the seller (and new owner of token)
     * to receive the same voting power they had prior to listing the token.
     *
     * @param tokenId Token identifier of veRWA token being delisted.
     *
     * @custom:error InvalidTokenId Thrown if tokenId is not listed.
     * @custom:error CallerIsNotOwnerOrSeller Thrown if the msg.sender is not seller.
     * @custom:event MarketItemDelisted Emitted if a tokenId was delisted.
     */
    function delistMarketItem(uint256 tokenId) external nonReentrant {
        MarketItem storage item = idToMarketItem[tokenId];
        address seller = item.seller;

        if (item.tokenId != tokenId || !item.listed) revert InvalidTokenId(tokenId);
        if (seller != msg.sender) revert CallerIsNotSeller(msg.sender);

        emit MarketItemDelisted(tokenId);
        _removeListing(item, tokenId, seller);
    }

    /**
     * @notice This method allows a buyer to purchase a token from the marketplace.
     * @dev The buyer will have to approve the specific price amount of paymentToken prior to purchasing the token.
     * If the idToMarketItem[tokenId].paymenToken == address(0) then the seller requires payment to be made in the form of ETH.
     * Once the token is successfully purchased, the token will be transferred to the custody of the buyer and the
     * voting power (vesting duration) of the token is restored, granting voting power to the buyer.
     * A tax is applied to the sale. By default this tax is 2.5%, but it is recommended you check what the current rate tax is
     * via Marketplace::fee. This fee is sent to the RevenueDistributor contract and later distributed to veRWA holders.
     * The rest of the payment is sent directly to the seller.
     *
     * @param tokenId Token identifier of veRWA token being purchased.
     *
     * @custom:error InvalidTokenId Thrown if tokenId is not listed.
     * @custom:error SellerCantPurchaseToken Thrown if buyer is the same as seller.
     * @custom:error InsufficientETH Thrown if amount of ETH is not sufficient for purchase.
     * @custom:error LowLevelCallFailed Thrown if the low level .call to transfer ETH has failed.
     * @custom:event MarketItemSold Emitted when the token sale has completed. Contains all sale info of token, seller, and buyer.
     */
    function purchaseMarketItem(uint256 tokenId) payable external nonReentrant {
        MarketItem storage item = idToMarketItem[tokenId];

        if (item.tokenId != tokenId || !item.listed) revert InvalidTokenId(tokenId);

        address buyer = msg.sender;
        uint256 price = item.price;
        address paymentToken = item.paymentToken;
        address seller = item.seller;

        if (seller == msg.sender) revert SellerCantPurchaseToken(msg.sender, tokenId);

        uint256 feeAmount;
        if (price != 0) {
            if (paymentToken == address(0)) { // ETH as payment
                if (msg.value != price) revert InsufficientETH(msg.value, price);

                feeAmount = (price * fee) / 1000;
                uint256 payout = price - feeAmount;
                
                bool sent;
                if (feeAmount != 0) {
                    (sent,) = revDistributor.call{value: feeAmount}("");
                    if (!sent) revert LowLevelCallFailed(revDistributor, feeAmount);
                }
                (sent,) = seller.call{value: payout}("");
                if (!sent) revert LowLevelCallFailed(seller, payout);

            } else { // ERC-20 as payment
                uint256 amountReceived = _pullTokens(buyer, paymentToken, price);

                feeAmount = (amountReceived * fee) / 1000;
                uint256 payout = amountReceived - feeAmount;
                
                if (feeAmount != 0) {
                    IERC20(paymentToken).safeTransfer(revDistributor, feeAmount);
                }
                IERC20(paymentToken).safeTransfer(seller, payout);
            }
        }

        emit MarketItemSold(tokenId, seller, buyer, paymentToken, price, feeAmount);
        _removeListing(item, tokenId, buyer);
    }

    /**
     * @notice This method allows the owner to add valid payment tokens.
     * @dev If a paymentToken is supported, a seller can request it as their preferred payment method when listing
     * a veRWA NFT on the marketplace.
     *
     * @param tokenAddress ERC-20 payment token to add.
     *
     * @custom:error InvalidZeroAddress Thrown if tokenAddress == addr(0)
     * @custom:error PaymentTokenAlreadyAdded Thrown if tokenAddress is already supported as a valid paymentToken.
     * @custom:event PaymentTokenAdded Token has been added as payment token.
     */
    function addPaymentToken(address tokenAddress) external onlyOwner {
        tokenAddress.requireNonZeroAddress();
        if (isPaymentToken[tokenAddress]) revert InvalidPaymentToken(tokenAddress);
        emit PaymentTokenAdded(tokenAddress);
        paymentTokens.push(tokenAddress);
        isPaymentToken[tokenAddress] = true;
    }

    /**
     * @notice This method allows the owner to remove valid payment tokens.
     *
     * @param tokenAddress ERC-20 payment token to remove.
     *
     * @custom:error InvalidZeroAddress Thrown if tokenAddress == addr(0)
     * @custom:error PaymentTokenAlreadyAdded Thrown if tokenAddress is not a valid paymentToken.
     * @custom:event PaymentTokenRemoved Token has been removed from payment tokens.
     */
    function removePaymentToken(address tokenAddress) external onlyOwner {
        tokenAddress.requireNonZeroAddress();
        if (!isPaymentToken[tokenAddress]) revert InvalidPaymentToken(tokenAddress);

        emit PaymentTokenRemoved(tokenAddress);
        delete isPaymentToken[tokenAddress];

        uint256 len = paymentTokens.length;
        for (uint256 i; i < len; ++i) {
            if (paymentTokens[i] == tokenAddress) {
                paymentTokens[i] = paymentTokens[len - 1];
                paymentTokens.pop();
            }
        }
    }

    /**
     * @dev Sets the TX fee that is applied to each purchase.
     *
     * @param fee_ New fee. Has 1 basis point (i.e. 25 == 2.5%).
     *
     * @custom:error ValueTooHigh `fee_` must be less than 100 (10%).
     * @custom:event FeeSet Emitted when the new fee has been set.
     */
    function setFee(uint256 fee_) external onlyOwner {
        fee_.requireLessThanOrEqualToUint256(100);
        emit FeeSet(fee_);
        fee = fee_;
    }

    /**
     * @dev Sets the address where TX fees are being sent to.
     *
     * @param revDistributor_ New Revenue Distributor address.
     *
     * @custom:error InvalidZeroAddress `revDistributor_` must not be equal to address(0).
     * @custom:error ValueUnchanged `revDistributor_` must not be equal to current Revenue Distributor.
     * @custom:event RevenueDistributorSet Emitted when the new address has been set as revDistributors.
     */
    function setRevDistributor(address revDistributor_) external onlyOwner {
        revDistributor_.requireNonZeroAddress();
        revDistributor_.requireDifferentAddress(revDistributor);
        emit RevenueDistributorSet(revDistributor_);
        revDistributor = revDistributor_;
    }

    /**
     * @dev Returns all valid payment tokens.
     */
    function getPaymentTokens() external view returns (address[] memory) {
        return paymentTokens;
    }

    /**
     * @dev Returns the market item for the provided id.
     */
    function getMarketItem(uint256 tokenId) external view returns (MarketItem memory) {
        return idToMarketItem[tokenId];
    }

    /**
     * @dev Returns a page of listed market items. Meant as UI helper.
     *
     * @param lastItemId Where to begin with page load.
     * @param pageSize Amount of elements to load in page.
     * @param ascending If true, will load items in ascending order from array.
     *
     * @return items -> Array of listed items returned based on filters provided. Will
     * return as MarketItem objects containing all data of listing.
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
        for (uint256 i; i < numItems; ++i) {
            items[i] = idToMarketItem[current.itemId];
            current = _listedItems.getNext(current, ascending);
        }
    }

    /**
     * @dev Returns a list of marktet items based on tokenIds provided.
     * @param itemIds TokenIds of market items being fetched.
     * @return items -> Array of listed items returned based on tokenIds provided. Will
     * return as MarketItem objects containing all data of each tokenId listing.
     */
    function fetchItems(uint256[] calldata itemIds)
        external
        view
        returns (MarketItem[] memory items)
    {
        uint256 len = itemIds.length;
        if (len > 0) {
            items = new MarketItem[](len);
            for (uint256 i; i < len; ++i) {
                items[i] = idToMarketItem[itemIds[i]];
            }
        }
    }


    // ---------------
    // Private Methods
    // ---------------

    /**
     * @dev Removes listing from contract. In the process will update token's vesting schedule back to normal,
     * transfer the token to the recipient's custody, and remove the listing from the contract's collection.
     * This method is only called if the item being removed is either purchased or delisted by the seller.
     *
     * @param item Item being removed from listing.
     * @param tokenId TokenId of item being removed.
     * @param recipient Address recipient of token.
     */
    function _removeListing(MarketItem storage item, uint256 tokenId, address recipient) internal {
        // restore vesting duration & transfer NFT to new owner
        nftContract.updateVestingDuration(tokenId, item.remainingTime);
        nftContract.safeTransferFrom(address(this), recipient, item.tokenId);

        delete idToMarketItem[tokenId];

        _listedItems.remove(tokenId);
    }

    /**
     * @dev This method will fetch items from the collection of listings and organize them based on input.
     *
     * @param collection Collection items are being fetched from.
     * @param lastItemId The last item being loaded previously.
     * @param ascending If true, load items in ascending order.
     * @param limit Number of items to return. If collection is large enough, will be equal to `numItems`.
     *
     * @return firstItem -> first item to load from collection in new page.
     * @return numItems -> Num of items to load. Takes into account firstItem.
     */
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
        for (uint256 i = limit; i > 0 && current.itemId != 0; --i) {
            numItems++;
            current = collection.getNext(current, ascending);
        }
    }


    // ----------------
    // Internal Methods
    // ----------------

    /**
     * @dev Transfers a specified amount of a supported asset from a user's address directly to this contract, adjusted
     * based on the redemption requirements. We assess the contract's balance before the transfer and after the transfer
     * to ensure the proper amount of tokens received is accounted. This comes in handy in the event a rebase rounding error
     * results in a slight deviation between amount transferred and the amount received.
     * @param user The address from which the asset will be pulled.
     * @param asset The address of the supported asset to be transferred.
     * @param amount The intended amount of the asset to transfer from the user. The function calculates the actual
     * transfer based on the asset’s pending redemption needs.
     * @return received The actual amount of the asset received to this contract, which may differ from
     * the intended amount due to transaction fees.
     */
    function _pullTokens(address user, address asset, uint256 amount)
        internal
        returns (uint256 received)
    {
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));
        IERC20(asset).safeTransferFrom(user, address(this), amount);
        received = IERC20(asset).balanceOf(address(this)) - balanceBefore;
    }

    /**
     * @notice Overriden from UUPSUpgradeable
     * @dev Restricts ability to upgrade contract to `DEFAULT_ADMIN_ROLE`
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
