// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

/// @title ITNFTMetadata interface defines the interface of the TNFTMetadata.
interface ITNFTMetadata {
    /// @dev FeatureInfo struct object for storing features metadata.
    struct FeatureInfo {
        uint256[] tnftTypes;
        bool added;
        string description;
    }

    /// @dev TNFTType struct object for storing tnft-type metadata.
    struct TNFTType {
        bool added;
        bool paysRent;
        string description;
    }

    /// @dev Returns an array of all supported tnft types.
    function tnftTypesArray(uint256 index) external view returns (uint256);

    // returns struct of tnft type
    /// @dev Returns a tnft type metadata object given the tnft type.
    function tnftTypes(
        uint256 _tnftType
    ) external view returns (bool added, bool paysRent, string memory description);

    /// @dev Returns a feature given the tnft type and index in the array where it resides.
    ///      features that are in specific type so that you can't add a type
    ///      to tnft that is not for that type (can't add beach house for gold).
    function typeFeatures(uint256 _tnftType, uint256 index) external view returns (uint256);

    /// @dev Returns a feature metadata object given the feature.
    function featureInfo(uint256 _feature) external view returns (FeatureInfo memory);

    // array of all features added
    /// @dev Returns a supported feature from the `featureList` array.
    function featureList(uint256 index) external view returns (uint256);

    /// @dev Returns whether a feature exists in `typeFeatures`.
    function featureInType(uint256 _tnftType, uint256 _feature) external view returns (bool);

    /// @dev Returns the `tnftTypesArray` array.
    function getTNFTTypes() external view returns (uint256[] memory);

    /// @dev Returns the `typeFeatures` mapped array.
    function getTNFTTypesFeatures(uint256 _tnftType) external view returns (uint256[] memory);

    /// @dev Returns the `featureList` array.
    function getFeatureList() external view returns (uint256[] memory);
}
