// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/// @title ICurrencyFeedV2 interface defines the interface of the CurrencyFeedV2.
interface ICurrencyFeedV2 {
    /// @dev Returns the price feed oracle used for the specified currency.
    function currencyPriceFeeds(
        string calldata currency
    ) external view returns (AggregatorV3Interface priceFeed);

    /// @dev Returns the conversion premium taken when exchanging currencies.
    function conversionPremiums(
        string calldata currency
    ) external view returns (uint256 conversionPremium);

    /// @dev Returns the price feed oracle used for the specified currency.
    function currencyPriceFeedsISONum(
        uint16 currencyISONum
    ) external view returns (AggregatorV3Interface priceFeed);

    /// @dev Returns the conversion premium taken when exchanging currencies.
    function conversionPremiumsISONum(
        uint16 currencyISONum
    ) external view returns (uint256 conversionPremium);

    /// @dev Given the currency ISO alpha code, will return the ISO numeric code.
    function ISOcurrencyCodeToNum(
        string calldata currencyCode
    ) external view returns (uint16 currencyISONum);

    /// @dev Given the currency ISO numeric code, will return the ISO alpha code.
    function ISOcurrencyNumToCode(
        uint16 currencyISONum
    ) external view returns (string memory currencyCode);

    /// @dev Given the country ISO alpha code, will return the ISO numeric code.
    function ISOcountryCodeToNum(
        string calldata countryCode
    ) external view returns (uint16 countryISONum);

    /// @dev Given the country ISO numeric code, will return the ISO alpha code.
    function ISOcountryNumToCode(
        uint16 countryISONum
    ) external view returns (string memory countryCode);
}
