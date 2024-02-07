// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "./ITangibleNFT.sol";

/// @title Interface for the OnSaleTracker.sol contract
interface IOnSaleTracker {
    /// @dev This external function is used to update the status of any listings on the Marketplace contract.
    function tnftSalePlaced(ITangibleNFT tnft, uint256 tokenId, bool placed) external;
}
