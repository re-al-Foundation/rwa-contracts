// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "./interfaces/ITangiblePriceManager.sol";
import "./abstract/FactoryModifiers.sol";

/**
 * @title TangiblePriceManager
 * @author Veljko Mihailovic
 * @notice This contract is used to facilitate the fetching/response of TangibleNFT prices
 */
contract TangiblePriceManagerV2 is ITangiblePriceManager, FactoryModifiers {
    // ~ State Variables ~

    /// @notice This maps TangibleNFT contracts to it's corresponding oracle.
    mapping(ITangibleNFT => IPriceOracle) public oracleForCategory;

    // ~ Events ~

    /// @notice This event is emitted when the `oracleForCategory` variable is updated.
    event CategoryPriceOracleAdded(address indexed category, address indexed priceOracle);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialized TangiblePriceManager.
     * @param _factory Factory provider contract address.
     */
    function initialize(address _factory) external initializer {
        __FactoryModifiers_init(_factory);
    }

    /**
     * @notice The function is used to set oracle contracts in the `oracleForCategory` mapping.
     * @param category TangibleNFT contract.
     * @param oracle PriceOracle contract.
     */
    function setOracleForCategory(
        ITangibleNFT category,
        IPriceOracle oracle
    ) external override onlyFactory {
        require(address(category) != address(0), "Zero category");
        require(address(oracle) != address(0), "Zero oracle");

        oracleForCategory[category] = oracle;
        emit CategoryPriceOracleAdded(address(category), address(oracle));
    }

    /**
     * @notice This function fetches pricing data for an array of products.
     * @param nft TangibleNFT contract reference.
     * @param paymentUSDToken Token being used as payment.
     * @param fingerprints Array of token fingerprints data.
     * @return weSellAt -> Price of item in oracle, market price.
     * @return weSellAtStock -> Stock of the item.
     * @return tokenizationCost -> Tokenization costs for tokenizing asset. Real Estate will never be 0.
     */
    function itemPriceBatchFingerprints(
        ITangibleNFT nft,
        IERC20Metadata paymentUSDToken,
        uint256[] calldata fingerprints
    )
        external
        view
        returns (
            uint256[] memory weSellAt,
            uint256[] memory weSellAtStock,
            uint256[] memory tokenizationCost
        )
    {
        uint256[] memory empty = new uint[](0);
        (weSellAt, weSellAtStock, tokenizationCost) = oracleForCategory[nft].usdPrices(
            nft,
            paymentUSDToken,
            fingerprints,
            empty
        );
    }

    /**
     *
     * @notice This function fetches pricing data for specific product.
     * @param nft TangibleNFT contract reference.
     * @param paymentUSDToken Token being used as payment.
     * @param fingerprint product fingerprint.
     * @return weSellAt -> Price of item in oracle, market price.
     * @return weSellAtStock -> Stock of the item.
     * @return tokenizationCost -> Tokenization costs for tokenizing asset.
     */
    function itemPriceFingerprint(
        ITangibleNFT nft,
        IERC20Metadata paymentUSDToken,
        uint256 fingerprint
    ) external view returns (uint256 weSellAt, uint256 weSellAtStock, uint256 tokenizationCost) {
        (weSellAt, weSellAtStock, tokenizationCost) = oracleForCategory[nft].usdPrice(
            nft,
            paymentUSDToken,
            fingerprint,
            0
        );
    }

    /**
     * @notice This function fetches pricing data for an array of tokenIds.
     * @param nft TangibleNFT contract reference.
     * @param paymentUSDToken Token being used as payment.
     * @param tokenIds Array of tokenIds.
     * @return weSellAt -> Price of item in oracle, market price.
     * @return weSellAtStock -> Stock of the item.
     * @return tokenizationCost -> Tokenization costs for tokenizing asset. Real Estate will never be 0.
     */
    function itemPriceBatchTokenIds(
        ITangibleNFT nft,
        IERC20Metadata paymentUSDToken,
        uint256[] calldata tokenIds
    )
        external
        view
        returns (
            uint256[] memory weSellAt,
            uint256[] memory weSellAtStock,
            uint256[] memory tokenizationCost
        )
    {
        uint256[] memory empty = new uint[](0);
        (weSellAt, weSellAtStock, tokenizationCost) = oracleForCategory[nft].usdPrices(
            nft,
            paymentUSDToken,
            empty,
            tokenIds
        );
    }

    /**
     *
     * @notice This function fetches USD pricing data for tokenId.
     * @param nft TangibleNFT contract reference.
     * @param paymentUSDToken Token being used as payment.
     * @param tokenId tokenId to fetch the price for.
     * @return weSellAt -> Price of item in oracle, market price.
     * @return weSellAtStock -> Stock of the item.
     * @return tokenizationCost -> Tokenization costs for tokenizing asset.
     */
    function itemPriceTokenId(
        ITangibleNFT nft,
        IERC20Metadata paymentUSDToken,
        uint256 tokenId
    ) external view returns (uint256 weSellAt, uint256 weSellAtStock, uint256 tokenizationCost) {
        (weSellAt, weSellAtStock, tokenizationCost) = oracleForCategory[nft].usdPrice(
            nft,
            paymentUSDToken,
            0,
            tokenId
        );
    }
}
