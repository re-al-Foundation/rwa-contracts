// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IFactory.sol";

/// @title ITangibleMarketplace interface defines the interface of the Marketplace
interface ITangibleMarketplace is IVoucher {
    /**
     * @notice This struct is used to track a token's status when listed on the Marketplace
     * @param nft TangibleNFT contract reference identifier.
     * @param tokenId Nft token identifier.
     * @param sellder Original owner address.
     * @param price Selling price for token.
     * @param minted If true, minted for buyUnminted.
     * @param designatedBuyer If not zero address, only this address can buy.
     */
    struct Lot {
        ITangibleNFT nft;
        IERC20 paymentToken;
        uint256 tokenId;
        address seller;
        uint256 price;
        address designatedBuyer;
    }

    /// @dev The function allows anyone to put on sale the TangibleNFTs they own
    /// if price is 0 - use oracle price when someone buys
    function sellBatch(
        ITangibleNFT nft,
        IERC20 paymentToken,
        uint256[] calldata tokenIds,
        uint256[] calldata price,
        address designatedBuyer
    ) external;

    /// @dev The function allows the owner of the minted TangibleNFT items to remove them from the Marketplace
    function stopBatchSale(ITangibleNFT nft, uint256[] calldata tokenIds) external;

    /// @dev The function allows the user to buy any TangibleNFT
    /// from the Marketplace for payment token that seller wants
    function buy(ITangibleNFT nft, uint256 tokenId, uint256 _years) external;

    /// @dev The function allows the user to buy any TangibleNFT from the Marketplace
    /// for defaultUSD token if paymentToken is empty, only for unminted items
    function buyUnminted(
        ITangibleNFT nft,
        IERC20 paymentToken,
        uint256 _fingerprint,
        uint256 _years
    ) external returns (uint256 tokenId);

    /// @dev The function returns the address of the fee storage.
    function sellFeeAddress() external view returns (address);

    /// @dev The function which buys additional storage to token.
    function payStorage(
        ITangibleNFT nft,
        IERC20Metadata paymentToken,
        uint256 tokenId,
        uint256 _years
    ) external;

    function setDesignatedBuyer(
        ITangibleNFT nft,
        uint256 tokenId,
        address designatedBuyer
    ) external;
}

interface ITangibleMarketplaceExt is ITangibleMarketplace {
    function marketplaceLot(address tnft, uint256 tokenId) external view returns (Lot memory);
}
