// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./NFTSwap.sol";
import "../Marketplace.sol";

contract NFTMigrator is Ownable {
    IERC20 private immutable tngbl;
    PassiveIncomeNFT private immutable oldNFT;
    PassiveIncomeNFT private immutable newNFT;
    Marketplace private immutable marketplace;

    mapping(uint256 => bool) private _migrated;

    constructor(
        address tngblAddress,
        address oldNftAddress,
        address newNftAddress,
        address marketplaceAddress
    ) {
        tngbl = IERC20(tngblAddress);
        oldNFT = PassiveIncomeNFT(oldNftAddress);
        newNFT = PassiveIncomeNFT(newNftAddress);
        marketplace = Marketplace(marketplaceAddress);
    }

    function migrate(uint256[] calldata tokenIds) external onlyOwner {
        uint256 len = tokenIds.length;
        for (uint256 i = 0; i < len; i++) {
            uint256 tokenId = tokenIds[i];
            if (!_migrated[tokenId]) {
                address owner = oldNFT.ownerOf(tokenId);
                if (owner == address(marketplace)) {
                    (, address seller, , , , ) = marketplace._idToMarketItem(
                        tokenId
                    );
                    owner = seller;
                }
                (
                    uint256 startTime,
                    uint256 endTime,
                    uint256 lockedAmount,
                    uint256 multiplier,
                    uint256 claimed,
                    uint256 maxPayout
                ) = oldNFT.locks(tokenId);
                uint8 lockDuration = uint8((endTime - startTime) / (30 days));
                newNFT.migrate(
                    owner,
                    lockedAmount,
                    multiplier,
                    lockDuration,
                    claimed,
                    maxPayout
                );
                _migrated[tokenId] = true;
            }
        }
    }
}
