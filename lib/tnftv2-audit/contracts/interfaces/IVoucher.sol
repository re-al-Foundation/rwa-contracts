// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "./ITangibleNFT.sol";

interface IVoucher {
    /// @dev Voucher for minting
    struct MintVoucher {
        ITangibleNFT token;
        uint256 mintCount;
        uint256 price;
        address vendor;
        address buyer;
        uint256 fingerprint;
        bool sendToVendor;
    }

    /// @dev Voucher for lazy-burning
    struct RedeemVoucher {
        ITangibleNFT token;
        uint256[] tokenIds;
        bool[] inOurCustody;
    }
}
