// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./ITangibleNFT.sol";

/// @title ITangiblePriceManager interface gives prices for categories added in TangiblePriceManager.
interface IPriceOracle {
    /// @dev The function latest price and latest timestamp when price was updated from oracle.
    function latestTimeStamp(uint256 fingerprint) external view returns (uint256);

    /// @dev The function that returns price decimals from oracle.
    function decimals() external view returns (uint8);

    /// @dev The function that returns rescription for oracle.
    function description() external view returns (string memory desc);

    /// @dev The function that returns version of the oracle.
    function version() external view returns (uint256);

    /// @dev The function that reduces sell stock when token is bought.
    function decrementSellStock(uint256 fingerprint) external;

    /// @dev The function reduces buy stock when we buy token.
    function availableInStock(uint256 fingerprint) external returns (uint256 weSellAtStock);

    /// @dev The function that returns item price in USD, indexed in payment token.
    function usdPrices(
        ITangibleNFT nft,
        IERC20Metadata paymentUSDToken,
        uint256[] calldata fingerprint,
        uint256[] calldata tokenId
    )
        external
        view
        returns (
            uint256[] memory weSellAt,
            uint256[] memory weSellAtStock,
            uint256[] memory tokenizationCost
        );

    function usdPrice(
        ITangibleNFT nft,
        IERC20Metadata paymentUSDToken,
        uint256 fingerprint,
        uint256 tokenId
    ) external view returns (uint256 weSellAt, uint256 weSellAtStock, uint256 tokenizationCost);

    function marketPriceNativeCurrency(
        uint256 fingerprint
    ) external view returns (uint256 nativePrice, uint256 currency);

    function marketPriceTotalNativeCurrency(
        uint256[] calldata fingerprints
    ) external view returns (uint256 nativePrice, uint256 currency);

    function marketPricesNativeCurrencies(
        uint256[] calldata fingerprints
    ) external view returns (uint256[] memory nativePrices, uint256[] memory currencies);
}
