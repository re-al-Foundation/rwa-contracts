// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "./interfaces/IFactory.sol";

import "./abstract/FactoryModifiers.sol";

/**
 * @title TNFTMetadata
 * @author Veljko Mihailovic
 * @notice This contract is used to manage TangibleNFT metadata; Specifically Tnft types and features.
 */
contract TNFTMetadata is FactoryModifiers {
    // ~ State Variables ~

    /**
     * @notice FeatureInfo struct object for storing features metadata.
     * @param description Description of feature
     * @param tnftTypes Tnft Types that exist under this feature or sub-category.
     * @param added If true, feature is supported.
     */
    struct FeatureInfo {
        uint256[] tnftTypes;
        bool added;
        string description;
    }

    /**
     * @notice TNFTType struct object for storing tnft-type metadata.
     * @param added If true, tnftType is supported.
     * @param paysRent If true, TangibleNFT contract for this type receives rent revenue share.
     *                 @dev If true, contract is most likely manages real estate assets and has rent paying tenants.
     * @param description Description of TnftType.
     */
    struct TNFTType {
        bool added;
        bool paysRent;
        string description;
    }

    /// @notice Array of supported Tnft Types.
    uint256[] public tnftTypesArray;

    /// @notice Array of supported features.
    uint256[] public featureList;

    /// @notice Used to store/fetch tnft type metadata.
    mapping(uint256 => TNFTType) public tnftTypes;

    /// @notice Used to store/fetch feature metadata.
    mapping(uint256 => FeatureInfo) public featureInfo;

    /// @notice This mapping stores an array of features for a tnft type as the key.
    /// @dev i.e. RE: beach housem pool || wine bottle size etc, gold if it is coins, tablets etc
    mapping(uint256 => uint256[]) public typeFeatures;

    /// @notice Mapping used to track if a feature is added in type tnftType.
    /// @dev tnftType -> feature -> bool (if added)
    mapping(uint256 => mapping(uint256 => bool)) public featureInType;

    /// @notice Stores the index where a feature(key) resides in featureList.
    mapping(uint256 => uint256) public featureIndexInList;

    // ~ Events ~

    /**
     * @notice This event is emitted when a new Tnft type has been added to `tnftTypesArray`.
     * @param tnftType Tnft type being added.
     * @param description Description of tnft type.
     */
    event TnftTypeAdded(uint256 indexed tnftType, string description);

    /**
     * @notice This event is emitted when a new feature has been added to `featureList`.
     * @param feature feature being added.
     * @param description Description of feature.
     */
    event FeatureAdded(uint256 indexed feature, string description);

    /**
     * @notice This event is emitted when a feature is removed.
     * @param feature feature being removed.
     */
    event FeatureRemoved(uint256 indexed feature);

    /**
     * @notice This event is emitted when a feature's description has been modified.
     * @param feature feature being modified.
     * @param description New description of feature.
     */
    event FeatureModified(uint256 indexed feature, string description);

    /**
     * @notice This event is emitted when a feature is added to `featureInType`.
     * @param tnftType tnft type we're adding features to.
     * @param feature New feature to add.
     */
    event FeatureAddedToTnftType(uint256 indexed tnftType, uint256 indexed feature);

    /**
     * @notice This event is emitted when a feature is removed from `featureInType`.
     * @param tnftType tnft type we're removing features from.
     * @param feature Feature to remove.
     */
    event FeatureRemovedFromTnftType(uint256 tnftType, uint256 indexed feature);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ~ Initializer ~

    /**
     * @notice Used to initialize TNFTMetadata.
     * @param _factory Address of Factory contract.
     */
    function initialize(address _factory) external initializer {
        __FactoryModifiers_init(_factory);
    }

    // ~ Functions ~

    /**
     * @notice This method allows the Factory owner to add new supported features to this contract.
     * @param _featureList Array of new features to add.
     * @param _featureDescriptions Array of corresponding descriptions for each new feature.
     */
    function addFeatures(
        uint256[] calldata _featureList,
        string[] calldata _featureDescriptions
    ) external onlyFactoryOwner {
        uint256 length = _featureList.length;
        require(length == _featureDescriptions.length, "not the same size");

        for (uint256 i; i < length; ) {
            uint256 item = _featureList[i];
            require(!featureInfo[item].added, "already added");

            featureInfo[item].added = true; // added
            featureInfo[item].description = _featureDescriptions[i]; // set description
            featureList.push(item); // add to featureList
            featureIndexInList[item] = featureList.length - 1; // update mapping for removing

            emit FeatureAdded(item, _featureDescriptions[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice This method allows the Factory owner to modify existing features' descriptions.
     * @param _featureList Array of features to modify.
     * @param _featureDescriptions Array of corresponding descriptions for each feature.
     */
    function modifyFeature(
        uint256[] calldata _featureList,
        string[] calldata _featureDescriptions
    ) external onlyFactoryOwner {
        uint256 length = _featureList.length;
        require(length == _featureDescriptions.length, "not the same size");

        for (uint256 i; i < length; ) {
            uint256 item = _featureList[i];
            require(featureInfo[item].added, "Add first!");

            featureInfo[item].description = _featureDescriptions[i];
            emit FeatureModified(item, _featureDescriptions[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice This method allows the Factory owner to remove features.
     * @param _featureList Array of features to remove.
     */
    function removeFeatures(uint256[] calldata _featureList) external onlyFactoryOwner {
        uint256 length = _featureList.length;
        for (uint256 i; i < length; ) {
            uint256 featureItem = _featureList[i];
            require(featureInfo[featureItem].added, "Add first!");

            // removing feature from types
            uint256 indexArrayLength = featureInfo[featureItem].tnftTypes.length;
            for (uint256 j; j < indexArrayLength; ) {
                uint256 typeItem = featureInfo[featureItem].tnftTypes[j];
                delete featureInType[typeItem][featureItem];
                // remove from typeFeatures
                uint256 _index = _findElementIntypeFeatures(typeItem, featureItem);
                require(_index != type(uint256).max);
                typeFeatures[typeItem][_index] = typeFeatures[typeItem][
                    typeFeatures[typeItem].length - 1
                ];
                typeFeatures[typeItem].pop();
                emit FeatureRemovedFromTnftType(typeItem, featureItem);

                unchecked {
                    ++j;
                }
            }

            // remove from array of added
            uint256 index = featureIndexInList[featureItem];
            delete featureIndexInList[featureItem];

            featureList[index] = featureList[featureList.length - 1]; // move last to index of removing
            featureIndexInList[featureList[featureList.length - 1]] = index;
            featureList.pop(); // pop last element
            delete featureInfo[featureItem]; // delete from featureInfo mapping

            emit FeatureRemoved(featureItem);

            unchecked {
                ++i;
            }
        }
    }

    function _findElementIntypeFeatures(
        uint256 _type,
        uint256 _feature
    ) internal view returns (uint256) {
        for (uint256 i; i < typeFeatures[_type].length; ) {
            if (typeFeatures[_type][i] == _feature) return i;
            unchecked {
                ++i;
            }
        }
        return type(uint256).max;
    }

    /**
     * @notice This method allows the Factory owner to add new Tnft types.
     * @param _tnftType New tnft type.
     * @param _description Description for new tnft type.
     * @param _paysRent If true, TangibleNFT will have a rent manager.
     */
    function addTNFTType(
        uint256 _tnftType,
        string calldata _description,
        bool _paysRent
    ) external onlyFactoryOwner {
        require(!tnftTypes[_tnftType].added, "already exists");

        tnftTypes[_tnftType].added = true;
        tnftTypes[_tnftType].description = _description;
        tnftTypes[_tnftType].paysRent = _paysRent;
        tnftTypesArray.push(_tnftType);

        emit TnftTypeAdded(_tnftType, _description);
    }

    /**
     * @notice This method allows the Factory owner to add a existing features to existing tnft type.
     * @param _tnftType Existing tnft type.
     * @param _features Features to add to tnft type.
     */
    function addFeaturesForTNFTType(
        uint256 _tnftType,
        uint256[] calldata _features
    ) external onlyFactoryOwner {
        require(tnftTypes[_tnftType].added, "tnftType doesn't exist");
        uint256 length = _features.length;

        for (uint256 i; i < length; ) {
            uint256 item = _features[i];
            require(featureInfo[item].added, "feature doesn't exist");

            typeFeatures[_tnftType].push(item);
            featureInfo[item].tnftTypes.push(_tnftType);
            featureInType[_tnftType][item] = true;

            emit FeatureAddedToTnftType(_tnftType, item);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice This function is used to return the `tnftTypesArray`.
     * @return Array of Tnft types as uint256.
     */
    function getTNFTTypes() external view returns (uint256[] memory) {
        return tnftTypesArray;
    }

    function getFeatureInfo(uint256 feature) external view returns (FeatureInfo memory) {
        return featureInfo[feature];
    }

    /**
     * @notice This function is used to return the `typeFeatures` mapped array.
     * @param _tnftType The tnft type we want to return the array of features for.
     * @return Array of features.
     */
    function getTNFTTypesFeatures(uint256 _tnftType) external view returns (uint256[] memory) {
        return typeFeatures[_tnftType];
    }

    /**
     * @notice This function is used to return the `featureList` array.
     * @return Array of all features supported.
     */
    function getFeatureList() external view returns (uint256[] memory) {
        return featureList;
    }

    /**
     * @notice This internal function is used to remove a feature from typeFeatures array.
     * @param _tnftType type to remove feature from.
     * @param _indexInType Index to remove from.
     */
    function _removeFromType(uint256 _tnftType, uint256 _indexInType) internal {
        require(tnftTypes[_tnftType].added, "non-existing tnftType");

        uint256 last = typeFeatures[_tnftType].length - 1; // get last index
        uint256 lastItem = typeFeatures[_tnftType][last]; // grab last item

        typeFeatures[_tnftType][_indexInType] = lastItem; // set last item to removed item's index
        typeFeatures[_tnftType].pop(); // remove last item
    }
}
