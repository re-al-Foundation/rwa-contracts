// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "./interfaces/IFactory.sol";

import "./interfaces/ITangibleNFT.sol";
import "./interfaces/ITNFTMetadata.sol";
import "./abstract/FactoryModifiers.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title TangibleNFTV2
 * @author Veljko Mihailovic
 * @notice This is the Erc721 contract for the Tangible NFTs. Manages each asset's unique metadata and category.
 */
contract TangibleNFTV2 is
    ITangibleNFT,
    ERC721EnumerableUpgradeable,
    ERC721PausableUpgradeable,
    FactoryModifiers
{
    using Strings for uint256;

    // ~ State variables -> packed: (591 bytes -> 19+ slots) ~

    /// @notice This mapping is used to store the storage expiration date of each tokenId.
    mapping(uint256 => uint256) public storageEndTime;

    /// @notice This mapping keeps track of all fingerprints that have been added.
    mapping(uint256 => bool) public fingerprintAdded;

    /// @notice A mapping from tokenId to fingerprint identifier.
    /// @dev eg 0x0000001 -> 3.
    mapping(uint256 => uint256) public tokensFingerprint;

    /// @notice A mapping from fingerprint identifier to an array of tokenIds.
    mapping(uint256 => uint256[]) public fingerprintTokens;

    /// @notice Array for storing fingerprint identifiers.
    uint256[] public fingeprintsInTnft;

    /// @notice Used to assign a unique tokenId identifier to each NFT minted.
    uint256 public lastTokenId;

    /// @notice A mapping used to store the address of original token minters.
    // mapping(uint256 => address) private _originalTokenOwners;

    /// @notice A mapping from tokenId to bool. If a tokenId is set to true.
    mapping(uint256 => bool) public blackListedTokens;

    /// @notice A mapping from tokenId to bool. If tokenId is set to true, it is in the custody of Tangible.
    mapping(uint256 => bool) public tnftCustody;

    /// @notice A mapping to store TNFT metadata tokenId -> feature -> feature Info.
    mapping(uint256 => mapping(uint256 => FeatureInfo)) public tokenFeatureAdded;

    /// @notice A mapping to store features added per tokenId.
    mapping(uint256 => uint256[]) public tokenFeatures;

    /// @notice The price per year for storage.
    uint256 public storagePricePerYear;

    /// @notice Identifier for product type
    /// @dev Categories are no longer unique, tnftType will be used to identify the type of products the TangibleNFT mints.
    uint256 public tnftType;

    /// @notice Used to store the block timestamp when this contract was deployed.
    uint256 public deploymentBlock;

    /// @notice TODO
    uint8 public storageDecimals;

    /// @notice Used to store the percentage price per year for storage.
    /// @dev Max percent precision is 2 decimals (i.e 100% is 10000 // 0.01% is 1).
    uint16 public storagePercentagePricePerYear;

    /// @notice If true, the storage price is a fixed price.
    bool public storagePriceFixed;

    /// @notice If true, storage is required for these NFTs.
    bool public storageRequired;

    /// @notice If true, the symbol is used in the metadata URI.
    bool public symbolInUri;

    /// @notice Used to assign a base metadata HTTP URI for appending/fetching token metadata.
    string private _baseUriLink;

    // ~ Events ~

    /**
     * @notice This event is emitted when `storagePricePerYear` is updated.
     * @param oldPrice The old yearly storage price.
     * @param newPrice The new yearly storage price.
     */
    event StoragePricePerYearSet(uint256 oldPrice, uint256 newPrice);

    /**
     * @notice This event is emitted when `storagePercentagePricePerYear` is updated.
     * @param oldPercentage The old yearly storage percent price.
     * @param newPercentage The new yearly storage percent price.
     */
    event StoragePercentagePricePerYearSet(uint256 oldPercentage, uint256 newPercentage);

    /**
     * @notice This event is emitted when storage for a specified token has been extended & paid for.
     * @param tokenId TNFT identifier.
     * @param _years Num of years to extend storage.
     * @param storageEnd New expiration date.
     */
    event StorageExtended(uint256 indexed tokenId, uint256 _years, uint256 storageEnd);

    /**
     * @notice This event is emitted when a new TNFT is minted.
     * @param tokenId TNFT identifier.
     */
    event ProducedTNFTs(uint256[] tokenId);

    /**
     * @notice This event is emitted when `blackListedTokens` is updated.
     * @param tokenId TNFT identifier.
     * @param blacklisted If true, NFT is blacklisted.
     */
    event BlackListedToken(uint256 indexed tokenId, bool indexed blacklisted);

    /**
     * @notice This event is emitted when a new fingerprint has been added.
     * @param fingerprint New fingerprint that's been added.
     */
    event FingerprintApproved(uint256 indexed fingerprint);

    /**
     * @notice This event is emitted when the value of `storageRequired` is updated.
     * @param value If true, storage is required for this contrat.
     */
    event StorageRequired(bool value);

    /**
     * @notice This event is emitted when the value of `storagePriceFixed` is updated.
     * @param value If true, storage price is a fixed price.
     */
    event StorageFixed(bool value);

    /**
     * @notice This event is emitted when a token is in Tangible custody.
     * @param tokenId TNFT identifier.
     * @param inOurCustody If true, the token is in Tangible custody. If false, asset was redeemed.
     */
    event InCustody(uint256 indexed tokenId, bool indexed inOurCustody);

    /**
     * @notice This event is emitted when a feature or multiple features are added/removed to a token's metadata.
     * @param tokenId TNFT identifier.
     * @param feature Feature that was added.
     * @param added If true, feature was added. Otherwise, false.
     */
    event TnftFeature(uint256 indexed tokenId, uint256 indexed feature, bool added);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ~ Initializer ~

    /**
     * @notice Initializes TangibleNFT.
     * @param _factory  Factory contract address.
     * @param _category TNFT contract name.
     * @param _symbol TNFT contract symbol.
     * @param _uri base URI for fetching metadata from provider.
     * @param _storagePriceFixed If true, the storage price per year per TNFT is fixed.
     * @param _storageRequired If true, storage is required for each minted TNFT.
     * @param _symbolInUri If true, `_symbol` will be appended to the `_uri`.
     * @param _tnftType Tnft Type -> TNFTMetdata tracks all supported types.
     */
    function initialize(
        address _factory,
        string memory _category,
        string memory _symbol,
        string memory _uri,
        bool _storagePriceFixed,
        bool _storageRequired,
        bool _symbolInUri,
        uint256 _tnftType
    ) external initializer {
        __ERC721_init(_category, _symbol);
        __ERC721Pausable_init();
        __ERC721Enumerable_init();
        __FactoryModifiers_init(_factory);
        _baseUriLink = _uri;

        storagePriceFixed = _storagePriceFixed;
        storagePricePerYear = 2000; // 20$ in 2 decimals
        storagePercentagePricePerYear = 10; // 0.1 percent
        storageRequired = _storageRequired;
        symbolInUri = _symbolInUri;

        deploymentBlock = block.number;
        tnftType = _tnftType;
        storageDecimals = 2;
        lastTokenId = 0;
    }

    // ~ External Functions ~

    /**
     * @notice This function is used to update `_baseUriLink`.
     * @dev Only callable by factory admin.
     * @param uri New base URI.
     */
    function setBaseURI(
        string calldata uri
    ) external onlyCategoryOwner(ITangibleNFT(address(this))) {
        _baseUriLink = uri;
    }

    /**
     * @notice This function is meant for the category owner to pause/unpause the contract.
     */
    function togglePause() external onlyCategoryOwner(ITangibleNFT(address(this))) {
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
    }

    /**
     * @notice Mints multiple TNFTs.
     * @dev Only callable by Factory.
     * @param count Amount of TNFTs to mint.
     * @param fingerprint Product identifier to mint.
     * @param to Receiver of the newly minted tokens.
     * @return Array of minted tokenIds.
     */
    function produceMultipleTNFTtoStock(
        uint256 count,
        uint256 fingerprint,
        address to
    ) external onlyFactory returns (uint256[] memory) {
        require(fingerprintAdded[fingerprint], "FNA");
        uint256[] memory mintedTnfts = new uint256[](count);

        for (uint256 i; i < count; ) {
            mintedTnfts[i] = _produceTNFTtoStock(to, fingerprint);

            unchecked {
                ++i;
            }
        }

        emit ProducedTNFTs(mintedTnfts);
        return mintedTnfts;
    }

    /**
     * @notice This method is used to burn TNFTs
     * @dev Only callable by category owner and msg.sender must be owner of the `tokenId`.
     * @param tokenId TNFT identifier.
     */
    function burn(uint256 tokenId) external onlyCategoryOwner(ITangibleNFT(address(this))) {
        require(msg.sender == ownerOf(tokenId), "NOW");
        _setTNFTStatus(tokenId, false);
        _burn(tokenId);
    }

    /**
     * @notice This method allows a category owner to set the custody status of a TNFT.
     * @dev If the asset was redeemed, it is no longer in our custody thus the NFT should not be sold.
     * @param tokenIds Array of tokenIds to update custody for.
     * @param inOurCustody If true, the NFT's asset is in our custody. Otherwise, false.
     */
    function setCustody(
        uint256[] calldata tokenIds,
        bool[] calldata inOurCustody
    ) external onlyCategoryOwner(ITangibleNFT(address(this))) {
        _setTNFTStatuses(tokenIds, inOurCustody);
    }

    /**
     * @notice This function is used to update the storage price per year.
     * @param _storagePricePerYear amount to pay for storage per year.
     */
    function setStoragePricePerYear(
        uint256 _storagePricePerYear
    ) external onlyCategoryOwner(ITangibleNFT(address(this))) {
        emit StoragePricePerYearSet(storagePricePerYear, _storagePricePerYear);
        storagePricePerYear = _storagePricePerYear;
    }

    /**
     * @notice This function is used to update `storageDecimals`.
     * @param decimals New decimal precision for `storageDecimals`.
     */
    function setStorageDecimals(
        uint8 decimals
    ) external onlyCategoryOwner(ITangibleNFT(address(this))) {
        require(decimals >= 0 && decimals <= 18, "wrong");
        storageDecimals = decimals;
    }

    /**
     * @notice This method is used to update the storage percentage price per year.
     * @dev Not necessary for TNFT contracts that have a fixed storage pricing model.
     * @param _storagePercentagePricePerYear percentage of token value to pay per year for storage.
     */
    function setStoragePercentPricePerYear(
        uint16 _storagePercentagePricePerYear
    ) external onlyCategoryOwner(ITangibleNFT(address(this))) {
        emit StoragePercentagePricePerYearSet(
            storagePercentagePricePerYear,
            _storagePercentagePricePerYear
        );
        storagePercentagePricePerYear = _storagePercentagePricePerYear;
    }

    /**
     * @notice This function is used to update the storage expiration timestamp for a token.
     * @param tokenId TNFT identifier.
     * @param _years Number of years to extend storage expiration.
     * @return If true, storage price is fixed
     */
    function adjustStorage(uint256 tokenId, uint256 _years) external onlyFactory returns (bool) {
        uint256 lastPaidDate = storageEndTime[tokenId];
        if (lastPaidDate == 0) {
            lastPaidDate = block.timestamp;
        }
        //calculate to which point storage will last
        lastPaidDate += _years * 365 days;
        storageEndTime[tokenId] = lastPaidDate;

        emit StorageExtended(tokenId, _years, lastPaidDate);

        return storagePriceFixed;
    }

    /**
     * @notice This method allows a category owner to enable/disable storage fees
     * @param value If true, there is a storage fee to be paid by TNFT holders.
     */
    function toggleStorageFee(bool value) external onlyCategoryOwner(ITangibleNFT(address(this))) {
        storagePriceFixed = value;
        emit StorageFixed(value);
    }

    /**
     * @notice This method allows a category owner to enable/disable storage requirements
     * @param value If true, storage is required.
     */
    function toggleStorageRequired(
        bool value
    ) external onlyCategoryOwner(ITangibleNFT(address(this))) {
        storageRequired = value;
        emit StorageRequired(value);
    }

    /**
     * @notice This function will push a new set of fingerprints to the fingeprintsInTnft array.
     * @dev Only callable by Factory admin.
     * @param fingerprints array of fingerprints to add.
     */
    function addFingerprints(uint256[] calldata fingerprints) external onlyFingerprintApprover {
        uint256 lengthArray = fingerprints.length;
        require(lengthArray > 0, "AE");

        for (uint256 i; i < lengthArray; ) {
            require(!fingerprintAdded[fingerprints[i]], "FAA");
            fingerprintAdded[fingerprints[i]] = true;
            emit FingerprintApproved(fingerprints[i]);
            fingeprintsInTnft.push(fingerprints[i]);

            unchecked {
                ++i;
            }
        }
    }

    function addMetadata(
        uint256 tokenId,
        uint256[] calldata _features
    ) external onlyCategoryOwner(ITangibleNFT(address(this))) {
        require(_ownerOf(tokenId) != address(0), "token not minted");
        ITNFTMetadata tnftMetadata = ITNFTMetadata(IFactory(factory()).tnftMetadata());
        uint256 length = _features.length;

        for (uint256 i; i < length; ) {
            uint256 feature = _features[i];
            require(tnftMetadata.featureInType(tnftType, feature), "feature not in tfntType");
            require(!tokenFeatureAdded[tokenId][feature].added, "already added");
            // add to array
            tokenFeatures[tokenId].push(feature);
            // add in map
            tokenFeatureAdded[tokenId][feature].added = true;
            tokenFeatureAdded[tokenId][feature].feature = feature;
            tokenFeatureAdded[tokenId][feature].index = tokenFeatures[tokenId].length - 1;
            emit TnftFeature(tokenId, feature, true);

            unchecked {
                ++i;
            }
        }
    }

    function removeMetadata(
        uint256 tokenId,
        uint256[] calldata _features
    ) external onlyCategoryOwner(ITangibleNFT(address(this))) {
        ITNFTMetadata tnftMetadata = ITNFTMetadata(IFactory(factory()).tnftMetadata());
        uint256 length = _features.length;

        for (uint256 i; i < length; ) {
            uint256 feature = _features[i];
            require(tnftMetadata.featureInType(tnftType, feature), "feature not in tfntType");
            require(tokenFeatureAdded[tokenId][feature].added, "!exist");
            // take last element
            uint256 last = tokenFeatures[tokenId][tokenFeatures[tokenId].length - 1];
            // set it to index
            tokenFeatures[tokenId][tokenFeatureAdded[tokenId][feature].index] = last;
            //remove from array
            tokenFeatures[tokenId].pop();
            // delete mapping and update index of the last
            tokenFeatureAdded[tokenId][last].index = tokenFeatureAdded[tokenId][feature].index;
            delete tokenFeatureAdded[tokenId][feature];
            emit TnftFeature(tokenId, feature, false);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice This function sets a tokenId to bool value in isBlacklisted mapping.
     * @dev If value is set to true, tokenId will not be able to be transfered.
     *      Function only callable by Factory admin.
     * @param tokenId TNFT identifier to be blacklisted.
     * @param blacklisted If true, tokenId will be blacklisted.
     */
    function blacklistToken(
        uint256 tokenId,
        bool blacklisted
    ) external onlyCategoryOwner(ITangibleNFT(address(this))) {
        blackListedTokens[tokenId] = blacklisted;
        emit BlackListedToken(tokenId, blacklisted);
    }

    /**
     * @notice This method returns the contract's `symbol` appended to the `_baseUriLink`.
     * @dev Will only return the symbol appended to baseUri if `symbolInUri` is true.
     * @return baseUri with appended symbol as a string.
     */
    function baseSymbolURI() external view returns (string memory) {
        if (symbolInUri) {
            return string(abi.encodePacked(_baseUriLink, "/", symbol(), "/"));
        } else {
            return string(abi.encodePacked(_baseUriLink, "/"));
        }
    }

    /**
     * @notice This method is used to return the array stored in `tokenFeatures` mapping.
     * @param tokenId TNFT identifier to return features array for.
     * @return Array of features for `tokenId`.
     */
    function getTokenFeatures(uint256 tokenId) external view returns (uint256[] memory) {
        return tokenFeatures[tokenId];
    }

    /**
     * @notice This method is used to return the length of `tokenFeatures` mapped array.
     * @param tokenId TNFT identifier to return features array length for.
     * @return Length of the array.
     */
    function getTokenFeaturesSize(uint256 tokenId) external view returns (uint256) {
        return tokenFeatures[tokenId].length;
    }

    /**
     * @notice This method is used to return the `fingeprintsInTnft` array.
     * @return Array of fingerprints stored in `fingeprintsInTnft`.
     */
    function getFingerprints() external view returns (uint256[] memory) {
        return fingeprintsInTnft;
    }

    /**
     * @notice This method is used to return the length of the `fingeprintsInTnft` array.
     * @return Length of `fingeprintsInTnft` array.
     */
    function getFingerprintsSize() external view returns (uint256) {
        return fingeprintsInTnft.length;
    }

    function getFingerprintTokens(uint256 fingerprint) external view returns (uint256[] memory) {
        return fingerprintTokens[fingerprint];
    }

    function getFingerprintTokensSize(uint256 fingerprint) external view returns (uint256) {
        return fingerprintTokens[fingerprint].length;
    }

    // ~ Public Functions ~

    /**
     * @notice This view function is used to return the `_baseUriLink` string with appended tokenId.
     * @param tokenId Unique token identifier for which token's metadata we want to fetch.
     * @return Unique token metadata uri.
     */
    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721Upgradeable, IERC721Metadata) returns (string memory) {
        return
            bytes(_baseUriLink).length > 0
                ? symbolInUri
                    ? string(abi.encodePacked(_baseUriLink, "/", symbol(), "/", tokenId.toString()))
                    : string(abi.encodePacked(_baseUriLink, "/", tokenId.toString()))
                : "";
    }

    /**
     * @notice This method is used to return if an `operator` is allows to manage assets of `account`.
     * @param account Owner of tokens.
     * @param operator Contract address or EOA allowed to manage tokens on behalf of `account`.
     * @return If true, operator is approved.
     */
    function isApprovedForAll(
        address account,
        address operator
    ) public view override(ERC721Upgradeable, IERC721) returns (bool) {
        return operator == factory() || ERC721Upgradeable.isApprovedForAll(account, operator);
    }

    /**
     * @notice This method is used to return whether or not the storage fee has been paid for.
     * @param tokenId TNFT identifier to see if storage has been paid for.
     * @return If true, storage has been paid for, otherwise false.
     */
    function isStorageFeePaid(uint256 tokenId) public view returns (bool) {
        return _isStorageFeePaid(tokenId);
    }

    /**
     * @notice This method is used to see if this contract is registered as an implementer of the interface defined by interfaceId.
     * @dev Support of the actual ERC165 interface is automatic and registering its interface id is not required.
     * @param interfaceId Interface identifier.
     * @return If true, this cotnract supports the interface defined by `interfaceId`.
     */
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, IERC165)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // ~ Internal functions ~

    /**
     * @notice Internal function which mints and produces a single TNFT.
     * @param to Receiver of new token.
     * @param fingerprint Identifier of product to mint a token for.
     * @return tokenId that is minted
     */
    function _produceTNFTtoStock(address to, uint256 fingerprint) internal returns (uint256) {
        uint256 tokenToMint = ++lastTokenId;

        //create new tnft and update last produced tnft in map
        _safeMint(to, tokenToMint);
        //store fingerprint to token id
        tokensFingerprint[tokenToMint] = fingerprint;
        //store token id to fingerprint
        fingerprintTokens[fingerprint].push(tokenToMint);
        // _originalTokenOwners[tokenToMint] = to;
        tnftCustody[tokenToMint] = true;

        return tokenToMint;
    }

    /**
     * @notice Internal function for updating status of token custody.
     * @param tokenIds tokens to update custody of.
     * @param inOurCustody If true, in Tangible custody, otherwise false.
     */
    function _setTNFTStatuses(uint256[] calldata tokenIds, bool[] calldata inOurCustody) internal {
        uint256 length = tokenIds.length;
        for (uint256 i; i < length; ) {
            _setTNFTStatus(tokenIds[i], inOurCustody[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Internal function for updating status of token custody.
     * @param tokenId token to update custody of.
     * @param inOurCustody Status of custody.
     */
    function _setTNFTStatus(uint256 tokenId, bool inOurCustody) internal {
        tnftCustody[tokenId] = inOurCustody;
        emit InCustody(tokenId, inOurCustody);
    }

    /**
     * @notice Internal fucntion to check conditions prior to initiating a transfer of NFT.
     * @param to the destination of the token.
     * @param tokenId TNFT identifier to transfer.
     * @param auth auth.
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    )
        internal
        override(ERC721EnumerableUpgradeable, ERC721PausableUpgradeable)
        returns (address from)
    {
        from = super._update(to, tokenId, auth);
        // Allow operations if admin, factory or 0 address
        address _factory = factory();
        if (
            IFactory(_factory).categoryOwner(ITangibleNFT(address(this))) == from ||
            (_factory == from) ||
            from == address(0) ||
            to == address(0)
        ) {
            return from;
        }

        // we prevent transfers if blacklisted or not in our custody(redeemed)
        if (blackListedTokens[tokenId] || !tnftCustody[tokenId]) {
            revert("BL");
        }
        // for houses there is no storage so just allow transfer
        if (!storageRequired) {
            return from;
        }
        if (!_isStorageFeePaid(tokenId)) {
            if (msg.sender != _factory) {
                revert("CT");
            }
        }
    }

    function _increaseBalance(
        address account,
        uint128 amount
    ) internal override(ERC721EnumerableUpgradeable, ERC721Upgradeable) {
        super._increaseBalance(account, amount);
    }

    /**
     * @notice This internal method is used to return the boolean value of whether storage has expired for a token.
     * @param tokenId TNFT identifier to see if storage has been expired.
     * @return If true, storage has not expired, otherwise false.
     */
    function _isStorageFeePaid(uint256 tokenId) internal view returns (bool) {
        //logic for no storage
        if (!_shouldPayStorage()) {
            return true;
        }
        return storageEndTime[tokenId] > block.timestamp;
    }

    function _shouldPayStorage() internal view returns (bool) {
        if (storageRequired) {
            if (
                (storagePriceFixed && storagePricePerYear == 0) ||
                (!storagePriceFixed && storagePercentagePricePerYear == 0)
            ) {
                return false;
            }
            return true;
        }
        return false;
    }
}
