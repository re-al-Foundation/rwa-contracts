// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC721Metadata.sol";
import "@openzeppelin/contracts/interfaces/IERC721Enumerable.sol";

/// @title ITangibleNFT interface defines the interface of the TangibleNFT contract.

interface ITangibleNFT is IERC721, IERC721Metadata {
    /// @notice This struct defines a Feature object
    /// @param feature Feature identifier.
    /// @param index Index in `tokenFeatures` array.
    /// @param added If feature added, true.
    struct FeatureInfo {
        uint256 feature;
        uint256 index;
        bool added;
    }

    /// @dev This method returns the contract's `symbol` appended to the `_baseUriLink`.
    function baseSymbolURI() external view returns (string memory);

    /// @dev This returns the decimal point precision for storage fees.
    function storageDecimals() external view returns (uint8);

    /// @dev Function allows a Factory to mint multiple tokenIds for provided vendorId to the given address(stock storage, usualy marketplace)
    /// with provided count.
    function produceMultipleTNFTtoStock(
        uint256 count,
        uint256 fingerprint,
        address toStock
    ) external returns (uint256[] memory);

    /// @dev The function returns whether storage fee is paid for the current time.
    function isStorageFeePaid(uint256 tokenId) external view returns (bool);

    /// @dev This returns the storage expiration date for each `tokenId`.
    function storageEndTime(uint256 tokenId) external view returns (uint256 storageEnd);

    /// @dev This returns if a specified `tokenId` is blacklisted.
    function blackListedTokens(uint256 tokenId) external view returns (bool);

    /// @dev The function returns the price per year for storage.
    function storagePricePerYear() external view returns (uint256);

    /// @dev The function returns the percentage of item price that is used for calculating storage.
    function storagePercentagePricePerYear() external view returns (uint16);

    /// @dev The function returns whether storage for the TNFT is paid in fixed amount or in percentage from price
    function storagePriceFixed() external view returns (bool);

    /// @dev The function returns whether storage for the TNFT is required. For example houses don't have storage
    function storageRequired() external view returns (bool);

    /// @dev The function returns the token fingerprint - used in oracle
    function tokensFingerprint(uint256 tokenId) external view returns (uint256);

    /// @dev The function accepts takes tokenId, and years, sets storage and returns if storage is fixed or percentage.
    function adjustStorage(uint256 tokenId, uint256 _years) external returns (bool);

    /// @dev This method is used to return the array stored in `tokenFeatures` mapping.
    function getTokenFeatures(uint256 tokenId) external view returns (uint256[] memory);

    /// @dev This method is used to return the length of `tokenFeatures` mapped array.
    function getTokenFeaturesSize(uint256 tokenId) external view returns (uint256);

    /// @dev Returns the type identifier for this category.
    function tnftType() external view returns (uint256);

    function fingerprintTokens(uint256 fingerprint, uint256 index) external view returns (uint256);

    function getFingerprintTokens(uint256 fingerprint) external view returns (uint256[] memory);

    function getFingerprintTokensSize(uint256 fingerprint) external view returns (uint256);
}

/// @title ITangibleNFTExt interface defines the extended interface of the TangibleNFT contract.
interface ITangibleNFTExt is ITangibleNFT {
    /// @dev Returns the feature status of a `tokenId`.
    function tokenFeatureAdded(
        uint256 tokenId,
        uint256 feature
    ) external view returns (FeatureInfo memory);
}
