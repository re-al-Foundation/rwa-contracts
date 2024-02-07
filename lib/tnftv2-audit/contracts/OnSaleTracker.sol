// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "./interfaces/IOnSaleTracker.sol";

import "./abstract/FactoryModifiers.sol";

/**
 * @title OnSaleTracker
 * @author Veljko Mihailovic
 * @notice This contract tracks the status of TNFTs listed on the Marketplace
 */
contract OnSaleTracker is IOnSaleTracker, FactoryModifiers {
    // ~ State Variables ~

    struct TokenArray {
        uint256[] tokenIds;
    }

    struct ContractItem {
        bool selling;
        uint256 index;
    }

    struct TnftSaleItem {
        ITangibleNFT tnft;
        uint256 tokenId;
        uint256 indexInCurrentlySelling;
    }

    /// @notice Array of TangibleNFT categories that are being sold on the marketplace.
    ITangibleNFT[] public tnftCategoriesOnSale;

    /// @notice Used to map TNFT category to whether it has tokens for sale and where it exists in `tnftCategoriesOnSale`.
    mapping(ITangibleNFT => ContractItem) public isTnftOnSale;

    /// @notice Used to store an array of tokenIds that are listed on sale for each TNFT category.
    mapping(ITangibleNFT => uint256[]) public tnftTokensOnSale;

    /// @notice Used to track each TNFT item that's on sale and where it exists inside `tnftTokensOnSale[]`.
    mapping(ITangibleNFT => mapping(uint256 => TnftSaleItem)) public tnftSaleMapper;

    /// @notice Stores the address of the Marketplace contract.
    address public marketplace;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ~ Initializer ~
    /**
     * @notice Initialize OnSaleTracker
     */
    function initialize(address _factory) external initializer {
        __FactoryModifiers_init(_factory);
    }

    // ~ Functions ~

    /**
     * @notice This external function is used to update the status of any listings on the Marketplace contract.
     * @dev Only callable by `marketplace`.
     * @param tnft TangibleNFT contract reference -> TNFT contract the `tokenId` derives from.
     * @param tokenId TNFT identifier.
     * @param place If true, the TNFT is being listed for sale, otherwise false.
     */
    function tnftSalePlaced(ITangibleNFT tnft, uint256 tokenId, bool place) external override {
        require(msg.sender == marketplace);

        if (place) {
            //check if something from this category is on sale already
            require(tnft.ownerOf(tokenId) == marketplace, "TM not owner");
            if (!isTnftOnSale[tnft].selling) {
                //add category to actively selling list
                tnftCategoriesOnSale.push(tnft);
                isTnftOnSale[tnft].selling = true;
                isTnftOnSale[tnft].index = tnftCategoriesOnSale.length - 1;
            }
            //something is added to marketplace

            tnftTokensOnSale[tnft].push(tokenId);
            TnftSaleItem memory tsi = TnftSaleItem(
                tnft,
                tokenId,
                (tnftTokensOnSale[tnft].length - 1)
            );
            tnftSaleMapper[tnft][tokenId] = tsi;
        } else {
            //something is removed from marketplace
            uint256 indexInTokenSale = tnftSaleMapper[tnft][tokenId].indexInCurrentlySelling;
            _removeCurrentlySellingTnft(tnft, indexInTokenSale);
            delete tnftSaleMapper[tnft][tokenId];

            if (tnftTokensOnSale[tnft].length == 0) {
                //all tokens are removed, nothing in category is selling anymore
                _removeCategory(isTnftOnSale[tnft].index);
                delete isTnftOnSale[tnft];
            }
        }
    }

    //this function is not preserving order, and we don't care about it
    /**
     * @notice This internal function removes a token from `tnftTokensOnSale`.
     * @param tnft TangibleNft contract. From which category we're removing a token for.
     * @param index Index in the `tnftTokensOnSale` we're removing the token from.
     */
    function _removeCurrentlySellingTnft(ITangibleNFT tnft, uint256 index) internal {
        require(index < tnftTokensOnSale[tnft].length, "IndexT");

        //take last token
        uint256 tokenId = tnftTokensOnSale[tnft][tnftTokensOnSale[tnft].length - 1];

        //replace it with the one we are removing
        tnftTokensOnSale[tnft][index] = tokenId;
        //set it's new index in saleData
        tnftSaleMapper[tnft][tokenId].indexInCurrentlySelling = index;
        tnftTokensOnSale[tnft].pop();
    }

    /**
     * @notice This internal method removes a category from `tnftCategoriesOnSale`.
     * @param index Index of category in the array to remove.
     */
    function _removeCategory(uint256 index) internal {
        require(index < tnftCategoriesOnSale.length, "IndexC");

        //take last token
        ITangibleNFT _tnft = tnftCategoriesOnSale[tnftCategoriesOnSale.length - 1];

        //replace it with the one we are removing
        tnftCategoriesOnSale[index] = _tnft;
        //set it's new index in saleData
        isTnftOnSale[_tnft].index = index;
        tnftCategoriesOnSale.pop();
    }

    /**
     * @notice This restricted function allows the admin to update the `marketplace` state variable.
     * @param _marketplace Address of new Marketplace contract.
     */
    function setMarketplace(address _marketplace) external onlyFactoryOwner {
        marketplace = _marketplace;
    }

    /**
     * @notice This view function returns the TNFTs listed for sale from a specified category.
     * @param tnfts TangibleNFT contract reference -> Category identifier.
     * @return result Array of tokenIds that are listed for sale on the Marketplace.
     */
    function getTnftTokensOnSaleBatch(
        ITangibleNFT[] calldata tnfts
    ) external view returns (TokenArray[] memory result) {
        uint256 length = tnfts.length;
        result = new TokenArray[](length);

        for (uint256 i; i < length; ) {
            TokenArray memory temp = TokenArray(tnftTokensOnSale[tnfts[i]]);
            result[i] = temp;

            unchecked {
                ++i;
            }
        }
        return result;
    }

    /**
     * @notice This view method returns the size of the `tnftTokensOnSale` mapped array.
     * @param tnft TangibleNFT contract.
     * @return Length of array.
     */
    function tnftTokensOnSaleSize(ITangibleNFT tnft) external view returns (uint256) {
        return tnftTokensOnSale[tnft].length;
    }

    /**
     * @notice This function returns the `tnftCategoriesOnSale` array.
     * @return Array of type ITangibleNFT.
     */
    function getTnftCategoriesOnSale() external view returns (ITangibleNFT[] memory) {
        return tnftCategoriesOnSale;
    }

    /**
     * @notice This function returns the length of `tnftCategoriesOnSale` array.
     * @return Length of array.
     */
    function tnftCategoriesOnSaleSize() external view returns (uint256) {
        return tnftCategoriesOnSale.length;
    }

    /**
     * @notice This view method returns the `tnftTokensOnSale` mapped array.
     * @param tnft TangibleNFT contract.
     * @return Array of type uint26.
     */
    function getTnftTokensOnSale(ITangibleNFT tnft) external view returns (uint256[] memory) {
        return tnftTokensOnSale[tnft];
    }
}
