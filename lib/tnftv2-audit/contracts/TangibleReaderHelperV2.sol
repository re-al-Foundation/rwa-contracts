// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "./interfaces/IFactory.sol";
import "./interfaces/ITangibleMarketplace.sol";
import "./interfaces/IMarketplace.sol";
import "./interfaces/IPassiveIncomeNFT.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TangibleReaderHelper
 * @author Veljko Mihailovic
 * @notice This contract allows for batch reads to several Tangible contracts for various purposes.
 */
contract TangibleReaderHelperV2 {
    // ~ State Variables ~

    /// @notice Stores a reference to the Factory contract.
    IFactory public factory;

    /// @notice Stores a reference to the passiveNFT contract.
    IPassiveIncomeNFT public passiveNft;

    /// @notice Stores a reference to the revenueShare contract.
    RevenueShare public revenueShare;

    // ~ Constructor ~

    /**
     * @notice Initializes TangibleReaderHelper
     * @param _factory Factory contract reference.
     * @param _passiveNft PassiveNFT contract reference.
     * @param _revenueShare RevenueShare contract reference.
     */
    constructor(IFactory _factory, IPassiveIncomeNFT _passiveNft, RevenueShare _revenueShare) {
        require(address(_factory) != address(0), "FP 0");
        factory = _factory;
        passiveNft = _passiveNft;
        revenueShare = _revenueShare;
    }

    // ~ Functions ~

    /**
     * @notice This method fetches a batch of lock data given an array of `tokenIds`.
     * @param tokenIds Array of token identifiers.
     * @return locksBatch -> Array of Lock data for each tokenId provided.
     */
    function getLocksBatch(
        uint256[] calldata tokenIds
    ) external view returns (IPassiveIncomeNFT.Lock[] memory locksBatch) {
        uint256 length = tokenIds.length;
        locksBatch = new IPassiveIncomeNFT.Lock[](length);

        for (uint256 i; i < length; ) {
            locksBatch[i] = passiveNft.locks(tokenIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice This method is used to fetch a batch of rev shares for each tokenId provided.
     * @param tokenIds Array of tokenIds.
     * @param fromAddress TangibleNFT contract. TODO: Verify
     * @return sharesBatch -> Array of shares
     * @return totalShare -> Total shares.
     */
    function getSharesBatch(
        uint256[] calldata tokenIds,
        address fromAddress
    ) external view returns (int256[] memory sharesBatch, uint256 totalShare) {
        uint256 length = tokenIds.length;
        sharesBatch = new int256[](length);

        totalShare = revenueShare.total();

        for (uint256 i; i < length; ) {
            sharesBatch[i] = revenueShare.share(abi.encodePacked(fromAddress, tokenIds[i]));
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice This method returns MarketItem data for each tokenId provided.
     * @param tokenIds Array of token identifiers
     * @return marketItems -> Array of MarketItem objects for each tokenId provided.
     */
    function getPiNFTMarketItemBatch(
        uint256[] calldata tokenIds
    ) external view returns (IMarketplace.MarketItem[] memory marketItems) {
        uint256 length = tokenIds.length;
        marketItems = new IMarketplace.MarketItem[](length);
        IMarketplace piMarketplace = passiveNft.marketplace();

        for (uint256 i; i < length; ) {
            marketItems[i] = piMarketplace._idToMarketItem(tokenIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice This function takes an array of `tokenIds` and fetches the array of owners.
     * @param tokenIds Array of tokenIds to query owners of.
     * @param contractAddress NFT contract we wish to query token ownership of.
     * @return owners -> Array of owners. Indexes correspond with the indexes of tokenIds.
     */
    function ownersOBatch(
        uint256[] calldata tokenIds,
        address contractAddress
    ) external view returns (address[] memory owners) {
        uint256 length = tokenIds.length;
        owners = new address[](length);

        for (uint256 i; i < length; ) {
            owners[i] = IERC721(contractAddress).ownerOf(tokenIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice This function takes an array of `tokenIds` and fetches the corresponding fingerprints.
     * @param tokenIds Array of tokenIds to query fingerprints for.
     * @param tnft TangibleNFT contract address.
     * @return fingerprints -> Array of fingerprints. Indexes correspond with the indexes of tokenIds.
     */
    function tokensFingerprintBatch(
        uint256[] calldata tokenIds,
        ITangibleNFT tnft
    ) external view returns (uint256[] memory fingerprints) {
        uint256 length = tokenIds.length;
        fingerprints = new uint256[](length);

        for (uint256 i; i < length; ) {
            fingerprints[i] = tnft.tokensFingerprint(tokenIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice This function takes an array of `tokenIds` and fetches the corresponding storage expiration date.
     * @param tokenIds Array of tokenIds to query expiration for.
     * @param tnft TangibleNFT contract address.
     * @return endTimes -> Array of timestamps of when each tokenIds storage expires.
     */
    function tnftsStorageEndTime(
        uint256[] calldata tokenIds,
        ITangibleNFT tnft
    ) external view returns (uint256[] memory endTimes) {
        uint256 length = tokenIds.length;
        endTimes = new uint256[](length);

        for (uint256 i; i < length; ) {
            endTimes[i] = tnft.storageEndTime(tokenIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice This method returns an array of tokenIds given the indexes.
     * @param indexes Array of indexes.
     * @param enumrableContract Enumerable erc721 contract address.
     * @return tokenIds -> Array of tokenIds.
     */
    function tokenByIndexBatch(
        uint256[] calldata indexes,
        address enumrableContract
    ) external view returns (uint256[] memory tokenIds) {
        uint256 length = indexes.length;
        tokenIds = new uint256[](length);

        for (uint256 i; i < length; ) {
            tokenIds[i] = IERC721Enumerable(enumrableContract).tokenByIndex(indexes[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice This method is used to fetch a batch of Lot metadata objects for each `tokenId` provided.
     * @param nft TangibleNFT contract address.
     * @param tokenIds Array of tokenIds.
     * @return result Array of Lot metadata.
     */
    function lotBatch(
        address nft,
        uint256[] calldata tokenIds
    ) external view returns (ITangibleMarketplaceExt.Lot[] memory result) {
        uint256 length = tokenIds.length;

        result = new ITangibleMarketplaceExt.Lot[](length);

        ITangibleMarketplaceExt marketplace = ITangibleMarketplaceExt(
            IFactory(factory).marketplace()
        );

        for (uint256 i; i < length; ) {
            result[i] = marketplace.marketplaceLot(nft, tokenIds[i]);
            unchecked {
                ++i;
            }
        }
    }
}
