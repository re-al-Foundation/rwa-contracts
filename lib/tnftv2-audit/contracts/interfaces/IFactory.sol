// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "./IVoucher.sol";
import "./ITangiblePriceManager.sol";
import "./IRentManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface RevenueShare {
    function claimForToken(address contractAddress, uint256 tokenId) external;

    function share(bytes memory token) external view returns (int256);

    function updateShare(address contractAddress, uint256 tokenId, int256 amount) external;

    function unregisterContract(address contractAddress) external;

    function total() external view returns (uint256);
}

interface RentShare {
    function forToken(address contractAddress, uint256 tokenId) external returns (RevenueShare);
}

/// @title IFactory interface defines the interface of the Factory which creates TNFTs.
interface IFactory is IVoucher {
    /// @dev The function which does lazy minting.
    function mint(MintVoucher calldata voucher) external returns (uint256[] memory);

    /// @dev The function returns the address of the marketplace.
    function marketplace() external view returns (address);

    /// @dev Returns labs owner.
    function tangibleLabs() external view returns (address);

    /// @dev The function returns the address of the tnft deployer.
    function tnftDeployer() external view returns (address);

    /// @dev The function returns the address of the priceManager.
    function priceManager() external view returns (ITangiblePriceManager);

    /// @dev The function returns an address of category NFT.
    function category(string calldata name) external view returns (ITangibleNFT);

    /// @dev The function pays for storage, called only by marketplace.
    function adjustStorageAndGetAmount(
        ITangibleNFT tnft,
        IERC20Metadata paymentToken,
        uint256 tokenId,
        uint256 _years
    ) external returns (uint256);

    /// @dev Returns the Erc20 token reference of the default USD stablecoin payment method.
    function defUSD() external returns (IERC20);

    /// @dev RentManager contract for specific TNFT.
    function rentManager(ITangibleNFT) external view returns (IRentManager);

    /// @notice Baskets manager address
    function basketsManager() external view returns (address);

    /// @notice Currency feed address
    function currencyFeed() external view returns (address);

    /// @dev Returns if the `nft` is a whitelisted category. If true, tnft's are whitelisted buyers only.
    function onlyWhitelistedForUnmintedCategory(ITangibleNFT nft) external view returns (bool);

    /// @dev Returns if a specified `buyer` is whitelisted to mint from `tnft`.
    function whitelistForBuyUnminted(ITangibleNFT tnft, address buyer) external view returns (bool);

    /// @dev Returns if a `minter` address is a defined as a category minter.
    function categoryMinter(address minter) external view returns (bool);

    /// @dev Returns if a specified `token` is accepted as a payment Erc20 method.
    function paymentTokens(IERC20 token) external view returns (bool);

    /// @dev Returns the address of the category owner for a specified `nft`.
    function categoryOwner(ITangibleNFT nft) external view returns (address);

    /// @dev Returns the address of the "approval manager" for a specified `nft`.
    function fingerprintApprovalManager(ITangibleNFT nft) external view returns (address);

    /// @dev Returns the address of the TangibleNFTMetadata contract.
    function tnftMetadata() external view returns (address);

    /// @dev Returns the address to be used while sending payments to categoryOwner (buyUnminted,storage).
    function categoryOwnerWallet(ITangibleNFT nft) external view returns (address);
}
