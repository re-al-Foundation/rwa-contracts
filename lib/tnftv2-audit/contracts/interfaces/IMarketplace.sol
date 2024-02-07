// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

interface IMarketplace {
    struct MarketItem {
        uint256 tokenId;
        address seller;
        address owner;
        address paymentToken;
        uint256 price;
        bool listed;
    }

    function _idToMarketItem(uint256 tokenId) external view returns (MarketItem memory);
}
