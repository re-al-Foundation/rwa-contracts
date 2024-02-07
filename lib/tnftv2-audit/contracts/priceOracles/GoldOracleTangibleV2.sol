// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "../interfaces/IPriceOracle.sol";
import "../abstract/FactoryModifiers.sol";
import "../abstract/PriceConverter.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "../interfaces/ICurrencyFeedV2.sol";

/**
 * @title GoldOracleTangible
 * @author Veljko Mihailovic
 * @notice This smart contract is used to manage the stock and pricing for gold products for the gold TNFTs.
 */
contract GoldOracleTangibleV2 is IPriceOracle, PriceConverter, FactoryModifiers {
    // ~ State Variables ~

    /**
     * @notice This struct is used to create a gold bar object.
     * @param grams Weight of gold bar.
     * @param weSellAtStock Amount of product in stock.
     */
    struct GoldBar {
        uint256 grams;
        uint256 weSellAtStock;
    }

    /// @notice Stores a reference to the CurrencyFeedV2 contract.
    ICurrencyFeedV2 public currencyFeed;

    /// @notice Mapping used to store GoldBar metadata for each gold bar fingerprint.
    mapping(uint256 => GoldBar) public goldBars;

    /// @notice Grams per ounce of gold.
    uint256 public constant unz = 31_1034768; // 7 decimals 31.1034768gr

    /// @notice ISO code for XAU (gold)
    uint16 public constant currencyISONum = 959;

    // ~ Events ~

    /**
     * @notice This event is emitted when a new gold bar product is added
     * @param fingerprint Product identifier that was added.
     * @param grams Weight of gold bar.
     */
    event GoldBarAdded(uint256 fingerprint, uint256 grams);

    /**
     * @notice This event is emitted when the stock of gold bars has been updated.
     * @param fingerprint Product identifier that was updated stock.
     * @param oldStock Old stock.
     * @param newStock New stock.
     */
    event GoldBarStockChanged(uint256 fingerprint, uint256 oldStock, uint256 newStock);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ~ Initializer ~

    /**
     * @notice This initializes the GoldOracleTangible contract.
     * @param _factory  Factory contract address.
     * @param _currencyFeed Address of price feed oracle.
     */
    function initialize(address _factory, address _currencyFeed) external initializer {
        __FactoryModifiers_init(_factory);
        require(_currencyFeed != address(0), "Empty address");
        currencyFeed = ICurrencyFeedV2(_currencyFeed);
    }

    // ~ Functions ~

    function updateCurrencyFeed(ICurrencyFeedV2 _currencyFeed) external onlyTangibleLabs {
        require(address(_currencyFeed) != address(0), "zero address");
        currencyFeed = _currencyFeed;
    }

    /**
     * @notice This returns the latest USD value for gold using the price feed oracle.
     * @param _fingerprint Product fingerprint to fetch GoldBar metadata.
     * @return Returns USD price per gram, premium fee, and tokization cost.
     */
    function _latestAnswer(uint256 _fingerprint) internal view returns (uint256) {
        require(goldBars[_fingerprint].grams != 0, "fingerprint must exist");
        AggregatorV3Interface priceFeed = currencyFeed.currencyPriceFeedsISONum(currencyISONum);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        if (price < 0) {
            price = 0;
        }

        uint256 priceForGrams = ((toDecimals(goldBars[_fingerprint].grams, 0, _decimals()) *
            uint256(price)) / toDecimals(unz, uint8(7), _decimals()));
        return (priceForGrams);
    }

    /**
     * @notice Get the latest completed round where the answer was updated.
     * @dev Inherited from IPriceOracle.
     * @param _fingerprint Product identifier.
     * @return Returns the latest block timestamp.
     */
    function latestTimeStamp(uint256 _fingerprint) external view override returns (uint256) {
        require(goldBars[_fingerprint].grams != 0, "fingerprint must exist");
        AggregatorV3Interface priceFeed = currencyFeed.currencyPriceFeedsISONum(currencyISONum);
        (, , , uint256 timeStamp, ) = priceFeed.latestRoundData();
        return timeStamp;
    }

    /**
     * @notice This internal method is used to fetch the decimals the oracle uses.
     * @return Returns the number of decimals the aggregator responses represent.
     */
    function decimals() external view override returns (uint8) {
        return _decimals();
    }

    /**
     * @notice Fetches decimals from price feed oracle.
     * @return Returns the number of decimals the aggregator responses represent.
     */
    function _decimals() internal view returns (uint8) {
        AggregatorV3Interface priceFeed = currencyFeed.currencyPriceFeedsISONum(currencyISONum);
        return priceFeed.decimals();
    }

    /**
     * @notice View method for fetching oracle description.
     * @dev Inherited from IPriceOracle
     * @return desc -> Returns the description of the aggregator the proxy points to. (i.e. "GBP / USD").
     */
    function description() external view override returns (string memory desc) {
        AggregatorV3Interface priceFeed = currencyFeed.currencyPriceFeedsISONum(currencyISONum);
        return priceFeed.description();
    }

    /**
     * @notice This view method is for fetching oracle version.
     * @return Returns the version number representing the type of aggregator the proxy points to. (i.e. `4`).
     */
    function version() external view override returns (uint256) {
        AggregatorV3Interface priceFeed = currencyFeed.currencyPriceFeedsISONum(currencyISONum);
        return priceFeed.version();
    }

    /**
     * @notice This method decrements amount of a product is in available stock.
     * @dev Is called after a purchase of this product.
     * @param _fingerprint Product that is decrementing in stock.
     */
    function decrementSellStock(uint256 _fingerprint) external override onlyFactory {
        require(goldBars[_fingerprint].weSellAtStock != 0, "Already zero sell");
        unchecked {
            goldBars[_fingerprint].weSellAtStock--;
        }
    }

    /**
     * @notice This method returns the amount of a gold bar product is still in stock.
     * @param _fingerprint Product identifier.
     * @return Returns amount that is available to be purchased.
     */
    function availableInStock(uint256 _fingerprint) external view override returns (uint256) {
        return (goldBars[_fingerprint].weSellAtStock);
    }

    /**
     * @notice This method returns the USD price data of a specified gold bar
     * @param _nft TangibleNFT contract reference.
     * @param _paymentUSDToken Token being used as payment.
     * @param _fingerprint Product identifier.
     * @param _tokenId Token identifier.
     * @return weSellAt -> Price of item in oracle, market price.
     * @return weSellAtStock -> Stock of the item. (Quantity)
     * @return tokenizationCost -> Tokenization costs for tokenizing asset. For gold, is 0.
     */
    function usdPrice(
        ITangibleNFT _nft,
        IERC20Metadata _paymentUSDToken,
        uint256 _fingerprint,
        uint256 _tokenId
    )
        external
        view
        override
        returns (uint256 weSellAt, uint256 weSellAtStock, uint256 tokenizationCost)
    {
        return _usdPrice(_nft, _paymentUSDToken, _fingerprint, _tokenId);
    }

    /**
     * @notice This method returns the USD prices data of a specified gold bars
     * @param _nft TangibleNFT contract reference.
     * @param _paymentUSDToken Token being used as payment.
     * @param _fingerprints Product identifiers.
     * @param _tokenIds Token identifiers.
     * @return weSellAt -> Prices of item in oracle, market price for corresponding _fingerprints or tokenIds.
     * @return weSellAtStock -> Stock of the item. (Quantity) for corresponding _fingerprints or tokenIds.
     * @return tokenizationCost -> Tokenization costs for tokenizing asset. For gold, is 0.
     */
    function usdPrices(
        ITangibleNFT _nft,
        IERC20Metadata _paymentUSDToken,
        uint256[] calldata _fingerprints,
        uint256[] calldata _tokenIds
    )
        external
        view
        override
        returns (
            uint256[] memory weSellAt,
            uint256[] memory weSellAtStock,
            uint256[] memory tokenizationCost
        )
    {
        bool useFingerprint = _fingerprints.length == 0 ? false : true;
        uint256 length = useFingerprint ? _fingerprints.length : _tokenIds.length;
        weSellAt = new uint256[](length);
        weSellAtStock = new uint256[](length);
        tokenizationCost = new uint256[](length);
        if (useFingerprint) {
            for (uint256 i; i < length; ) {
                (weSellAt[i], weSellAtStock[i], tokenizationCost[i]) = _usdPrice(
                    _nft,
                    _paymentUSDToken,
                    _fingerprints[i],
                    0
                );
                unchecked {
                    ++i;
                }
            }
        } else {
            for (uint256 i; i < length; ) {
                (weSellAt[i], weSellAtStock[i], tokenizationCost[i]) = _usdPrice(
                    _nft,
                    _paymentUSDToken,
                    0,
                    _tokenIds[i]
                );
                unchecked {
                    ++i;
                }
            }
        }
    }

    /**
     * @notice This internal method returns the USD price data of a specified gold bar
     */
    function _usdPrice(
        ITangibleNFT _nft,
        IERC20Metadata _paymentUSDToken,
        uint256 _fingerprint,
        uint256 _tokenId
    ) internal view returns (uint256 weSellAt, uint256 weSellAtStock, uint256 tokenizationCost) {
        require(
            (address(_nft) != address(0) && _tokenId != 0) || (_fingerprint != 0),
            "Must provide fingerprint or tokenId"
        );
        if (_fingerprint == 0) {
            _fingerprint = _nft.tokensFingerprint(_tokenId);
        }

        uint256 _priceOracle = _latestAnswer(_fingerprint);

        uint8 decimalsLocal = _decimals();

        weSellAt = toDecimals(_priceOracle, decimalsLocal, _paymentUSDToken.decimals()); //plus premium to add

        weSellAtStock = goldBars[_fingerprint].weSellAtStock;

        return (weSellAt, weSellAtStock, tokenizationCost);
    }

    /**
     * @notice This method allows the Tangible Labs multisig to add new gold bars
     * @param _fingerprint Fingerprint product identifier.
     * @param _grams Amount of grams of gold bar.
     */
    function addGoldBar(uint256 _fingerprint, uint256 _grams) external onlyTangibleLabs {
        require(_grams != 0 && _fingerprint != 0, "Zeros");

        if (goldBars[_fingerprint].grams != 0) {
            //we update
            goldBars[_fingerprint].grams = _grams;
        } else {
            //we add new
            GoldBar memory gb = GoldBar({grams: _grams, weSellAtStock: 0});
            goldBars[_fingerprint] = gb;
        }

        emit GoldBarAdded(_fingerprint, _grams);
    }

    /**
     * @notice This method allows the Tangible Labs multisig to update the stock of specific gold bars
     * @param _fingerprint Fingerprint product identifier.
     * @param _weSellAtStock New stock of product.
     */
    function addGoldBarStock(
        uint256 _fingerprint,
        uint256 _weSellAtStock
    ) external onlyTangibleLabs {
        require(goldBars[_fingerprint].grams != 0, "Bar not added");
        emit GoldBarStockChanged(
            _fingerprint,
            goldBars[_fingerprint].weSellAtStock,
            _weSellAtStock
        );

        goldBars[_fingerprint].weSellAtStock = _weSellAtStock;
    }

    function marketPriceNativeCurrency(
        uint256 fingerprint
    ) external view returns (uint256 nativePrice, uint256 currency) {
        currency = currencyISONum;
        nativePrice = goldBars[fingerprint].grams;
    }

    function marketPriceTotalNativeCurrency(
        uint256[] calldata fingerprints
    ) external view returns (uint256 nativePrice, uint256 currency) {
        uint256 length = fingerprints.length;
        currency = currencyISONum;

        for (uint256 i; i < length; i++) {
            nativePrice += goldBars[fingerprints[i]].grams;
        }
    }

    function marketPricesNativeCurrencies(
        uint256[] calldata fingerprints
    ) external view returns (uint256[] memory nativePrices, uint256[] memory currencies) {
        uint256 length = fingerprints.length;
        nativePrices = new uint256[](length);
        currencies = new uint256[](length);
        for (uint256 i; i < length; ) {
            currencies[i] = currencyISONum;
            nativePrices[i] = goldBars[fingerprints[i]].grams;
            unchecked {
                ++i;
            }
        }
    }
}
